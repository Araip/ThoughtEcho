import 'dart:convert';

import 'package:dio/dio.dart';

/// 定制版：坚果云明文文档读取服务
///
/// 负责通过 WebDAV 列出并下载「坚果云/易码」与「坚果云/hnote-data-v2」
/// 下的明文文档（.md / .txt 等）及其图片资源，供导入页写入便签库。
class NutstoreSource {
  const NutstoreSource(
    this.name, {
    this.subdirs = const <String>[],
    this.assetDirs = const <String>[],
    this.skipFiles = const <String>{},
    this.metaIndex = false,
  });

  /// 坚果云根目录下的目录名。
  final String name;

  /// 需要一并扫描的正文子目录（相对 [name]）。
  final List<String> subdirs;

  /// 图片等资源所在子目录（相对 [name]）。
  final List<String> assetDirs;

  /// 需要跳过的文件名（例如 hnote 的 meta.json 索引本身不是笔记）。
  final Set<String> skipFiles;

  /// 是否读取 meta.json 还原真实标题与图片清单。
  final bool metaIndex;
}

/// `meta.json` 中一条笔记的元信息。
class NutstoreMetaInfo {
  const NutstoreMetaInfo({this.title, this.images = const <String>[]});

  final String? title;
  final List<String> images;
}

/// 一个可导入的远端文档。
class NutstoreEntry {
  const NutstoreEntry({
    required this.url,
    required this.name,
    required this.group,
    this.title,
    this.images = const <String>[],
    this.isDir = false,
    this.size = 0,
    this.modified,
  });

  final String url;
  final String name;
  final String group;
  final String? title;

  /// 该笔记引用的图片文件名（相对资源目录）。
  final List<String> images;
  final bool isDir;
  final int size;
  final DateTime? modified;

  /// `易码/xxx.md` 这样的完整展示名。
  String get display => group.isEmpty ? name : '$group/$name';

  /// 优先展示 meta.json 里的真实标题。
  String get label {
    final String t = (title ?? '').trim();
    return t.isEmpty ? name : t;
  }

  /// 为标题为空的图片笔记兜底一个可读名字。
  String get resolvedLabel {
    final String l = label;
    if (l.isNotEmpty) return l;
    if (images.isNotEmpty) return '图片笔记';
    return name;
  }

  NutstoreEntry copyWith({
    String? title,
    String? group,
    List<String>? images,
  }) =>
      NutstoreEntry(
        url: url,
        name: name,
        group: group ?? this.group,
        title: title ?? this.title,
        images: images ?? this.images,
        isDir: isDir,
        size: size,
        modified: modified,
      );
}

class NutstoreImportService {
  NutstoreImportService({
    required this.server,
    required this.username,
    required this.password,
  });

  final String server;
  final String username;
  final String password;

  /// 需要拉取的目录清单。
  static const List<NutstoreSource> sources = <NutstoreSource>[
    NutstoreSource('易码', assetDirs: <String>['assets']),
    NutstoreSource(
      'hnote-data-v2',
      subdirs: <String>['notes', '蜜蜂便签'],
      assetDirs: <String>['res'],
      skipFiles: <String>{'meta.json'},
      metaIndex: true,
    ),
  ];

  /// 二进制后缀，直接跳过。
  static const Set<String> _binaryExt = <String>{
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', 'svg', 'heic', 'tiff',
    'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'amr',
    'mp4', 'mov', 'avi', 'mkv', 'webm', '3gp',
    'zip', 'rar', '7z', 'gz', 'bz2', 'xz', 'tar',
    'apk', 'jar', 'dex', 'so', 'dll', 'exe',
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
    'ttf', 'otf', 'woff', 'woff2', 'db', 'sqlite',
  };

  /// 可识别为图片的后缀。
  static const Set<String> imageExt = <String>{
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic',
  };

  static bool looksPlaintext(String name) {
    final int i = name.lastIndexOf('.');
    if (i < 0) return true;
    return !_binaryExt.contains(name.substring(i + 1).toLowerCase());
  }

  static bool looksImage(String name) {
    final int i = name.lastIndexOf('.');
    if (i < 0) return false;
    return imageExt.contains(name.substring(i + 1).toLowerCase());
  }

  static String stem(String name) {
    final int i = name.lastIndexOf('.');
    return i <= 0 ? name : name.substring(0, i);
  }

  static String extOf(String name) {
    final int i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  String get _base {
    final String s =
        server.trim().isEmpty ? 'https://dav.jianguoyun.com/dav/' : server.trim();
    return s.endsWith('/') ? s : '$s/';
  }

  Dio _newDio() {
    final String token =
        'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 20),
        headers: <String, dynamic>{
          'Authorization': token,
          'User-Agent': 'ThoughtEcho-Custom/4.1.0',
        },
      ),
    );
  }

  // ── 单文件 ────────────────────────────────────────────────

  Future<String> download(NutstoreEntry entry) async {
    final List<int>? data = await downloadBytes(entry.url);
    if (data == null || data.isEmpty) return '';
    try {
      return utf8.decode(data);
    } catch (_) {
      return utf8.decode(data, allowMalformed: true);
    }
  }

  Future<List<int>?> downloadBytes(String url) async {
    final Dio dio = _newDio();
    final Response<List<int>> resp = await dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    return resp.data;
  }

  // ── 扫描 ──────────────────────────────────────────────────

  /// 扫描结果：文档列表 + 「图片文件名 -> 下载地址」索引。
  Future<NutstoreScanResult> scan() async {
    final Dio dio = _newDio();
    final List<NutstoreEntry> root = await _list(dio, _base, '');
    final List<NutstoreEntry> out = <NutstoreEntry>[];
    final Map<String, String> assets = <String, String>{};

    for (final NutstoreSource spec in sources) {
      NutstoreEntry? dir;
      for (final NutstoreEntry e in root) {
        if (e.isDir && e.name == spec.name) {
          dir = e;
          break;
        }
      }
      if (dir == null) continue;

      Map<String, NutstoreMetaInfo> metas = <String, NutstoreMetaInfo>{};
      if (spec.metaIndex) {
        metas = await _metaIndex(dio, dir.url);
      }

      List<NutstoreEntry> kids;
      try {
        kids = await _list(dio, dir.url, spec.name);
      } catch (_) {
        continue;
      }

      // 资源目录：图片文件名 -> URL
      for (final String assetDir in spec.assetDirs) {
        for (final NutstoreEntry e in kids) {
          if (!e.isDir || e.name != assetDir) continue;
          try {
            final List<NutstoreEntry> files =
                await _list(dio, e.url, '${spec.name}/$assetDir');
            for (final NutstoreEntry f in files) {
              if (!f.isDir && looksImage(f.name)) {
                // 同时按「纯文件名」和「相对路径」建索引：
                // hnote 的 meta.json 里存的是 res/xxx.jpg 这种相对路径，
                // 只按文件名建键会导致图片永远匹配不上。
                assets.putIfAbsent(f.name, () => f.url);
                assets.putIfAbsent('$assetDir/${f.name}', () => f.url);
              }
            }
          } catch (_) {
            // 资源目录读取失败不影响正文导入。
          }
        }
      }

      _collect(kids, out, spec, metas);

      for (final String sub in spec.subdirs) {
        NutstoreEntry? sd;
        for (final NutstoreEntry e in kids) {
          if (e.isDir && e.name == sub) {
            sd = e;
            break;
          }
        }
        if (sd == null) continue;
        try {
          final List<NutstoreEntry> sk =
              await _list(dio, sd.url, '${spec.name}/$sub');
          _collect(sk, out, spec, metas);
        } catch (_) {
          // 单个子目录失败不影响整体。
        }
      }
    }
    return NutstoreScanResult(documents: out, assets: assets);
  }

  void _collect(
    List<NutstoreEntry> kids,
    List<NutstoreEntry> out,
    NutstoreSource spec,
    Map<String, NutstoreMetaInfo> metas,
  ) {
    for (final NutstoreEntry e in kids) {
      if (e.isDir) continue;
      if (e.name.startsWith('.')) continue;
      if (spec.skipFiles.contains(e.name)) continue;
      if (!looksPlaintext(e.name)) continue;
      final NutstoreMetaInfo? meta = metas[stem(e.name)];
      out.add(
        NutstoreEntry(
          url: e.url,
          name: e.name,
          group: e.group,
          size: e.size,
          modified: e.modified,
          title: meta?.title,
          images: meta?.images ?? const <String>[],
        ),
      );
    }
  }

  /// 读取 hnote-data-v2/meta.json，建立 `objectId -> 标题/图片` 映射。
  Future<Map<String, NutstoreMetaInfo>> _metaIndex(
    Dio dio,
    String dirUrl,
  ) async {
    final Map<String, NutstoreMetaInfo> map = <String, NutstoreMetaInfo>{};
    try {
      final List<int>? data = await downloadBytes('${dirUrl}meta.json');
      if (data == null || data.isEmpty) return map;
      final Object? decoded = jsonDecode(utf8.decode(data, allowMalformed: true));
      if (decoded is! Map) return map;
      final Object? notes = decoded['notes'];
      if (notes is! List) return map;
      for (final Object? n in notes) {
        if (n is! Map) continue;
        final String id = (n['objectId'] ?? '').toString();
        if (id.isEmpty) continue;
        final String title = (n['title'] ?? '').toString().trim();
        final List<String> images = <String>[];
        final Object? rawImages = n['images'];
        if (rawImages is String && rawImages.trim().isNotEmpty) {
          for (final String part in rawImages.split('|')) {
            final String p = part.trim();
            if (p.isNotEmpty) images.add(p);
          }
        } else if (rawImages is List) {
          for (final Object? p in rawImages) {
            final String s = (p ?? '').toString().trim();
            if (s.isNotEmpty) images.add(s);
          }
        }
        map[id] = NutstoreMetaInfo(
          title: title.isEmpty ? null : title,
          images: images,
        );
      }
    } catch (_) {
      // 索引读取失败时退化为文件名。
    }
    return map;
  }

  // ── WebDAV PROPFIND ───────────────────────────────────────

  Future<List<NutstoreEntry>> _list(
    Dio dio,
    String url,
    String group,
  ) async {
    const String body = '<?xml version="1.0" encoding="utf-8"?>'
        '<d:propfind xmlns:d="DAV:"><d:prop>'
        '<d:getcontentlength/><d:getlastmodified/><d:resourcetype/>'
        '</d:prop></d:propfind>';

    final Response<dynamic> resp = await dio.request<dynamic>(
      url,
      data: body,
      options: Options(
        method: 'PROPFIND',
        responseType: ResponseType.plain,
        headers: <String, dynamic>{
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        validateStatus: (int? s) => s != null && s < 400,
      ),
    );

    final String raw = resp.data?.toString() ?? '';
    if (raw.isEmpty) return <NutstoreEntry>[];

    final Uri origin = Uri.parse(url);
    final String originPrefix =
        '${origin.scheme}://${origin.host}${origin.port == 80 || origin.port == 443 ? '' : ':${origin.port}'}';

    final List<NutstoreEntry> out = <NutstoreEntry>[];
    final RegExp reResp = RegExp(
      r'<(?:[A-Za-z0-9_.-]+:)?response\b[^>]*>(.*?)</(?:[A-Za-z0-9_.-]+:)?response>',
      dotAll: true,
    );

    for (final RegExpMatch m in reResp.allMatches(raw)) {
      final String block = m.group(1) ?? '';
      final String href = _tag(block, 'href');
      if (href.isEmpty) continue;

      final bool isDir =
          RegExp(r'<(?:[A-Za-z0-9_.-]+:)?collection\b').hasMatch(block);

      final String full = href.startsWith('http')
          ? href
          : '$originPrefix${href.startsWith('/') ? href : '/$href'}';
      final String self = url.endsWith('/') ? url : '$url/';
      if (full == url || full == self || '$full/' == self) continue;

      String decoded;
      try {
        decoded = Uri.decodeComponent(href);
      } catch (_) {
        decoded = href;
      }
      final String trimmed = decoded.endsWith('/')
          ? decoded.substring(0, decoded.length - 1)
          : decoded;
      final int k = trimmed.lastIndexOf('/');
      final String name = k >= 0 ? trimmed.substring(k + 1) : trimmed;
      if (name.isEmpty) continue;

      out.add(
        NutstoreEntry(
          url: full,
          name: name,
          group: group,
          isDir: isDir,
          size: int.tryParse(_tag(block, 'getcontentlength')) ?? 0,
          modified: _parseDate(_tag(block, 'getlastmodified')),
        ),
      );
    }
    return out;
  }

  /// 从 XML 片段里取第一个简单标签的文本。
  static String _tag(String block, String name) {
    final RegExp re = RegExp(
      '<(?:[A-Za-z0-9_.-]+:)?$name\\b[^>]*>(.*?)</(?:[A-Za-z0-9_.-]+:)?$name>',
      dotAll: true,
    );
    final RegExpMatch? m = re.firstMatch(block);
    if (m == null) return '';
    String v = m.group(1) ?? '';
    if (v.contains('<')) {
      v = v.replaceAll(RegExp(r'<[^>]*>'), '');
    }
    return v.trim();
  }

  /// 解析 RFC1123（`Mon, 05 Oct 2026 10:00:00 GMT`）形式的时间。
  static DateTime? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    final RegExpMatch? m = RegExp(
      r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(raw);
    if (m == null) return DateTime.tryParse(raw);
    const Map<String, int> months = <String, int>{
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final int? mo = months[m.group(2)!.toLowerCase()];
    if (mo == null) return null;
    try {
      return DateTime.utc(
        int.parse(m.group(3)!),
        mo,
        int.parse(m.group(1)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6)!),
      ).toLocal();
    } catch (_) {
      return null;
    }
  }
}

/// 扫描结果。
class NutstoreScanResult {
  const NutstoreScanResult({required this.documents, required this.assets});

  final List<NutstoreEntry> documents;

  /// 图片文件名 -> 下载地址。
  final Map<String, String> assets;
}

import 'dart:convert';

import 'package:dio/dio.dart';

/// 定制版：坚果云明文文档读取服务
///
/// 负责通过 WebDAV 列出并下载「坚果云/易码」与「坚果云/hnote-data-v2」
/// 下的明文文档（.md / .txt 等），供导入页写入便签库。
class NutstoreSource {
  const NutstoreSource(
    this.name, {
    this.subdirs = const <String>[],
    this.skipFiles = const <String>{},
    this.titleIndex = false,
  });

  /// 坚果云根目录下的目录名。
  final String name;

  /// 需要一并扫描的子目录（相对 [name]）。
  final List<String> subdirs;

  /// 需要跳过的文件名（例如 hnote 的 meta.json 索引本身不是笔记）。
  final Set<String> skipFiles;

  /// 是否读取 meta.json 还原真实标题。
  final bool titleIndex;
}

/// 一个可导入的远端文档。
class NutstoreEntry {
  const NutstoreEntry({
    required this.url,
    required this.name,
    required this.group,
    this.title,
    this.isDir = false,
    this.size = 0,
    this.modified,
  });

  final String url;
  final String name;
  final String group;
  final String? title;
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

  NutstoreEntry copyWith({String? title, String? group}) => NutstoreEntry(
        url: url,
        name: name,
        group: group ?? this.group,
        title: title ?? this.title,
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
    NutstoreSource('易码'),
    NutstoreSource(
      'hnote-data-v2',
      subdirs: <String>['notes', '蜜蜂便签'],
      skipFiles: <String>{'meta.json'},
      titleIndex: true,
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

  static bool looksPlaintext(String name) {
    final int i = name.lastIndexOf('.');
    if (i < 0) return true;
    return !_binaryExt.contains(name.substring(i + 1).toLowerCase());
  }

  static String _stem(String name) {
    final int i = name.lastIndexOf('.');
    return i <= 0 ? name : name.substring(0, i);
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
        receiveTimeout: const Duration(seconds: 60),
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
    final Dio dio = _newDio();
    final Response<List<int>> resp = await dio.get<List<int>>(
      entry.url,
      options: Options(responseType: ResponseType.bytes),
    );
    final List<int>? data = resp.data;
    if (data == null || data.isEmpty) return '';
    try {
      return utf8.decode(data);
    } catch (_) {
      return utf8.decode(data, allowMalformed: true);
    }
  }

  // ── 扫描 ──────────────────────────────────────────────────

  /// 列出所有可导入的明文文档。
  Future<List<NutstoreEntry>> scan() async {
    final Dio dio = _newDio();
    final List<NutstoreEntry> root = await _list(dio, _base, '');
    final List<NutstoreEntry> out = <NutstoreEntry>[];

    for (final NutstoreSource spec in sources) {
      NutstoreEntry? dir;
      for (final NutstoreEntry e in root) {
        if (e.isDir && e.name == spec.name) {
          dir = e;
          break;
        }
      }
      if (dir == null) continue;

      Map<String, String> titles = <String, String>{};
      if (spec.titleIndex) {
        titles = await _titleIndex(dio, dir.url);
      }

      List<NutstoreEntry> kids;
      try {
        kids = await _list(dio, dir.url, spec.name);
      } catch (_) {
        continue;
      }
      _collect(kids, out, spec, titles);

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
          _collect(sk, out, spec, titles);
        } catch (_) {
          // 单个子目录失败不影响整体。
        }
      }
    }
    return out;
  }

  void _collect(
    List<NutstoreEntry> kids,
    List<NutstoreEntry> out,
    NutstoreSource spec,
    Map<String, String> titles,
  ) {
    for (final NutstoreEntry e in kids) {
      if (e.isDir) continue;
      if (e.name.startsWith('.')) continue;
      if (spec.skipFiles.contains(e.name)) continue;
      if (!looksPlaintext(e.name)) continue;
      final String? title = titles[_stem(e.name)];
      out.add(title == null ? e : e.copyWith(title: title));
    }
  }

  /// 读取 hnote-data-v2/meta.json，建立 `objectId -> 标题` 映射。
  Future<Map<String, String>> _titleIndex(Dio dio, String dirUrl) async {
    final Map<String, String> map = <String, String>{};
    try {
      final Response<List<int>> resp = await dio.get<List<int>>(
        '${dirUrl}meta.json',
        options: Options(responseType: ResponseType.bytes),
      );
      final List<int>? data = resp.data;
      if (data == null || data.isEmpty) return map;
      final Object? decoded = jsonDecode(utf8.decode(data, allowMalformed: true));
      if (decoded is! Map) return map;
      final Object? notes = decoded['notes'];
      if (notes is! List) return map;
      for (final Object? n in notes) {
        if (n is! Map) continue;
        final String id = (n['objectId'] ?? '').toString();
        final String title = (n['title'] ?? '').toString().trim();
        if (id.isNotEmpty && title.isNotEmpty) map[id] = title;
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

      final bool isDir = RegExp(r'<(?:[A-Za-z0-9_.-]+:)?collection\b')
          .hasMatch(block);

      String full = href.startsWith('http')
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
      final String trimmed =
          decoded.endsWith('/') ? decoded.substring(0, decoded.length - 1) : decoded;
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

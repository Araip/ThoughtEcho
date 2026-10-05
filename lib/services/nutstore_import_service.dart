import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

/// 坚果云（WebDAV）明文文档导入服务 —— 定制版
///
/// 扫描「坚果云/易码」「坚果云/hnote-data-v2」两个目录下的明文文档
/// （.md / .txt / .markdown 以及无后缀纯文本），下载后逐条导入便签库。
class NutstoreImportService {
  NutstoreImportService({
    required this.server,
    required this.username,
    required this.password,
  });

  /// WebDAV 根地址，例如 https://dav.jianguoyun.com/dav/
  final String server;
  final String username;
  final String password;

  /// 需要拉取的两个目录。
  static const List<String> targetDirs = <String>['易码', 'hnote-data-v2'];

  static const String _propfindBody = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:getcontentlength/><d:getlastmodified/><d:resourcetype/>'
      '</d:prop></d:propfind>';

  Dio _newDio() => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 30),
          responseType: ResponseType.plain,
          validateStatus: (int? code) => code != null && code < 400,
          followRedirects: true,
        ),
      );

  Options get _propfindOptions => Options(
        method: 'PROPFIND',
        headers: <String, dynamic>{
          'Authorization': _auth,
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        responseType: ResponseType.plain,
      );

  Options get _getOptions => Options(
        method: 'GET',
        headers: <String, dynamic>{'Authorization': _auth},
        responseType: ResponseType.plain,
      );

  String get _auth =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  String get _rootUrl {
    final String s = server.endsWith('/') ? server : '$server/';
    return s;
  }

  /// 扫描两个目标目录，返回可导入的明文文件清单。
  Future<List<NutstoreEntry>> scan() async {
    final Dio dio = _newDio();
    final List<NutstoreEntry> rootEntries = await _list(dio, _rootUrl);
    final List<NutstoreEntry> result = <NutstoreEntry>[];

    for (final NutstoreEntry dir in rootEntries) {
      if (!dir.isDir) continue;
      if (!targetDirs.contains(dir.name)) continue;
      try {
        final List<NutstoreEntry> children = await _list(dio, dir.url);
        for (final NutstoreEntry child in children) {
          if (child.isDir) continue;
          if (!_looksPlaintext(child.name)) continue;
          result.add(
            NutstoreEntry(
              url: child.url,
              name: child.name,
              isDir: false,
              size: child.size,
              modified: child.modified,
              dir: dir.name,
            ),
          );
        }
      } catch (_) {
        // 单个目录失败不影响另一个
      }
    }
    return result;
  }

  /// 下载单个文件并返回 UTF-8 文本。
  Future<String> download(NutstoreEntry entry) async {
    final Dio dio = _newDio();
    final Response<dynamic> resp = await dio.get<dynamic>(
      entry.url,
      options: _getOptions,
    );
    final dynamic data = resp.data;
    if (data is List<int>) return utf8.decode(data, allowMalformed: true);
    return data?.toString() ?? '';
  }

  Future<List<NutstoreEntry>> _list(Dio dio, String url) async {
    final Response<dynamic> resp = await dio.request<dynamic>(
      url,
      data: _propfindBody,
      options: _propfindOptions,
    );
    final String body = resp.data?.toString() ?? '';
    if (body.trim().isEmpty) return const <NutstoreEntry>[];

    final XmlDocument doc = XmlDocument.parse(body);
    final List<NutstoreEntry> out = <NutstoreEntry>[];

    for (final XmlElement response in doc.descendants
        .whereType<XmlElement>()
        .where((XmlElement e) => e.name.local == 'response')) {
      String? href;
      bool isDir = false;
      int size = 0;
      DateTime? modified;

      for (final XmlElement el in response.descendants.whereType<XmlElement>()) {
        switch (el.name.local) {
          case 'href':
            href ??= el.innerText.trim();
            break;
          case 'collection':
            isDir = true;
            break;
          case 'getcontentlength':
            size = int.tryParse(el.innerText.trim()) ?? 0;
            break;
          case 'getlastmodified':
            modified = _parseHttpDate(el.innerText.trim());
            break;
        }
      }
      if (href == null || href.isEmpty) continue;

      final Uri? uri = Uri.tryParse(href);
      String name = uri != null && uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : href;
      name = Uri.decodeComponent(name);
      if (name.isEmpty) continue;

      // 跳过集合自身的 href（目录条目本身）
      final String full =
          href.startsWith('http') ? href : '${Uri.parse(_rootUrl).origin}$href';
      if (full == url || '$full/' == url) continue;

      out.add(
        NutstoreEntry(
          url: full,
          name: name,
          isDir: isDir,
          size: size,
          modified: modified,
        ),
      );
    }
    return out;
  }

  DateTime? _parseHttpDate(String raw) {
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  static const Set<String> _binaryExt = <String>{
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico',
    'zip', 'gz', '7z', 'rar', 'apk', 'exe', 'bin',
    'mp3', 'wav', 'm4a', 'mp4', 'mov', 'avi', 'pdf',
    'db', 'sqlite', 'ttf', 'otf', 'woff', 'woff2',
  };

  static const Set<String> _plainExt = <String>{
    'md', 'markdown', 'txt', 'text', 'json', 'csv', 'log', 'org', 'html', 'htm',
  };

  static bool _looksPlaintext(String name) {
    final int dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      // 无后缀：按纯文本处理
      return true;
    }
    final String ext = name.substring(dot + 1).toLowerCase();
    return !_binaryExt.contains(ext);
  }
}

/// 一个 WebDAV 条目。
class NutstoreEntry {
  const NutstoreEntry({
    required this.url,
    required this.name,
    required this.isDir,
    this.size = 0,
    this.modified,
    this.dir,
  });

  final String url;
  final String name;
  final bool isDir;
  final int size;
  final DateTime? modified;

  /// 所属目标目录（易码 / hnote-data-v2）。
  final String? dir;

  String get display => dir == null ? name : '$dir/$name';
}

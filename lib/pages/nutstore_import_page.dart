import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quote_model.dart';
import '../services/database_service.dart';
import '../services/nutstore_import_service.dart';
import '../services/webdav_sync_service.dart';

/// 定制版：坚果云文档导入（独立页面入口）
class NutstoreImportPage extends StatelessWidget {
  const NutstoreImportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('坚果云文档导入')),
      body: const SafeArea(child: NutstoreImportBody()),
    );
  }
}

/// 定制版：坚果云文档导入正文（可直接嵌入云同步页）
///
/// 账号不再单独填写，直接复用「云同步」里已经保存的坚果云配置，
/// 因此同一套账号只需输入一次。
class NutstoreImportBody extends StatefulWidget {
  const NutstoreImportBody({super.key, this.embedded = false});

  /// 嵌入其它滚动页面时置为 true，避免嵌套滚动冲突。
  final bool embedded;

  @override
  State<NutstoreImportBody> createState() => _NutstoreImportBodyState();
}

class _NutstoreImportBodyState extends State<NutstoreImportBody> {
  static const String _kDone = 'nutstore_import_done';
  static const String _defaultServer = 'https://dav.jianguoyun.com/dav/';

  List<NutstoreEntry> _entries = <NutstoreEntry>[];
  final Map<String, String> _assets = <String, String>{};

  /// 分组名 -> 标签 id 缓存，避免重复建标签。
  final Map<String, String> _groupTagIds = <String, String>{};

  bool _busy = false;
  String _status = '点「扫描目录」开始；账号沿用上方云同步设置，不用重复填写。';

  // ── 凭据（复用云同步设置） ────────────────────────────────

  Future<NutstoreImportService?> _buildService() async {
    final WebDAVSyncService sync = context.read<WebDAVSyncService>();
    final String server =
        sync.url.trim().isEmpty ? _defaultServer : sync.url.trim();
    final String user = sync.username.trim();
    String password = '';
    try {
      password = (await sync.getPassword())?.trim() ?? '';
    } catch (_) {
      password = '';
    }
    if (user.isEmpty || password.isEmpty) return null;
    return NutstoreImportService(
      server: server,
      username: user,
      password: password,
    );
  }

  static const String _needAccount = '请先在上方「云同步」里填好服务器地址、坚果云账号和应用密码并保存，再回来导入。';

  // ── 资源匹配 ──────────────────────────────────────────────

  /// 把正文/元数据里出现的图片引用解析成可下载地址。
  ///
  /// 兼容三类写法：纯文件名（`a.jpg`）、相对路径（`res/a.jpg`）、
  /// 以及被 URL 编码过的路径（`res/a%20b.jpg`）。
  String? _resolveAsset(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final List<String> candidates = <String>[];
    void add(String value) {
      final String v = value.trim();
      if (v.isNotEmpty && !candidates.contains(v)) candidates.add(v);
    }

    add(trimmed);
    try {
      add(Uri.decodeComponent(trimmed));
    } catch (_) {
      // 解码失败时保留原样。
    }
    // 去掉 query / fragment 后再补一轮
    final int cut = trimmed.indexOf(RegExp(r'[?#]'));
    if (cut > 0) add(trimmed.substring(0, cut));
    // 所有候选都补一份「只留文件名」的版本
    for (final String c in List<String>.from(candidates)) {
      final String base = c.split('/').last.split(r'\').last;
      add(base);
    }

    for (final String c in candidates) {
      final String? url = _assets[c];
      if (url != null) return url;
    }
    return null;
  }

  /// 从正文里提取图片引用：markdown、HTML、以及裸文件名。
  static List<String> _extractImageRefs(String text) {
    final List<String> out = <String>[];
    void add(String? value) {
      final String v = (value ?? '').trim();
      if (v.isNotEmpty && !out.contains(v)) out.add(v);
    }

    for (final RegExpMatch m
        in RegExp(r'!\[[^\]]*\]\(([^)]+)\)').allMatches(text)) {
      add(m.group(1));
    }
    for (final RegExpMatch m in RegExp(
      "<img[^>]+src=[\"']([^\"']+)[\"']",
      caseSensitive: false,
    ).allMatches(text)) {
      add(m.group(1));
    }
    for (final RegExpMatch m in RegExp(
      r'([A-Za-z0-9_\-./]+\.(?:jpe?g|png|gif|webp|bmp))',
      caseSensitive: false,
    ).allMatches(text)) {
      add(m.group(1));
    }
    return out;
  }

  /// 图片已经成功内嵌时，把正文里的占位符清掉，避免重复显示 `# [图片]`。
  static String _stripImagePlaceholders(String input) {
    String out = input;
    out = out.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
    out = out.replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), '');
    out = out.replaceAll(
      RegExp(r'^[ \t]*#?[ \t]*\[图片\][ \t]*$', multiLine: true),
      '',
    );
    out = out.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return out.trim();
  }

  // ── 分组标签 ──────────────────────────────────────────────

  /// 取来源的第一段作为分组名，避免 notes/res 之类的子目录拆出碎片标签。
  static String _groupName(String group) {
    final String g = group.trim();
    if (g.isEmpty) return '坚果云';
    return g.split('/').first;
  }

  /// 按分组名拿到（必要时创建）标签 id，让导入的便签真的归入分组。
  Future<String?> _ensureGroupTag(DatabaseService db, String group) async {
    final String name = _groupName(group);
    if (name.isEmpty) return null;
    final String? cached = _groupTagIds[name];
    if (cached != null) return cached;
    try {
      final List<dynamic> tags = await db.getTags();
      for (final dynamic t in tags) {
        if (t.name == name) {
          final String id = t.id as String;
          _groupTagIds[name] = id;
          return id;
        }
      }
      await db.addTag(name);
      final List<dynamic> again = await db.getTags();
      for (final dynamic t in again) {
        if (t.name == name) {
          final String id = t.id as String;
          _groupTagIds[name] = id;
          return id;
        }
      }
    } catch (_) {
      // 建标签失败不影响正文导入。
    }
    return null;
  }

  // ── 扫描 ─────────────────────────────────────────────────

  Future<void> _scan() async {
    final NutstoreImportService? service = await _buildService();
    if (!mounted) return;
    if (service == null) {
      setState(() => _status = _needAccount);
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在扫描…';
    });
    try {
      final NutstoreScanResult res = await service.scan();
      if (!mounted) return;
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final Set<String> done =
          (sp.getStringList(_kDone) ?? <String>[]).toSet();
      final int fresh = res.documents
          .where((NutstoreEntry e) => !done.contains(e.url))
          .length;
      final int withImages =
          res.documents.where((NutstoreEntry e) => e.images.isNotEmpty).length;
      setState(() {
        _entries = res.documents;
        _assets
          ..clear()
          ..addAll(res.assets);
        _busy = false;
        _status = res.documents.isEmpty
            ? '没有找到可导入的明文文档（检查账号密码 / 目录名）。'
            : '共 ${res.documents.length} 个文档（$withImages 个带图片索引），'
                '其中 $fresh 个尚未导入；可用图片 ${res.assets.length} 张。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '扫描失败：$e';
      });
    }
  }

  // ── 图片落盘 ─────────────────────────────────────────────

  Future<String> _saveImage(String name, List<int> bytes) async {
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(p.join(docs.path, 'media', 'images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final String base = name.split('/').last.split(r'\').last;
    final String safe =
        'nutstore_${DateTime.now().millisecondsSinceEpoch}_${base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';
    final File f = File(p.join(dir.path, safe));
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  /// 组装 Quill Delta：标题 + 正文 + 图片嵌入。
  String _buildDelta(String title, String body, List<String> images) {
    final String head = body.trim();
    final String t = title.trim();
    final String text = t.isEmpty ? head : '# $t\n\n$head';
    final List<Object> ops = <Object>[];
    if (text.isNotEmpty) {
      ops.add(<String, Object>{'insert': '$text\n'});
    }
    for (final String img in images) {
      ops.add(<String, Object>{
        'insert': <String, Object>{'image': img},
      });
      ops.add(<String, Object>{'insert': '\n'});
    }
    return jsonEncode(ops);
  }

  String _plain(String title, String body, int imageCount) {
    final String head = body.trim();
    final String t = title.trim();
    final String base =
        t.isEmpty ? head : (head.isEmpty ? t : '$t\n\n$head');
    if (imageCount == 0) return base;
    return '$base\n\n[图片 ×$imageCount]';
  }

  // ── 导入 ─────────────────────────────────────────────────

  Future<void> _importEntries(List<NutstoreEntry> targets) async {
    if (targets.isEmpty) {
      setState(() => _status = '没有可导入的文档。');
      return;
    }
    final NutstoreImportService? service = await _buildService();
    if (!mounted) return;
    if (service == null) {
      setState(() => _status = _needAccount);
      return;
    }
    final DatabaseService db = context.read<DatabaseService>();
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final Set<String> doneSet =
        (sp.getStringList(_kDone) ?? <String>[]).toSet();

    setState(() {
      _busy = true;
      _status = '正在导入…';
    });

    int ok = 0;
    int skipped = 0;
    int imageCount = 0;
    int missingImages = 0;
    final List<String> failed = <String>[];

    for (final NutstoreEntry e in targets) {
      if (doneSet.contains(e.url)) {
        skipped++;
        continue;
      }
      try {
        final String text = await service.download(e);
        final String title = e.resolvedLabel;

        // 候选图片 = 元数据索引 + 正文里出现的引用（覆盖没有 meta.json 的源）。
        final List<String> refs = <String>[];
        void addRef(String value) {
          final String v = value.trim();
          if (v.isNotEmpty && !refs.contains(v)) refs.add(v);
        }

        for (final String s in e.images) {
          addRef(s);
        }
        for (final String s in _extractImageRefs(text)) {
          addRef(s);
        }

        final List<String> localImages = <String>[];
        for (final String ref in refs) {
          final String? url = _resolveAsset(ref);
          if (url == null) {
            missingImages++;
            continue;
          }
          try {
            final List<int>? bytes = await service.downloadBytes(url);
            if (bytes == null || bytes.isEmpty) continue;
            localImages.add(await _saveImage(ref, bytes));
            imageCount++;
          } catch (_) {
            // 单张图片失败不影响其余内容。
          }
        }

        // 图片已内嵌时清掉正文里的占位符，否则保留让用户知道这里原本有图。
        final String body =
            localImages.isEmpty ? text : _stripImagePlaceholders(text);

        if (body.trim().isEmpty && localImages.isEmpty) {
          skipped++;
          continue;
        }

        // 按来源分组，让导入的便签真的归入分组标签。
        final String? tagId = await _ensureGroupTag(db, e.group);

        final String when = (e.modified ?? DateTime.now()).toIso8601String();
        await db.addQuote(
          Quote(
            content: _plain(title, body, localImages.length),
            deltaContent: _buildDelta(title, body, localImages),
            // 关键：渲染侧（QuoteContent.build）只有当 editSource == 'fullscreen'
            // 时才会走富文本渲染分支，否则退回纯文本、内嵌图片全部不显示。
            // 编辑器保存时都会写这个字段，导入也必须写，否则图片永远看不到。
            editSource: 'fullscreen',
            date: when,
            source: '坚果云/${e.display}',
            lastModified: when,
            // 关键：分类页（getUserQuotes(categoryId:)）过滤的是 quotes.category_id，
            // 只写 quote_tags 关联表的话，便签在分类里根本不会出现。
            categoryId: tagId,
            tagIds: tagId == null ? const <String>[] : <String>[tagId],
          ),
        );
        doneSet.add(e.url);
        ok++;
        if (mounted) {
          setState(
            () => _status =
                '已导入 $ok 个（图片 $imageCount 张）…（$title）',
          );
        }
      } catch (err) {
        failed.add('${e.display}: $err');
      }
    }

    await sp.setStringList(_kDone, doneSet.toList());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = '导入完成：新增 $ok，跳过 $skipped，图片 $imageCount 张，'
          '未匹配图片 $missingImages 处，失败 ${failed.length}。'
          '${failed.isEmpty ? '' : '\n失败示例：${failed.first}'}';
    });
  }

  Future<void> _resetHistory() async {
    final SharedPreferences sp = await SharedPreferences.getInstance();
    await sp.remove(_kDone);
    if (!mounted) return;
    setState(() => _status = '已清除导入记录，下次会重新导入全部文档。');
  }

  // ── UI ───────────────────────────────────────────────────

  Widget _buildAccountBar(ThemeData theme) {
    return Consumer<WebDAVSyncService>(
      builder: (BuildContext context, WebDAVSyncService sync, Widget? _) {
        final bool ready = sync.username.trim().isNotEmpty;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                ready ? Icons.check_circle_outline : Icons.info_outline,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ready
                      ? '使用云同步账号：${sync.username}（无需重复输入密码）'
                      : '尚未配置坚果云账号，请先在上方「云同步」里填写并保存。',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, List<NutstoreEntry>> groups =
        <String, List<NutstoreEntry>>{};
    for (final NutstoreEntry e in _entries) {
      groups.putIfAbsent(_groupName(e.group), () => <NutstoreEntry>[]).add(e);
    }

    return ListView(
      shrinkWrap: widget.embedded,
      physics: widget.embedded
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: widget.embedded
          ? const EdgeInsets.only(top: 4, bottom: 8)
          : const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: <Widget>[
        _buildAccountBar(theme),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.search),
                label: const Text('扫描目录'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _importEntries(_entries),
                icon: const Icon(Icons.download),
                label: const Text('全部导入'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(_status, style: theme.textTheme.bodyMedium),
        if (_entries.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _resetHistory,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('清除导入记录'),
            ),
          ),
        const Divider(height: 28),
        Text(
          '读取范围：坚果云/易码（顶层文档 + assets 图片）、'
          '坚果云/hnote-data-v2（notes、蜜蜂便签 + res 图片）。'
          '图片会复制到本机并内嵌进便签，同时按来源自动生成分组标签。',
          style: theme.textTheme.bodySmall,
        ),
        for (final MapEntry<String, List<NutstoreEntry>> g
            in groups.entries)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '分组：${g.key}（${g.value.length}）',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _importEntries(g.value),
                  child: const Text('导入本组'),
                ),
              ],
            ),
          ),
        for (final NutstoreEntry e in _entries)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              e.images.isEmpty ? Icons.description_outlined : Icons.image,
            ),
            title: Text(
              e.resolvedLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${e.display} · ${e.size} 字节'
              '${e.images.isEmpty ? '' : ' · 图片索引 ${e.images.length}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: _busy ? null : () => _importEntries(<NutstoreEntry>[e]),
          ),
      ],
    );
  }
}

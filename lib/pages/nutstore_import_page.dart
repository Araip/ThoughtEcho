import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quote_model.dart';
import '../services/database_service.dart';
import '../services/nutstore_import_service.dart';

/// 定制版：坚果云明文文档导入页
///
/// 从「坚果云/易码」「坚果云/hnote-data-v2」拉取明文文档并导入便签库。
class NutstoreImportPage extends StatefulWidget {
  const NutstoreImportPage({super.key});

  @override
  State<NutstoreImportPage> createState() => _NutstoreImportPageState();
}

class _NutstoreImportPageState extends State<NutstoreImportPage> {
  final TextEditingController _server = TextEditingController(
    text: 'https://dav.jianguoyun.com/dav/',
  );
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();

  static const String _kServer = 'nutstore_import_server';
  static const String _kUser = 'nutstore_import_user';
  static const String _kPass = 'nutstore_import_pass';
  static const String _kDone = 'nutstore_import_done';

  List<NutstoreEntry> _entries = <NutstoreEntry>[];
  bool _busy = false;
  String _status = '填写账号后点击「扫描目录」。';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final SharedPreferences sp = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _server.text = sp.getString(_kServer) ?? _server.text;
      _user.text = sp.getString(_kUser) ?? '';
      _pass.text = sp.getString(_kPass) ?? '';
    });
  }

  Future<void> _savePrefs() async {
    final SharedPreferences sp = await SharedPreferences.getInstance();
    await sp.setString(_kServer, _server.text.trim());
    await sp.setString(_kUser, _user.text.trim());
    await sp.setString(_kPass, _pass.text);
  }

  NutstoreImportService _service() => NutstoreImportService(
        server: _server.text.trim(),
        username: _user.text.trim(),
        password: _pass.text,
      );

  Future<void> _scan() async {
    if (_user.text.trim().isEmpty) {
      setState(() => _status = '请先填写坚果云账号（邮箱）。');
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在扫描…';
    });
    await _savePrefs();
    try {
      final List<NutstoreEntry> list = await _service().scan();
      if (!mounted) return;
      setState(() {
        _entries = list;
        _busy = false;
        _status = list.isEmpty
            ? '没有找到可导入的明文文档（检查账号密码 / 目录名）。'
            : '共找到 ${list.length} 个文档。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '扫描失败：$e';
      });
    }
  }

  Future<void> _importAll() async {
    if (_entries.isEmpty) {
      setState(() => _status = '请先扫描目录。');
      return;
    }
    final DatabaseService db = context.read<DatabaseService>();
    final SharedPreferences sp = await SharedPreferences.getInstance();
    final List<String> done = sp.getStringList(_kDone) ?? <String>[];
    final Set<String> doneSet = done.toSet();
    final NutstoreImportService service = _service();

    setState(() {
      _busy = true;
      _status = '正在导入…';
    });

    int ok = 0;
    int skipped = 0;
    final List<String> failed = <String>[];

    for (final NutstoreEntry e in _entries) {
      if (doneSet.contains(e.url)) {
        skipped++;
        continue;
      }
      try {
        final String text = await service.download(e);
        if (text.trim().isEmpty) {
          skipped++;
          continue;
        }
        final String when =
            (e.modified ?? DateTime.now()).toIso8601String();
        await db.addQuote(
          Quote(
            content: text,
            date: when,
            source: '坚果云/${e.display}',
            lastModified: when,
          ),
        );
        doneSet.add(e.url);
        ok++;
        if (mounted) {
          setState(() => _status = '已导入 $ok 个…（${e.display}）');
        }
      } catch (err) {
        failed.add('${e.display}: $err');
      }
    }

    await sp.setStringList(_kDone, doneSet.toList());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = '导入完成：新增 $ok，跳过 $skipped，失败 ${failed.length}。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('坚果云文档导入')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: <Widget>[
            TextField(
              controller: _server,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://dav.jianguoyun.com/dav/',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _user,
              decoration: const InputDecoration(
                labelText: '坚果云账号（邮箱）',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '应用密码',
                helperText: '坚果云 → 安全选项 → 添加应用密码',
              ),
            ),
            const SizedBox(height: 16),
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
                    onPressed: _busy ? null : _importAll,
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
            const Divider(height: 32),
            Text(
              '将读取 坚果云/易码 与 坚果云/hnote-data-v2 下的明文文档。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final NutstoreEntry e in _entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(e.display),
                subtitle: Text('${e.size} 字节'),
              ),
          ],
        ),
      ),
    );
  }
}

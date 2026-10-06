import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';

/// 定制版：编辑器工具栏分组顺序设置页。
/// 通过拖动手柄调整每个分组在工具栏中的前后顺序。
class EditorToolbarOrderPage extends StatefulWidget {
  const EditorToolbarOrderPage({super.key});

  @override
  State<EditorToolbarOrderPage> createState() =>
      _EditorToolbarOrderPageState();
}

class _EditorToolbarOrderPageState extends State<EditorToolbarOrderPage> {
  static const Map<String, String> _groupNames = <String, String>{
    'history': '撤销 / 重做',
    'basic': '加粗 · 斜体 · 下划线 · 删除线',
    'header': '标题',
    'font': '字号 · 字体',
    'color': '文字色 / 背景色',
    'alignment': '对齐方式',
    'list': '列表 · 缩进',
    'quote': '引用 · 代码块',
    'link': '链接',
    'media': '图片 · 视频 · 音频',
    'misc': '清除格式 · 查找',
  };

  static const Map<String, IconData> _groupIcons = <String, IconData>{
    'history': Icons.undo,
    'basic': Icons.format_bold,
    'header': Icons.title,
    'font': Icons.format_size,
    'color': Icons.palette_outlined,
    'alignment': Icons.format_align_left,
    'list': Icons.format_list_bulleted,
    'quote': Icons.format_quote,
    'link': Icons.link,
    'media': Icons.image_outlined,
    'misc': Icons.format_clear,
  };

  late List<String> _order;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _order = _readSettings();
  }

  List<String> _readSettings() {
    final SettingsService settings = context.read<SettingsService>();
    final List<String> configured = settings.editorToolbarGroupOrder;
    final List<String> recommended = <String>[
      for (final String id in SettingsService.defaultToolbarOrder)
        if (!configured.contains(id)) id,
    ];
    return <String>[...configured, ...recommended];
  }

  Future<void> _save() async {
    await context.read<SettingsService>().setEditorToolbarGroupOrder(_order);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('工具栏排序已保存'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _reset() async {
    await context
        .read<SettingsService>()
        .setEditorToolbarGroupOrder(SettingsService.defaultToolbarOrder);
    if (!mounted) return;
    setState(() {
      _order = List.of(SettingsService.defaultToolbarOrder);
      _dirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已恢复默认顺序'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑器工具栏排序'),
        actions: <Widget>[
          TextButton(
            onPressed: _dirty ? _save : null,
            child: const Text('保存'),
          ),
          IconButton(
            tooltip: '恢复默认',
            onPressed: _reset,
            icon: const Icon(Icons.restore),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '拖动每行右侧手柄调整工具组的前后顺序；'
              '「保存」后编辑器顶部工具栏即按此顺序显示。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              buildDefaultDragHandles: false,
              itemCount: _order.length,
              onReorder: (int oldIndex, int newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final String item = _order.removeAt(oldIndex);
                  _order.insert(newIndex, item);
                  _dirty = true;
                });
              },
              itemBuilder: (BuildContext context, int index) {
                final String id = _order[index];
                final String label = _groupNames[id] ?? id;
                final IconData icon = _groupIcons[id] ?? Icons.widgets_outlined;
                return Card(
                  key: ValueKey<String>('toolbar-group-$id'),
                  elevation: 0,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
                    title: Text(label),
                    trailing: ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
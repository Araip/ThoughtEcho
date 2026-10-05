import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_tag.dart';
import '../services/database_service.dart';

/// 定制版：通用标签选择底部弹窗。
///
/// 返回用户选中的 [NoteTag]；返回 null 表示取消。
Future<NoteTag?> showTagPicker(
  BuildContext context, {
  String? selectedId,
  String title = '选择标签',
  bool allowCreate = true,
}) {
  return showModalBottomSheet<NoteTag>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _TagPickerSheet(
      selectedId: selectedId,
      title: title,
      allowCreate: allowCreate,
    ),
  );
}

class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet({
    required this.selectedId,
    required this.title,
    required this.allowCreate,
  });

  final String? selectedId;
  final String title;
  final bool allowCreate;

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  final TextEditingController _newTagController = TextEditingController();
  List<NoteTag> _tags = <NoteTag>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<NoteTag> tags = await context.read<DatabaseService>().getTags();
      if (!mounted) return;
      setState(() {
        _tags = tags
            .where((NoteTag t) => t.id != DatabaseService.hiddenTagId)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tags = <NoteTag>[];
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final String name = _newTagController.text.trim();
    if (name.isEmpty) return;
    try {
      await context.read<DatabaseService>().addTag(name);
      _newTagController.clear();
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('新建标签失败')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.allowCreate)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _newTagController,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '新建标签…',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _create(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _create,
                        child: const Text('新建'),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_tags.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('还没有标签，可在上方新建。'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _tags.length,
                    itemBuilder: (BuildContext context, int index) {
                      final NoteTag tag = _tags[index];
                      final bool selected = tag.id == widget.selectedId;
                      return ListTile(
                        leading: Text(
                          _iconFor(tag),
                          style: const TextStyle(fontSize: 20),
                        ),
                        title: Text(tag.name),
                        trailing: selected
                            ? Icon(
                                Icons.check,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                        onTap: () => Navigator.of(context).pop(tag),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _iconFor(NoteTag tag) {
    final String? emoji = tag.icon;
    if (emoji != null && emoji.trim().isNotEmpty && emoji.length <= 4) {
      return emoji;
    }
    final String? name = tag.iconName;
    if (name != null && name.trim().isNotEmpty && name.length <= 4) {
      return name;
    }
    return '🏷️';
  }
}

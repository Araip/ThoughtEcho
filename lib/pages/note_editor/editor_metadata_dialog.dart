part of '../note_full_editor_page.dart';

/// Metadata editing bottom sheet dialog.
extension _NoteEditorMetadataDialog on _NoteFullEditorPageState {
  /// 定制版：输入并返回一个新标签名称。
  Future<String?> _promptNewTagName(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '标签名称'),
          onSubmitted: (String v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return null;
    final String name = result.trim();
    return name.isEmpty ? null : name;
  }

  Future<void> _showMetadataDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // 定制版：外层未传入标签时，主动从数据库加载，避免标签分组显示为空
    if (_metaDialogTags.isEmpty) {
      final List<NoteTag>? provided = widget.allTags;
      if (provided != null && provided.isNotEmpty) {
        _metaDialogTags = provided;
      } else {
        try {
          _metaDialogTags = await context.read<DatabaseService>().getTags();
        } catch (_) {
          _metaDialogTags = <NoteTag>[];
        }
      }
      _metaDialogTags = _metaDialogTags
          .where((NoteTag t) => t.id != DatabaseService.hiddenTagId)
          .toList();
      if (!mounted) return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppShapeTokens.of(context).dialogRadius),
        ),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void updateMetadataDialogState(VoidCallback fn) {
              setDialogState(fn);
              _updateState(() {});
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Row(
                        children: [
                          Text(
                            AppLocalizations.of(context).editMetadata,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            icon: const Icon(Icons.check),
                            label: Text(AppLocalizations.of(context).done),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          // 作者/作品输入
                          Text(
                            l10n.sourceInfo,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _metadataState.authorController,
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(
                                      context,
                                    ).authorPerson,
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppShapeTokens.of(context)
                                              .inputRadius),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 12,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _metadataState.workController,
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(
                                      context,
                                    ).workSource,
                                    prefixIcon: const Icon(
                                      Icons.menu_book_outlined,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppShapeTokens.of(context)
                                              .inputRadius),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                      horizontal: 12,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          const SizedBox(height: 24),

                          // 颜色选择
                          Text(
                            l10n.colorLabel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Material(
                            color: theme.colorScheme.surfaceContainerLow,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppShapeTokens.of(context).cardRadius),
                              side: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: ListTile(
                              title: Text(l10n.selectCardColorLabel),
                              subtitle: Text(
                                _metadataState.selectedColorHex == null
                                    ? l10n.noColor
                                    : l10n.colorSet,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: _metadataState.selectedColorHex != null
                                      ? Color(
                                          int.parse(
                                                _metadataState.selectedColorHex!
                                                    .substring(1),
                                                radix: 16,
                                              ) |
                                              0xFF000000,
                                        )
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color:
                                        _metadataState.selectedColorHex == null
                                            ? theme.colorScheme.outline
                                            : Colors.transparent,
                                  ),
                                ),
                                child: _metadataState.selectedColorHex == null
                                    ? Icon(
                                        Icons.block,
                                        size: 16,
                                        color: theme.colorScheme.outline,
                                      )
                                    : null,
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(
                                      AppShapeTokens.of(context).cardRadius),
                                ),
                              ),
                              onTap: () async {
                                // 使用async/await确保颜色选择完成后刷新UI
                                if (!context.mounted) return;
                                await _showCustomColorPicker(context);
                                // 强制刷新对话框UI以显示新选的颜色
                                if (mounted) {
                                  updateMetadataDialogState(() {});
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 24),

                          _buildMetadataLocationWeatherSection(
                            theme,
                            l10n,
                            updateMetadataDialogState,
                          ),
                          const SizedBox(height: 24),
                          // 标签选择
                          Row(
                            children: [
                              Text(
                                l10n.tagsLabel,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                l10n.selectedTagsCount(
                                    _metadataState.selectedTagIds.length),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Material(
                            color: theme.colorScheme.surfaceContainerLow,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppShapeTokens.of(context).cardRadius),
                              side: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: ExpansionTile(
                              title: Text(
                                AppLocalizations.of(context).selectTags,
                              ),
                              leading: const Icon(Icons.sell_outlined),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(
                                      AppShapeTokens.of(context).cardRadius),
                                ),
                              ),
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                16,
                              ),
                              children: [
                                // 搜索框
                                TextField(
                                  controller:
                                      _metadataState.tagSearchController,
                                  decoration: InputDecoration(
                                    hintText: AppLocalizations.of(
                                      context,
                                    ).searchTags,
                                    prefixIcon: const Icon(Icons.search),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppShapeTokens.of(context)
                                              .inputRadius),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 8.0,
                                      horizontal: 12.0,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    updateMetadataDialogState(() {
                                      _metadataState.tagSearchQuery =
                                          value.toLowerCase();
                                    });
                                  },
                                ),
                                const SizedBox(height: 8), // 标签列表
                                Container(
                                  constraints: const BoxConstraints(
                                    maxHeight: 200,
                                  ),
                                  child: SingleChildScrollView(
                                    child: Builder(
                                      builder: (context) {
                                        // 过滤标签
                                        final filteredTags =
                                            _metaDialogTags.where((tag) {
                                          return _metadataState
                                                  .tagSearchQuery.isEmpty ||
                                              tag
                                                  .localizedName(l10n)
                                                  .toLowerCase()
                                                  .contains(_metadataState
                                                      .tagSearchQuery);
                                        }).toList();

                                        return Wrap(
                                          spacing: 8.0,
                                          runSpacing: 8.0,
                                          children: <Widget>[
                                            if (filteredTags.isEmpty)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  vertical: 8,
                                                ),
                                                child: Text(
                                                  '还没有标签，点右侧「新建标签」',
                                                  style: TextStyle(
                                                    color: theme.colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                            ...filteredTags.map((tag) {
                                            final selected = _metadataState
                                                .selectedTagIds
                                                .contains(tag.id);
                                            return FilterChip(
                                              selected: selected,
                                              label: Text(
                                                tag.localizedName(l10n),
                                              ),
                                              avatar: _tagAvatarSmall(
                                                tag.iconName,
                                              ),
                                              onSelected: (bool value) {
                                                updateMetadataDialogState(() {
                                                  _metadataState.toggleTag(
                                                    tag.id,
                                                    selected: value,
                                                  );
                                                });
                                              },
                                              selectedColor: theme
                                                  .colorScheme.primaryContainer,
                                              checkmarkColor:
                                                  theme.colorScheme.primary,
                                            );
                                            }),
                                            ActionChip(
                                              avatar: const Icon(
                                                Icons.add,
                                                size: 18,
                                              ),
                                              label: const Text('新建标签'),
                                              onPressed: () async {
                                                final DatabaseService db =
                                                    context
                                                        .read<DatabaseService>();
                                                final String? name =
                                                    await _promptNewTagName(
                                                  context,
                                                );
                                                if (name == null) return;
                                                try {
                                                  await db.addTag(name);
                                                  _metaDialogTags =
                                                      (await db.getTags())
                                                          .where(
                                                            (NoteTag t) =>
                                                                t.id !=
                                                                DatabaseService
                                                                    .hiddenTagId,
                                                          )
                                                          .toList();
                                                } catch (_) {
                                                  return;
                                                }
                                                updateMetadataDialogState(
                                                  () {},
                                                );
                                              },
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 显示已选标签
                          if (_metadataState.selectedTagIds.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(
                                    AppShapeTokens.of(context).cardRadius),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.selectedTags,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8.0,
                                    runSpacing: 4.0,
                                    children: _metadataState.selectedTagIds
                                        .map((tagId) {
                                      final tag =
                                          _metaDialogTags.firstWhere(
                                        (t) => t.id == tagId,
                                        orElse: () => NoteTag(
                                          id: tagId,
                                          name: l10n.unknownTagWithId(
                                            tagId.substring(
                                              0,
                                              min(4, tagId.length),
                                            ),
                                          ),
                                          iconName: 'help_outline',
                                        ),
                                      );
                                      return Chip(
                                        label: Text(tag.localizedName(l10n)),
                                        avatar: _buildTagIcon(tag),
                                        onDeleted: () {
                                          updateMetadataDialogState(() {
                                            _metadataState.removeTag(tagId);
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );

    // 优化：对话框关闭后使用单次 setState 更新UI
    if (mounted) {
      _updateState(() {
        // 强制刷新所有状态
      });
    }
  }
}

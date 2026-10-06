import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_tag.dart';
import '../models/quote_model.dart';
import '../services/database_service.dart';
import '../services/smart_category_service.dart';
import '../widgets/tag_picker_sheet.dart';
import 'note_full_editor_page.dart';

/// 定制版：便签分类页
///
/// 作为应用的主页（替代原先的「每日一言」首页），按「分类 / 标签」聚合展示
/// 全部便签。点击某个分类即可进入该分类下的便签列表。
/// 「全部便签」只显示**未分类**的便签，方便知道还剩多少没有分类；
/// 支持一键本地「智能分类」（关键词规则，无需联网）。
class CategoryHomePage extends StatefulWidget {
  const CategoryHomePage({super.key});

  @override
  State<CategoryHomePage> createState() => _CategoryHomePageState();
}

/// 单个分类的展示数据。
class _CategoryEntry {
  const _CategoryEntry({required this.tag, required this.count});

  final NoteTag tag;
  final int count;
}

class _CategoryHomePageState extends State<CategoryHomePage> {
  bool _loading = true;
  bool _classifying = false;
  String? _error;
  List<_CategoryEntry> _entries = const <_CategoryEntry>[];

  /// 未分类便签数（「全部便签」只显示这些）。
  int _uncategorizedCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategories();
    });
  }

  Future<void> _loadCategories() async {
    if (!mounted) return;
    final DatabaseService db = context.read<DatabaseService>();
    try {
      final List<NoteTag> tags = await db.getTags();
      final List<_CategoryEntry> entries = <_CategoryEntry>[];
      for (final NoteTag tag in tags) {
        int count = 0;
        try {
          count = await db.getNotesCountByCategory(tag.id);
        } catch (_) {
          count = 0;
        }
        entries.add(_CategoryEntry(tag: tag, count: count));
      }
      entries.sort((_CategoryEntry a, _CategoryEntry b) =>
          b.count.compareTo(a.count));
      int uncategorized = 0;
      try {
        // 全部便签只显示未分类的：统计未分类条数。
        final List<Quote> all = await db.getUserQuotes(
          categoryId: null,
          limit: 5000,
        );
        uncategorized = all
            .where((Quote q) => !SmartCategoryService.isCategorized(q))
            .length;
      } catch (_) {
        uncategorized = 0;
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _uncategorizedCount = uncategorized;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openCategory(String title, String? categoryId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryNotesPage(
          title: title,
          categoryId: categoryId,
        ),
      ),
    );
    if (mounted) {
      await _loadCategories();
    }
  }

  /// 一键智能分类：本地关键词规则自动给未分类便签打标签。
  Future<void> _runSmartClassify() async {
    if (_classifying) return;
    setState(() => _classifying = true);
    final DatabaseService db = context.read<DatabaseService>();
    int done = 0;
    try {
      done = await SmartCategoryService.run(db);
    } catch (_) {
      done = -1;
    }
    if (!mounted) return;
    setState(() => _classifying = false);
    await _loadCategories();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done < 0
              ? '智能分类执行失败，请重试'
              : done == 0
                  ? '没有可智能分类的便签（可能都已分类，或没有匹配的内置分类）'
                  : '智能分类完成：已自动分类 $done 条便签',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      // 作为主页 tab 内嵌使用，不自带 AppBar（外层已有），仅保留安全区。
      body: SafeArea(
        child: _buildBody(theme, colors),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colors) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline, size: 48, color: colors.error),
              const SizedBox(height: 12),
              const Text('分类加载失败'),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadCategories();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCategories,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '便签分类',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : _loadCategories,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildAllCard(theme, colors),
          const SizedBox(height: 20),
          Text(
            '分类',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (_entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  '还没有分类，先去「设置 - 标签管理」创建一个吧',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _entries.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.55,
              ),
              itemBuilder: (BuildContext context, int index) {
                return _buildCategoryCard(_entries[index], theme, colors);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAllCard(ThemeData theme, ColorScheme colors) {
    return Column(
      children: <Widget>[
        Material(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openCategory('全部便签', null),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.inbox_rounded, color: colors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '全部便签',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '还有 $_uncategorizedCount 条未分类',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.onPrimaryContainer),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 定制版：一键智能分类（本地关键词规则，无需联网）。
        Material(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _classifying ? null : _runSmartClassify,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colors.secondary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: _classifying
                        ? Padding(
                            padding: const EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: colors.secondary,
                            ),
                          )
                        : Icon(Icons.auto_awesome_rounded,
                            color: colors.secondary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '智能分类',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '按关键词自动把未分类便签分到对应标签',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_classifying)
                    Icon(Icons.chevron_right,
                        color: colors.onSecondaryContainer),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(
    _CategoryEntry entry,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final String? icon = entry.tag.icon;
    final bool hasEmoji =
        icon != null && icon.trim().isNotEmpty && icon.trim().length <= 4;

    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openCategory(entry.tag.name, entry.tag.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              if (hasEmoji)
                Text(icon.trim(), style: const TextStyle(fontSize: 22))
              else
                Icon(Icons.folder_rounded, color: colors.primary, size: 24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    entry.tag.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.count} 条',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 定制版：某个分类下的便签列表。
///
/// 支持：点击条目直接进入编辑（进入即聚焦正文）、长按进入多选、
/// 一键全选、批量「移动至标签」、批量删除，以及按标签分组筛选。
class CategoryNotesPage extends StatefulWidget {
  const CategoryNotesPage({
    super.key,
    required this.title,
    this.categoryId,
  });

  final String title;

  /// 为 null 时表示「全部便签」。
  final String? categoryId;

  @override
  State<CategoryNotesPage> createState() => _CategoryNotesPageState();
}

class _CategoryNotesPageState extends State<CategoryNotesPage> {
  bool _loading = true;
  bool _busy = false;
  List<Quote> _quotes = const <Quote>[];
  List<NoteTag> _tags = const <NoteTag>[];
  final Set<String> _selectedIds = <String>{};
  String? _filterTagId;

  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    final DatabaseService db = context.read<DatabaseService>();
    List<Quote> quotes = const <Quote>[];
    List<NoteTag> tags = const <NoteTag>[];
    try {
      final String? cid = widget.categoryId;
      // 定制版：分类和标签共用 categories 表，但查询走两条不同路径
      // （quotes.category_id 单值 / quote_tags 多对多关联）。两条都查再合并，
      // 用户不管从哪条路径分好的组，在这里都能看到。
      final Map<String, Quote> merged = <String, Quote>{};
      final List<Quote> byCategory = await db.getUserQuotes(
        categoryId: cid,
        limit: 500,
      );
      for (final Quote q in byCategory) {
        final String? id = q.id;
        if (id != null) merged[id] = q;
      }
      if (cid != null && cid.isNotEmpty) {
        final List<Quote> byTag = await db.getUserQuotes(
          tagIds: <String>[cid],
          limit: 500,
        );
        for (final Quote q in byTag) {
          final String? id = q.id;
          if (id != null) merged.putIfAbsent(id, () => q);
        }
      }
      quotes = merged.values.toList()
        ..sort(
          (Quote a, Quote b) => b.date.compareTo(a.date),
        );
      // 定制版：「全部便签」只显示**未分类**的便签。已分到任何分类/标签
      // （例如“C类日常”）的便签不再出现，这样一看就知道还剩多少没分类。
      if (cid == null) {
        quotes = quotes
            .where((Quote q) => !SmartCategoryService.isCategorized(q))
            .toList();
      }
    } catch (_) {
      quotes = const <Quote>[];
    }
    try {
      tags = await db.getTags();
    } catch (_) {
      tags = const <NoteTag>[];
    }
    if (!mounted) return;
    final Set<String> alive = quotes
        .map((Quote q) => q.id)
        .whereType<String>()
        .toSet();
    setState(() {
      _quotes = quotes;
      _tags = tags
          .where((NoteTag t) => t.id != DatabaseService.hiddenTagId)
          .toList();
      _selectedIds.removeWhere((String id) => !alive.contains(id));
      if (_filterTagId != null &&
          !_tags.any((NoteTag t) => t.id == _filterTagId)) {
        _filterTagId = null;
      }
      _loading = false;
    });
  }

  /// 当前标签筛选下可见的便签。
  List<Quote> get _visible {
    final String? f = _filterTagId;
    if (f == null) return _quotes;
    return _quotes.where((Quote q) => q.tagIds.contains(f)).toList();
  }

  /// 便签所属分类名（用于「全部便签」里显示它在什么类下面）。
  String _categoryNameOf(Quote quote) {
    final String? cid = quote.categoryId;
    if (cid != null && cid.trim().isNotEmpty) {
      for (final NoteTag t in _tags) {
        if (t.id == cid) return '分类：${t.name}';
      }
    }
    final List<String> tagIds = quote.tagIds;
    if (tagIds.isNotEmpty) {
      for (final String tid in tagIds) {
        for (final NoteTag t in _tags) {
          if (t.id == tid) return '分类：${t.name}';
        }
      }
    }
    return '未分类';
  }

  Future<void> _openQuote(Quote quote) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteFullEditorPage(
          initialContent: quote.content,
          initialQuote: quote,
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  // ── 多选 ────────────────────────────────────────────────

  void _toggleSelected(Quote quote) {
    final String? id = quote.id;
    if (id == null) return;
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(_visible.map((Quote q) => q.id).whereType<String>());
    });
  }

  void _clearSelection() {
    setState(_selectedIds.clear);
  }

  List<Quote> get _selectedQuotes =>
      _quotes.where((Quote q) => _selectedIds.contains(q.id)).toList();

  Future<void> _moveSelectedToTag() async {
    final List<Quote> targets = _selectedQuotes;
    if (targets.isEmpty) return;
    final NoteTag? tag = await showTagPicker(
      context,
      title: '移动 ${targets.length} 条便签至标签',
    );
    if (tag == null || !mounted) return;

    setState(() => _busy = true);
    final DatabaseService db = context.read<DatabaseService>();
    final String now = DateTime.now().toIso8601String();
    int ok = 0;
    int failed = 0;
    for (final Quote q in targets) {
      try {
        // 分类页走 quotes.category_id，标签走 quote_tags，二者都要写，
        // 否则"移动"在分类里看不到。
        final QuoteUpdateResult result = await db.updateQuote(
          q.copyWith(
            tagIds: <String>[tag.id],
            categoryId: tag.id,
            lastModified: now,
          ),
        );
        if (result == QuoteUpdateResult.updated) {
          ok++;
        } else {
          failed++;
        }
      } catch (_) {
        // 单条失败不阻塞其余。
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selectedIds.clear();
    });
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已移动 $ok 条至「${tag.name}」${failed > 0 ? '，失败 $failed 条' : ''}',
        ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final List<Quote> targets = _selectedQuotes;
    if (targets.isEmpty) return;
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除便签'),
        content: Text('确定删除选中的 ${targets.length} 条便签吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() => _busy = true);
    final DatabaseService db = context.read<DatabaseService>();
    int ok = 0;
    for (final Quote q in targets) {
      final String? id = q.id;
      if (id == null) continue;
      try {
        await db.deleteQuote(id);
        ok++;
      } catch (_) {
        // 单条失败不阻塞其余。
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selectedIds.clear();
    });
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除 $ok 条')),
    );
  }

  // ── UI ──────────────────────────────────────────────────

  Widget _buildTagFilterBar(ThemeData theme) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
            child: FilterChip(
              label: Text('全部（${_quotes.length}）'),
              selected: _filterTagId == null,
              onSelected: (_) => setState(() => _filterTagId = null),
            ),
          ),
          for (final NoteTag tag in _tags)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
              child: FilterChip(
                label: Text(tag.name),
                selected: _filterTagId == tag.id,
                onSelected: (_) => setState(() {
                  _filterTagId = _filterTagId == tag.id ? null : tag.id;
                }),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final List<Quote> visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? '已选 ${_selectedIds.length} 条'
              : widget.categoryId == null
                  ? '全部便签（未分类 ${_quotes.length} 条）'
                  : widget.title,
        ),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: '退出多选',
                onPressed: _clearSelection,
              )
            : null,
        actions: <Widget>[
          if (!_selectionMode)
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: '多选',
              onPressed:
                  visible.isEmpty ? null : () => setState(_selectAll),
            )
          else ...<Widget>[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: '全选',
              onPressed: _selectAll,
            ),
            IconButton(
              icon: const Icon(Icons.label_outline),
              tooltip: '移动至标签',
              onPressed: _busy ? null : _moveSelectedToTag,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: _busy ? null : _deleteSelected,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                if (_busy) const LinearProgressIndicator(),
                _buildTagFilterBar(theme),
                const Divider(height: 1),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            _quotes.isEmpty
                                ? (widget.categoryId == null
                                    ? '所有便签都已分类 🎉'
                                    : '这个分类下还没有便签')
                                : '该标签下还没有便签',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (BuildContext context, int index) {
                              final Quote quote = visible[index];
                              final bool checked = quote.id != null &&
                                  _selectedIds.contains(quote.id);
                              return ListTile(
                                leading: _selectionMode
                                    ? Checkbox(
                                        value: checked,
                                        onChanged: (_) =>
                                            _toggleSelected(quote),
                                      )
                                    : null,
                                title: Text(
                                  quote.content,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  // 定制版：显示便签当前所属分类（如“C类日常”）。
                                  '${_categoryNameOf(quote)} · ${quote.date}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                trailing: _selectionMode
                                    ? null
                                    : const Icon(
                                        Icons.chevron_right,
                                        size: 18,
                                      ),
                                onTap: _selectionMode
                                    ? () => _toggleSelected(quote)
                                    : () => _openQuote(quote),
                                onLongPress: () => _toggleSelected(quote),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

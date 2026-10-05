import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_tag.dart';
import '../models/quote_model.dart';
import '../services/database_service.dart';
import 'note_full_editor_page.dart';

/// 定制版：便签分类页
///
/// 作为应用的主页（替代原先的「每日一言」首页），按「分类 / 标签」聚合展示
/// 全部便签。点击某个分类即可进入该分类下的便签列表。
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
  String? _error;
  List<_CategoryEntry> _entries = const <_CategoryEntry>[];
  int _totalCount = 0;

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
      int total = 0;
      try {
        total = await db.getQuotesCount();
      } catch (_) {
        total = 0;
      }
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _totalCount = total;
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
    return Material(
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
                      '共 $_totalCount 条记录',
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
  List<Quote> _quotes = const <Quote>[];

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
    try {
      quotes = await db.getUserQuotes(
        categoryId: widget.categoryId,
        limit: 500,
      );
    } catch (_) {
      quotes = const <Quote>[];
    }
    if (!mounted) return;
    setState(() {
      _quotes = quotes;
      _loading = false;
    });
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _quotes.isEmpty
              ? Center(
                  child: Text(
                    '这个分类下还没有便签',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
                    itemCount: _quotes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      final Quote quote = _quotes[index];
                      return ListTile(
                        title: Text(
                          quote.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          quote.date,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => _openQuote(quote),
                      );
                    },
                  ),
                ),
    );
  }
}

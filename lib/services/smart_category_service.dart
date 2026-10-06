import '../models/note_tag.dart';
import '../models/quote_model.dart';
import 'database_service.dart';

/// 定制版：本地启发式「智能分类」。
///
/// 规则（按用户要求）：
/// 1. 正文含 http/https/www 链接 → 「网络」。
/// 2. 正文以数字开头或数字占比高（账号 / 密码 / 卡号等）→ 「账密」。
/// 3. 其余全部 → 「教程」（教程 / 文字 / 技术交流等）。
///
/// 分类簇通过「用户标签名」匹配；某个簇没有对应标签时会自动创建内置标签，
/// 保证一键分类总能生效。纯本地规则，不联网、不泄露内容。
class SmartCategoryService {
  SmartCategoryService._();

  /// 内置分类簇（优先级从高到低：网络 > 账密 > 教程兜底）。
  static const List<_SmartCategoryRule> _rules = <_SmartCategoryRule>[
    _SmartCategoryRule(
      labelKeywords: <String>['网络', '网址', '网站', '链接', 'http', 'https', '网页', '浏览器'],
      defaultTagName: '网络',
      urlKeywords: <String>['http://', 'https://', 'www.', '://'],
    ),
    _SmartCategoryRule(
      labelKeywords: <String>['账号', '密码', '账密', '账户', '帐号', '账号密码', '登录', '密保'],
      defaultTagName: '账密',
      digitBased: true,
    ),
    _SmartCategoryRule(
      labelKeywords: <String>['教程', '技术', '交流', '文字', '文章', '文档', '资料', '学习', '笔记', '知识', '备忘', '记录'],
      defaultTagName: '教程',
      catchAll: true,
    ),
  ];

  /// 便签是否已被分类（两种路径任一命中即视为已分类）。
  static bool isCategorized(Quote quote) {
    final List<String> tagIds = quote.tagIds;
    if (tagIds.isNotEmpty) return true;
    final String? cid = quote.categoryId;
    return cid != null && cid.trim().isNotEmpty;
  }

  /// 执行一轮智能分类，返回成功条数。
  static Future<int> run(DatabaseService db) async {
    // 1. 用户标签 → 命中簇；缺失的簇自动创建内置标签。
    final List<NoteTag> tags = await db.getTags();
    final Map<String, _SmartCategoryRule> tagToRule = <String, _SmartCategoryRule>{};
    for (final _SmartCategoryRule rule in _rules) {
      NoteTag? hit;
      for (final NoteTag tag in tags) {
        if (tag.id == DatabaseService.hiddenTagId) continue;
        final String name = tag.name.trim().toLowerCase();
        if (name.isEmpty) continue;
        if (rule.matchesLabel(name)) {
          hit = tag;
          break;
        }
      }
      if (hit == null) {
        // 自动创建内置标签，保证智能分类总能执行。
        try {
          await db.addTag(rule.defaultTagName);
          final List<NoteTag> after = await db.getTags();
          for (final NoteTag tag in after) {
            if (tag.id == DatabaseService.hiddenTagId) continue;
            if (tag.name.trim().toLowerCase() ==
                rule.defaultTagName.toLowerCase()) {
              hit = tag;
              break;
            }
          }
        } catch (_) {
          // 创建失败则跳过该簇。
        }
      }
      if (hit != null) {
        tagToRule[hit.id] = rule;
      }
    }
    if (tagToRule.isEmpty) return 0;

    // 2. 拉取全部便签，只处理未分类的（最多 3000 条足够日常使用）。
    final List<Quote> all = await db.getUserQuotes(
      categoryId: null,
      limit: 3000,
    );
    final List<Quote> pending = all
        .where((Quote q) => !isCategorized(q))
        .toList(growable: false);
    final String now = DateTime.now().toIso8601String();

    // 3. 逐条匹配，命中最高分簇即打标签。
    int ok = 0;
    for (final Quote q in pending) {
      final String body = q.content.trim().toLowerCase();
      if (body.isEmpty) continue;

      String? bestTagId;
      int bestScore = 0;
      for (final MapEntry<String, _SmartCategoryRule> entry
          in tagToRule.entries) {
        final int score = entry.value.score(body);
        if (score > bestScore) {
          bestScore = score;
          bestTagId = entry.key;
        }
      }
      if (bestTagId == null || bestScore <= 0) continue;

      try {
        final QuoteUpdateResult result = await db.updateQuote(
          q.copyWith(
            tagIds: <String>[bestTagId],
            categoryId: bestTagId,
            lastModified: now,
          ),
        );
        if (result == QuoteUpdateResult.updated) {
          ok++;
        }
      } catch (_) {
        // 单条失败不阻塞其余。
      }
    }
    return ok;
  }
}

/// 一个分类簇：labelKeywords 匹配标签名，形态规则匹配便签正文。
class _SmartCategoryRule {
  const _SmartCategoryRule({
    required this.labelKeywords,
    required this.defaultTagName,
    this.urlKeywords = const <String>[],
    this.digitBased = false,
    this.catchAll = false,
    this.keywords = const <String>[],
  });

  final List<String> labelKeywords;
  final String defaultTagName;
  final List<String> urlKeywords;
  final bool digitBased;
  final bool catchAll;
  final List<String> keywords;

  /// 标签名是否属于本簇。
  bool matchesLabel(String labelLower) {
    for (final String k in labelKeywords) {
      if (labelLower.contains(k.toLowerCase())) return true;
    }
    return false;
  }

  /// 正文命中本簇的得分；0 表示不命中。
  int score(String bodyLower) {
    if (catchAll) return 1;
    if (urlKeywords.isNotEmpty) {
      for (final String k in urlKeywords) {
        if (bodyLower.contains(k)) return 5;
      }
      return 0;
    }
    if (digitBased) {
      final String trimmed = bodyLower.trimLeft();
      if (trimmed.isEmpty) return 0;
      // 开头是数字，或数字字符占比 ≥ 35%（账号 / 密码 / 卡号类便签）。
      final int first = trimmed.codeUnitAt(0);
      if (first >= 0x30 && first <= 0x39) return 4;
      int digits = 0;
      for (int i = 0; i < bodyLower.length; i++) {
        final int c = bodyLower.codeUnitAt(i);
        if (c >= 0x30 && c <= 0x39) digits++;
      }
      if (digits * 100 ~/ bodyLower.length >= 35) return 4;
      return 0;
    }
    int s = 0;
    for (final String k in keywords) {
      if (bodyLower.contains(k)) s++;
    }
    return s;
  }
}

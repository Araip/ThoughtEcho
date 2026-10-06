import '../models/note_tag.dart';
import '../models/quote_model.dart';
import 'database_service.dart';

/// 定制版：本地启发式「智能分类」。
///
/// 没有云端 AI 模型，纯本地关键词规则，不联网、不泄露内容：
/// 1. 为每个分类簇内置一组中文关键词（工作/学习/日常/健康/财务/灵感/旅行/家庭）。
/// 2. 用「用户标签名」匹配簇（标签名里带“工作”“日常”等字样即命中该簇），
///    没有对应标签的簇不会凭空创建标签。
/// 3. 遍历全部未分类便签，正文命中簇内关键词（按命中数取最高分簇）就自动打上
///    该标签（同时写 quotes.category_id 与 quote_tags，两条查询路径都能看到）。
///
/// 返回成功分类的条数。
class SmartCategoryService {
  SmartCategoryService._();

  /// 内置分类簇。labelKeywords 匹配用户标签名，keywords 匹配便签正文。
  static const List<_SmartCategoryRule> _rules = <_SmartCategoryRule>[
    _SmartCategoryRule(
      labelKeywords: <String>['工作', '办公', '职场', '上班', '业务', '项目', '客户'],
      keywords: <String>[
        '开会', '会议', '客户', '项目', '汇报', '报告', '周报', '月报', '需求', '上线',
        '加班', '领导', '同事', '面试', 'offer', '简历', 'ppt', '合同', '报价',
        '任务', '截止', '待办', '工位', '工单', '排期', '评审', '迭代',
      ],
    ),
    _SmartCategoryRule(
      labelKeywords: <String>['学习', '读书', '阅读', '课程', '考试', '复习', '备考', '考研'],
      keywords: <String>[
        '学习', '读书', '阅读', '课程', '考试', '复习', '笔记', '论文', '单词', '英语',
        '网课', '刷题', '作业', '老师', '学校', '考研', '备考', '知识点', '教材',
        '课本', '练习', '测验', '背诵', '默写',
      ],
    ),
    _SmartCategoryRule(
      labelKeywords: <String>['日常', '生活', '家务', '琐事', '杂事', '琐碎'],
      keywords: <String>[
        '买菜', '做饭', '洗碗', '家务', '打扫', '洗衣', '快递', '取件', '寄件', '缴费',
        '水费', '电费', '燃气', '购物', '超市', '修理', '充电', '买菜', '晾衣',
        '倒垃圾', '拖地', '擦窗', '换被套', '买菜做饭', '取快递',
      ],
    ),
    _SmartCategoryRule(
      labelKeywords: <String>['健康', '运动', '健身', '身体', '养生'],
      keywords: <String>[
        '健身', '跑步', '运动', '锻炼', '体检', '吃药', '医院', '医生', '看病', '挂号',
        '睡眠', '早睡', '熬夜', '头疼', '感冒', '发烧', '拉伸', '瑜伽', '游泳',
        '骑车', '步行', '散步', '血压', '血糖', '疫苗', '复查', '医嘱',
      ],
    ),
    _SmartCategoryRule(
      labelKeywords: <String>['财务', '理财', '金钱', '账', '收支'],
      keywords: <String>[
        '工资', '报销', '账单', '转账', '收款', '付款', '发票', '税', '公积金', '社保',
        '预算', '存钱', '理财', '银行卡', '还款', '房贷', '车贷', '租金', '收入',
        '支出', '余额', '利息', '股票', '基金', '红包',
      ],
    ),
    _SmartCategoryRule(
      labelKeywords: <String>['灵感', '想法', '创意', '点子'],
      keywords: <String>[
        '想法', '点子', '灵感', '创意', '脑洞', '梦到', '构思', '设想', '突然',
        '有个主意', '记录一下', '备忘', '提醒自己',
      ],
    ),
    _SmartCategoryRule(
      labelKeywords: <String>['旅行', '旅游', '出行', '旅程'],
      keywords: <String>[
        '旅行', '旅游', '机票', '高铁', '酒店', '民宿', '景点', '攻略', '行程',
        '出发', '行李', '火车票', '护照', '签证', '自驾', '景点门票', '航班',
      ],
    ),
    _SmartCategoryRule(
      labelKeywords: <String>['家庭', '家人', '亲情', '家里'],
      keywords: <String>[
        '爸妈', '妈妈', '爸爸', '孩子', '宝宝', '家人', '家庭', '亲戚', '回家',
        '过年', '生日', '礼物', '团圆', '做饭给', '接孩子', '送爸妈',
      ],
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
    // 1. 用户标签 → 命中簇。
    final List<NoteTag> tags = await db.getTags();
    final Map<String, _SmartCategoryRule> tagToRule = <String, _SmartCategoryRule>{};
    for (final NoteTag tag in tags) {
      if (tag.id == DatabaseService.hiddenTagId) continue;
      final String name = tag.name.trim().toLowerCase();
      if (name.isEmpty) continue;
      for (final _SmartCategoryRule rule in _rules) {
        if (rule.matchesLabel(name)) {
          tagToRule[tag.id] = rule;
          break;
        }
      }
    }
    if (tagToRule.isEmpty) {
      // 没有任何标签能对应到内置簇，无法智能分类。
      return 0;
    }

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

/// 一个分类簇：labelKeywords 匹配标签名，keywords 匹配便签正文。
class _SmartCategoryRule {
  const _SmartCategoryRule({
    required this.labelKeywords,
    required this.keywords,
  });

  final List<String> labelKeywords;
  final List<String> keywords;

  /// 标签名是否属于本簇。
  bool matchesLabel(String labelLower) {
    for (final String k in labelKeywords) {
      if (labelLower.contains(k.toLowerCase())) return true;
    }
    return false;
  }

  /// 正文命中本簇关键词的个数。
  int score(String bodyLower) {
    int s = 0;
    for (final String k in keywords) {
      if (bodyLower.contains(k)) s++;
    }
    return s;
  }
}

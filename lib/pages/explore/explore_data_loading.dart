part of '../explore_page.dart';

extension _ExploreDataLoading on _ExplorePageState {
  /// 加载周期数据
  ///
  /// [showLoading] 为 false 时做静默刷新：保留当前内容，不把整页换成转圈，
  /// 这样数据库连续通知时页面不会来回闪。
  Future<void> _loadPeriodData({bool showLoading = true}) async {
    final token = ++_loadToken;
    // 首次加载还没有任何内容可保留，必须显示 loading
    final shouldShowLoading = showLoading || !_hasLoadedOnce;
    if (shouldShowLoading && !_isLoadingData) {
      _updateState(() {
        _isLoadingData = true;
      });
    }

    try {
      final databaseService = context.read<DatabaseService>();

      final range = ReportPeriodUtils.dateRange(_selectedPeriod, _selectedDate);

      List<Quote> quotes;
      if (range != null) {
        // 使用优化后的日期范围查询，仅返回周期报告所需字段
        quotes =
            await databaseService.getQuotesForPeriod(range.start, range.end);
      } else {
        // 获取所有笔记（排除隐藏笔记，隐藏笔记不参与AI分析统计）
        quotes = await databaseService.getAllQuotes();
      }

      // 调试：打印获取到的所有笔记数量
      AppLogger.d('getQuotes returned notes count: ${quotes.length}');
      // 打印每条笔记的日期（前10条）
      for (var i = 0; i < quotes.length && i < 10; i++) {
        AppLogger.d('  Raw note[$i]: date=${quotes[i].date}');
      }

      // 根据选择的时间范围筛选笔记 (内存中再次确认筛选，处理可能存在的跨时区或边界情况)
      final filteredQuotes = _filterQuotesByPeriod(quotes);

      // 已有更新的加载在跑，丢弃这次的结果，避免旧数据把新数据顶掉
      if (token != _loadToken) return;

      // 更新数据版本key，触发动画
      final newDataKey =
          '${_selectedPeriod}_${_selectedDate.millisecondsSinceEpoch}';
      final dataChanged = newDataKey != _dataKey;

      _hasLoadedOnce = true;
      _updateState(() {
        _periodQuotes = filteredQuotes;
        _isLoadingData = false;
        _dataKey = newDataKey;
        // 只在数据真正变化时才播放动画
        _shouldAnimateOverview = dataChanged;
      });

      // 计算“最多”指标并触发洞察
      await _computeExtrasAndInsight(token);
    } catch (e) {
      if (token != _loadToken) return;
      _updateState(() {
        _isLoadingData = false;
      });
      AppLogger.e('Failed to load period data', error: e);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.loadDataFailed(e.toString())),
            duration: AppConstants.snackBarDurationError,
          ),
        );
      }
    }
  }

  Future<void> _computeExtrasAndInsight(int token) async {
    if (!mounted || token != _loadToken) return;
    final l10n = AppLocalizations.of(context);

    // 计算总字数、最常见时间段、最常见天气和标签，单遍遍历完成
    var totalWords = 0;
    final Map<String, int> periodCounts = {};
    final Map<String, int> weatherCategoryCounts = {};
    final Map<String, int> tagCounts = {};
    for (final q in _periodQuotes) {
      totalWords += q.content.length;

      final p = q.dayPeriod?.trim();
      if (p != null && p.isNotEmpty) {
        periodCounts[p] = (periodCounts[p] ?? 0) + 1;
      }

      final w = q.weather?.trim();
      if (w != null && w.isNotEmpty) {
        // 先尝试通过key获取分类，如果失败则直接用原值
        String? category = WeatherService.getFilterCategoryByWeatherKey(w);
        if (category == null) {
          // 如果是中文描述，尝试反查key再获取分类
          final key = WeatherCodeMapper.getKeyByDescription(w);
          if (key != null) {
            category = WeatherService.getFilterCategoryByWeatherKey(key);
          }
        }
        final finalCategory = category ?? w; // 如果找不到分类就用原值
        weatherCategoryCounts[finalCategory] =
            (weatherCategoryCounts[finalCategory] ?? 0) + 1;
      }

      for (final tagId in q.tagIds) {
        tagCounts[tagId] = (tagCounts[tagId] ?? 0) + 1;
      }
    }

    // 生成数据签名（用于判断洞察能不能复用缓存）。
    //
    // 原来是「周期_本地化日期文案_笔记数_总字数」，三处都不够：
    // - 改错别字、换个等长的词，笔记数和总字数都不动，签名不变，于是永远
    //   返回旧洞察；反过来两批完全不同的笔记也可能撞签名。改成把每条笔记的
    //   id 和内容一起折进指纹，用异或合并，与查询返回的顺序无关。
    // - 日期文案是本地化字符串，切换界面语言就白白重算一遍。改用 ISO 日期。
    // - 签名不含提示词版本和模型，所以改完提示词或换了模型，老缓存照样命中，
    //   用户根本看不到变化。两样都折进来。
    var contentFingerprint = 0;
    for (final quote in _periodQuotes) {
      contentFingerprint ^= Object.hash(quote.id, quote.content);
    }

    final range = ReportPeriodUtils.dateRange(_selectedPeriod, _selectedDate);
    final rangeStart = range?.start.toIso8601String().substring(0, 10);
    final rangeEnd = range?.end.toIso8601String().substring(0, 10);
    final rangeKey = range == null ? 'all' : '$rangeStart~$rangeEnd';
    final provider =
        context.read<SettingsService>().multiAISettings.currentProvider;
    final model = provider?.model ?? '-';

    final dataSignature = [
      _selectedPeriod,
      rangeKey,
      _periodQuotes.length,
      totalWords,
      contentFingerprint,
      'p1',
      model,
    ].join('_');

    final mostPeriod = periodCounts.entries.isNotEmpty
        ? periodCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key
        : null;

    final mostWeather = weatherCategoryCounts.entries.isNotEmpty
        ? weatherCategoryCounts.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key
        : null;

    // 最常用标签（根据tagIds统计，然后映射为名称）
    String? topTagName;
    String? topTagId;
    dynamic topTagIcon;
    try {
      if (tagCounts.isNotEmpty) {
        topTagId =
            tagCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
        final db = context.read<DatabaseService>();
        final cats = await db.getTags();
        final category = cats.firstWhere(
          (c) => c.id == topTagId,
          orElse: () => cats.first,
        );
        topTagName = category.name;
        topTagIcon = IconUtils.getDisplayIcon(category.iconName);
      }
    } catch (_) {
      // 如解析失败，保持null
    }

    // 笔记片段预览（最多5条，每条截断80字）
    final samples = _periodQuotes.take(5).map((q) {
      var t = q.content.trim().replaceAll('\n', ' ');
      if (t.length > 80) t = '${t.substring(0, 80)}…';
      return '- $t';
    }).join('\n');

    if (!mounted || token != _loadToken) return;

    // 处理时段显示：转换为本地化标签
    String? dayPeriodDisplay;
    IconData? dayPeriodIcon;
    if (mostPeriod != null) {
      dayPeriodDisplay = TimeUtils.getLocalizedDayPeriodLabel(
        context,
        mostPeriod,
      );
      dayPeriodIcon = TimeUtils.getDayPeriodIconByKey(mostPeriod);
    }

    // 处理天气显示：转换为中文
    String? weatherDisplay;
    IconData? weatherIcon;
    if (mostWeather != null) {
      // 如果是筛选分类key，直接使用分类标签
      if (WeatherService.filterCategoryToKeys.containsKey(mostWeather)) {
        weatherDisplay = WeatherService.getLocalizedFilterCategoryLabel(
          context,
          mostWeather,
        );
        weatherIcon = WeatherService.getFilterCategoryIcon(mostWeather);
      } else {
        // 否则按原逻辑处理
        weatherDisplay = WeatherCodeMapper.getLocalizedDescription(
          l10n,
          mostWeather,
        );
        weatherIcon = WeatherCodeMapper.getIcon(mostWeather);

        // 如果返回的是未知描述，说明mostWeather可能已经是描述
        if (weatherDisplay == l10n.weatherUnknown) {
          weatherDisplay = mostWeather;
          // 反向匹配：根据中文描述找到key以获取更准确的图标
          final key = WeatherCodeMapper.getKeyByDescription(mostWeather);
          weatherIcon =
              key != null ? WeatherCodeMapper.getIcon(key) : Icons.cloud_queue;
        }
      }
    }
    if (!mounted || token != _loadToken) return;
    _updateState(() {
      _totalWordCount = totalWords;
      _mostDayPeriod = mostPeriod;
      _mostWeather = mostWeather;
      _mostTopTag = topTagName;
      _notesPreview = samples.isEmpty ? null : samples;

      // 设置显示用的文本和图标
      _mostDayPeriodDisplay = dayPeriodDisplay;
      _mostDayPeriodIcon = dayPeriodIcon;
      _mostWeatherDisplay = weatherDisplay;
      _mostWeatherIcon = weatherIcon;
      _mostTopTagIcon = topTagIcon;
    });

  }

  List<Quote> _filterQuotesByPeriod(List<Quote> quotes) {
    final filtered = ReportPeriodUtils.filterByCreatedPeriod(
      quotes,
      selectedPeriod: _selectedPeriod,
      selectedDate: _selectedDate,
    );

    // 调试日志
    AppLogger.d(
      'Filter conditions: period=$_selectedPeriod, selectedDate=$_selectedDate',
    );
    AppLogger.d('Total notes: ${quotes.length}');
    AppLogger.d('Filtered notes count: ${filtered.length}');
    // 打印前5条笔记的日期以便调试
    for (var i = 0; i < filtered.length && i < 5; i++) {
      AppLogger.d('  Note[$i]: ${filtered[i].date}');
    }

    return filtered;
  }
}

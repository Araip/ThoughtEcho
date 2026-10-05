import 'package:flutter/material.dart';
import 'package:thoughtecho/gen_l10n/app_localizations.dart';

class IconUtils {
  // 保留原有Material图标
  static final Map<String, IconData> categoryIcons = {
    'home': Icons.home,
    'work': Icons.work,
    'school': Icons.school,
    'book': Icons.book,
    'movie': Icons.movie,
    'music_note': Icons.music_note,
    'flight': Icons.flight,
    'restaurant': Icons.restaurant,
    'shopping_cart': Icons.shopping_cart,
    'sports_basketball': Icons.sports_basketball,
    'health_and_safety': Icons.health_and_safety,
    'attach_money': Icons.attach_money,
    'family_restroom': Icons.family_restroom,
    'people': Icons.people,
    'pets': Icons.pets,
    'nature': Icons.nature,
    'palette': Icons.palette,
    'computer': Icons.computer,
    'sports_esports': Icons.sports_esports,
    'more_horiz': Icons.more_horiz,
    'format_quote': Icons.format_quote,
    'theaters': Icons.theaters,
    'menu_book': Icons.menu_book,
    'auto_stories': Icons.auto_stories,
    'create': Icons.create,
    'public': Icons.public,
    'category': Icons.category,
    'psychology': Icons.psychology,
    'mood': Icons.mood,
    'bookmark': Icons.bookmark,
    'label': Icons.label,
    'brush': Icons.brush,
    // 系统/特殊用途图标
    'lock': Icons.lock_outline,
  };

  // 常用emoji分类 - 与笔记和思考相关的emoji
  static final Map<String, List<String>> emojiCategories = {
    '情感': [
      '😊',
      '😌',
      '🥰',
      '😍',
      '🤔',
      '🧐',
      '🤯',
      '😲',
      '😢',
      '😭',
      '😤',
      '😠',
      '😩',
      '🥺',
      '😵',
      '🥴',
    ],
    '思考': [
      '💭',
      '🧠',
      '💡',
      '✨',
      '🔍',
      '🔎',
      '📝',
      '✏️',
      '📔',
      '📕',
      '📒',
      '📚',
      '🗂️',
      '📋',
      '📌',
      '🖋️',
    ],
    '自然': [
      '🌈',
      '☀️',
      '🌤️',
      '⛅',
      '🌥️',
      '☁️',
      '🌦️',
      '🌧️',
      '⛈️',
      '🌩️',
      '🌨️',
      '❄️',
      '🌪️',
      '🌫️',
      '🌊',
      '🏞️',
    ],
    '心情': [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
    ],
    '生活': [
      '🏡',
      '🌃',
      '🌆',
      '🌇',
      '🌉',
      '🏙️',
      '🚗',
      '🚶',
      '🧘',
      '🍵',
      '☕',
      '🍷',
      '🎵',
      '🎬',
      '🎨',
      '🎭',
    ],
    '成长': [
      '🌱',
      '🌿',
      '🌴',
      '🌳',
      '🌲',
      '🌵',
      '🌾',
      '🍀',
      '🍃',
      '🌺',
      '🌻',
      '🌼',
      '🌷',
      '🪴',
      '🎋',
      '🪷',
    ],
    '奖励': [
      '🏆',
      '🥇',
      '🥈',
      '🥉',
      '🏅',
      '🎖️',
      '🏵️',
      '🎗️',
      '⭐',
      '🌟',
      '🔥',
      '💯',
      '🎯',
      '👑',
      '🎊',
      '🎉',
    ],
    '交通': ['🚗', '✈️', '🚢', '🚲', '🚀'],
    '其他': ['💡', '🔥', '💧', '🌍', '⭐'],
  };

  // Internal category keys for lookup
  static const List<String> _categoryKeys = [
    '情感',
    '思考',
    '自然',
    '心情',
    '生活',
    '成长',
    '奖励',
    '交通',
    '其他',
  ];

  // Get localized category name
  static String getLocalizedCategoryName(
    String chineseKey,
    AppLocalizations l10n,
  ) {
    switch (chineseKey) {
      case '情感':
        return l10n.emotion;
      case '思考':
        return l10n.thinking;
      case '自然':
        return l10n.nature;
      case '心情':
        return l10n.mood;
      case '生活':
        return l10n.life;
      case '成长':
        return l10n.growth;
      case '奖励':
        return l10n.reward;
      case '交通':
        return l10n.transport;
      case '其他':
        return l10n.otherCategory;
      default:
        return chineseKey;
    }
  }

  // Get localized emoji categories
  static Map<String, List<String>> getLocalizedEmojiCategories(
    AppLocalizations l10n,
  ) {
    final result = <String, List<String>>{};
    for (final key in _categoryKeys) {
      if (emojiCategories.containsKey(key)) {
        result[getLocalizedCategoryName(key, l10n)] = emojiCategories[key]!;
      }
    }
    return result;
  }

  // 检查图标名称是否为emoji
  static bool isEmoji(String? iconName) {
    if (iconName == null || iconName.isEmpty) return false;

    // 简单检测是否是emoji - 单个字符且不在分类图标中
    return iconName.characters.length == 1 &&
        !categoryIcons.containsKey(iconName);
  }

  // 获取图标数据
  static dynamic getIconData(String? iconName) {
    if (iconName == null || iconName.isEmpty) {
      return Icons.label; // 默认图标
    }

    // 如果是emoji，直接返回
    if (isEmoji(iconName)) {
      return Icons.emoji_emotions; // 占位图标，实际显示时会使用emoji文本
    }

    // 返回Material图标
    return categoryIcons[iconName] ?? Icons.label;
  }

  // 获取要显示的图标 - 可能是IconData或emoji字符串
  static dynamic getDisplayIcon(String? iconName) {
    if (iconName == null || iconName.isEmpty) {
      return Icons.label;
    }

    // 如果是emoji，直接返回emoji字符串
    if (isEmoji(iconName)) {
      return iconName;
    }

    // 返回Material图标
    return categoryIcons[iconName] ?? Icons.label;
  }

  static Widget getIcon(String iconName, {Color? color, double? size}) {
    if (categoryIcons.containsKey(iconName)) {
      return Icon(categoryIcons[iconName], color: color, size: size);
    }
    // 检查是否是Emoji
    for (var category in emojiCategories.values) {
      if (category.contains(iconName)) {
        return Text(iconName, style: TextStyle(fontSize: size ?? 24));
      }
    }
    // 默认图标
    return Icon(Icons.label, color: color, size: size);
  }

  // 获取所有可用图标
  static List<MapEntry<String, dynamic>> getAllIcons() {
    final List<MapEntry<String, dynamic>> allIcons = [];

    // 添加基础emoji
    final allEmojis =
        emojiCategories.values.expand((emojis) => emojis).toList();
    allIcons.addAll(allEmojis.map((emoji) => MapEntry(emoji, emoji)));

    // 添加Material图标
    allIcons.addAll(categoryIcons.entries);

    return allIcons;
  }

  // 获取分类后的emoji
  static Map<String, List<String>> getCategorizedEmojis() {
    return emojiCategories;
  }

  // 获取分类图标 - 适用于显示在UI中
  static Widget getCategoryIcon(String? iconName) {
    if (iconName == null || iconName.isEmpty) {
      return const Icon(Icons.label);
    }

    // 如果是emoji，返回文本widget
    if (isEmoji(iconName)) {
      return Text(iconName, style: const TextStyle(fontSize: 24));
    }

    // 返回Material图标
    return Icon(categoryIcons[iconName] ?? Icons.label);
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 定制版：应用名称与图标伪装。
///
/// 通过切换 Android 启动器入口（activity-alias）实现：
/// - 关闭时使用 `.LauncherEntry`（名称「心迹」+ 原图标）
/// - 开启时使用 `.CalculatorEntry`（名称「计算器」+ 计算器图标）
///
/// 原生侧实现在 `MainActivity` 的 `com.shangjin.thoughtecho/disguise` 通道，
/// 组件启用状态由系统持久化，重启/升级后依旧保持，不需要在 Flutter 侧重复同步。
class DisguiseService {
  DisguiseService._();

  static const MethodChannel _channel =
      MethodChannel('com.shangjin.thoughtecho/disguise');

  /// 是否支持伪装（仅 Android 原生侧提供实现）。
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 读取当前伪装状态。失败时返回 false，不抛异常。
  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    try {
      final value = await _channel.invokeMethod<bool>('isDisguiseEnabled');
      return value ?? false;
    } catch (e) {
      debugPrint('[DisguiseService] 读取伪装状态失败: $e');
      return false;
    }
  }

  /// 切换伪装状态，返回是否切换成功。
  static Future<bool> setEnabled(bool enabled) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setDisguise', enabled);
      return ok ?? false;
    } catch (e) {
      debugPrint('[DisguiseService] 切换伪装状态失败: $e');
      return false;
    }
  }
}

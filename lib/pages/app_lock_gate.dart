import 'package:flutter/material.dart';

import 'calculator_disguise_page.dart';

/// 定制版：应用入口锁
///
/// 冷启动时**先进入伪装计算器**；只有在计算器右上角长按并输入解锁码后，
/// 才会切到真实的 [child]（便签主界面）。这样别人拿到手机解锁屏幕看到的
/// 只是一个计算器。
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  /// 解锁后展示的真实主界面。
  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  bool _unlocked = false;

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return CalculatorDisguisePage(
      onUnlocked: () {
        if (mounted) setState(() => _unlocked = true);
      },
    );
  }
}

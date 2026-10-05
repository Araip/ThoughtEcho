import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import 'nutstore_import_page.dart';

/// 定制版：伪装计算器页
///
/// 外观与行为都是一个**真正可用**的简单计算器，用于隐藏「隐私与安全」入口。
/// 在计算器上输入解锁码 [unlockCode]（默认 `1234`）后按「=」，
/// 才会弹出真实的隐私与安全设置面板。
class CalculatorDisguisePage extends StatefulWidget {
  const CalculatorDisguisePage({super.key, this.onUnlocked});

  /// 解锁成功后的回调：由 AppLockGate 注入，用于切到便签主界面。
  final VoidCallback? onUnlocked;

  /// 解锁码：右上角长按输入该密码，或输入该数字后按「=」即可进入便签。
  static const String unlockCode = '1234';

  @override
  State<CalculatorDisguisePage> createState() =>
      _CalculatorDisguisePageState();
}

class _CalculatorDisguisePageState extends State<CalculatorDisguisePage> {
  String _display = '0';
  double? _accumulator;
  String? _pendingOp;
  bool _freshEntry = true;

  // ══════════════ 计算器核心逻辑 ══════════════

  void _inputDigit(String d) {
    setState(() {
      if (_freshEntry || _display == '0') {
        _display = d;
        _freshEntry = false;
      } else if (_display.replaceAll('-', '').replaceAll('.', '').length < 12) {
        _display = '$_display$d';
      }
    });
  }

  void _inputDot() {
    setState(() {
      if (_freshEntry) {
        _display = '0.';
        _freshEntry = false;
      } else if (!_display.contains('.')) {
        _display = '$_display.';
      }
    });
  }

  void _clearAll() {
    setState(() {
      _display = '0';
      _accumulator = null;
      _pendingOp = null;
      _freshEntry = true;
    });
  }

  void _toggleSign() {
    setState(() {
      if (_display.startsWith('-')) {
        _display = _display.substring(1);
      } else if (_display != '0') {
        _display = '-$_display';
      }
    });
  }

  void _percent() {
    setState(() {
      final double v = double.tryParse(_display) ?? 0;
      _display = _format(v / 100);
      _freshEntry = false;
    });
  }

  void _setOperator(String op) {
    setState(() {
      final double current = double.tryParse(_display) ?? 0;
      if (_accumulator != null && _pendingOp != null && !_freshEntry) {
        final double? r = _compute(_accumulator!, current, _pendingOp!);
        if (r == null) {
          _display = '错误';
          _accumulator = null;
          _pendingOp = null;
          _freshEntry = true;
          return;
        }
        _accumulator = r;
        _display = _format(r);
      } else {
        _accumulator = current;
      }
      _pendingOp = op;
      _freshEntry = true;
    });
  }

  void _equals() {
    // ── 解锁判定：输入解锁码后按「=」 ──
    if (_pendingOp == null &&
        _accumulator == null &&
        _display == CalculatorDisguisePage.unlockCode) {
      _clearAll();
      _unlock();
      return;
    }

    setState(() {
      final double current = double.tryParse(_display) ?? 0;
      if (_pendingOp != null && _accumulator != null) {
        final double? r = _compute(_accumulator!, current, _pendingOp!);
        if (r == null) {
          _display = '错误';
        } else {
          _display = _format(r);
        }
      }
      _accumulator = null;
      _pendingOp = null;
      _freshEntry = true;
    });
  }

  double? _compute(double a, double b, String op) {
    switch (op) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        if (b == 0) return null;
        return a / b;
    }
    return b;
  }

  String _format(double v) {
    if (v.isNaN || v.isInfinite) return '错误';
    if (v == v.roundToDouble() && v.abs() < 1e15) {
      return v.toInt().toString();
    }
    String s = v.toStringAsFixed(8);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  // ══════════════ 解锁流程 ══════════════

  /// 右上角长按：弹密码框，输入正确密码后进入便签主界面。
  Future<void> _promptPassword() async {
    final TextEditingController ctrl = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('输入密码'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '密码'),
            onSubmitted: (_) => Navigator.of(ctx).pop(true),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    final String input = ctrl.text;
    ctrl.dispose();
    if (ok != true) return;
    if (input == CalculatorDisguisePage.unlockCode) {
      _unlock();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码错误')),
      );
    }
  }

  /// 通过校验后切到便签主界面。
  void _unlock() {
    final VoidCallback? cb = widget.onUnlocked;
    if (cb != null) {
      cb();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// 长按显示区域：进入坚果云文档导入页。
  void _openNutstoreImport() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const NutstoreImportPage(),
      ),
    );
  }

  // ══════════════ 解锁后的真实隐私设置 ══════════════

  void _openPrivacyPanel() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (BuildContext ctx) {
        return Consumer<SettingsService>(
          builder: (BuildContext c, SettingsService settings, Widget? child) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.security_outlined,
                          color: Theme.of(c).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '隐私与安全',
                        style: Theme.of(c).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('查看隐藏笔记需生物识别'),
                    subtitle: const Text('开启后，查看隐藏笔记前需要验证指纹或面容'),
                    value: settings.requireBiometricForHidden,
                    onChanged: (bool v) =>
                        settings.setRequireBiometricForHidden(v),
                  ),
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '提示：本页由「计算器」伪装入口进入。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ══════════════ UI ══════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: _openNutstoreImport,
                    child: Container(
                      alignment: Alignment.bottomRight,
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: Text(
                          _display,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 72,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  child: _buildKeypad(),
                ),
              ],
            ),
            // 右上角热区：长按 → 输入密码 → 进入便签主界面
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: _promptPassword,
                child: const SizedBox(width: 96, height: 88),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    final List<List<_Key>> rows = <List<_Key>>[
      <_Key>[
        _Key('C', _KeyKind.function, () => _clearAll()),
        _Key('±', _KeyKind.function, () => _toggleSign()),
        _Key('%', _KeyKind.function, () => _percent()),
        _Key('÷', _KeyKind.operator, () => _setOperator('÷')),
      ],
      <_Key>[
        _Key('7', _KeyKind.digit, () => _inputDigit('7')),
        _Key('8', _KeyKind.digit, () => _inputDigit('8')),
        _Key('9', _KeyKind.digit, () => _inputDigit('9')),
        _Key('×', _KeyKind.operator, () => _setOperator('×')),
      ],
      <_Key>[
        _Key('4', _KeyKind.digit, () => _inputDigit('4')),
        _Key('5', _KeyKind.digit, () => _inputDigit('5')),
        _Key('6', _KeyKind.digit, () => _inputDigit('6')),
        _Key('−', _KeyKind.operator, () => _setOperator('−')),
      ],
      <_Key>[
        _Key('1', _KeyKind.digit, () => _inputDigit('1')),
        _Key('2', _KeyKind.digit, () => _inputDigit('2')),
        _Key('3', _KeyKind.digit, () => _inputDigit('3')),
        _Key('+', _KeyKind.operator, () => _setOperator('+')),
      ],
      <_Key>[
        _Key('0', _KeyKind.digit, () => _inputDigit('0'), flex: 2),
        _Key('.', _KeyKind.digit, () => _inputDot()),
        _Key('=', _KeyKind.operator, () => _equals()),
      ],
    ];

    return Column(
      children: rows
          .map(
            (List<_Key> row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: <Widget>[
                  for (final _Key k in row)
                    Expanded(
                      flex: k.flex,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _buildButton(k),
                      ),
                    ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildButton(_Key k) {
    late final Color bg;
    late final Color fg;
    switch (k.kind) {
      case _KeyKind.function:
        bg = const Color(0xFF3A3A3C);
        fg = Colors.white;
        break;
      case _KeyKind.operator:
        bg = const Color(0xFFFF9F0A);
        fg = Colors.white;
        break;
      case _KeyKind.digit:
        bg = const Color(0xFF1C1C1E);
        fg = Colors.white;
        break;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(40),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: k.onTap,
        child: SizedBox(
          height: 68,
          child: Center(
            child: Text(
              k.label,
              style: TextStyle(
                color: fg,
                fontSize: 30,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _KeyKind { digit, operator, function }

class _Key {
  const _Key(this.label, this.kind, this.onTap, {this.flex = 1});

  final String label;
  final _KeyKind kind;
  final VoidCallback onTap;
  final int flex;
}

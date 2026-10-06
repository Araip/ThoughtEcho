import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import 'nutstore_import_page.dart';

/// 定制版：伪装计算器页（仿 Google 计算器 · 深夜模式）
///
/// 外观与行为是一个真正可用的计算器（支持表达式、三角函数、对数、
/// 复数 i 等），用于隐藏「隐私与安全」入口。
/// 在计算器上输入解锁码 [unlockCode]（默认 `1234`）后按「=」，
/// 才会进入便签主界面；右上角长按可输入密码解锁。
class CalculatorDisguisePage extends StatefulWidget {
  const CalculatorDisguisePage({super.key, this.onUnlocked});

  /// 解锁成功后的回调：由 AppLockGate 注入，用于切到便签主界面。
  final VoidCallback? onUnlocked;

  /// 解锁码：输入该数字后按「=」即可进入便签。
  static const String unlockCode = '1234';

  @override
  State<CalculatorDisguisePage> createState() =>
      _CalculatorDisguisePageState();
}

class _CalculatorDisguisePageState extends State<CalculatorDisguisePage> {
  // ── 显示状态（仿 Google 计算器：输入表达式 + 实时结果输出） ──
  String _expression = '';
  String _output = '';
  Color _outputColor = const Color(0xFFFFFFFF);

  // ══════════════ 按钮输入 ══════════════

  void _append(String s) {
    setState(() {
      _expression += s;
      _updateOutput();
    });
  }

  void _clearAll() {
    setState(() {
      _expression = '';
      _output = '';
      _outputColor = const Color(0xFFFFFFFF);
    });
  }

  void _backspace() {
    setState(() {
      if (_expression.isNotEmpty) {
        _expression = _expression.substring(0, _expression.length - 1);
      }
      _updateOutput();
    });
  }

  /// 输入「=」：若表达式恰为解锁码则解锁；否则计算结果并回填。
  void _equals() {
    final String trimmed = _expression.replaceAll(' ', '');
    if (trimmed == CalculatorDisguisePage.unlockCode) {
      _clearAll();
      _unlock();
      return;
    }
    final _Cplx? v = _eval(_expression);
    setState(() {
      if (v == null) {
        _output = '无效的运算';
        _outputColor = const Color(0xFFEF5350);
      } else {
        final String s = _fmt(v);
        _expression = s;
        _output = s;
        _outputColor = const Color(0xFFFFFFFF);
      }
    });
  }

  /// 实时求值：成功显示结果，失败回显原表达式。
  void _updateOutput() {
    if (_expression.trim().isEmpty) {
      _output = '';
      _outputColor = const Color(0xFFFFFFFF);
      return;
    }
    final _Cplx? v = _eval(_expression);
    if (v == null) {
      _output = _expression;
      _outputColor = const Color(0x88FFFFFF);
    } else {
      _output = _fmt(v);
      _outputColor = const Color(0xFFFFFFFF);
    }
  }

  /// 「F」更多函数菜单：插入 sin( cos( tan( ln( floor( 等。
  void _moreMenu() {
    const List<(String, String)> items = <(String, String)>[
      ('sin', 'sin('),
      ('cos', 'cos('),
      ('tan', 'tan('),
      ('ln', 'ln('),
      ('floor', 'floor('),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (String label, String insert) in items)
              ListTile(
                leading: const Icon(Icons.functions),
                title: Text(label),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _append(insert);
                },
              ),
          ],
        ),
      ),
    );
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

  // ══════════════ UI（仿 Google 计算器） ══════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                // 顶部：输入表达式 + 实时结果 + 指示条
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: _openNutstoreImport,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          // 输入表达式（左对齐、横向滚动）
                          SizedBox(
                            height: 48,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              reverse: true,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  _expression.isEmpty ? '0' : _expression,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 36,
                                    color: Color(0xFFE6E6E6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          // 输出结果（右对齐、大字）
                          SingleChildScrollView(
                            reverse: true,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                _output.isEmpty ? '0' : _output,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 76,
                                  fontWeight: FontWeight.w300,
                                  color: _outputColor,
                                ),
                              ),
                            ),
                          ),
                          // 指示条
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0xDDE6E6E6),
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(3),
                                  ),
                                ),
                                child: SizedBox(width: 36, height: 5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 按钮区
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
    final List<List<_CalcKey>> rows = <List<_CalcKey>>[
      // 第一行：e i π ^ F（五个）
      <_CalcKey>[
        _CalcKey('e', _CalcKeyKind.light, 20, () => _append('e')),
        _CalcKey('i', _CalcKeyKind.light, 20, () => _append('i')),
        _CalcKey('π', _CalcKeyKind.light, 20, () => _append('pi')),
        _CalcKey('^', _CalcKeyKind.light, 20, () => _append('^')),
        _CalcKey('F', _CalcKeyKind.light, 20, _moreMenu),
      ],
      // 第二行：AC ( ) ÷
      <_CalcKey>[
        _CalcKey('AC', _CalcKeyKind.ac, 30, _clearAll),
        _CalcKey('(', _CalcKeyKind.function, 30, () => _append('(')),
        _CalcKey(')', _CalcKeyKind.function, 30, () => _append(')')),
        _CalcKey('÷', _CalcKeyKind.function, 30, () => _append('/')),
      ],
      // 第三行：1 2 3 ×
      <_CalcKey>[
        _CalcKey('1', _CalcKeyKind.digit, 30, () => _append('1')),
        _CalcKey('2', _CalcKeyKind.digit, 30, () => _append('2')),
        _CalcKey('3', _CalcKeyKind.digit, 30, () => _append('3')),
        _CalcKey('×', _CalcKeyKind.function, 30, () => _append('*')),
      ],
      // 第四行：4 5 6 -
      <_CalcKey>[
        _CalcKey('4', _CalcKeyKind.digit, 30, () => _append('4')),
        _CalcKey('5', _CalcKeyKind.digit, 30, () => _append('5')),
        _CalcKey('6', _CalcKeyKind.digit, 30, () => _append('6')),
        _CalcKey('-', _CalcKeyKind.function, 30, () => _append('-')),
      ],
      // 第五行：7 8 9 +
      <_CalcKey>[
        _CalcKey('7', _CalcKeyKind.digit, 30, () => _append('7')),
        _CalcKey('8', _CalcKeyKind.digit, 30, () => _append('8')),
        _CalcKey('9', _CalcKeyKind.digit, 30, () => _append('9')),
        _CalcKey('+', _CalcKeyKind.function, 30, () => _append('+')),
      ],
      // 第六行：0 . 删 =
      <_CalcKey>[
        _CalcKey('0', _CalcKeyKind.digit, 30, () => _append('0')),
        _CalcKey('.', _CalcKeyKind.digit, 30, () => _append('.')),
        _CalcKey('删', _CalcKeyKind.function, 30, _backspace),
        _CalcKey('=', _CalcKeyKind.function, 30, _equals),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows
          .map(
            (List<_CalcKey> row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: <Widget>[
                  for (final _CalcKey k in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
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

  Widget _buildButton(_CalcKey k) {
    late final Color bg;
    switch (k.kind) {
      case _CalcKeyKind.ac:
        bg = const Color(0xFF5A2A45); // 深粉
        break;
      case _CalcKeyKind.function:
        bg = const Color(0xFF2C2F55); // 深紫蓝
        break;
      case _CalcKeyKind.digit:
      case _CalcKeyKind.light:
        bg = const Color(0xFF2A2A2E); // 深灰
        break;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: k.onTap,
        child: SizedBox(
          height: 56,
          child: Center(
            child: Text(
              k.label,
              style: TextStyle(
                color: const Color(0xFFF2F2F5),
                fontSize: k.fontSize,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════ 按钮模型 ══════════════

enum _CalcKeyKind { digit, function, light, ac }

class _CalcKey {
  const _CalcKey(this.label, this.kind, this.fontSize, this.onTap);

  final String label;
  final _CalcKeyKind kind;
  final double fontSize;
  final VoidCallback onTap;
}

// ══════════════ 表达式求值（支持实数 + 复数 i） ══════════════

class _EvalError implements Exception {}

/// 复数类型：re + im·i
class _Cplx {
  const _Cplx(this.re, this.im);

  final double re;
  final double im;

  static const _Cplx zero = _Cplx(0, 0);
  static const _Cplx e = _Cplx(2.718281828459045, 0);
  static const _Cplx pi = _Cplx(3.141592653589793, 0);
  static const _Cplx i = _Cplx(0, 1);

  bool get isReal => im.abs() < 1e-12;

  double get real => re;

  _Cplx add(_Cplx o) => _Cplx(re + o.re, im + o.im);
  _Cplx sub(_Cplx o) => _Cplx(re - o.re, im - o.im);
  _Cplx neg() => _Cplx(-re, -im);

  _Cplx mul(_Cplx o) => _Cplx(
        re * o.re - im * o.im,
        re * o.im + im * o.re,
      );

  _Cplx div(_Cplx o) {
    final double d = o.re * o.re + o.im * o.im;
    if (d == 0) throw _EvalError();
    return _Cplx(
      (re * o.re + im * o.im) / d,
      (im * o.re - re * o.im) / d,
    );
  }

  /// 模长
  double get abs => math.sqrt(re * re + im * im);

  /// 辐角
  double get arg => math.atan2(im, re);

  _Cplx pow(_Cplx o) {
    if (isReal && o.isReal) {
      final double r = math.pow(re, o.re).toDouble();
      if (r.isNaN) throw _EvalError();
      return _Cplx(r, 0);
    }
    // 极坐标：z^w = e^(w·ln z)
    final double m = abs;
    if (m == 0) return _Cplx.zero;
    final double lnM = math.log(m);
    final double a = arg;
    final double realPart = o.re * lnM - o.im * a;
    final double imagPart = o.re * a + o.im * lnM;
    final double scale = math.exp(realPart);
    return _Cplx(scale * math.cos(imagPart), scale * math.sin(imagPart));
  }

  _Cplx sin() {
    if (isReal) return _Cplx(math.sin(re), 0);
    return _Cplx(
      math.sin(re) * _cosh(im),
      math.cos(re) * _sinh(im),
    );
  }

  _Cplx cos() {
    if (isReal) return _Cplx(math.cos(re), 0);
    return _Cplx(
      math.cos(re) * _cosh(im),
      -math.sin(re) * _sinh(im),
    );
  }

  _Cplx tan() => sin().div(cos());

  _Cplx sinh() {
    if (isReal) return _Cplx(_sinh(re), 0);
    return _Cplx(
      _sinh(re) * math.cos(im),
      _cosh(re) * math.sin(im),
    );
  }

  _Cplx cosh() {
    if (isReal) return _Cplx(_cosh(re), 0);
    return _Cplx(
      _cosh(re) * math.cos(im),
      _sinh(re) * math.sin(im),
    );
  }

  _Cplx exp() {
    if (isReal) return _Cplx(math.exp(re), 0);
    final double scale = math.exp(re);
    return _Cplx(scale * math.cos(im), scale * math.sin(im));
  }

  _Cplx ln() {
    final double m = abs;
    if (m == 0) throw _EvalError();
    if (isReal && re > 0) return _Cplx(math.log(re), 0);
    return _Cplx(math.log(m), arg);
  }

  _Cplx sqrt() {
    if (isReal) {
      if (re >= 0) return _Cplx(math.sqrt(re), 0);
      return _Cplx(0, math.sqrt(-re));
    }
    final double m = abs;
    if (m == 0) return _Cplx.zero;
    final double a = arg / 2;
    final double s = math.sqrt(m);
    return _Cplx(s * math.cos(a), s * math.sin(a));
  }

  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
  static double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;
}

/// 词法单元
enum _TokKind { number, ident, op, lparen, rparen, comma }

class _Token {
  const _Token(this.kind, this.text);

  final _TokKind kind;
  final String text;
}

bool _isDigit(String c) => c.length == 1 && c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

bool _isIdentStart(String c) {
  if (c.isEmpty) return false;
  final int u = c.codeUnitAt(0);
  return (u >= 0x61 && u <= 0x7A) || (u >= 0x41 && u <= 0x5A) || u == 0x5F;
}

bool _isIdentPart(String c) => _isIdentStart(c) || _isDigit(c);

List<_Token> _tokenize(String s) {
  final List<_Token> out = <_Token>[];
  int i = 0;
  while (i < s.length) {
    final String c = s[i];
    if (c == ' ') {
      i++;
      continue;
    }
    if (_isDigit(c) || c == '.') {
      int j = i;
      bool seenDot = false;
      while (j < s.length) {
        final String ch = s[j];
        if (_isDigit(ch)) {
          j++;
        } else if (ch == '.' && !seenDot) {
          seenDot = true;
          j++;
        } else {
          break;
        }
      }
      // 科学计数法 e±digits
      if (j < s.length && (s[j] == 'e' || s[j] == 'E')) {
        int k = j + 1;
        if (k < s.length && (s[k] == '+' || s[k] == '-')) k++;
        if (k < s.length && _isDigit(s[k])) {
          while (k < s.length && _isDigit(s[k])) k++;
          j = k;
        }
      }
      out.add(_Token(_TokKind.number, s.substring(i, j)));
      i = j;
    } else if (_isIdentStart(c)) {
      int j = i;
      while (j < s.length && _isIdentPart(s[j])) j++;
      out.add(_Token(_TokKind.ident, s.substring(i, j)));
      i = j;
    } else {
      switch (c) {
        case '+':
        case '-':
        case '*':
        case '/':
        case '^':
          out.add(_Token(_TokKind.op, c));
          break;
        case '(':
          out.add(_Token(_TokKind.lparen, c));
          break;
        case ')':
          out.add(_Token(_TokKind.rparen, c));
          break;
        case ',':
          out.add(_Token(_TokKind.comma, c));
          break;
        default:
          break; // 忽略未知字符
      }
      i++;
    }
  }
  return out;
}

/// 递归下降解析器：expr -> term (+/- term)* ; term -> unary (*/ unary)* ;
/// unary -> (-) unary | power ; power -> atom (^ unary)? ; atom -> 数字/变量/函数/括号
class _Parser {
  _Parser(this.ts);

  final List<_Token> ts;
  int pos = 0;

  bool get atEnd => pos >= ts.length;

  _Token next() => ts[pos++];

  bool peekKind(_TokKind k) => !atEnd && ts[pos].kind == k;

  bool peekOp(String op) => !atEnd && ts[pos].kind == _TokKind.op && ts[pos].text == op;

  void expect(_TokKind k) {
    if (!peekKind(k)) throw _EvalError();
    pos++;
  }

  _Cplx parseExpr() {
    _Cplx left = parseTerm();
    while (peekOp('+') || peekOp('-')) {
      final String op = next().text;
      final _Cplx right = parseTerm();
      left = op == '+' ? left.add(right) : left.sub(right);
    }
    return left;
  }

  _Cplx parseTerm() {
    _Cplx left = parseUnary();
    while (peekOp('*') || peekOp('/')) {
      final String op = next().text;
      final _Cplx right = parseUnary();
      left = op == '*' ? left.mul(right) : left.div(right);
    }
    return left;
  }

  _Cplx parseUnary() {
    if (peekOp('-')) {
      next();
      return parseUnary().neg();
    }
    if (peekOp('+')) {
      next();
      return parseUnary();
    }
    return parsePower();
  }

  _Cplx parsePower() {
    final _Cplx base = parseAtom();
    if (peekOp('^')) {
      next();
      final _Cplx exp = parseUnary(); // 右结合
      return base.pow(exp);
    }
    return base;
  }

  _Cplx parseAtom() {
    if (peekKind(_TokKind.number)) {
      final double v = double.tryParse(next().text) ?? 0;
      return _Cplx(v, 0);
    }
    if (peekKind(_TokKind.ident)) {
      final String name = next().text.toLowerCase();
      if (name == 'e') return _Cplx.e;
      if (name == 'pi' || name == 'π') return _Cplx.pi;
      if (name == 'i') return _Cplx.i;
      if (peekKind(_TokKind.lparen)) {
        next(); // (
        final List<_Cplx> args = <_Cplx>[];
        if (!peekKind(_TokKind.rparen)) {
          args.add(parseExpr());
          while (peekKind(_TokKind.comma)) {
            next();
            args.add(parseExpr());
          }
        }
        expect(_TokKind.rparen);
        return _applyFunc(name, args);
      }
      throw _EvalError();
    }
    if (peekKind(_TokKind.lparen)) {
      next();
      final _Cplx v = parseExpr();
      expect(_TokKind.rparen);
      return v;
    }
    throw _EvalError();
  }
}

_Cplx _applyFunc(String name, List<_Cplx> args) {
  if (args.isEmpty) throw _EvalError();
  final _Cplx a = args[0];
  switch (name) {
    case 'sin':
      return a.sin();
    case 'cos':
      return a.cos();
    case 'tan':
      return a.tan();
    case 'sinh':
      return a.sinh();
    case 'cosh':
      return a.cosh();
    case 'tanh':
      return a.sinh().div(a.cosh());
    case 'arcsin':
    case 'asin':
      if (!a.isReal) throw _EvalError();
      return _Cplx(math.asin(a.real), 0);
    case 'arccos':
    case 'acos':
      if (!a.isReal) throw _EvalError();
      return _Cplx(math.acos(a.real), 0);
    case 'arctan':
    case 'atan':
      if (!a.isReal) throw _EvalError();
      return _Cplx(math.atan(a.real), 0);
    case 'ln':
      return a.ln();
    case 'lg':
      return a.ln().div(_Cplx(math.log(10), 0));
    case 'log':
      if (args.length < 2) throw _EvalError();
      return args[1].ln().div(a.ln());
    case 'exp':
      return a.exp();
    case 'abs':
      return _Cplx(a.abs, 0);
    case 'floor':
      if (!a.isReal) throw _EvalError();
      return _Cplx(a.real.floor().toDouble(), 0);
    case 'ceil':
      if (!a.isReal) throw _EvalError();
      return _Cplx(a.real.ceil().toDouble(), 0);
    case 'deg':
      if (!a.isReal) throw _EvalError();
      return _Cplx(a.real * 180 / math.pi, 0);
    case 'rad':
      if (!a.isReal) throw _EvalError();
      return _Cplx(a.real * math.pi / 180, 0);
    case 'mod':
      if (!a.isReal || args.length < 2 || !args[1].isReal) {
        throw _EvalError();
      }
      return _Cplx(a.real % args[1].real, 0);
    case 'atan2':
      if (!a.isReal || args.length < 2 || !args[1].isReal) {
        throw _EvalError();
      }
      return _Cplx(math.atan2(a.real, args[1].real), 0);
    case 'sqrt':
      return a.sqrt();
    default:
      throw _EvalError();
  }
}

/// 计算表达式，失败返回 null。
_Cplx? _eval(String expr) {
  try {
    final List<_Token> ts = _tokenize(expr);
    if (ts.isEmpty) return null;
    final _Parser p = _Parser(ts);
    final _Cplx v = p.parseExpr();
    if (!p.atEnd) return null;
    return v;
  } catch (_) {
    return null;
  }
}

String _fmt(_Cplx v) {
  if (v.im.abs() < 1e-12) {
    return _fmtReal(v.re);
  }
  // 复数显示
  final String imPart = _fmtImag(v.im);
  if (v.re.abs() < 1e-12) {
    return imPart;
  }
  final String rePart = _fmtReal(v.re);
  if (v.im < 0) {
    return '$rePart-${_fmtImag(-v.im)}';
  }
  return '$rePart+$imPart';
}

String _fmtImag(double x) {
  if (x.abs() < 0.001) return '0';
  if ((x - 1).abs() < 1e-12) return 'i';
  if ((x + 1).abs() < 1e-12) return '-i';
  return '${_trimNum(x)}i';
}

String _fmtReal(double x) {
  if (x.isNaN || x.isInfinite) return '无效的运算';
  if (x.abs() < 0.001) return '0';
  if (x == x.roundToDouble() && x.abs() < 1e15) {
    return x.toInt().toString();
  }
  return _trimNum(x);
}

String _trimNum(double x) {
  String s = x.toStringAsFixed(10);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  if (s == '-0') s = '0';
  return s;
}

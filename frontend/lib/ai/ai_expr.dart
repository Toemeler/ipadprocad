/// Arithmetic in action arguments — what lets the assistant write the number
/// it MEANS instead of a number it rounded.
///
/// ISSUE #83 — the first block of the session drew a C-clip from two arcs and
/// two lines. The model worked out `5·cos 30° = 4.330` in its head, wrote
/// three decimals, and the profile missed closing by 0.000127 mm. The app then
/// widened its weld tolerance to cover that one rounding. The tolerance was
/// never the problem: the model was being asked to do trigonometry and type
/// the answer, and every such answer is a rounded guess at a number the app
/// could compute exactly.
///
/// So any numeric argument may be an expression:
///
///   {"op": "sketch_line", "x1": "r_out*cos(30)", "y1": "r_out*sin(30)", ...}
///
/// evaluated here in double precision, so two ends written from the same
/// formula are the same point to the last bit, and no gap exists to weld.
///
/// DELIBERATELY TINY. Numbers, + - * / ^, parentheses, a fixed set of
/// functions, and names looked up through a callback. No assignment, no
/// strings, no loops, no user functions: nothing in a model reply is ever
/// executed as code, and this evaluates arithmetic only. Bounded in length and
/// depth so a hostile or runaway argument costs microseconds, not a hang.
library;

import 'dart:math' as math;

/// Longest expression accepted. A real one is a dozen characters.
const int kAiExprMaxLength = 240;

/// Deepest nesting accepted, in parentheses and unary signs together.
const int kAiExprMaxDepth = 32;

/// Why an expression did not evaluate — said so the next block can fix it.
class AiExprError implements Exception {
  const AiExprError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Looks a name up. Returns null for a name that does not exist, which the
/// evaluator turns into an error naming it.
typedef AiExprLookup = double? Function(String name);

/// The functions an expression may call. Trigonometry takes and returns
/// DEGREES, because every angle anywhere else in the protocol is in degrees
/// and a model mixing the two is exactly the error this file exists to remove.
const Set<String> kAiExprFunctions = {
  'sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'atan2', //
  'sqrt', 'abs', 'min', 'max', 'hypot', 'round', 'floor', 'ceil',
};

const double _d2r = math.pi / 180;

/// A trailing unit on the WHOLE argument: "12 mm", "30 deg", "30°". Units
/// are not converted — only the document's own units are accepted, so the
/// suffix is a label and nothing more (see [AiAction.number]).
final RegExp _unit = RegExp(r'\s*(mm|deg|°)\s*$', caseSensitive: false);

/// Whether [text] looks like arithmetic rather than a word.
///
/// "outer", "join", "Sketch2" are words and stay words; "12", "r+2",
/// "cos(30)" and "sk.cx" (a dotted anchor) are arithmetic. A bare identifier
/// is arithmetic only when [isName] says it is a known variable, so an
/// argument that happens to be a single word is never swallowed.
bool aiLooksLikeExpression(String text, {bool Function(String)? isName}) {
  final t = text.replaceFirst(_unit, '').trim();
  if (t.isEmpty) return false;
  // A single plain name — "outer", "Sketch1", "F3" — is a word unless it is
  // a variable the model defined. Checked FIRST: a name may contain digits.
  if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(t)) {
    return isName != null && isName(t);
  }
  if (RegExp(r'[0-9()+\-*/^]').hasMatch(t)) return true;
  return t.contains('.');
}

/// Evaluates [source]. Throws [AiExprError] with a message a model can act on.
double aiEvalExpression(String source, AiExprLookup lookup) {
  final text = source.replaceFirst(_unit, '').trim();
  if (text.isEmpty) throw const AiExprError('the expression is empty');
  if (text.length > kAiExprMaxLength) {
    throw const AiExprError(
        'the expression is longer than $kAiExprMaxLength characters');
  }
  final p = _Parser(text, lookup);
  final v = p.parse();
  if (!v.isFinite) {
    throw AiExprError('"$source" does not evaluate to a finite number');
  }
  return v;
}

class _Parser {
  _Parser(this.s, this.lookup);
  final String s;
  final AiExprLookup lookup;
  int i = 0;
  int depth = 0;

  double parse() {
    final v = _sum();
    _ws();
    if (i < s.length) {
      throw AiExprError('unexpected "${s[i]}" at position ${i + 1} in "$s"');
    }
    return v;
  }

  void _ws() {
    while (i < s.length && (s[i] == ' ' || s[i] == '\t')) {
      i++;
    }
  }

  bool _eat(String c) {
    _ws();
    if (i < s.length && s[i] == c) {
      i++;
      return true;
    }
    return false;
  }

  void _enter() {
    if (++depth > kAiExprMaxDepth) {
      throw const AiExprError('the expression is nested too deeply');
    }
  }

  double _sum() {
    var v = _product();
    while (true) {
      if (_eat('+')) {
        v += _product();
      } else if (_eat('-')) {
        v -= _product();
      } else {
        return v;
      }
    }
  }

  double _product() {
    var v = _unary();
    while (true) {
      if (_eat('*')) {
        v *= _unary();
      } else if (_eat('/')) {
        final d = _unary();
        if (d == 0) throw AiExprError('division by zero in "$s"');
        v /= d;
      } else {
        return v;
      }
    }
  }

  double _unary() {
    _enter();
    try {
      if (_eat('-')) return -_unary();
      if (_eat('+')) return _unary();
      return _power();
    } finally {
      depth--;
    }
  }

  double _power() {
    final base = _primary();
    if (_eat('^')) {
      // Right-associative, and binds tighter than a unary minus on its right
      // operand only: 2^-1 is 0.5, -2^2 is -4 as on paper.
      final e = _unary();
      return math.pow(base, e).toDouble();
    }
    return base;
  }

  double _primary() {
    _ws();
    if (i >= s.length) throw AiExprError('"$s" ends too early');
    final c = s.codeUnitAt(i);
    if (c == 0x28) {
      // (
      i++;
      _enter();
      final v = _sum();
      depth--;
      if (!_eat(')')) throw AiExprError('a ")" is missing in "$s"');
      return v;
    }
    if (_isDigit(c) || c == 0x2E) return _number();
    if (_isIdentStart(c)) return _identifier();
    throw AiExprError('unexpected "${s[i]}" at position ${i + 1} in "$s"');
  }

  double _number() {
    final start = i;
    while (i < s.length && (_isDigit(s.codeUnitAt(i)) || s[i] == '.')) {
      i++;
    }
    if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
      final save = i;
      i++;
      if (i < s.length && (s[i] == '+' || s[i] == '-')) i++;
      if (i < s.length && _isDigit(s.codeUnitAt(i))) {
        while (i < s.length && _isDigit(s.codeUnitAt(i))) {
          i++;
        }
      } else {
        i = save;
      }
    }
    final v = double.tryParse(s.substring(start, i));
    if (v == null) {
      throw AiExprError('"${s.substring(start, i)}" is not a number');
    }
    return v;
  }

  double _identifier() {
    final start = i;
    while (i < s.length && _isIdentPart(s.codeUnitAt(i))) {
      i++;
    }
    final name = s.substring(start, i);
    if (_eat('(')) {
      final args = <double>[];
      _enter();
      if (!_eat(')')) {
        do {
          args.add(_sum());
        } while (_eat(','));
        if (!_eat(')')) throw AiExprError('a ")" is missing after $name(...');
      }
      depth--;
      return _call(name, args);
    }
    if (name == 'pi') return math.pi;
    final v = lookup(name);
    if (v == null) {
      throw AiExprError('unknown name "$name" in "$s" — define it in the '
          'block\'s "vars", or use an anchor such as sk.cx or part.ymax');
    }
    return v;
  }

  double _call(String name, List<double> a) {
    void arity(int n) {
      if (a.length != n) {
        throw AiExprError('$name takes $n argument${n == 1 ? "" : "s"}, '
            'not ${a.length}');
      }
    }

    switch (name) {
      case 'sin':
        arity(1);
        return _clean(math.sin(a[0] * _d2r));
      case 'cos':
        arity(1);
        return _clean(math.cos(a[0] * _d2r));
      case 'tan':
        arity(1);
        return math.tan(a[0] * _d2r);
      case 'asin':
        arity(1);
        return math.asin(a[0]) / _d2r;
      case 'acos':
        arity(1);
        return math.acos(a[0]) / _d2r;
      case 'atan':
        arity(1);
        return math.atan(a[0]) / _d2r;
      case 'atan2':
        arity(2);
        return math.atan2(a[0], a[1]) / _d2r;
      case 'sqrt':
        arity(1);
        if (a[0] < 0) throw AiExprError('sqrt of a negative number in "$s"');
        return math.sqrt(a[0]);
      case 'abs':
        arity(1);
        return a[0].abs();
      case 'hypot':
        arity(2);
        return math.sqrt(a[0] * a[0] + a[1] * a[1]);
      case 'round':
        arity(1);
        return a[0].roundToDouble();
      case 'floor':
        arity(1);
        return a[0].floorToDouble();
      case 'ceil':
        arity(1);
        return a[0].ceilToDouble();
      case 'min':
      case 'max':
        if (a.isEmpty) throw AiExprError('$name needs at least one argument');
        return a.reduce(name == 'min' ? math.min : math.max);
    }
    throw AiExprError('unknown function "$name" — available: '
        '${kAiExprFunctions.join(", ")}');
  }

  /// sin(180) is 1.2e-16 in doubles, and a coordinate written as r*sin(180)
  /// should be exactly zero. Snapping the trig results that are within a few
  /// ulps of 0 or ±1 keeps the obvious angles exact without touching any
  /// value that is genuinely small.
  static double _clean(double v) {
    if (v.abs() < 1e-15) return 0;
    if ((v - 1).abs() < 1e-15) return 1;
    if ((v + 1).abs() < 1e-15) return -1;
    return v;
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
  static bool _isIdentStart(int c) =>
      (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;
  static bool _isIdentPart(int c) =>
      _isIdentStart(c) || _isDigit(c) || c == 0x2E;
}

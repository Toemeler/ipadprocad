// M41 — Inventors Parameter-/Ausdrucks-System für Bemaßungen.
//
// Jede Bemaßung IST ein benannter Parameter (Auto-Name d0, d1, … wie
// Inventor; umbenennbar per "Name = Ausdruck" im Edit-Feld). Das Edit-Feld
// akzeptiert vollwertige Ausdrücke: Zahlen mit Einheiten-Suffix, die
// Operatoren + - * / ^ % mit algebraischer Präzedenz, Klammern, die
// eingebauten Konstanten PI und E, Funktionen (sin/cos/tan in GRAD wie
// Inventors Default-Winkeleinheit, asin/acos/atan liefern Grad, dazu
// sqrt/abs/floor/ceil/round/exp/ln/log/sign/min/max/pow) und REFERENZEN auf
// andere Bemaßungen über deren Parameternamen. Ungültige Syntax färbt das
// Feld rot (Inventor), committet wird nur Gültiges.
//
// Einheiten pragmatisch wie die App (Basis mm bzw. Grad): Literale dürfen
// mm/cm/m bzw. deg/rad tragen und werden in die Basis umgerechnet, "ul"
// markiert einheitenlos. Parameter-Referenzen liefern ihren Basiswert
// direkt. Eine volle Einheiten-Algebra (mm^3-Fehlerprüfung etc.) ist
// bewusst NICHT nachgebaut — der Ausdruck wird numerisch ausgewertet.

import 'dart:math' as math;

/// Reserved words that cannot be parameter names.
const Set<String> kReservedIdents = {
  'pi', 'e', 'ul', 'mm', 'cm', 'm', 'deg', 'rad',
  'sin', 'cos', 'tan', 'asin', 'acos', 'atan',
  'sqrt', 'abs', 'floor', 'ceil', 'round', 'exp', 'ln', 'log', 'sign',
  'min', 'max', 'pow',
};

final RegExp _identRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// True when [s] is a legal user parameter name (Inventor: identifier,
/// not a reserved word/unit/function).
bool isValidParamName(String s) =>
    _identRe.hasMatch(s) && !kReservedIdents.contains(s.toLowerCase());

/// True when [s] is a PLAIN number entry (optional unit suffix) — such an
/// entry is stored as a value, not as an expression, so the label carries no
/// fx: prefix (Inventor shows fx: only for equation-driven dimensions).
bool isPlainNumber(String s) {
  var t = s.trim().toLowerCase().replaceAll(',', '.');
  for (final u in const ['mm', 'cm', 'deg', 'rad', 'ul', 'm']) {
    if (t.endsWith(u)) {
      t = t.substring(0, t.length - u.length).trim();
      break;
    }
  }
  return double.tryParse(t) != null;
}

/// Splits an optional "Name = expr" entry (Inventor renames/creates the
/// parameter this way). Returns (name|null, expr). A null name means the
/// entry is just an expression.
(String?, String) splitAssignment(String s) {
  final i = s.indexOf('=');
  if (i < 0) return (null, s);
  final name = s.substring(0, i).trim();
  final rest = s.substring(i + 1).trim();
  return (name, rest);
}

/// The parameter identifiers an expression references (excluding functions,
/// constants and unit suffixes). Empty set on a parse error.
Set<String> exprRefs(String expr) {
  try {
    final t = _Tokenizer(expr).tokens();
    return {
      for (final tk in t)
        if (tk.kind == _K.ident && !kReservedIdents.contains(tk.text.toLowerCase()))
          tk.text
    };
  } catch (_) {
    return {};
  }
}

/// Evaluates [expr] against [params] (name -> base value in mm resp. deg).
/// [angle] selects the default unit domain of bare literals: false = length
/// (mm), true = angle (deg). Returns null on any syntax/semantic error —
/// the caller shows Inventors red text.
double? evalExpr(String expr, Map<String, double> params,
    {bool angle = false}) {
  try {
    final p = _Parser(_Tokenizer(expr).tokens(), params, angle);
    final v = p.parseExpr();
    p.expectEnd();
    if (!v.isFinite) return null;
    return v;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------- tokenizer

enum _K { num, ident, op, lparen, rparen, semi, end }

class _Tok {
  final _K kind;
  final String text;
  final double num;
  _Tok(this.kind, this.text, [this.num = 0]);
}

class _Tokenizer {
  final String s;
  int i = 0;
  _Tokenizer(this.s);

  List<_Tok> tokens() {
    final out = <_Tok>[];
    while (i < s.length) {
      final c = s[i];
      if (c == ' ' || c == '\t') {
        i++;
      } else if (_isDigit(c) || c == '.' || c == ',') {
        out.add(_number());
      } else if (_isAlpha(c)) {
        final st = i;
        while (i < s.length && (_isAlpha(s[i]) || _isDigit(s[i]))) {
          i++;
        }
        out.add(_Tok(_K.ident, s.substring(st, i)));
      } else if ('+-*/^%'.contains(c)) {
        out.add(_Tok(_K.op, c));
        i++;
      } else if (c == '(') {
        out.add(_Tok(_K.lparen, c));
        i++;
      } else if (c == ')') {
        out.add(_Tok(_K.rparen, c));
        i++;
      } else if (c == ';') {
        // Inventor: ';' delimits multi-argument functions (',' collides with
        // the European decimal separator)
        out.add(_Tok(_K.semi, c));
        i++;
      } else {
        throw const FormatException('bad char');
      }
    }
    out.add(_Tok(_K.end, ''));
    return out;
  }

  _Tok _number() {
    final st = i;
    var dot = false;
    while (i < s.length) {
      final c = s[i];
      if (_isDigit(c)) {
        i++;
      } else if ((c == '.' || c == ',') && !dot) {
        dot = true;
        i++;
      } else {
        break;
      }
    }
    final t = s.substring(st, i).replaceAll(',', '.');
    final v = double.tryParse(t);
    if (v == null) throw const FormatException('bad number');
    return _Tok(_K.num, t, v);
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
  static bool _isAlpha(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5a) || (u >= 0x61 && u <= 0x7a) || c == '_';
  }
}

// ------------------------------------------------------------------ parser
//
// Recursive descent, algebraic order of operations (Inventor):
//   expr   := term (('+'|'-') term)*
//   term   := power (('*'|'/'|'%') power)*
//   power  := unary ('^' power)?          (right associative)
//   unary  := ('+'|'-')* atom
//   atom   := number unit? | ident | func '(' expr (';' expr)* ')'
//           | '(' expr ')' unit?

class _Parser {
  final List<_Tok> t;
  final Map<String, double> params;
  final bool angle;
  int p = 0;
  _Parser(this.t, this.params, this.angle);

  _Tok get cur => t[p];

  void expectEnd() {
    if (cur.kind != _K.end) throw const FormatException('trailing input');
  }

  double parseExpr() {
    var v = _term();
    while (cur.kind == _K.op && (cur.text == '+' || cur.text == '-')) {
      final op = cur.text;
      p++;
      final r = _term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _term() {
    var v = _power();
    while (cur.kind == _K.op &&
        (cur.text == '*' || cur.text == '/' || cur.text == '%')) {
      final op = cur.text;
      p++;
      final r = _power();
      if (op == '*') {
        v *= r;
      } else if (op == '/') {
        v /= r;
      } else {
        v = _fmod(v, r);
      }
    }
    return v;
  }

  double _power() {
    final v = _unary();
    if (cur.kind == _K.op && cur.text == '^') {
      p++;
      return math.pow(v, _power()).toDouble(); // right associative
    }
    return v;
  }

  double _unary() {
    var neg = false;
    while (cur.kind == _K.op && (cur.text == '+' || cur.text == '-')) {
      if (cur.text == '-') neg = !neg;
      p++;
    }
    final v = _atom();
    return neg ? -v : v;
  }

  double _atom() {
    final tk = cur;
    if (tk.kind == _K.num) {
      p++;
      return _applyUnit(tk.num);
    }
    if (tk.kind == _K.lparen) {
      p++;
      final v = parseExpr();
      if (cur.kind != _K.rparen) throw const FormatException(') expected');
      p++;
      return _maybeUnit(v);
    }
    if (tk.kind == _K.ident) {
      final name = tk.text;
      final low = name.toLowerCase();
      p++;
      if (cur.kind == _K.lparen) return _func(low);
      if (low == 'pi') return math.pi; // Inventors unitless PI = 3.14159…
      if (low == 'e') return math.e;
      final v = params[name];
      if (v == null) throw FormatException('unknown parameter $name');
      return v;
    }
    throw const FormatException('value expected');
  }

  double _func(String name) {
    p++; // '('
    final args = <double>[parseExpr()];
    while (cur.kind == _K.semi) {
      p++;
      args.add(parseExpr());
    }
    if (cur.kind != _K.rparen) throw const FormatException(') expected');
    p++;
    double a1() => args[0];
    switch (name) {
      case 'sin':
        return math.sin(a1() * math.pi / 180);
      case 'cos':
        return math.cos(a1() * math.pi / 180);
      case 'tan':
        return math.tan(a1() * math.pi / 180);
      case 'asin':
        return math.asin(a1()) * 180 / math.pi;
      case 'acos':
        return math.acos(a1()) * 180 / math.pi;
      case 'atan':
        return math.atan(a1()) * 180 / math.pi;
      case 'sqrt':
        return math.sqrt(a1());
      case 'abs':
        return a1().abs();
      case 'floor':
        return a1().floorToDouble();
      case 'ceil':
        return a1().ceilToDouble();
      case 'round':
        return a1().roundToDouble();
      case 'exp':
        return math.exp(a1());
      case 'ln':
        return math.log(a1());
      case 'log':
        return math.log(a1()) / math.ln10;
      case 'sign':
        return a1().sign;
      case 'min':
        return args.reduce(math.min);
      case 'max':
        return args.reduce(math.max);
      case 'pow':
        if (args.length != 2) throw const FormatException('pow needs 2 args');
        return math.pow(args[0], args[1]).toDouble();
    }
    throw FormatException('unknown function $name');
  }

  /// Consumes an optional unit ident after a literal / parenthesised value.
  double _maybeUnit(double v) {
    if (cur.kind == _K.ident) {
      final f = _unitFactor(cur.text.toLowerCase());
      if (f != null) {
        p++;
        return v * f;
      }
    }
    return v;
  }

  double _applyUnit(double v) => _maybeUnit(v);

  /// mm/deg are the base units; null = not a unit (identifier follows for
  /// other reasons, e.g. implicit multiplication is NOT supported — Inventor
  /// requires explicit operators too).
  double? _unitFactor(String u) {
    if (angle) {
      switch (u) {
        case 'deg':
          return 1;
        case 'rad':
          return 180 / math.pi;
        case 'ul':
          return 1;
      }
      return null;
    }
    switch (u) {
      case 'mm':
        return 1;
      case 'cm':
        return 10;
      case 'm':
        return 1000;
      case 'ul':
        return 1;
    }
    return null;
  }

  static double _fmod(double a, double b) => a - b * (a / b).truncateToDouble();
}

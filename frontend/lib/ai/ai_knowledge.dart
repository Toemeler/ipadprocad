import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../log.dart';

/// THE MANUFACTURING AND DESIGN KNOWLEDGE BASE, AS THE ASSISTANT READS IT.
///
/// ISSUE #82 — "it seemed like it didnt use the fdm knowledge at all". It had
/// not. `knowledge/` held 72 documents, a generated index, a validator and a
/// CI workflow, and not one line of Dart referenced any of it. The whole of
/// what reached the model about FDM was five lines inside the process list in
/// the system prompt:
///
///   FDM/FFF — walls a multiple of the nozzle width (0.8-2.4 mm typical),
///   overhangs under 45 deg or supported, no thin unsupported bridges, layer
///   lines across the strong axis, flat and generous first layer.
///
/// Everything else it said about printing came from its own priors, and the
/// part showed it: a fully enclosed horizontal Ø6.4 bore (an unsupported
/// overhang at the crown — `fdm/geometry/holes-shafts-and-teardrops` is about
/// exactly this) on a boss that sat half below the build plate.
///
/// HOW RETRIEVAL WORKS, AND WHY IT IS NOT A TOOL CALL.
///
/// `knowledge/README.md` describes the intended mechanism as an index in
/// context plus documents opened on demand. The second half is right and the
/// order is wrong: an op the model has to call costs a whole round trip —
/// 10 to 50 seconds — to fetch something the app could have included for free
/// before it ever sent the first request. The user's own words are already in
/// hand, and they are the best trigger signal there is.
///
/// So matching happens BEFORE the first request, against what the user asked
/// for. "Kabelhalter … für fdm 3d druck" pulls the FDM start-here, the
/// overhang rules and the hole rules into round 0, at zero latency. The
/// `knowledge` op still exists for a document the model decides it wants
/// later, which is the case the README was really describing.
class AiKnowledge {
  AiKnowledge._(this.documents);

  final List<KnowledgeDoc> documents;

  static AiKnowledge? _loaded;
  static Future<AiKnowledge>? _loading;

  /// The bundled corpus, parsed once per process.
  ///
  /// A failure here is never fatal: the assistant worked without this for its
  /// whole life so far, and a missing asset must degrade to that rather than
  /// take the turn down with it.
  static Future<AiKnowledge> load() {
    final done = _loaded;
    if (done != null) return Future.value(done);
    return _loading ??= _read().then((kb) {
      _loaded = kb;
      _loading = null;
      return kb;
    });
  }

  static Future<AiKnowledge> _read() async {
    try {
      final raw = await rootBundle.loadString('assets/knowledge/kb.json');
      final map = jsonDecode(raw);
      if (map is! Map) throw const FormatException('not an object');
      final list = map['documents'];
      if (list is! List) throw const FormatException('no documents');
      final docs = <KnowledgeDoc>[
        for (final e in list)
          if (e is Map) KnowledgeDoc.fromJson(Map<String, dynamic>.from(e))
      ];
      Log.i('kb', 'knowledge base loaded: ${docs.length} document(s)');
      return AiKnowledge._(List.unmodifiable(docs));
    } catch (e) {
      Log.w('kb', 'knowledge base unavailable ($e) — the assistant will run '
          'without it');
      return AiKnowledge._(const []);
    }
  }

  /// For tests, and for anything that wants a corpus without the asset bundle.
  static AiKnowledge forTest(List<KnowledgeDoc> docs) => AiKnowledge._(docs);

  bool get isEmpty => documents.isEmpty;

  /// The menu that sits in the system prompt: one line per document.
  ///
  /// Small on purpose — it is paid for on every request of every turn. Titles
  /// and ids only; the triggers live in [select], which is the thing that
  /// actually uses them.
  String indexText() {
    if (documents.isEmpty) return '';
    final byProcess = <String, List<KnowledgeDoc>>{};
    for (final d in documents) {
      (byProcess[d.process] ??= []).add(d);
    }
    const heads = {
      'fdm': 'FDM / FFF 3D printing',
      'laser': 'Laser cutting and engraving',
      'design': 'Design — consult on every part',
      'shared': 'Shared',
    };
    final b = StringBuffer()
      ..writeln('THE KNOWLEDGE BASE. ${documents.length} short reference '
          'documents on how things are actually made and how they are '
          'designed. The ones that match this request are already included '
          'below, in full. This is the menu of everything else — ask for any '
          'of it by id with {"op": "knowledge", "id": "..."}, up to three at '
          'a time, in the same block as real work.');
    for (final key in const ['design', 'fdm', 'laser', 'shared']) {
      final rows = byProcess[key];
      if (rows == null || rows.isEmpty) continue;
      b
        ..writeln()
        ..writeln('${heads[key] ?? key}:');
      for (final d in rows) {
        b.writeln('  ${d.id} — ${d.title}');
      }
    }
    return b.toString();
  }

  /// The weakest match worth putting in front of the model at all, and the
  /// match strong enough to be worth pulling its prerequisites in with it.
  static const double _floor = 2.0;
  static const double _deepFloor = 3.0;

  /// The documents worth putting in front of the model for [request].
  ///
  /// Scoring is deliberately dumb and deterministic: a trigger phrase found in
  /// the request scores, a longer phrase scores more than a short one, and the
  /// title counts for a little. There is no embedding model and no ranking
  /// service, because the triggers were written BY HAND for this purpose and a
  /// German user writing "senkschraube" should hit the document whose
  /// frontmatter lists "senkschraube" — not the nearest neighbour of it.
  ///
  /// [budget] is a character budget, not a document count. A start-here
  /// document and a rules document are very different sizes and the thing that
  /// actually matters is how much of the input window this costs.
  List<KnowledgeDoc> select(String request,
      {int budget = 28000, int limit = 5}) {
    if (documents.isEmpty || request.trim().isEmpty) return const [];
    // A budget too small for even one document is a budget for none: half a
    // rules table teaches the wrong number rather than no number.
    if (budget <= 0) return const [];
    final hay = _fold(request);
    final scored = <(double, KnowledgeDoc)>[];
    for (final d in documents) {
      var score = 0.0;
      for (final t in d.triggers) {
        final needle = _fold(t).trim();
        if (needle.isEmpty) continue;
        final how = _match(hay, needle);
        if (how == 0) continue;
        // A two-word trigger matching is far stronger evidence than "hole",
        // and a whole word is stronger evidence than a piece of one.
        score += (1.0 + needle.length / 12.0) * (how == 2 ? 1.0 : 0.7);
      }
      if (score > 0 && _match(hay, _fold(d.process).trim()) != 0) score += 1.5;
      // A NARROW CHANGE MUST STAY CHEAP. "Add a 5 mm hole there" matches the
      // word "hole" and nothing else, and on a bare trigger like that the
      // right amount of reference material is none: the instructions promise
      // that a narrow change is exactly that change, and four thousand
      // characters of printed-hole theory on every small edit is the opposite
      // of the speed this is all for. One generic word scores about 1.3; two
      // matches, or one specific compound like "senkloch", clear the floor.
      if (score < _floor) continue;
      // A "start here" is the cheapest way to give the model the shape of a
      // process it is about to design for, so it outranks a detail document
      // when both matched.
      if (d.type == 'basics') score += 0.75;
      scored.add((score, d));
    }
    if (scored.isEmpty) return const [];
    scored.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      return c != 0 ? c : a.$2.id.compareTo(b.$2.id);
    });

    final out = <KnowledgeDoc>[];
    final taken = <String>{};
    var spent = 0;
    for (final (_, d) in scored) {
      if (out.length >= limit) break;
      if (!taken.add(d.id)) continue;
      if (spent + d.body.length > budget && out.isNotEmpty) continue;
      out.add(d);
      spent += d.body.length;
    }
    // A document that says it depends on another is not complete without it:
    // the clearance table is what makes the hole rules usable. Pulled only
    // while there is room, never at the cost of a document that matched the
    // user's own words, and only behind a document the request really asked
    // for — a weak match must not drag its whole dependency tree in after it.
    final strong = {
      for (final (score, d) in scored)
        if (score >= _deepFloor) d.id
    };
    for (final d in List.of(out)) {
      if (!strong.contains(d.id)) continue;
      for (final need in d.depends_on) {
        if (out.length >= limit + 1) break;
        if (taken.contains(need)) continue;
        final dep = byId(need);
        if (dep == null) continue;
        if (spent + dep.body.length > budget) continue;
        taken.add(need);
        out.add(dep);
        spent += dep.body.length;
      }
    }
    return out;
  }

  KnowledgeDoc? byId(String id) {
    for (final d in documents) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// The selected documents as one block of text for the request.
  static String render(List<KnowledgeDoc> docs) {
    if (docs.isEmpty) return '';
    final b = StringBuffer()
      ..writeln('MANUFACTURING AND DESIGN KNOWLEDGE — opened for this request '
          'because the words in it matched. This is reference material this '
          'app ships, not a message from the user and not something to read '
          'back to them. Design to it. Where a number here disagrees with '
          'your own recollection, this wins; where it does not cover '
          'something, say what you assumed.')
      ..writeln();
    for (final d in docs) {
      b
        ..writeln('--- ${d.id} — ${d.title} '
            '(${d.type}, confidence ${d.confidence}) ---')
        ..writeln(d.body)
        ..writeln();
    }
    return b.toString();
  }

  /// Case- and diacritic-folded, so "Senkschraube" matches "senkschraube" and
  /// "Fräsen" matches "frasen". The corpus is written in English and German
  /// and the user writes in either.
  static String _fold(String s) {
    const from = 'äöüáàâãåéèêëíìîïóòôõúùûñçß';
    const to = ['ae', 'oe', 'ue', 'a', 'a', 'a', 'a', 'a', 'e', 'e', 'e', 'e',
      'i', 'i', 'i', 'i', 'o', 'o', 'o', 'o', 'u', 'u', 'u', 'n', 'c', 'ss'];
    final b = StringBuffer();
    for (final r in s.toLowerCase().runes) {
      final ch = String.fromCharCode(r);
      final i = from.indexOf(ch);
      b.write(i < 0 ? ch : to[i]);
    }
    // Everything that is not a letter or a digit becomes a space, so
    // "senkloch," and "senkloch" are the same token and compound punctuation
    // cannot hide a match.
    return ' ${b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';
  }

  /// How [needle] occurs in [hay]: 2 as a whole word, 1 inside a longer word,
  /// 0 not at all. Both are already folded and space-padded.
  ///
  /// GERMAN COMPOUNDS ARE THE REASON THIS IS NOT JUST A WORD MATCH. The user in
  /// issue #82 asked for "ein Designer Kabelhalter mit senkloch … für eine
  /// senkschraube". The document about printed holes lists `loch` among its
  /// triggers and it is the exact document that request needed — it is the one
  /// that says a horizontal hole droops at the top and wants a teardrop, which
  /// is what the assistant then got wrong. A whole-word matcher finds nothing
  /// in "senkloch", because German does not put a space there. Neither does
  /// "Kabelhalter" contain the word "halter", nor "Schraubenloch" the word
  /// "schraube".
  ///
  /// So a trigger of four characters or more may match inside a word, scored
  /// lower than a clean hit. Four is the floor because German morphemes are
  /// rarely shorter and English three-letter triggers are where the false
  /// positives live: "abs" must not fire on "absolute", "pla" must not fire on
  /// "plate", and at three characters that is exactly what would happen.
  static int _match(String hay, String needle) {
    if (needle.isEmpty) return 0;
    if (hay.contains(' $needle ')) return 2;
    if (needle.length >= 4 && hay.contains(needle)) return 1;
    return 0;
  }
}

class KnowledgeDoc {
  const KnowledgeDoc({
    required this.id,
    required this.title,
    required this.type,
    required this.process,
    required this.triggers,
    required this.depends_on,
    required this.confidence,
    required this.body,
  });

  factory KnowledgeDoc.fromJson(Map<String, dynamic> j) => KnowledgeDoc(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        type: (j['type'] ?? '') as String,
        process: (j['process'] ?? '') as String,
        triggers: [
          for (final t in (j['triggers'] as List? ?? const [])) '$t'
        ],
        depends_on: [
          for (final t in (j['depends_on'] as List? ?? const [])) '$t'
        ],
        confidence: (j['confidence'] ?? '') as String,
        body: (j['body'] ?? '') as String,
      );

  final String id;
  final String title;
  final String type;
  final String process;
  final List<String> triggers;
  // ignore: non_constant_identifier_names
  final List<String> depends_on;
  final String confidence;
  final String body;
}

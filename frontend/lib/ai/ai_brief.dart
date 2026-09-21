/// What the part is FOR — the requirements a shape cannot tell you.
///
/// Perception has a ceiling that no amount of pixels raises. The digest can
/// measure a wall at 2.8 mm and never know it has to clear a 6 mm cable; a
/// render can show a stance and never know the thing clamps to a desk edge.
/// That is not a gap in seeing, it is a gap in being told, and it is the
/// cheapest of the remaining gaps to close.
///
/// A brief is a small, per-document list of requirements. Each one keeps the
/// USER'S OWN WORDING separately from the assistant's reading of it, because
/// those are different claims and only one of them is evidence.
///
/// WHAT THIS IS NOT. It is not a spec format, a verification framework, or a
/// contract the app enforces. Nothing here checks a requirement against
/// geometry. It exists so the assistant stops re-asking what it was told two
/// turns ago, and so the user can see what it believes it was told — which is
/// the thing that makes a wrong reading correctable instead of invisible.
library;

import 'ai_models.dart';

/// How firm a requirement is. The distinction is the point: an assistant that
/// treats a preference as a constraint designs something nobody wanted, and
/// one that treats a constraint as a preference designs something that does
/// not fit.
enum AiRequirementKind {
  /// Must hold. A mating dimension, a clearance, an interface.
  must,

  /// Preferred. Taste, finish, "rather soft than technical".
  prefer,

  /// The assistant's own assumption, recorded so it can be corrected. Never
  /// promoted to [must] by the assistant — only the user can do that.
  assumption,
}

AiRequirementKind aiRequirementKindFrom(String? s) => switch (s) {
      'must' => AiRequirementKind.must,
      'prefer' => AiRequirementKind.prefer,
      _ => AiRequirementKind.assumption,
    };

class AiRequirement {
  AiRequirement({
    required this.text,
    this.kind = AiRequirementKind.assumption,
    this.source,
    this.done = false,
    String? id,
    DateTime? createdAt,
  })  : id = id ?? aiId(),
        createdAt = createdAt ?? DateTime.now().toUtc();

  final String id;

  /// The assistant's formalisation — what it believes the requirement means
  /// for this model.
  final String text;

  final AiRequirementKind kind;

  /// The user's own words, kept verbatim and never rewritten. When the two
  /// disagree, this is the one that is evidence.
  final String? source;

  final bool done;
  final DateTime createdAt;

  AiRequirement copyWith({bool? done}) => AiRequirement(
        id: id,
        text: text,
        kind: kind,
        source: source,
        done: done ?? this.done,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'kind': kind.name,
        if (source != null) 'source': source,
        if (done) 'done': true,
        'at': createdAt.toIso8601String(),
      };

  static AiRequirement fromJson(Map<String, dynamic> j) {
    final text = j['text'] as String? ?? '';
    if (text.isEmpty || text.length > kAiRequirementMaxLength) {
      throw const FormatException('Invalid requirement');
    }
    return AiRequirement(
      id: j['id'] as String? ?? aiId(),
      text: text,
      kind: aiRequirementKindFrom(j['kind'] as String?),
      source: j['source'] as String?,
      done: j['done'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(j['at'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
    );
  }
}

/// Bounds, for the same reason every other AI structure in this app has them:
/// this rides in the same store as the conversations and is replayed into the
/// context on every turn, so an unbounded one is an unbounded bill.
const int kAiRequirementMaxLength = 300;
const int kAiMaxRequirements = 40;

/// Every document's brief, keyed by document id.
class AiBriefs {
  final Map<String, List<AiRequirement>> _byDocument = {};

  List<AiRequirement> of(String documentId) =>
      List.unmodifiable(_byDocument[documentId] ?? const []);

  bool get isEmpty => _byDocument.values.every((l) => l.isEmpty);

  AiRequirement add(String documentId, AiRequirement requirement) {
    final list = _byDocument.putIfAbsent(documentId, () => []);
    if (list.length >= kAiMaxRequirements) {
      throw const AiException('context');
    }
    list.add(requirement);
    return requirement;
  }

  /// Marks one done. Returns null when the id is not in this document's brief
  /// — a caller that is told nothing would report a requirement satisfied that
  /// was never recorded.
  AiRequirement? markDone(String documentId, String id) {
    final list = _byDocument[documentId];
    if (list == null) return null;
    final i = list.indexWhere((r) => r.id == id);
    if (i < 0) return null;
    return list[i] = list[i].copyWith(done: true);
  }

  bool remove(String documentId, String id) {
    final list = _byDocument[documentId];
    if (list == null) return false;
    final before = list.length;
    list.removeWhere((r) => r.id == id);
    return list.length != before;
  }

  /// Document identities move when a document is renamed, exactly as the
  /// sessions' do.
  void migrate(String oldId, String newId) {
    final moved = _byDocument.remove(oldId);
    if (moved != null) _byDocument[newId] = moved;
  }

  void clear() => _byDocument.clear();

  /// The brief as the model reads it. Open requirements first: a satisfied one
  /// is history, and history is not what the next decision needs.
  String? contextFor(String documentId) {
    final all = of(documentId);
    if (all.isEmpty) return null;
    final open = [for (final r in all) if (!r.done) r];
    final done = all.length - open.length;
    if (open.isEmpty) return 'BRIEF: all $done requirement(s) marked done.';
    final b = StringBuffer('BRIEF (what the user has asked for, '
        'in their words where quoted):\n');
    for (final r in open) {
      b.writeln('- [${r.kind.name}] ${r.text}'
          '${r.source == null ? "" : '  — user said: "${r.source}"'}');
    }
    if (done > 0) b.writeln('($done more marked done.)');
    b.write('Do not re-ask what is already here. Do not weaken a "must" or '
        'promote your own assumption to one — only the user can.');
    return b.toString();
  }

  Map<String, dynamic> toJson() => {
        for (final e in _byDocument.entries)
          if (e.value.isNotEmpty)
            e.key: [for (final r in e.value) r.toJson()]
      };

  void loadJson(Map<String, dynamic> j) {
    _byDocument.clear();
    for (final e in j.entries) {
      final list = <AiRequirement>[];
      for (final r in (e.value as List? ?? const [])) {
        list.add(AiRequirement.fromJson(
            Map<String, dynamic>.from(r as Map)));
      }
      if (list.length > kAiMaxRequirements) {
        throw const FormatException('Brief too long');
      }
      if (list.isNotEmpty) _byDocument[e.key] = list;
    }
  }
}

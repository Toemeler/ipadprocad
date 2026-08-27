// M272 — an appearance on a body, and a kind you can see in the gallery.
//
// "in part mode i want to have a material selection all on the right in the
// ribbon. just a dropdown to assign a material to the currently selected
// solid. in assembly mode the same. [...] also in the menu each item should
// have some type of color to see if its an assembly, a part or a sketch."
//
// The colour itself is the easy half. These tests are about the three things
// that decide whether it is right:
//
//   * WHAT WINS. A body can be painted, selected and hovered at once, and the
//     three cannot compound. Selection is a question the user just asked; an
//     appearance is a fact they set once; so the question is on top.
//   * WHERE IT LIVES. On the BODY in a part (several features build one body),
//     on the OCCURRENCE in an assembly (two instances of one bracket may be
//     painted differently and the part document learns nothing). And it
//     follows a rename and dies with a delete, because it is keyed by name.
//   * WHAT A DOCUMENT WRITES. Nothing, when nothing is painted — a file from
//     before this milestone and a file after it are the same bytes.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/doc_file.dart' show kAssemblyDocKind;
import 'package:prototype/l10n/l.dart';
import 'package:prototype/materials.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_assembly.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/home_view.dart';

AppState _app() {
  final a = AppState();
  a.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m272_');
  return a;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(T.resetForTest);
  tearDown(T.resetForTest);

  group('the list itself', () {
    test('every offered id resolves to a colour, and steel to none', () {
      // Steel is the ABSENCE of a material: null leaves the renderer's own
      // steel material alone, shading and all. A colour that merely looked
      // like steel would flatten it.
      expect(materialArgb(kMaterialSteel), isNull);
      expect(materialArgb(null), isNull);
      for (final m in kMaterials) {
        expect(materialArgb(m.id), m.argb, reason: m.id);
        expect(m.argb >> 24 & 0xFF, 0xFF, reason: '${m.id} must be opaque');
      }
    });

    test('steel leads the menu and every id is offered exactly once', () {
      expect(materialIds.first, kMaterialSteel);
      expect(materialIds.toSet().length, materialIds.length);
      expect(materialIds.length, kMaterials.length + 1);
    });

    test('every colour is MUTED enough to still look lit', () {
      // A saturated primary on a shaded solid loses its modelling: the lit
      // face and the shadow converge on one screaming hue and the body reads
      // flat. This is the rule that keeps a later addition honest.
      for (final m in kMaterials) {
        final hsl = HSLColor.fromColor(m.color);
        expect(hsl.saturation, lessThan(0.5), reason: '${m.id} is too loud');
        expect(hsl.lightness, greaterThan(0.25), reason: '${m.id} is too dark');
        expect(hsl.lightness, lessThan(0.88), reason: '${m.id} is too pale');
      }
    });

    test('a stored id this build does not offer becomes steel', () {
      // Unlike a settings preference the user can re-pick, a body carrying an
      // unrenderable appearance would just look wrong with nothing on screen
      // to say why.
      expect(sanitiseMaterial('unobtainium'), isNull);
      expect(sanitiseMaterial(''), isNull);
      expect(sanitiseMaterial(kMaterialSteel), isNull);
      expect(sanitiseMaterial(7), isNull);
      expect(sanitiseMaterial('brass'), 'brass');
    });

    test('every appearance is named in the ARB, in both languages', () {
      for (final l in [const Locale('de'), const Locale('en')]) {
        final t = L.stringsFor(l);
        for (final id in materialIds) {
          expect(materialName(t, id), isNotEmpty, reason: id);
        }
        // Distinct names, or the menu has two rows that read the same.
        final names = [for (final id in materialIds) materialName(t, id)];
        expect(names.toSet().length, names.length);
      }
      expect(L.stringsFor(const Locale('de')).matBrass,
          isNot(L.stringsFor(const Locale('en')).matBrass));
    });
  });

  group('a part remembers it on the BODY', () {
    test('an unpainted part writes exactly the bytes it always did', () {
      final p = PartModel('P');
      expect(p.toJson().containsKey('materials'), isFalse);
    });

    test('painted, it round-trips', () {
      final p = PartModel('P');
      p.bodyMaterials['Solid1'] = 'brass';
      final back = PartModel('P')..loadJson(p.toJson());
      expect(back.bodyMaterials, {'Solid1': 'brass'});
    });

    test('an unknown id in a stored file is dropped, not kept', () {
      final back = PartModel('P')
        ..loadJson({
          'materials': {'Solid1': 'unobtainium', 'Solid2': 'copper'}
        });
      expect(back.bodyMaterials, {'Solid2': 'copper'});
    });
  });

  group('an assembly remembers it on the OCCURRENCE', () {
    AssemblyOccurrence occ({String? material}) => AssemblyOccurrence(
        id: 'Bracket:1', source: 'Bracket', material: material);

    test('an unpainted component writes nothing extra', () {
      expect(occ().toJson().containsKey('mat'), isFalse);
    });

    test('painted, it round-trips, and an unknown id becomes steel', () {
      final j = occ(material: 'copper').toJson();
      expect(AssemblyOccurrence.fromJson(j)!.material, 'copper');
      expect(
          AssemblyOccurrence.fromJson({...j, 'mat': 'unobtainium'})!.material,
          isNull);
    });

    test('two instances of ONE part can be painted differently', () {
      // The reason it is on the occurrence. Same rule M248 set for the mirror:
      // the part document learns nothing about either.
      final a = AssemblyModel('A');
      a.occurrences.add(occ(material: 'red'));
      a.occurrences.add(AssemblyOccurrence(
          id: 'Bracket:2', source: 'Bracket', material: 'blue'));
      expect(placedMaterials(a), ['red', 'blue']);
    });

    test('placedMaterials lines up with placedComponents, hidden ones too', () {
      // They are taken index for index by the painter; the same visibility
      // filter has to apply to both or it paints the wrong component.
      final a = AssemblyModel('A');
      a.occurrences.add(occ(material: 'red'));
      a.occurrences.add(AssemblyOccurrence(
          id: 'B:1', source: 'B', material: 'blue', visible: false));
      a.occurrences.add(AssemblyOccurrence(
          id: 'C:1', source: 'C', material: 'green'));
      expect(placedMaterials(a), ['red', 'green']);
      expect(placedMaterials(a).length, placedComponents(a).length);
    });
  });

  group('what wins on the wire', () {
    AssemblyOccurrence occ(String id, {String? material}) =>
        AssemblyOccurrence(id: id, source: 'P', material: material);

    test('selection beats the appearance, and hover beats it too', () {
      final a = AssemblyModel('A');
      final o = occ('P:1', material: 'red');
      a.occurrences.add(o);

      // Painted and idle: the appearance.
      expect(assemblyTint(a, o), materialArgb('red'));

      // Hovered: the hover tone, because the user is asking about it now.
      expect(assemblyTint(a, o, hoverId: 'P:1'), isNot(materialArgb('red')));

      // Selected: the selection colour, and selection beats hover as before.
      a.selected = o;
      expect(assemblyTint(a, o), T.faceHighlight.toARGB32());
      expect(assemblyTint(a, o, hoverId: 'P:1'), T.faceHighlight.toARGB32());
    });

    test('an unpainted component is still kNoTint, byte for byte', () {
      // The whole no-material path must be unchanged: kNoTint means the
      // renderer keeps its own steel material rather than being handed a
      // colour that happens to look like it.
      final a = AssemblyModel('A');
      final o = occ('P:1');
      a.occurrences.add(o);
      expect(assemblyTint(a, o), 0);
    });
  });

  group('the appearance follows the body it belongs to', () {
    test('a rename carries it', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      p.features.add(ExtrudeFeature(
          name: 'Extrusion1',
          bodyName: 'Solid1',
          sketchName: 'S',
          profiles: [ProfileSel(0, 0, 100)]));
      p.bodyMaterials['Solid1'] = 'brass';
      expect(app.renameBody('Solid1', 'Housing'), isTrue);
      // Keyed by NAME, so a rename that did not carry it would silently
      // repaint the body steel.
      expect(p.bodyMaterials, {'Housing': 'brass'});
    });

    test('a delete takes it', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      p.features.add(ExtrudeFeature(
          name: 'Extrusion1',
          bodyName: 'Solid1',
          sketchName: 'S',
          profiles: [ProfileSel(0, 0, 100)]));
      p.bodyMaterials['Solid1'] = 'brass';
      app.deleteBody('Solid1');
      expect(p.bodyMaterials, isEmpty);
    });
  });

  group('the ribbon control has something to act on', () {
    test('nothing selected, nothing to paint', () async {
      final app = _app();
      await app.createNamedPart('P');
      expect(app.canSetMaterial, isFalse);
      expect(app.selectedMaterial, isNull);
      // And it is inert rather than throwing: the control is dimmed, but a
      // stale tap must not be able to do anything either.
      app.setSelectedMaterial('brass');
      expect(app.currentPart!.bodyMaterials, isEmpty);
    });

    test('a selected body can be painted and stripped again', () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      p.features.add(ExtrudeFeature(
          name: 'Extrusion1',
          bodyName: 'Solid1',
          sketchName: 'S',
          profiles: [ProfileSel(0, 0, 100)]));
      app.selectBody('Solid1');
      expect(app.canSetMaterial, isTrue);

      app.setSelectedMaterial('copper');
      expect(app.selectedMaterial, 'copper');

      // Steel is a row in the same menu, so "back to plain" is one tap — and
      // it REMOVES the entry rather than storing the word.
      app.setSelectedMaterial(kMaterialSteel);
      expect(app.selectedMaterial, isNull);
      expect(p.bodyMaterials.containsKey('Solid1'), isFalse);
    });
  });

  group('the gallery says which kind a document is', () {
    test('a part is the un-tinted baseline; the other two lean', () {
      // Parts are the commonest document, and the neutral one is what the
      // other two are read against.
      for (final g in [kEmber, kChalk]) {
        expect(cardNameColor(g, 'part'), g.cardName);
        expect(cardNameColor(g, 'sketch'), isNot(g.cardName));
        expect(cardNameColor(g, kAssemblyDocKind), isNot(g.cardName));
        expect(cardNameColor(g, 'sketch'),
            isNot(cardNameColor(g, kAssemblyDocKind)));
      }
    });

    test('the tint is SLIGHT — the name still reads as the name', () {
      // "very slight and not too strong". Each channel stays within a third of
      // the way to the hue, which is what the constant says and what keeps a
      // column of names one typographic voice.
      expect(kKindTint, lessThanOrEqualTo(0.4));
      for (final g in [kEmber, kChalk]) {
        for (final kind in ['sketch', kAssemblyDocKind]) {
          final c = cardNameColor(g, kind);
          // Still recognisably the card ink, not a coloured label.
          expect((c.r - g.cardName.r).abs(), lessThan(0.35), reason: kind);
          expect((c.g - g.cardName.g).abs(), lessThan(0.35), reason: kind);
          expect((c.b - g.cardName.b).abs(), lessThan(0.35), reason: kind);
        }
      }
    });

    test('an unknown kind reads as the baseline rather than disappearing', () {
      expect(cardNameColor(kEmber, 'hologram'), kEmber.cardName);
    });
  });
}

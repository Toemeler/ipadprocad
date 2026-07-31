// M177 — the document-location model.
//
// These tests pin the rules that decide where a document lives and where Save
// puts it back. They are pure: no filesystem, so the rules can be stated once
// and checked without a device.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/doc_file.dart';
import 'package:prototype/doc_ref.dart';

const String _app = '/var/app/Documents';

void main() {
  group('M177 openActionFor', () {
    test('one of ours inside the app folder opens internally', () {
      expect(openActionFor('$_app/Bracket.ptp', _app), OpenAction.openInternal);
      expect(openActionFor('$_app/Plate.pts', _app), OpenAction.openInternal);
    });

    test('one of ours from anywhere else opens externally', () {
      expect(openActionFor('/private/iCloud/Bracket.ptp', _app),
          OpenAction.openExternal);
    });

    test('a sub-folder of the app folder is still external', () {
      // Prefix matching would call this internal, and Save would then quietly
      // relocate the file up one level.
      expect(openActionFor('$_app/Archive/Bracket.ptp', _app),
          OpenAction.openExternal);
    });

    test('a trailing slash on the app dir does not change the answer', () {
      expect(openActionFor('$_app/Bracket.ptp', '$_app/'),
          OpenAction.openInternal);
    });

    test('a folder merely starting with the app dir name is external', () {
      expect(openActionFor('${_app}Backup/Bracket.ptp', _app),
          OpenAction.openExternal);
    });

    test('STEP and DXF import, wherever they sit', () {
      expect(openActionFor('/somewhere/flange.dxf', _app), OpenAction.import);
      expect(openActionFor('/somewhere/flange.STEP', _app), OpenAction.import);
      expect(openActionFor('/somewhere/flange.stp', _app), OpenAction.import);
      // Even inside the app folder a STEP is not one of our documents.
      expect(openActionFor('$_app/flange.step', _app), OpenAction.import);
    });

    test('anything else is unsupported', () {
      expect(openActionFor('/somewhere/notes.txt', _app), OpenAction.unsupported);
      expect(openActionFor('/somewhere/Bracket', _app), OpenAction.unsupported);
      // ".ptp" as a bare name is a dotfile, not a document called "".
      expect(openActionFor('/somewhere/model.ptp.bak', _app),
          OpenAction.unsupported);
    });

    test('extension case does not matter for our own files', () {
      expect(openActionFor('$_app/Bracket.PTP', _app), OpenAction.openInternal);
    });
  });

  group('M177 saveTargetFor', () {
    test('external saves back to the file it was opened from', () {
      final r = DocRef('Bracket', 'part', '/private/iCloud/Bracket.ptp',
          DocSource.external);
      expect(saveTargetFor(r, _app), '/private/iCloud/Bracket.ptp');
    });

    test('external keeps its own filename even when it differs from the name',
        () {
      // The user renamed the file in Files; Save must not recreate the old one.
      final r = DocRef('Bracket', 'part', '/private/iCloud/Bracket v2.ptp',
          DocSource.external);
      expect(saveTargetFor(r, _app), '/private/iCloud/Bracket v2.ptp');
    });

    test('internal saves into the app folder under its document name', () {
      final r = DocRef('Bracket', 'part', '$_app/Bracket.ptp', DocSource.internal);
      expect(saveTargetFor(r, _app), '$_app/Bracket.$kPartExt');
    });

    test('an internal sketch gets the sketch extension', () {
      final r =
          DocRef('Plate', 'sketch', '$_app/Plate.pts', DocSource.internal);
      expect(saveTargetFor(r, _app), '$_app/Plate.$kSketchExt');
    });

    test('a trailing slash on the app dir does not double up', () {
      final r = DocRef('Bracket', 'part', '$_app/Bracket.ptp', DocSource.internal);
      expect(saveTargetFor(r, '$_app/'), '$_app/Bracket.$kPartExt');
    });
  });

  group('M177 scanAppFolder', () {
    test('picks up documents nobody imported', () {
      // The whole point: drop a file in the folder, it is there on next open.
      final got = scanAppFolder(
          ['Dropped.ptp', 'Sketch1.pts', 'notes.txt', 'flange.step'], _app);
      expect(got.map((d) => d.name), ['Dropped', 'Sketch1']);
      expect(got.map((d) => d.kind), ['part', 'sketch']);
      expect(got.first.path, '$_app/Dropped.ptp');
      expect(got.every((d) => d.source == DocSource.internal), isTrue);
    });

    test('sorts case-insensitively by name', () {
      final got = scanAppFolder(['beta.ptp', 'Alpha.ptp', 'gamma.ptp'], _app);
      expect(got.map((d) => d.name), ['Alpha', 'beta', 'gamma']);
    });

    test('an empty folder lists nothing rather than failing', () {
      expect(scanAppFolder(const [], _app), isEmpty);
    });

    test('never-opened documents carry no timestamp', () {
      expect(scanAppFolder(['Dropped.ptp'], _app).single.lastOpened, isNull);
    });
  });

  group('M177 mergedLibrary', () {
    final internal = [
      DocRef('Bracket', 'part', '$_app/Bracket.ptp', DocSource.internal),
    ];

    test('externals appear alongside internals', () {
      final got = mergedLibrary(internal, [
        DocRef('Adapter', 'part', '/icloud/Adapter.ptp', DocSource.external),
      ]);
      expect(got.map((d) => d.name), ['Adapter', 'Bracket']);
    });

    test('a vanished external is dropped', () {
      final got = mergedLibrary(internal, [
        DocRef('Gone', 'part', '/icloud/Gone.ptp', DocSource.external),
      ], stillExists: (_) => false);
      expect(got.map((d) => d.name), ['Bracket']);
    });

    test('without an existence check nothing is dropped', () {
      // iOS security-scoped paths can be temporarily unreachable; forgetting
      // the document then would lose the user's link to it for good.
      final got = mergedLibrary(internal, [
        DocRef('Maybe', 'part', '/icloud/Maybe.ptp', DocSource.external),
      ]);
      expect(got.map((d) => d.name), ['Bracket', 'Maybe']);
    });

    test('a remembered entry that is now inside the app folder does not double',
        () {
      final got = mergedLibrary(internal, [
        DocRef('Bracket', 'part', '$_app/Bracket.ptp', DocSource.external,
            DateTime.utc(2026, 1, 1)),
      ]);
      expect(got.length, 1);
    });

    test('a remembered internal entry is ignored', () {
      final got = mergedLibrary(internal, [
        DocRef('Stale', 'part', '$_app/Stale.ptp', DocSource.internal),
      ]);
      expect(got.map((d) => d.name), ['Bracket']);
    });
  });

  group('M177 remembered list round trip', () {
    test('externals survive encode and decode', () {
      final at = DateTime.utc(2026, 7, 31, 12, 30);
      final raw = encodeRemembered([
        DocRef('Adapter', 'part', '/icloud/Adapter.ptp', DocSource.external, at),
        DocRef('Plate', 'sketch', '/icloud/Plate.pts', DocSource.external),
      ]);
      final got = decodeRemembered(raw);
      expect(got.length, 2);
      expect(got.first.name, 'Adapter');
      expect(got.first.kind, 'part');
      expect(got.first.path, '/icloud/Adapter.ptp');
      expect(got.first.lastOpened, at);
      expect(got.last.kind, 'sketch');
      expect(got.last.lastOpened, isNull);
    });

    test('internals are never written out', () {
      final raw = encodeRemembered([
        DocRef('Bracket', 'part', '$_app/Bracket.ptp', DocSource.internal),
      ]);
      expect(decodeRemembered(raw), isEmpty);
      expect(raw, '[]');
    });

    test('garbage decodes to nothing rather than throwing', () {
      expect(decodeRemembered(null), isEmpty);
      expect(decodeRemembered(''), isEmpty);
      expect(decodeRemembered('   '), isEmpty);
      expect(decodeRemembered('not json'), isEmpty);
      expect(decodeRemembered('{"a":1}'), isEmpty);
      expect(decodeRemembered('[1,2,3]'), isEmpty);
    });

    test('a malformed entry is skipped and its neighbours survive', () {
      const raw = '[{"kind":"part"},'
          '{"name":"Ok","kind":"part","path":"/x/Ok.ptp","src":"external"}]';
      final got = decodeRemembered(raw);
      expect(got.map((d) => d.name), ['Ok']);
    });

    test('withOpenedAt only moves the timestamp', () {
      final r =
          DocRef('Adapter', 'part', '/icloud/Adapter.ptp', DocSource.external);
      final t = DateTime.utc(2026, 7, 31);
      final u = r.withOpenedAt(t);
      expect(u.name, r.name);
      expect(u.kind, r.kind);
      expect(u.path, r.path);
      expect(u.source, r.source);
      expect(u.lastOpened, t);
    });
  });
}

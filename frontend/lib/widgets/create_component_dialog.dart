// M250 — Inventor's CREATE IN-PLACE COMPONENT dialog.
//
// The layout, and how much of Inventor's is here:
//
//   ┌ Create In-Place Component ──────────────── ✕ ┐
//   │  New Component Name                          │
//   │  [Part1________________________________]     │
//   │  ☐ Constrain sketch plane to the selected    │
//   │    face                                      │
//   │                        [ OK ]  [ Cancel ]    │
//   └──────────────────────────────────────────────┘
//
// Inventor's has four more rows — Template, New File Location, Default BOM
// Structure and Virtual Component — and every one of them is absent rather
// than drawn disabled. The reasoning is in the Create Component section of
// AppState, and the short form is that each controls something this app does
// not have (one part kind, one gallery, no BOM), so a greyed row would invite
// the user to go looking for a feature that was never in the product.
//
// NOTE ON PROVENANCE, because this repo records it. M242's Place Constraint
// dialog is a transcription from screenshots of the real thing. This one is
// not: the field list is established from the Autodesk help (read as search
// summaries — help.autodesk.com is blocked from this network) and the LAYOUT
// is inferred. What is claimed is that these two controls are Inventor's, with
// Inventor's default for the checkbox (off). What is not claimed is that the
// arrangement matches pixel for pixel.
//
// The dialog is MODAL in spirit and modeless in mechanism: it takes no
// selection from the viewport (unlike Place Constraint, which is the reason
// that one floats), and OK does not finish the command — it hands over to the
// plane pick, which is what needs the viewport clear. So it is drawn as the
// same floating card every other panel in this app is, and it takes itself
// away the moment OK is accepted.
//
// Chrome from dialog_dock.dart, like every other floating panel here.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/l.dart';
import '../theme.dart';
import 'dialog_dock.dart';

class CreateComponentDialog extends StatefulWidget {
  final AppState app;
  const CreateComponentDialog({super.key, required this.app});

  @override
  State<CreateComponentDialog> createState() => _CreateComponentDialogState();
}

class _CreateComponentDialogState extends State<CreateComponentDialog> {
  Offset? _pos;
  final _name = TextEditingController();

  /// The session this controller was last filled from, so re-opening the
  /// command re-seeds the field and a rebuild mid-typing does not.
  CreateComponentSession? _seeded;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.createComponentSession;
    // Gone the moment the plane pick starts: the command is then out in the
    // viewport and the card would be sitting over the face you are trying to
    // point at. Nothing is lost — the name and the checkbox are on the
    // session, not in this widget.
    if (s == null || s.picking) return const SizedBox.shrink();
    final t = L.of(context);
    if (!identical(_seeded, s)) {
      _seeded = s;
      _name.text = s.name;
    }

    // 360, not 320: at 320 the title ellipsised to "Create In-Place Co…" in
    // the host's font, and the German one is longer again. Found by rendering
    // it — the ellipsis is the safety net, not the layout.
    const w = 360.0;
    const h = 176.0;
    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, const Size(w, h));
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: w,
          decoration: BoxDecoration(
            color: T.panel,
            border: Border.all(color: T.sep),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(color: T.scrim, blurRadius: 24, offset: Offset(0, 6)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _title(app, t),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.lblComponentName, style: ts(11, T.dim)),
                  const SizedBox(height: 4),
                  Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: T.fly,
                      border: Border.all(color: T.panelSep),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Center(
                      child: TextField(
                        controller: _name,
                        autofocus: true,
                        style: ts(12.5, T.text),
                        decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero),
                        onChanged: (v) => s.name = v,
                        onSubmitted: (_) => _ok(app, s),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _checkbox(
                    on: s.constrainSketchPlane,
                    label: t.chkConstrainSketchPlane,
                    onTap: () => setState(
                        () => s.constrainSketchPlane = !s.constrainSketchPlane),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                _flatButton(t.ok, () => _ok(app, s), primary: true),
                const SizedBox(width: 6),
                _flatButton(t.cancel, app.cancelCreateComponent),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// OK hands over to the plane pick. It does NOT close the command — the
  /// button in the ribbon stays lit, because naming the part and choosing what
  /// to sketch on are two halves of one command, and cancelling during the
  /// pick has to undo both.
  void _ok(AppState app, CreateComponentSession s) {
    s.name = _name.text;
    app.beginCreateComponentPick();
  }

  Widget _title(AppState app, AppL10n t) => GestureDetector(
        onPanUpdate: (d) => setState(() {
          final vp = MediaQuery.sizeOf(context);
          _pos = (_pos ?? DialogDock.spot(vp, const Size(360, 176))) + d.delta;
        }),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: T.fly,
            border: Border(bottom: BorderSide(color: T.panelSep)),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
          child: Row(children: [
            // EXPANDED, and no Spacer beside it. A `Flexible` next to a
            // `Spacer` splits the free width between them — the Spacer is an
            // Expanded with the same flex — so the title got half the card and
            // ellipsised at "Komponente vor Ort …" on a 360-wide dialog that
            // had room for all of it. Found by rendering it in German.
            Expanded(
              child: Text(t.dlgCreateComponent,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(13, T.text, w: FontWeight.w600)),
            ),
            GestureDetector(
              onTap: app.cancelCreateComponent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('✕', style: ts(12, T.dim)),
              ),
            ),
          ]),
        ),
      );

  Widget _checkbox({
    required bool on,
    required String label,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Container(
              width: 13,
              height: 13,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? T.accent : T.fly,
                border: Border.all(color: on ? T.accent : T.panelSep),
                borderRadius: BorderRadius.circular(2),
              ),
              child: on
                  ? const Icon(Icons.check, size: 10, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          // Two lines and wrapping, not ellipsis: the German label is long and
          // a truncated checkbox says nothing about what it does.
          Expanded(
            child: Text(label, maxLines: 2, style: ts(11, T.text)),
          ),
        ]),
      );

  /// [width] is a FLOOR, not a size — the same rule the ribbon's buttons and
  /// the constraint dialog's footer follow, so a longer German label grows the
  /// button instead of being clipped by it.
  Widget _flatButton(String label, VoidCallback? onTap,
          {bool primary = false, double width = 62}) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minWidth: width),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onTap == null
                ? T.fly
                : (primary ? T.accent.withValues(alpha: 0.22) : T.fly),
            border: Border.all(
                color: onTap != null && primary ? T.accent : T.panelSep),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(12, onTap == null ? T.dim : T.text,
                  w: primary ? FontWeight.w600 : FontWeight.normal)),
        ),
      );
}

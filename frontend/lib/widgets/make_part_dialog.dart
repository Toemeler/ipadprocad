// M255 — Inventor's MAKE PART dialog.
//
// The layout, and how much of Inventor's is here:
//
//   ┌ Make Part ──────────────────────────────── ✕ ┐
//   │  New Part Name                               │
//   │  [Solid4_______________________________]     │
//   │  Target Assembly                             │
//   │  [Assembly1____________________________]     │
//   │  Stays linked to “Bracket”.                  │
//   │                        [ OK ]  [ Cancel ]    │
//   └──────────────────────────────────────────────┘
//
// Inventor's has three more rows — Template, New File Location and BOM
// Structure — and a Solid Body list. Every one of them is absent rather than
// drawn disabled, for the reasons the Make Part section of AppState sets out:
// the body is the row you long-pressed, and the other three control things
// this app does not have. A greyed row for a concept that does not exist
// invites the user to go looking for a feature that was never in the product.
//
// THE LINE UNDER THE FIELDS is not Inventor's, and it is here on purpose. The
// whole difference between this command and "duplicate the body into a new
// file" is the link, the link is invisible, and the moment a user is deciding
// what to call the thing is the moment to say what they are getting.
//
// NOTE ON PROVENANCE, because this repo records it. Like M250's Create
// Component dialog and unlike M242's Place Constraint, this is NOT a
// transcription: the field list comes from the Autodesk help read as search
// summaries (help.autodesk.com is blocked from this network) and the LAYOUT is
// inferred. What is claimed is that these two fields are Inventor's. What is
// not claimed is that the arrangement matches pixel for pixel.
//
// Chrome from dialog_dock.dart, like every other floating panel here.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../l10n/l.dart';
import '../theme.dart';
import 'dialog_dock.dart';

class MakePartDialog extends StatefulWidget {
  final AppState app;
  const MakePartDialog({super.key, required this.app});

  @override
  State<MakePartDialog> createState() => _MakePartDialogState();
}

class _MakePartDialogState extends State<MakePartDialog> {
  Offset? _pos;
  final _part = TextEditingController();
  final _asm = TextEditingController();

  /// The session these controllers were last filled from, so re-opening the
  /// command re-seeds the fields and a rebuild mid-typing does not.
  MakePartSession? _seeded;

  static const double _w = 360;
  static const double _h = 236;

  @override
  void dispose() {
    _part.dispose();
    _asm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.makePartSession;
    if (s == null) return const SizedBox.shrink();
    final t = L.of(context);
    if (!identical(_seeded, s)) {
      _seeded = s;
      _part.text = s.partName;
      _asm.text = s.assemblyName;
    }
    final origin = app.currentPart?.name ?? s.body;

    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, const Size(_w, _h));
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: _w,
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
                  _field(t.lblNewPartName, _part,
                      autofocus: true,
                      onChanged: (v) => s.partName = v,
                      onSubmitted: (_) => _ok(app, s)),
                  const SizedBox(height: 10),
                  _field(t.lblTargetAssembly, _asm,
                      onChanged: (v) => s.assemblyName = v,
                      onSubmitted: (_) => _ok(app, s)),
                  const SizedBox(height: 10),
                  // Two lines and wrapping, not ellipsis: a truncated promise
                  // says nothing, and the German is longer.
                  Text(t.hintMakePartLink(origin),
                      maxLines: 2, style: ts(11, T.dim)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                _flatButton(t.ok, () => _ok(app, s), primary: true),
                const SizedBox(width: 6),
                _flatButton(t.cancel, app.cancelMakePart),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// OK finishes the command outright — unlike Create Component's, which hands
  /// over to a plane pick. There is nothing left to point at: the body was
  /// chosen by the long-press that opened this, and where the part goes is
  /// decided by the geometry (see the Make Part section of AppState), not by
  /// the user.
  void _ok(AppState app, MakePartSession s) {
    s.partName = _part.text;
    s.assemblyName = _asm.text;
    app.makePart();
  }

  Widget _field(
    String label,
    TextEditingController c, {
    bool autofocus = false,
    required ValueChanged<String> onChanged,
    required ValueChanged<String> onSubmitted,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: ts(11, T.dim)),
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
                controller: c,
                autofocus: autofocus,
                style: ts(12.5, T.text),
                decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero),
                onChanged: onChanged,
                onSubmitted: onSubmitted,
              ),
            ),
          ),
        ],
      );

  Widget _title(AppState app, AppL10n t) => GestureDetector(
        onPanUpdate: (d) => setState(() {
          final vp = MediaQuery.sizeOf(context);
          _pos = (_pos ?? DialogDock.spot(vp, const Size(_w, _h))) + d.delta;
        }),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: T.fly,
            border: Border(bottom: BorderSide(color: T.panelSep)),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
          child: Row(children: [
            // EXPANDED, and no Spacer beside it — see CreateComponentDialog:
            // a Flexible next to a Spacer splits the free width between them
            // and the title ellipsises at half the card.
            Expanded(
              child: Text(t.dlgMakePart,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(13, T.text, w: FontWeight.w600)),
            ),
            GestureDetector(
              onTap: app.cancelMakePart,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('✕', style: ts(12, T.dim)),
              ),
            ),
          ]),
        ),
      );

  /// [width] is a FLOOR, not a size — the same rule the ribbon's buttons and
  /// every other dialog footer here follow, so a longer German label grows the
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

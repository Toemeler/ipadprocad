// M255 — Inventor's MAKE PART dialog.
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
// M338 — drawn as an iOS panel (widgets/ios_kit.dart): two grouped sections,
// each headed by what its field is for, the promise about the link as the
// second one's footer, and OK / Cancel in the navigation bar.
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../l10n/l.dart';
import 'dialog_dock.dart';
import 'ios_kit.dart';

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
  /// command re-seeds them and a rebuild mid-typing does not.
  MakePartSession? _seeded;

  static const _size = Size(400, 320);

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
    final pos = _pos ?? DialogDock.spot(vp, _size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: IosPanel(
        width: _size.width,
        nav: IosNavBar(
          title: t.dlgMakePart,
          onDrag: (d) => setState(() => _pos = pos + d),
          leading: IosBarButton(label: t.cancel, onTap: app.cancelMakePart),
          trailing: IosBarButton(
              label: t.ok, prominent: true, onTap: () => _ok(app, s)),
        ),
        children: [
          iosSection(
            header: t.lblNewPartName,
            children: [
              iosTextRow(
                controller: _part,
                autofocus: true,
                onChanged: (v) => s.partName = v,
                onSubmitted: (_) => _ok(app, s),
              ),
            ],
          ),
          iosSection(
            header: t.lblTargetAssembly,
            footer: t.hintMakePartLink(origin),
            children: [
              iosTextRow(
                controller: _asm,
                onChanged: (v) => s.assemblyName = v,
                onSubmitted: (_) => _ok(app, s),
              ),
            ],
          ),
        ],
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
}

// M250 — Inventor's CREATE IN-PLACE COMPONENT dialog.
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
// The dialog is MODAL in spirit and modeless in mechanism: it takes no
// selection from the viewport (unlike Place Constraint, which is the reason
// that one floats), and OK does not finish the command — it hands over to the
// plane pick, which is what needs the viewport clear. So it is drawn as the
// same floating card every other panel in this app is, and it takes itself
// away the moment OK is accepted.
//
// M338 — that card is an iOS panel now (widgets/ios_kit.dart): the name is a
// field in a one-row grouped section, the checkbox is a switch, and OK and
// Cancel are the navigation bar's two ends.
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../l10n/l.dart';
import 'dialog_dock.dart';
import 'ios_kit.dart';

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

  static const _size = Size(400, 240);

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
    // point at. Nothing is lost — the name and the switch are on the session,
    // not in this widget.
    if (s == null || s.picking) return const SizedBox.shrink();
    final t = L.of(context);
    if (!identical(_seeded, s)) {
      _seeded = s;
      _name.text = s.name;
    }

    final vp = MediaQuery.sizeOf(context);
    final pos = _pos ?? DialogDock.spot(vp, _size);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: IosPanel(
        width: _size.width,
        nav: IosNavBar(
          title: t.dlgCreateComponent,
          onDrag: (d) => setState(() => _pos = pos + d),
          leading:
              IosBarButton(label: t.cancel, onTap: app.cancelCreateComponent),
          trailing: IosBarButton(
              label: t.ok, prominent: true, onTap: () => _ok(app, s)),
        ),
        children: [
          iosSection(
            header: t.lblComponentName,
            children: [
              iosTextRow(
                controller: _name,
                autofocus: true,
                onChanged: (v) => s.name = v,
                onSubmitted: (_) => _ok(app, s),
              ),
            ],
          ),
          iosSection(
            children: [
              iosSwitchRow(
                label: t.chkConstrainSketchPlane,
                value: s.constrainSketchPlane,
                onChanged: (v) =>
                    setState(() => s.constrainSketchPlane = v),
              ),
            ],
          ),
        ],
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
}

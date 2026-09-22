// The Delete Face / Direct Edit / Shell panel.
//
// M217 built the three face commands down to the feature, the kernel call and
// the viewport's face picking — and never built this. A user could open Delete
// Face, tap faces and watch them highlight, and then nothing in the interface
// could apply the edit: `applyFaceEdit()` had no caller. The commands looked
// finished and did nothing, which is the most expensive kind of control there
// is. #85 then added Shell on the same session and found it the same way.
//
// One panel for all five, as one session serves them: the picked faces, and
// the ONE number each command needs —
//
//   Delete Face   nothing
//   Move          a distance, along the first picked face's own normal
//   Size          how much the picked round faces' radius changes
//   Scale         a factor (no faces: the whole body)
//   Shell         the wall thickness, and whether it grows outward
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../ios_design.dart';
import '../part_model.dart' show FaceEditKind, FaceEditSession;
import 'dialog_dock.dart';
import 'ios_kit.dart';
import '../l10n/cad_terms.dart';
import '../l10n/l.dart';

class FaceEditDialog extends StatefulWidget {
  final AppState app;
  const FaceEditDialog({super.key, required this.app});

  @override
  State<FaceEditDialog> createState() => _FaceEditDialogState();
}

class _FaceEditDialogState extends State<FaceEditDialog> {
  final _value = TextEditingController();
  bool _open = true;
  Offset? _pos;
  String? _syncedFor;

  static const _size = Size(IosMetrics.panelWidth, 300);

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  /// Seed the field ONCE per session, like every other panel: re-seeding on
  /// each build would fight the cursor while the user types.
  void _syncOnce(FaceEditSession s) {
    final id = '${s.kind}/${identityHashCode(s)}';
    if (_syncedFor == id) return;
    _syncedFor = id;
    _value.text = switch (s.kind) {
      FaceEditKind.move => _fmt(s.distance),
      FaceEditKind.size => _fmt(s.dx),
      FaceEditKind.scale => _fmt(s.factor),
      FaceEditKind.shell => _fmt(s.thickness),
      FaceEditKind.delete => '',
    };
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  /// A typed number, accepting a decimal comma, or null while it is not one.
  static double? _parse(String v) =>
      double.tryParse(v.trim().replaceAll(',', '.'));

  void _changed(FaceEditSession s, String v) {
    final n = _parse(v);
    if (n == null) return;
    final app = widget.app;
    switch (s.kind) {
      case FaceEditKind.move:
        app.setFaceEditValue(distance: n);
      case FaceEditKind.size:
        app.setFaceEditValue(dx: n);
      case FaceEditKind.scale:
        app.setFaceEditValue(factor: n);
      case FaceEditKind.shell:
        app.setFaceEditValue(thickness: n);
      case FaceEditKind.delete:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final s = app.faceEdit;
    if (s == null) return const SizedBox.shrink();
    _syncOnce(s);
    final t = L.of(context);
    final n = s.faces.length;
    final vp = DialogDock.viewport(context);
    final pos = _pos ?? DialogDock.spot(vp, _size);
    final valueLabel = switch (s.kind) {
      FaceEditKind.move => t.lblDistance,
      FaceEditKind.size => t.lblRadiusChange,
      FaceEditKind.scale => t.lblScaleFactor,
      FaceEditKind.shell => t.lblThickness,
      FaceEditKind.delete => null,
    };
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: IosPanel(
        width: _size.width,
        nav: IosNavBar(
          title: faceEditName(t, s.kind),
          onDrag: (d) => setState(() => _pos = pos + d),
          leading: IosBarButton(label: t.cancel, onTap: app.cancelFaceEdit),
          trailing: IosBarButton(
              label: t.ok,
              prominent: true,
              onTap: app.faceEditReady ? () => app.applyFaceEdit() : null),
        ),
        children: [
          iosSection(
            header: t.secInputGeometry,
            open: _open,
            onToggle: () => setState(() => _open = !_open),
            footer: s.kind == FaceEditKind.move ? t.hintAlongFirstFace : null,
            children: [
              // Scale takes the whole body; there is nothing to pick.
              if (s.kind != FaceEditKind.scale)
                iosPickRow(
                  label: t.lblFaces,
                  value: n == 0 ? null : t.lblFaceCount(n),
                  hint: t.hintTapFacesIn3d,
                  armed: n == 0,
                  filled: n > 0,
                ),
              if (valueLabel != null)
                iosValueRow(
                  app: app,
                  label: valueLabel,
                  controller: _value,
                  unit: s.kind == FaceEditKind.scale ? null : 'mm',
                  onChanged: (v) => _changed(s, v),
                ),
              if (s.kind == FaceEditKind.shell)
                iosSwitchRow(
                  label: t.lblOutward,
                  value: s.outward,
                  onChanged: (v) => app.setFaceEditValue(outward: v),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

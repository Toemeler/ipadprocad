// iPadProCAD — home view (#home): a Procreate-style sketch gallery.
//
// Big bold title top-left, a round "+" (new sketch) button top-right, and a
// responsive grid of large, rounded, drop-shadowed thumbnail cards — one per
// saved sketch. Tapping a card opens that sketch (the bottom tab bar keeps
// switching between open sketches). Fresh installs show a friendly empty
// state instead of the old design-dummy cards.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_state.dart';
import '../svg_icons.dart';
import '../theme.dart';

// Card sizing: previews are rendered 380x240 (see _writePreview), so the cards
// keep that landscape aspect. We aim for a comfortable, touch-friendly width
// and let the grid pack as many even columns as fit the iPad width.
const double _kCardTarget = 250; // preferred card width
const double _kCardAspect = 380 / 240; // preview aspect (w/h)
const double _kGap = 26; // spacing between cards
const double _kPad = 34; // outer padding

class HomeView extends StatelessWidget {
  final AppState app;
  const HomeView({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: T.galleryBg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ---- gallery header: title left, new-sketch button right ----
        Padding(
          padding: const EdgeInsets.fromLTRB(_kPad, 22, _kPad, 18),
          child: Row(children: [
            Text('CAD',
                style: ts(32, T.galleryTitle, w: FontWeight.w700, height: 1.0)),
            const Spacer(),
            _PlusButton(onTap: app.createNewSketch),
          ]),
        ),
        Expanded(
          child: app.saved.isEmpty
              ? _EmptyState(onNew: app.createNewSketch)
              : _Grid(app: app),
        ),
      ]),
    );
  }
}

class _Grid extends StatelessWidget {
  final AppState app;
  const _Grid({required this.app});

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final avail = c.maxWidth - 2 * _kPad;
      // How many columns fit at (roughly) the target width, min 1.
      var cols = ((avail + _kGap) / (_kCardTarget + _kGap)).floor();
      if (cols < 1) cols = 1;
      final cardW = (avail - (cols - 1) * _kGap) / cols;
      final cardH = cardW / _kCardAspect;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(_kPad, 4, _kPad, 30),
        child: Wrap(
          spacing: _kGap,
          runSpacing: _kGap,
          children: [
            for (final s in app.saved)
              SizedBox(
                width: cardW,
                child: _Card(
                  name: s.name,
                  date: _fmt(s.modified),
                  preview: s.preview,
                  thumbHeight: cardH,
                  onTap: () => app.openSketch(s.name),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _PlusButton extends StatefulWidget {
  final VoidCallback onTap;
  const _PlusButton({required this.onTap});
  @override
  State<_PlusButton> createState() => _PlusButtonState();
}

class _PlusButtonState extends State<_PlusButton> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _h ? T.galleryActionBgHover : T.galleryActionBg,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add, color: T.galleryTitle, size: 26),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyState({required this.onNew});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Opacity(
          opacity: 0.5,
          child: SvgPicture.string(sketchCubeIcon, width: 54, height: 54),
        ),
        const SizedBox(height: 20),
        Text('No sketches yet',
            style: ts(18, T.cardName, w: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Tap  +  to start a new sketch',
            style: ts(13.5, T.cardDate)),
      ]),
    );
  }
}

class _Card extends StatefulWidget {
  final String name, date;
  final File? preview;
  final double thumbHeight;
  final VoidCallback onTap;
  const _Card({
    required this.name,
    required this.date,
    required this.preview,
    required this.thumbHeight,
    required this.onTap,
  });
  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AnimatedScale(
            scale: _h ? 1.02 : 1.0,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: Container(
              height: widget.thumbHeight,
              decoration: BoxDecoration(
                color: T.galleryThumb,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _h ? T.cardHoverBorder : Colors.transparent,
                    width: 1.5),
                boxShadow: const [
                  BoxShadow(
                      color: T.cardShadow, blurRadius: 14, offset: Offset(0, 6)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.5),
                child: widget.preview != null
                    ? Image.file(widget.preview!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _blank())
                    : _blank(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(widget.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: ts(13.5, T.cardName, w: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(widget.date,
              textAlign: TextAlign.center,
              style: ts(11.5, T.cardDate)),
        ]),
      ),
    );
  }

  Widget _blank() => Center(
        child: Opacity(
          opacity: 0.5,
          child: SvgPicture.string(sketchCubeIcon, width: 30, height: 30),
        ),
      );
}

// iPadProCAD — home view (#home), simplified Inventor start page, 1:1 port.
// "Recent" heading + 190px card grid. No sorting/search/pinning (deliberate).
// Cards: real saved sketches with generated preview PNGs; while nothing has
// been saved yet, the six design dummies from the mock (no content).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_state.dart';
import '../svg_icons.dart';
import '../theme.dart';

class HomeView extends StatelessWidget {
  final AppState app;
  const HomeView({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final cards = <(String, String, File?)>[];
    if (app.saved.isNotEmpty) {
      String fmt(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      for (final s in app.saved) {
        cards.add((s.name, fmt(s.modified), s.preview));
      }
    } else {
      for (final (n, d) in AppState.dummyCards) {
        cards.add((n, d, null));
      }
    }
    return Container(
      color: T.bg,
      padding: const EdgeInsets.fromLTRB(34, 26, 34, 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Recent',
            style: ts(20, T.homeH1, w: FontWeight.w600)),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final c in cards)
                  _Card(
                      name: c.$1,
                      date: c.$2,
                      preview: c.$3,
                      onTap: () => app.openSketch(c.$1)),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _Card extends StatefulWidget {
  final String name, date;
  final File? preview;
  final VoidCallback onTap;
  const _Card(
      {required this.name,
      required this.date,
      required this.preview,
      required this.onTap});
  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 190,
          decoration: BoxDecoration(
            color: T.cardBg,
            border: Border.all(color: _h ? T.cardHoverBorder : T.cardBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 120,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.2),
                    radius: 0.95,
                    colors: [Color(0xFF333A42), Color(0xFF23282E)],
                    stops: [0.0, 0.75],
                  ),
                ),
                child: widget.preview != null
                    ? Image.file(widget.preview!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _cube())
                    : _cube(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name,
                        style: ts(12.5, T.cardName, w: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(widget.date, style: ts(11.5, T.cardDate)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _cube() => Center(
        child: Opacity(
          opacity: 0.55,
          child: SvgPicture.string(sketchCubeIcon, width: 26, height: 26),
        ),
      );
}

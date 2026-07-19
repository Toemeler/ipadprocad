// iPadProCAD — bottom tab bar (#tabbar, 30px, #14171B), 1:1 port.
// Home on the left, one tab per open sketch with ✕, active tab lighter with
// a 2px blue underline, burger on the far right.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_state.dart';
import '../svg_icons.dart';
import '../theme.dart';

class BottomTabBar extends StatelessWidget {
  final AppState app;
  const BottomTabBar({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: const BoxDecoration(
        color: T.tabbarBg,
        border: Border(top: BorderSide(color: T.tabbarBorder)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The Home tab runs flush to the LEFT EDGE — its background and blue
        // underline fill into the iPad's rounded bottom-left screen corner
        // instead of leaving a dead 16px gutter there. Only its CONTENT is
        // pushed inward (leftPad), so the icon and label still clear the
        // corner radius and cannot be clipped. Previously the whole tab was
        // offset by 16, which put the label at 16+12=28 — leftPad keeps the
        // label exactly where it was and moves only the background.
        _Tab(
          leftPad: 28,
          on: app.isHome,
          onTap: app.goHome,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SvgPicture.string(homeTabIcon, width: 13, height: 13),
            const SizedBox(width: 6),
            const Text('Home'),
          ]),
        ),
        for (final t in app.openTabs)
          _Tab(
            on: app.curTab == t,
            onTap: () => app.openSketch(t),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(t),
              const SizedBox(width: 6),
              _CloseX(onTap: () => app.closeTab(t)),
            ]),
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(child: Text('☰', style: ts(15, T.tabText))),
        ),
      ]),
    );
  }
}

class _Tab extends StatefulWidget {
  final bool on;
  final VoidCallback onTap;
  final Widget child;

  /// Left inset of the tab's CONTENT only — the background still starts at the
  /// tab's own origin. Used to clear the screen's rounded corner.
  final double leftPad;
  const _Tab({
    required this.on,
    required this.onTap,
    required this.child,
    this.leftPad = 12,
  });
  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.on || _h ? Colors.white : T.tabText;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: widget.on ? T.tabOnBg : T.tabBg,
            border: const Border(right: BorderSide(color: T.tabbarBorder)),
          ),
          child: Stack(children: [
            Padding(
              padding: EdgeInsets.only(left: widget.leftPad, right: 12),
              child: Center(
                child: DefaultTextStyle(
                  style: ts(12.5, color),
                  child: widget.child,
                ),
              ),
            ),
            if (widget.on)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SizedBox(
                    height: 2,
                    child: ColoredBox(color: T.tabUnderline)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _CloseX extends StatefulWidget {
  final VoidCallback onTap;
  const _CloseX({required this.onTap});
  @override
  State<_CloseX> createState() => _CloseXState();
}

class _CloseXState extends State<_CloseX> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Text('✕',
              style: ts(11, _h ? Colors.white : const Color(0xFF8B9197))),
        ),
      ),
    );
  }
}

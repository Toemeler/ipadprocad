// Prototype — bottom tab bar (#tabbar, 30px, #14171B), 1:1 port.
// Home on the left, one tab per open sketch with ✕, active tab lighter with
// a 2px blue underline, burger on the far right.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../svg_icons.dart';
import '../theme.dart';

/// M149 — the tab model handed to UIKit. Pure, so it can be tested on the
/// host: this is where "which document is current" and "what may be closed"
/// are decided, and none of that should live in Swift.
List<GlassTab> buildTabs(AppState app) => [
      GlassTab(
        id: kHomeTabId,
        // The house speaks for itself — the word next to it was redundant.
        symbol: app.isHome ? 'house.fill' : 'house',
        selected: app.isHome,
      ),
      for (final t in app.openTabs)
        GlassTab(
          id: t,
          label: t,
          // Same glyph vocabulary as the model browser: a part is a cube, a
          // sketch is stacked squares. Two panels naming the same thing two
          // different ways is worse than either name.
          symbol: app.parts.containsKey(t) ? 'cube' : 'square.on.square',
          selected: !app.isHome && app.curTab == t,
          closable: true,
        ),
    ];

/// Identity of the Home tab on the wire. Not a document id, so it cannot
/// collide with one.
const String kHomeTabId = '\u0000home';

/// The bar. Native UIKit on iOS (M149); the original Flutter row everywhere
/// else, so the host tests and any desktop run keep working unchanged.
class BottomTabBar extends StatelessWidget {
  final AppState app;
  const BottomTabBar({super.key, required this.app});

  /// Height of the native bar including its floating margin.
  static const double kNativeHeight = 52;

  /// Vertical space the bar claims at the bottom of the content area, for
  /// anything that floats above it (the model browser, the origin triad). Zero
  /// off iOS, where the bar keeps its own row in the Column and the content
  /// area already stops above it.
  static double get floatingHeight =>
      GlassTabBar.isSupported ? kNativeHeight : 0;

  @override
  Widget build(BuildContext context) {
    if (GlassTabBar.isSupported) {
      return SizedBox(
        height: kNativeHeight,
        child: GlassTabBar(
          tabs: buildTabs(app),
          onTap: (id) => id == kHomeTabId ? app.goHome() : app.openDocument(id),
          onClose: app.closeTab,
        ),
      );
    }
    return _flutterBar();
  }

  Widget _flutterBar() {
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
          // The house speaks for itself — the word next to it was redundant.
          child: SvgPicture.string(homeTabIcon, width: 15, height: 15),
        ),
        for (final t in app.openTabs)
          _Tab(
            on: app.curTab == t,
            onTap: () => app.openDocument(t),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(t),
              const SizedBox(width: 6),
              _CloseX(onTap: () => app.closeTab(t)),
            ]),
          ),
        const Spacer(),
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

// Prototype — bottom tab bar (#tabbar, 30px, #14171B), 1:1 port.
// Home on the left, one tab per open sketch with ✕, active tab lighter with
// a 2px blue underline, burger on the far right.
import 'package:flutter/material.dart';

import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../menus.dart';
import '../svg_icons.dart';
import '../icon_preview.dart';
import '../ios_design.dart';
import '../theme.dart';

/// M149 — the tab model handed to UIKit. Pure, so it can be tested on the
/// host: this is where "which document is current" and "what may be closed"
/// are decided, and none of that should live in Swift.
/// M271 — HOME IS ONLY THERE WHEN IT TAKES YOU SOMEWHERE.
///
/// The house used to be the first tab always, including while the gallery was
/// on screen — where it was a button that led to where you already were, and a
/// permanently lit one at that. On the gallery the bar's whole job is the
/// other direction: here are the documents you have open, tap one to go back
/// into it. So on the gallery the bar is exactly that list, and the house
/// comes back the moment there is somewhere to come back FROM.
///
/// The bar can now be empty — gallery, nothing open — and [BottomTabBar]
/// renders nothing at all rather than an empty pill.
List<GlassTab> buildTabs(AppState app) => [
      if (!app.isHome)
        const GlassTab(
          id: kHomeTabId,
          // The house speaks for itself — the word next to it was redundant.
          // Never `house.fill`: the filled glyph meant "you are here", and the
          // one state it could say that in is the one state it is not in.
          symbol: 'house',
        ),
      for (final t in app.openTabs)
        GlassTab(
          id: t,
          label: t,
          // Same glyph vocabulary as the model browser: a part is a cube, a
          // sketch is stacked squares, an assembly is cubes on cubes. Two
          // panels naming the same thing two different ways is worse than
          // either name.
          symbol: app.assemblies.containsKey(t)
              ? 'square.stack.3d.up'
              : app.parts.containsKey(t)
                  ? 'cube'
                  : 'square.on.square',
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
      GlassPanel.isSupported ? kNativeHeight : 0;

  /// The same space, for chrome that also renders on the GALLERY.
  ///
  /// M271 — the bar can be absent there (nothing open, so nothing to go back
  /// to), and anything holding a gap for a bar that is not on screen leaves a
  /// gap. Viewport chrome keeps using [floatingHeight]: in a document the bar
  /// always has at least the house in it.
  static double floatingHeightFor(AppState app) =>
      buildTabs(app).isEmpty ? 0 : floatingHeight;

  @override
  Widget build(BuildContext context) {
    final tabs = buildTabs(app);
    // Nothing open and nothing to go back to: an empty glass pill floating
    // over the gallery is chrome about chrome.
    if (tabs.isEmpty) return const SizedBox.shrink();
    if (GlassTabBar.isSupported) {
      return SizedBox(
        height: kNativeHeight,
        child: GlassTabBar(
          tabs: tabs,
          // M260 — folds to the open document while the model is under a
          // finger. The bar is the only chrome the viewport runs underneath,
          // so it is the only chrome that has to get out of the way.
          engaged: app.viewEngaged,
          // M205 — a native bar's tap arrives over a method channel, past
          // any Flutter barrier a menu put up. Switching documents while a
          // ribbon flyout is open still counts as clicking elsewhere.
          onTap: (id) {
            OpenMenus.closeAll();
            id == kHomeTabId ? app.goHome() : app.openDocument(id);
          },
          onClose: (id) {
            OpenMenus.closeAll();
            app.closeTab(id);
          },
        ),
      );
    }
    // M367 — off iOS the bar is Flutter's, and it FLOATS where there is glass
    // to float on. Same reason as the model browser's card: the document runs
    // edge to edge underneath, and a 30 pt opaque strip across the bottom is a
    // strip the model visibly stops at (M150, which is why the native bar
    // stopped being a row of the Column).
    if (GlassPanel.isSupported) return _floatingBar();
    return _flutterBar();
  }

  /// The glass pill: the bar's own tabs, on the material, inset from the
  /// screen edges and shaped like the native one.
  Widget _floatingBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          height: kFloatingHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kFloatingHeight / 2),
            boxShadow: iosPanelShadow(),
          ),
          child: Stack(children: [
            Positioned.fill(
                child: GlassPanel(cornerRadius: kFloatingHeight / 2)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _tabWidgets(floating: true),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// The height of the pill itself, inside [kNativeHeight]'s margin.
  static const double kFloatingHeight = 38;

  Widget _flutterBar() {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: T.tabbarBg,
        border: Border(top: BorderSide(color: T.tabbarBorder)),
      ),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [..._tabWidgets(floating: false), const Spacer()]),
    );
  }

  /// The tabs themselves. ONE list, two surfaces: the strip that takes a row
  /// of the layout where there is no glass, and the pill that floats over the
  /// document where there is. A second copy of this would be a second place
  /// for the home tab's rule (M271) to be got wrong.
  List<Widget> _tabWidgets({required bool floating}) => [
        // The Home tab runs flush to the LEFT EDGE in the strip — its
        // background and blue underline fill into the iPad's rounded
        // bottom-left screen corner instead of leaving a dead 16px gutter
        // there. Only its CONTENT is pushed inward (leftPad), so the icon and
        // label still clear the corner radius and cannot be clipped. In the
        // pill there is no screen corner to clear, so it takes the ordinary
        // inset.
        //
        // M271 — and it is not there at all on the gallery. See buildTabs.
        if (!app.isHome)
          _Tab(
            leftPad: floating ? 12 : 28,
            on: false,
            floating: floating,
            onTap: app.goHome,
            // The house speaks for itself — the word next to it was redundant.
            child: iconWidget(homeTabIcon, 15),
          ),
        for (final t in app.openTabs)
          _Tab(
            on: !app.isHome && app.curTab == t,
            floating: floating,
            onTap: () => app.openDocument(t),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(t),
              const SizedBox(width: 6),
              _CloseX(onTap: () => app.closeTab(t)),
            ]),
          ),
      ];
}

class _Tab extends StatefulWidget {
  final bool on;
  final VoidCallback onTap;
  final Widget child;

  /// In the floating pill: a rounded chip with no dividers and no underline.
  /// In the strip: a square cell with a right hairline and the active tab's
  /// accent bar along its bottom edge.
  final bool floating;

  /// Left inset of the tab's CONTENT only — the background still starts at the
  /// tab's own origin. Used to clear the screen's rounded corner.
  final double leftPad;
  const _Tab({
    required this.on,
    required this.onTap,
    required this.child,
    this.floating = false,
    this.leftPad = 12,
  });
  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.on || _h ? T.text : T.tabText;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: widget.floating
              ? const EdgeInsets.symmetric(vertical: 4, horizontal: 2)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            // Over glass the INACTIVE chip is transparent: a fill for every
            // tab would tile the pill with panels and hide the material it is
            // made of. Only the open document gets a plate.
            color: widget.floating
                ? (widget.on ? T.tabOnBg : null)
                : (widget.on ? T.tabOnBg : T.tabBg),
            borderRadius:
                widget.floating ? BorderRadius.circular(13) : null,
            border: widget.floating
                ? null
                : Border(right: BorderSide(color: T.tabbarBorder)),
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
            // The active tab's accent bar. Only in the strip: a 2 pt line
            // across the bottom of a rounded chip cuts its corners off, and
            // the chip's own plate is already what says which document is
            // open.
            if (widget.on && !widget.floating)
              Positioned(
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
              style: ts(11, _h ? T.text : T.mbDimmed)),
        ),
      ),
    );
  }
}

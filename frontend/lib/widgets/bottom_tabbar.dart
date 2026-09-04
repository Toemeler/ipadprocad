// Prototype — bottom tab bar (#tabbar, 30px, #14171B), 1:1 port.
// Home on the left, one tab per open sketch with ✕, active tab lighter with
// a 2px blue underline, burger on the far right.
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../menus.dart';
import '../svg_icons.dart';
import '../icon_preview.dart';
import '../ios_design.dart';
import '../theme.dart';
import 'context_menu.dart';

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

  // ---- GlassTabBarView's own geometry -------------------------------------
  //
  // M368 — the floating bar off iOS is the SAME bar, so these are the Swift
  // side's constants rather than a second set that happens to look like them.
  // A change over there has exactly one place to land here.

  /// Height of every group, and so the diameter of the two circles. 44 pt is
  /// Apple's touch minimum and the bar's own 52 pt height less the 8 pt it
  /// floats above the screen edge.
  static const double kGroupH = 44;

  /// Between groups. Half the outer inset, so the split reads as one object
  /// broken up rather than three unrelated ones.
  static const double kGroupGap = 8;

  /// Inside the documents capsule, around the row of chips.
  static const double kRowPad = 5;

  /// The house inside the Home circle. Measured off the device rather than
  /// taken from the symbol's point size: SF draws `house` at 15 pt about 20 pt
  /// wide, and a glyph half the circle's diameter is what makes the button
  /// read as a button rather than as a dot.
  static const double kHomeGlyph = 21;

  /// A document chip's own height.
  ///
  /// NOT `kGroupH - 2 * kRowPad`. UIKit sizes the chip to its content — 4 pt
  /// of `contentInsets` above and below a 12 pt symbol beside a 12.5 pt label
  /// — and the stack view centres it in the capsule; the 5 pt row padding is
  /// the MINIMUM clearance, not the chip's height. Stretching the chip to fill
  /// the capsule made it a plate with a hairline of glass around it, which is
  /// the one thing the capsule is not supposed to look like.
  static const double kChipH = 23;

  /// Margin around the floating bar. Mirrors the ribbon's sides so the three
  /// panels — ribbon, browser, tab bar — float on one shared edge.
  static const EdgeInsets kBarInset = EdgeInsets.fromLTRB(14, 0, 14, 8);

  /// Folded is the resting state (M265). This is how long an open bar waits
  /// before it folds back to the document you are in.
  static const Duration kIdleFold = Duration(seconds: 3);

  /// An ease, not a spring: the capsule's edge is a straight edge, and a
  /// straight edge that overshoots its target and comes back reads as a
  /// mis-set constraint rather than as life.
  static const Duration kFold = Duration(milliseconds: 260);

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
    if (GlassPanel.isSupported) {
      return _FloatingTabBar(
        tabs: tabs,
        // M368 — the fold is the bar's own, but WHEN to fold is Dart's, the
        // same split the native bar has: a camera under a finger is a gesture
        // Flutter owns, and nothing else may open the bar.
        engaged: app.viewEngaged,
        onTap: (id) {
          OpenMenus.closeAll();
          id == kHomeTabId ? app.goHome() : app.openDocument(id);
        },
        onClose: (id) {
          OpenMenus.closeAll();
          app.closeTab(id);
        },
      );
    }
    return _flutterBar();
  }


  Widget _flutterBar() {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: T.tabbarBg,
        border: Border(top: BorderSide(color: T.tabbarBorder)),
      ),
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [..._tabWidgets(), const Spacer()]),
    );
  }

  /// The tabs of the OPAQUE strip — the surface a platform with no material
  /// at all still gets. The floating bar is [_FloatingTabBar], which renders
  /// the same [buildTabs] model the native bar is pushed, so the two glass
  /// surfaces cannot drift.
  List<Widget> _tabWidgets() => [
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
            leftPad: 28,
            on: false,
            onTap: app.goHome,
            // The house speaks for itself — the word next to it was redundant.
            child: iconWidget(homeTabIcon, 15),
          ),
        for (final t in app.openTabs)
          _Tab(
            on: !app.isHome && app.curTab == t,
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
    final color = widget.on || _h ? T.text : T.tabText;
    return MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: widget.on ? T.tabOnBg : T.tabBg,
            border: Border(right: BorderSide(color: T.tabbarBorder)),
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
            // The active tab's accent bar.
            if (widget.on)
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

// ---------------------------------------------------------------------------
// M368 — the floating bar, off iOS
// ---------------------------------------------------------------------------

/// THE BAR IS THREE OBJECTS, and off iOS it has to be the same three.
///
/// M367 put the Flutter bar on the material, but it put it on ONE pill with
/// the house inside it and nothing on the right — which is the M260 slab
/// again, only smaller. What iOS 26 actually ships, and what
/// `GlassTabBar.swift` builds, is three separate glass groups rounded to
/// their own height:
///
///     ( ⌂ )  ( cube Rolle ✕ · cube 2joint ✕ )              ( ☰ )
///      home              documents                          all
///
/// with the island on the right as the escape hatch — every open document in
/// one menu, always reachable, whatever the capsule scrolled or folded away.
///
/// Every number here is `GlassTabBarView`'s own: the 44 pt group height, the
/// 14/8 insets, the 8 pt gap, the 5 pt row padding, the 3 s idle fold and the
/// 260 ms ease. This is the same bar, not a Flutter approximation of one, and
/// the constants are together at the top so a change on the Swift side has one
/// place to land.
class _FloatingTabBar extends StatefulWidget {
  final List<GlassTab> tabs;

  /// The model is under a finger. Folds the bar at once; never opens it —
  /// M265's rule, and the reason `setEngaged` on the Swift side ignores false.
  final bool engaged;
  final void Function(String id) onTap;
  final void Function(String id) onClose;
  const _FloatingTabBar({
    required this.tabs,
    required this.engaged,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<_FloatingTabBar> createState() => _FloatingTabBarState();
}

class _FloatingTabBarState extends State<_FloatingTabBar> {
  /// Open. False is the resting state: the bar shows the document you are in
  /// and opens when you reach for it.
  bool _awake = false;
  Timer? _idle;

  @override
  void didUpdateWidget(covariant _FloatingTabBar old) {
    super.didUpdateWidget(old);
    // Camera motion folds it at once. Only the fold half — a camera that has
    // stopped moving is not a reason to open the bar.
    if (widget.engaged && !old.engaged) _rest();
    // Landing somewhere new is worth seeing once. It folds itself back.
    final was = _selectedId(old.tabs);
    final now = _selectedId(widget.tabs);
    if (now != null && now != was) _wake();
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  /// Someone reached for the bar. Open it, and start counting again.
  void _wake() {
    _idle?.cancel();
    _idle = Timer(BottomTabBar.kIdleFold, _rest);
    if (_awake) return;
    setState(() => _awake = true);
  }

  /// Back to the document you are in.
  void _rest() {
    _idle?.cancel();
    _idle = null;
    if (!_awake || !mounted) return;
    setState(() => _awake = false);
  }

  @override
  Widget build(BuildContext context) {
    final homes = widget.tabs.where((t) => !t.closable).toList();
    final home = homes.isEmpty ? null : homes.first;
    final docs = widget.tabs.where((t) => t.closable).toList();
    // No documents open: the Home circle alone is the whole bar, which is the
    // truth of that state and much quieter than an empty pill.
    final empty = docs.isEmpty;
    const h = BottomTabBar.kGroupH;
    const gap = BottomTabBar.kGroupGap;

    return Padding(
      padding: BottomTabBar.kBarInset,
      child: SizedBox(
        height: h,
        child: MouseRegion(
          // Pointer, for the trackpad: reaching for the bar can happen without
          // ever touching the glass.
          onEnter: (_) => _wake(),
          onHover: (_) => _wake(),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _wake(),
            child: Stack(children: [
              // The left group scrolls: a CAD session ends up with more open
              // documents than fit, and a tab that cannot be reached is a lost
              // file. It stops where the island begins, so the two can never
              // overlap by construction.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                right: empty ? 0 : h + gap,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (home != null) ...[
                        _Group(
                          size: h,
                          onTap: () => widget.onTap(home.id),
                          child: Center(
                            child: _TabGlyph(
                                symbol: home.symbol,
                                size: BottomTabBar.kHomeGlyph),
                          ),
                        ),
                        if (!empty) const SizedBox(width: gap),
                      ],
                      if (!empty)
                        _Group(
                          padding:
                              const EdgeInsets.all(BottomTabBar.kRowPad),
                          child: AnimatedSize(
                            duration: BottomTabBar.kFold,
                            curve: Curves.easeInOut,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final t in docs)
                                  // Folded, every chip but the one you are in
                                  // is gone. AnimatedSize collapses the capsule
                                  // around what is left, which is the stack
                                  // view's own animation on the Swift side.
                                  if (_awake || t.selected || !_hasSelection)
                                    _DocChip(
                                      tab: t,
                                      onTap: () => widget.onTap(t.id),
                                      onClose: () => widget.onClose(t.id),
                                    ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // The island: every open document in one menu. This is what
              // makes the fold safe — with the row collapsed to one chip, this
              // is how you reach the rest.
              if (!empty)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Builder(
                    builder: (ctx) => _Group(
                      size: h,
                      onTap: () => _openIsland(ctx, docs),
                      child: Center(
                        child: Icon(Icons.format_list_bulleted,
                            size: 17, color: T.tabText),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Nothing folds unless a document is actually current — otherwise the
  /// capsule would collapse to nothing and reappear as a stub, which reads as
  /// a glitch rather than as chrome getting out of the way.
  bool get _hasSelection => _selectedId(widget.tabs) != null;

  static String? _selectedId(List<GlassTab> tabs) {
    for (final t in tabs) {
      if (t.closable && t.selected) return t.id;
    }
    return null;
  }

  /// Every open document, current one ticked. Built when it opens, not when
  /// the tabs change: the menu has to show the documents as they are at the
  /// moment of the press.
  Future<void> _openIsland(BuildContext ctx, List<GlassTab> docs) async {
    _wake();
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final at = box.localToGlobal(Offset.zero);
    final picked = await showAppContextMenu(
      ctx,
      // Above the island and aligned to its right edge: a menu that opened
      // downward from a control on the bottom edge would open off-screen.
      at: Offset(at.dx + box.size.width, at.dy),
      groups: [
        [
          for (final t in docs)
            NativeMenuItem(
                id: t.id,
                title: t.label,
                symbol: t.selected ? 'checkmark' : null),
        ]
      ],
    );
    if (picked != null) widget.onTap(picked);
  }
}

/// One glass object of the bar, rounded to its own height.
class _Group extends StatelessWidget {
  /// Square groups (home, island) pass their diameter; the documents capsule
  /// sizes to its chips and only its height is fixed.
  final double? size;
  final EdgeInsets padding;
  final Widget child;
  final VoidCallback? onTap;
  const _Group({
    required this.child,
    this.size,
    this.padding = EdgeInsets.zero,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const r = BottomTabBar.kGroupH / 2;
    final body = SizedBox(
      width: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          boxShadow: iosPanelShadow(),
        ),
        // Centred, because the documents capsule's chips are shorter than it
        // is (see BottomTabBar.kChipH) and a Stack parks a loose child at its
        // top-left corner.
        child: Stack(alignment: Alignment.center, children: [
          const Positioned.fill(child: GlassPanel(cornerRadius: r)),
          Padding(padding: padding, child: child),
        ]),
      ),
    );
    if (onTap == null) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: body,
      ),
    );
  }
}

/// A document chip: capsule, glyph, name, and a real close button inside the
/// selected tint rather than floating next to it.
class _DocChip extends StatefulWidget {
  final GlassTab tab;
  final VoidCallback onTap;
  final VoidCallback onClose;
  const _DocChip(
      {required this.tab, required this.onTap, required this.onClose});
  @override
  State<_DocChip> createState() => _DocChipState();
}

class _DocChipState extends State<_DocChip> {
  bool _hoverX = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tab;
    const h = BottomTabBar.kChipH;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: DecoratedBox(
        // A capsule with a tint is how iPadOS shows a selected chip. The
        // INACTIVE chip is transparent: a fill for every tab would tile the
        // capsule with panels and hide the material it is made of.
        decoration: BoxDecoration(
          color: t.selected ? T.accent.withValues(alpha: 0.30) : null,
          borderRadius: BorderRadius.circular(h / 2),
        ),
        child: SizedBox(
          height: h,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.fromLTRB(10, 0, t.label.isEmpty ? 10 : 5, 0),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _TabGlyph(symbol: t.symbol, size: 12),
                  if (t.label.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Text(t.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(12.5, t.selected ? T.text : T.tabText)
                            .copyWith(
                                fontWeight: t.selected
                                    ? FontWeight.w600
                                    : FontWeight.w400)),
                  ],
                ]),
              ),
            ),
            MouseRegion(
              onEnter: (_) => setState(() => _hoverX = true),
              onExit: (_) => setState(() => _hoverX = false),
              child: GestureDetector(
                onTap: widget.onClose,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 8, 0),
                  child: Icon(Icons.cancel,
                      size: 15,
                      color: _hoverX
                          ? T.text
                          : (t.selected ? T.tabText : T.mbDimmed)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The SF Symbol a tab carries, drawn with the app's own artwork.
///
/// [buildTabs] speaks SF Symbol names because the native bar consumes them;
/// this is the one place off iOS that turns them back into glyphs, and it uses
/// the SAME icons the model browser gives a part, an assembly and a sketch —
/// two panels naming the same thing two different ways is worse than either
/// name.
class _TabGlyph extends StatelessWidget {
  final String symbol;
  final double size;
  const _TabGlyph({required this.symbol, required this.size});

  @override
  Widget build(BuildContext context) {
    switch (symbol) {
      case 'house':
        // The app's own house, not Material's: it is the glyph the opaque
        // strip has always used, and it is the outlined roof-and-walls SF
        // draws rather than a filled door. M271 means Home is never the
        // selected tab — it is absent on the gallery and you are in a document
        // whenever it is there — so it never needs a state colour, which is
        // what lets it be artwork rather than a font glyph.
        return iconWidget(tabHomeIcon, size);
      case 'square.stack.3d.up':
        return iconWidget(assemblyCubeIcon, size);
      case 'square.on.square':
        return iconWidget(sketchCubeIcon, size);
      case 'cube':
      default:
        return iconWidget(partCubeIcon, size);
    }
  }
}

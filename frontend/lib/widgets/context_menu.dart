// Prototype — the Flutter stand-in for a UIKit context menu.
//
// A long press on a gallery card opens a real `UIContextMenuInteraction` on
// the iPad: the card lifts, the menu blurs in beside it, a `destructive` row
// is drawn red by UIKit and the sections are separated for us. None of that
// exists off iOS, and until now nothing stood in for it — a right-click on a
// desktop gallery card did nothing at all, so Rename, Duplicate, Export,
// Share and Delete were reachable on the iPad and unreachable everywhere else.
//
// This is that menu, drawn by Flutter, from the SAME [NativeMenuTarget]
// groups the native path is handed. That is the whole point of the file: there
// is one description of what a context menu contains (sketchMenuGroups, and
// its equivalents), and two things that can draw it. A second hand-written
// list of rows would be a second thing to keep in step, and the first one to
// fall out of it.
//
// It follows the conventions the rest of the app's popups already have:
//
//   * The surface is [T.fly] with a [T.sep] hairline and the app's shadow —
//     the same slab the model browser's own context menu uses, because they
//     are the same thing and must not look like two.
//   * Groups become sections with a separator between them, which is what
//     keeps Delete alone at the bottom exactly as UIKit puts it there.
//   * A `destructive` item is [T.err]. Never coloured anywhere else, for the
//     same reason the native side never colours it: red means one thing.
//   * It registers with [OpenMenus] (M205), so a click ANYWHERE — including
//     one that never becomes a tap, and one that lands on a native surface —
//     cancels it.
//   * It is clamped into the view. A card in the last column would otherwise
//     open a menu half off the right edge, which is a thing only a desktop
//     window narrow enough can produce and therefore the thing nobody would
//     have found on a fixed-size iPad.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:native_menu/native_menu.dart';

import '../menus.dart';
import '../theme.dart';

/// Opens [groups] at [at] (global coordinates) and completes with the chosen
/// item's id, or null when the user dismissed it.
///
/// [title] is drawn as a header, mirroring `NativeMenuTarget.title`. An empty
/// or null title draws no header, exactly as the native side treats it.
Future<String?> showAppContextMenu(
  BuildContext context, {
  required Offset at,
  required List<List<NativeMenuItem>> groups,
  String? title,
}) {
  final rows = <List<NativeMenuItem>>[
    for (final g in groups)
      if (g.isNotEmpty) g
  ];
  if (rows.isEmpty) return Future<String?>.value(null);

  final overlay = Overlay.of(context);
  final completer = _MenuCompleter();
  late OverlayEntry entry;

  void close([String? id]) {
    if (completer.isDone) return;
    OpenMenus.unregister(completer.dismiss);
    entry.remove();
    completer.complete(id);
  }

  completer.dismiss = close;

  entry = OverlayEntry(
    builder: (ctx) {
      return Stack(children: [
        // The barrier listens to raw pointer DOWNs rather than taps: a click
        // that jitters into a drag is still the moment the user meant to
        // dismiss. See menus.dart for the whole argument.
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => close(),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _MenuLayout(at),
            child: _MenuCard(title: title, groups: rows, onPick: close),
          ),
        ),
      ]);
    },
  );

  overlay.insert(entry);
  OpenMenus.register(completer.dismiss);
  return completer.future;
}

/// Holds the future and the one closer registered with [OpenMenus].
///
/// A small object rather than two locals, because [OpenMenus.register]
/// de-duplicates by identity: the closer has to be ONE callback that outlives
/// every rebuild of the overlay, or a second registration would leave a menu
/// standing after `closeAll`.
class _MenuCompleter {
  final Completer<String?> _completer = Completer<String?>();
  late VoidCallback dismiss;
  bool get isDone => _completer.isCompleted;
  Future<String?> get future => _completer.future;
  void complete(String? id) {
    if (!_completer.isCompleted) _completer.complete(id);
  }
}

/// Where a menu opens, kept inside the view.
///
/// The pointer is the menu's top-left corner when there is room — the shape
/// every desktop context menu has. When there is not, the menu FLIPS to the
/// other side of the pointer rather than sliding along the edge: a slid menu
/// ends up underneath the cursor, and the row that lands there is one the user
/// can pick by accident on the way in. Only if flipping does not fit either
/// does it slide, and then it is pinned to the margin.
///
/// A [CustomSingleChildLayout] rather than arithmetic on an estimated width,
/// because the delegate is handed the menu's REAL size after it lays out. The
/// width depends on the longest label, which depends on the language — an
/// estimate would be right in German and wrong in English, or the reverse.
class _MenuLayout extends SingleChildLayoutDelegate {
  final Offset at;
  const _MenuLayout(this.at);

  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // The menu may use the whole view minus the margins; it scrolls inside
    // itself if a long menu still does not fit.
    return BoxConstraints.loose(Size(
      (constraints.maxWidth - 2 * _margin).clamp(0.0, constraints.maxWidth),
      (constraints.maxHeight - 2 * _margin).clamp(0.0, constraints.maxHeight),
    ));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double place(double anchor, double child, double extent) {
      if (anchor + child + _margin <= extent) return anchor;   // fits below/right
      if (anchor - child >= _margin) return anchor - child;    // flip
      return (extent - child - _margin).clamp(_margin, extent); // pin
    }

    return Offset(
      place(at.dx, childSize.width, size.width),
      place(at.dy, childSize.height, size.height),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.at != at;
}

class _MenuCard extends StatelessWidget {
  final String? title;
  final List<List<NativeMenuItem>> groups;
  final void Function(String id) onPick;
  const _MenuCard(
      {required this.title, required this.groups, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final header = title;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: T.fly,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: T.sep),
          boxShadow: [
            BoxShadow(color: T.shadow, blurRadius: 22, offset: const Offset(0, 8)),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (header != null && header.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 7, 16, 5),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(header,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(11.5, T.dim)),
                ),
              ),
              Divider(height: 1, thickness: 1, color: T.sep),
            ],
            for (var g = 0; g < groups.length; g++) ...[
              if (g > 0) Divider(height: 7, thickness: 1, color: T.sep),
              for (final item in groups[g])
                _ContextMenuRow(item: item, onTap: () => onPick(item.id)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _ContextMenuRow extends StatefulWidget {
  final NativeMenuItem item;
  final VoidCallback onTap;
  const _ContextMenuRow({required this.item, required this.onTap});
  @override
  State<_ContextMenuRow> createState() => _ContextMenuRowState();
}

class _ContextMenuRowState extends State<_ContextMenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final danger = widget.item.destructive;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          color: _hover ? T.flyHov : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Text(
            widget.item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ts(12.5, danger ? T.err : T.text),
          ),
        ),
      ),
    );
  }
}

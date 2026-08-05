// M205 — one register of every transient popup, so that a click ANYWHERE
// cancels it.
//
// "When a context menu is open and i click anywhere else this should count as
// a cancel."
//
// Each menu in this app already ships its own full-screen barrier behind
// itself, and that is enough for the clicks the barrier can see. It cannot see
// two kinds:
//
//  * A click that never becomes a TAP. The ribbon's flyout barrier used a
//    GestureDetector, and a gesture detector's onTap has to win the arena —
//    a trackpad click that jitters two pixels, a Pencil that rolls, a press
//    that turns into a drag: all of those are legitimately not taps, and every
//    one of them left the menu standing. Barriers now listen to raw pointer
//    DOWNs instead, which is the moment the user meant.
//
//  * A click that lands on a NATIVE view. The quick-tool bar, the tab bar and
//    the model browser are UIKit platform views; when one of them takes a
//    touch, the Flutter barrier above it is not in that touch's path at all.
//    The tap comes back over a method channel instead, and by then there is no
//    pointer event left to dismiss anything with.
//
// Hence this: a menu registers its closer while it is on screen, and the
// native tap handlers call [OpenMenus.closeAll] before they do their own work.
// It is deliberately dumb — a list of callbacks, no widgets, no context, no
// dependency on the tree that owns the menu.
import 'package:flutter/foundation.dart';

/// The closers of every popup currently on screen.
class OpenMenus {
  OpenMenus._();

  static final List<VoidCallback> _closers = <VoidCallback>[];

  /// True while at least one popup is open.
  static bool get any => _closers.isNotEmpty;

  /// Number of popups currently registered (tests read this).
  static int get count => _closers.length;

  /// Call when a popup goes up. The same [close] may be registered only once;
  /// a second call replaces nothing and adds nothing.
  static void register(VoidCallback close) {
    if (!_closers.contains(close)) _closers.add(close);
  }

  /// Call when a popup comes down BY ITSELF (picked an item, toggled shut).
  static void unregister(VoidCallback close) => _closers.remove(close);

  /// Closes everything. The list is emptied FIRST so that a closer calling
  /// [unregister] on its way out — which every one of them does — cannot
  /// mutate the list being walked.
  static void closeAll() {
    if (_closers.isEmpty) return;
    final pending = List<VoidCallback>.of(_closers);
    _closers.clear();
    for (final close in pending) {
      close();
    }
  }

  /// Tests only: forget everything without invoking anything.
  @visibleForTesting
  static void reset() => _closers.clear();
}

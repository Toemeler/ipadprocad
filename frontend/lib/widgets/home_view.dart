// Prototype — home view (#home): a Procreate-style sketch gallery.
//
// Big bold title top-left, a round "+" (new sketch) button top-right, and a
// responsive grid of large, rounded, drop-shadowed thumbnail cards — one per
// saved sketch. Tapping a card opens that sketch (the bottom tab bar keeps
// switching between open sketches). Fresh installs show a friendly empty
// state instead of the old design-dummy cards.
//
// Long-pressing a card opens a REAL UIKit context menu (see
// packages/native_menu): Rename / Duplicate / Export / Share, and Delete in
// its own destructive section. The menu is not drawn by Flutter — we only
// publish the cards' hit rectangles to the native side and act on the item id
// that comes back. Off iOS every one of those calls is inert, so the host test
// suite and desktop runs behave exactly as before.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../backdrop.dart';
import '../doc_file.dart';
import '../doc_ref.dart';
import '../l10n/l.dart';
import '../log.dart';
import '../menus.dart';
import '../sync/lan_sync.dart';
import '../sync/sync_store.dart';
import '../svg_icons.dart';
import '../icon_preview.dart';
import '../theme.dart';
import 'context_menu.dart';
import 'native_prompts.dart';
import 'settings_sheet.dart';

// Card sizing: previews are rendered 380x240 (see _writePreview), so the cards
// keep that landscape aspect. We aim for a comfortable, touch-friendly width
// and let the grid pack as many even columns as fit the iPad width.
const double _kCardTarget = 250; // preferred card width
const double _kCardAspect = 380 / 240; // preview aspect (w/h)
const double _kGap = 26; // spacing between cards
const double _kPad = 34; // outer padding
const double _kThumbRadius = 14; // matches the card's BorderRadius

/// The gallery card menu. Each inner list becomes a visually separated
/// section, which is what puts Delete alone at the bottom — UIKit paints a
/// `destructive` row red on its own, we never colour it ourselves.
///
/// Top-level so tests can assert the contract without a device. It takes the
/// strings rather than reading a global, so a test can pin BOTH languages.
/// M345 — [isSketch] adds the two entries that only make sense on a 2D
/// document: Copy (the clipboard's version of Duplicate, which can be pasted
/// into a part or an open sketch as well as back into the gallery) and "Create
/// Part from Sketch". Defaulted so the existing callers — and the tests that
/// pin this contract — read exactly as they did.
/// M420 — [hasLocalChanges] adds "Discard changes", in its OWN section above
/// Delete. Only when that document has actually been changed here since this
/// device and the group last agreed: an entry that would do nothing is worse
/// than no entry, because it invites a press and then has to explain itself.
/// Its own section rather than beside Rename, because it throws work away and
/// the separator is what says so before the words do.
List<List<NativeMenuItem>> sketchMenuGroups(AppL10n t,
        {bool isSketch = false, bool hasLocalChanges = false}) =>
    [
      [
        NativeMenuItem(id: 'rename', title: t.rename, symbol: 'pencil'),
        NativeMenuItem(
            id: 'duplicate',
            title: t.duplicate,
            symbol: 'plus.square.on.square'),
        NativeMenuItem(id: 'copy', title: t.btnCopy, symbol: 'doc.on.doc'),
        if (isSketch)
          NativeMenuItem(
              id: 'toPart',
              title: t.ctxPartFromSketch,
              symbol: 'cube'),
        NativeMenuItem(
            id: 'export',
            title: t.exportEllipsis,
            symbol: 'square.and.arrow.down'),
        NativeMenuItem(
            id: 'share',
            title: t.shareEllipsis,
            symbol: 'square.and.arrow.up'),
      ],
      if (hasLocalChanges)
        [
          NativeMenuItem(
              id: 'discard',
              title: t.syncDiscard,
              symbol: 'arrow.uturn.backward',
              destructive: true),
        ],
      [
        NativeMenuItem(
            id: 'delete', title: t.delete, symbol: 'trash', destructive: true),
      ],
    ];

/// The gallery "+" menu: New 2D Sketch / New 3D Part. Item ids match the
/// values the Flutter fallback (showMenu) returns, so the native and non-native
/// paths funnel into one branch in [_showNewMenu]. Top-level + const so a test
/// can pin the contract (ids, order, labels) without a device.
List<NativeMenuItem> newDocMenuItems(AppL10n t, {bool canPaste = false}) => [
      NativeMenuItem(
          id: '2d', title: t.galleryNew2dSketch, symbol: 'square.on.square'),
      NativeMenuItem(id: '3d', title: t.galleryNew3dPart, symbol: 'cube'),
      // M240 — the third document kind, on the same shelf as the other two.
      NativeMenuItem(
          id: 'asm',
          title: t.galleryNewAssembly,
          symbol: 'square.stack.3d.up'),
      // M117 — Open belongs HERE, next to the two ways of starting a
      // document, because that is what it is: a third way to get one. In the
      // ribbon it was a tool among modelling tools, which is the wrong shelf.
      //
      // M177 — and it is called "Open", not "Import STEP / DXF", because one
      // verb covers all of it: a Prototype document from anywhere on the iPad
      // opens in place, a STEP or DXF is converted. Which one happens follows
      // from the file, not from a menu the user has to get right first.
      NativeMenuItem(id: 'import', title: t.openEllipsis, symbol: 'folder'),
      // M345 — and a fourth: whatever is on the clipboard, as a document. It
      // belongs here because that is what a paste in the gallery IS — a new
      // document — and only while there is something to paste, so the "+" of
      // a session that has copied nothing reads exactly as it always did.
      if (canPaste)
        NativeMenuItem(
            id: 'paste', title: t.btnPaste, symbol: 'doc.on.clipboard'),
      // M261 — and NOTHING ELSE. Language (M234) and Appearance (M236) used to
      // sit here, each noting that the "+" was "the app's only menu that
      // belongs to the APP rather than to a document". That was true of the
      // menus that existed, and it was still the wrong shelf: "+" is a verb,
      // and it means "make me a new document". Two preferences behind a create
      // button is where people stop looking for them.
      //
      // They are in Settings now, reached by the gear beside this button. What
      // is left in here is four ways to get a document — which is one idea,
      // and the whole of what the "+" is for.
    ];

/// M289 — which file formats a card's Export action may offer, before the
/// destination is ever chosen. 3D parts can write both STL and STEP; sketches
/// only DXF, assemblies only STEP.
List<String> exportFormatsFor(String kind) => switch (kind) {
      'part' || 'ptp' => ['stl', 'step'],
      'sketch' || 'pts' => ['dxf'],
      kAssemblyDocKind => ['step'],
      _ => ['step'],
    };

/// M272 — how strongly a card's name leans toward its kind's hue.
///
/// "very slight and not too strong but still helping to see what is an
/// assembly what is a part and what a sketch". A third of the way is where a
/// column of names still reads as one typographic voice while a neighbouring
/// pair is plainly two different things. Past about half it stops being a
/// gallery of documents and starts being a colour-coded list.
const double kKindTint = 0.34;

/// The colour a card's NAME is written in, for its document kind.
///
/// The hues are not invented here — they are the ones the browser's cube
/// glyphs have used since M84: a sketch cube is the app's accent blue, a part
/// cube is neutral grey. So a sketch name leans accent, and a PART name leans
/// nowhere at all. That last one is deliberate: parts are the commonest
/// document, an un-tinted baseline is what the other two are read against, and
/// three tints with nothing neutral between them is the wall of colour the
/// request explicitly did not ask for.
///
/// An assembly is the one kind whose glyph has no hue of its own (it is a grey
/// cube and a blue one), so it takes the palette's green — the only remaining
/// chromatic token with no meaning on this surface, and the easiest thing to
/// tell from blue at a glance in a grid.
Color cardNameColor(Palette g, String kind) => switch (kind) {
      'sketch' => Color.lerp(g.cardName, g.accent, kKindTint)!,
      kAssemblyDocKind => Color.lerp(g.cardName, g.okText, kKindTint)!,
      _ => g.cardName, // 'part', and anything a later build adds
    };

class HomeView extends StatefulWidget {
  final AppState app;
  const HomeView({super.key, required this.app});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final Map<String, GlobalKey> _cardKeys = {};
  final GlobalKey _scrollKey = GlobalKey();
  final GlobalKey _plusKey = GlobalKey(); // anchor for the native "+" sheet
  String? _lastPayload;
  bool _pushScheduled = false;

  /// M418 — a refresh is running. The button spins and a second press is
  /// ignored: pressing it again does not make the network faster, and two
  /// overlapping refreshes would report each other's results.
  bool _refreshing = false;

  /// The one line under the header: what the last refresh did. Cleared by a
  /// tap, and by the next refresh.
  String? _syncNote;

  /// M421 — versions the last refresh replaced, while Undo is still offered.
  List<SyncBackup> _undoable = const <SyncBackup>[];

  @override
  void initState() {
    super.initState();
    NativeMenu.setSelectionHandler(NativeMenu.kGallery, _onMenuSelection);
    // Both are what the note reads, so both have to repaint it: forks arrive
    // on their own, without anyone having pressed anything.
    LanSync.instance.recentForks.addListener(_onSyncChanged);
    ShareCodes.current.addListener(_onSyncChanged);
    _schedulePush();
  }

  void _onSyncChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    LanSync.instance.recentForks.removeListener(_onSyncChanged);
    ShareCodes.current.removeListener(_onSyncChanged);
    // Pushing an empty list REMOVES the interaction from the Flutter view, so
    // leaving the gallery cannot shadow the CAD viewport's own long press.
    NativeMenu.setSelectionHandler(NativeMenu.kGallery, null);
    NativeMenu.setTargets(NativeMenu.kGallery, const []);
    super.dispose();
  }

  GlobalKey _keyFor(String name) =>
      _cardKeys.putIfAbsent(name, () => GlobalKey());

  /// One push per frame at most, and only when something actually moved.
  void _schedulePush() {
    if (_pushScheduled) return;
    _pushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pushScheduled = false;
      if (mounted) _pushTargets();
    });
  }

  Rect? _globalRect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _pushTargets() {
    if (!NativeMenu.isSupported) return;
    final targets = <NativeMenuTarget>[];
    // Cards scrolled out of the gallery still have render objects inside the
    // cache extent; clip against the scroll view so an off-screen card can
    // never claim a long press.
    final clip = _globalRect(_scrollKey);
    for (final s in widget.app.saved) {
      final key = _cardKeys[s.name];
      if (key == null) continue;
      final full = _globalRect(key);
      if (full == null) continue;
      final hit = clip == null ? full : full.intersect(clip);
      if (hit.width <= 1 || hit.height <= 1) continue;
      targets.add(NativeMenuTarget(
        id: s.name,
        title: s.name,
        rect: hit,
        // Only the thumbnail lifts — the label below it stays on the page,
        // exactly like Photos and Procreate.
        previewRect:
            Rect.fromLTWH(full.left, full.top, full.width, full.width / _kCardAspect),
        cornerRadius: _kThumbRadius,
        previewImagePath: s.preview?.path,
        groups: sketchMenuGroups(L.of(context),
            isSketch: s.kind == 'sketch',
            hasLocalChanges: _hasLocalChanges(s)),
      ));
    }
    final payload = jsonEncode([for (final t in targets) t.toMap()]);
    if (payload == _lastPayload) return;
    _lastPayload = payload;
    NativeMenu.setTargets(NativeMenu.kGallery, targets);
  }

  // ---- menu actions ----

  /// The gallery card's context menu, off iOS.
  ///
  /// Same groups the native path is given (`sketchMenuGroups`) and the same
  /// handler underneath (`_onMenuSelection`), so Rename, Duplicate, Copy,
  /// Create Part, Export, Share and Delete behave identically whichever side
  /// drew the menu. Before this the desktop had NONE of them: the only way to
  /// reach a card's actions was a long press UIKit answered, and off iOS
  /// nobody answered it.
  Future<void> _showCardMenu(String name, Offset at) async {
    final doc = widget.app.saved.where((d) => d.name == name);
    if (doc.isEmpty) return;
    final choice = await showAppContextMenu(
      context,
      at: at,
      title: name,
      groups: sketchMenuGroups(L.current,
          isSketch: doc.first.kind == 'sketch',
          hasLocalChanges: _hasLocalChanges(doc.first)),
    );
    if (choice != null) _onMenuSelection(name, choice);
  }

  void _onMenuSelection(String sketch, String item) {
    if (!mounted) return;
    switch (item) {
      case 'discard':
        unawaited(_discardChanges(sketch));
        break;
      case 'rename':
        _promptRename(sketch);
        break;
      case 'duplicate':
        widget.app.duplicateDocument(sketch);
        break;
      case 'export':
        _sendFile(sketch, share: false);
        break;
      case 'share':
        _sendFile(sketch, share: true);
        break;
      case 'delete':
        _confirmDelete(sketch);
        break;
      // M345
      case 'copy':
        widget.app.copyDocument(sketch);
        break;
      case 'toPart':
        unawaited(widget.app.partFromSketch(sketch));
        break;
    }
  }

  /// Every new sketch is named UP FRONT. The old flow handed out "Sketch7"
  /// and left renaming as a chore nobody did.
  Future<void> _promptNewSketch() async {
    final app = widget.app;
    final t = L.of(context);
    final name = await promptForText(
      context,
      title: t.dlgNewSketch,
      initialValue: app.suggestedSketchName(),
      placeholder: t.phSketchName,
      confirmLabel: t.create,
      validate: (v) =>
          app.validateSketchName(v) ??
          (app.docNameExists(v.trim()) ? t.errNameTaken : null),
    );
    if (name == null) return;
    await app.createNamedSketch(name);
  }

  /// M266 — one of the gallery header's two buttons, drawn by UIKit.
  ///
  /// These were Flutter: a Container with a BoxDecoration circle and a
  /// MATERIAL glyph (Icons.add, Icons.settings_outlined). Next to a ribbon, a
  /// model browser, a tab bar and a tool bar that are all native glass, two
  /// Material circles on the front page are the first thing anyone sees and
  /// the first thing that looks wrong — "they seem like flutter", and they
  /// were.
  ///
  /// A ONE-ITEM [GlassToolBar] rather than a new platform view. That bar is
  /// already a 54pt glass slab holding one 44pt SF-Symbol button, it already
  /// carries M205's recovery for the press UIKit hands back as a cancel, and
  /// it is the same object the quick-tool bar is made of — so the header now
  /// matches the rest of the app's chrome instead of approximating it. A
  /// bespoke round button would have been new Swift for a shape.
  ///
  /// [anchor] is the key the "+" menu measures to place its popover; only one
  /// branch of the switch is ever built, so the GlobalKey is never attached
  /// twice.
  Widget _headerButton({
    GlobalKey? anchor,
    required String id,
    required String symbol,
    required String fallbackSymbol,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    if (GlassToolBar.isSupported) {
      return GlassToolBar(
        key: anchor,
        // M267 — ROUND. The bar's own radius is a 16pt squircle, which is
        // right for a column of tools and wrong for a single button on the
        // front page: half the slab's width makes the same glass a circle,
        // and the 44pt button inside is already a capsule, so it lands
        // concentric with no second shape to keep in step.
        cornerRadius: GlassToolBar.width / 2,
        items: [
          GlassToolItem(
              id: id, symbol: symbol, fallback: fallbackSymbol, label: label),
        ],
        onTap: (_) => onTap(),
      );
    }
    // Off iOS there are no SF Symbols and no glass. The Material circle stays
    // as the host/desktop stand-in — same size, same job, and the widget tests
    // that drive the "+" still find something to tap.
    return _RoundButton(key: anchor, icon: icon, semanticLabel: label,
        onTap: onTap);
  }

  Widget _buildGrid(AppState app) => _Grid(
        app: app,
        scrollKey: _scrollKey,
        keyFor: _keyFor,
        onLayoutChanged: _schedulePush,
        // On the iPad the UIKit interaction registered by _pushTargets owns
        // the long press; a second menu on the same card would be two menus
        // racing for one gesture.
        onContextMenu: NativeMenu.isSupported ? null : _showCardMenu,
      );

  /// M420 — has THIS document been changed here since the group last agreed?
  ///
  /// Answered against the gallery's own entries, which are exactly the
  /// documents in the app's folder — the ones the mirror carries. A file
  /// opened from somewhere else never reaches this: it is not in `saved` under
  /// a mirror name, so it has no agreed version and nothing to be put back to.
  static bool _hasLocalChanges(SavedSketchInfo d) =>
      LanSync.instance.hasLocalChanges(_mirrorPath(d));

  /// The name the mirror knows a document by: `Bracket` + its kind's
  /// extension, which is how [DocFile] names it on disk.
  static String _mirrorPath(SavedSketchInfo d) =>
      '${d.name}.${extForKind(d.kind)}';

  /// M420 — GIVE UP THIS DEVICE'S CHANGES to one document.
  ///
  /// "I want a clear all changes button but also when I longpress a menu item
  /// a clear changes button only for this item."
  ///
  /// The confirmation says what actually happens AND that a copy is kept,
  /// which is the difference between "gone" and "recoverable" and the reason
  /// this can be put in front of a beginner at all.
  Future<void> _discardChanges(String name) async {
    final t = L.current;
    final doc = widget.app.saved.where((d) => d.name == name);
    if (doc.isEmpty) return;
    final path = _mirrorPath(doc.first);
    if (!LanSync.instance.hasLocalChanges(path)) return;
    final ok = await confirmAction(
      context,
      title: t.syncDiscardTitle(name),
      message: t.syncDiscardBody,
      confirmLabel: t.syncDiscard,
    );
    if (!ok || !mounted) return;
    final done = await LanSync.instance.discardLocalChanges([path]);
    if (!mounted) return;
    setState(() => _syncNote =
        done.isEmpty ? t.syncDiscardOffline : t.syncDiscardDone(done.length));
  }

  /// M418 — SYNC NOW. The button on the desktop and the drag-down on a touch
  /// screen both land here.
  ///
  /// The mirror is continuous, so this is not what makes sharing work — it is
  /// what makes it ANSWERABLE. "Did it sync?" had no way of being asked, and
  /// somebody who cannot ask that does not trust the feature, which was most
  /// of what "the syncing is dangerous" was about.
  Future<void> _syncNow() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _syncNote = null;
    });
    final result = await LanSync.instance.refresh();
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _syncNote = _noteFor(result);
      // M421 — UNDO, for the ten seconds in which somebody realises the
      // version that just arrived was not the one they wanted. It is offered
      // only when something was actually replaced: a refresh that took a
      // document this device did not have has nothing to undo.
      _undoable = result.outcome == SyncRefreshOutcome.updated
          ? LanSync.instance
              .backups()
              .where((b) =>
                  b.reason == 'replaced' &&
                  DateTime.now().difference(b.at) < const Duration(minutes: 1))
              .toList()
          : const <SyncBackup>[];
    });
  }

  /// M421 — puts back everything the last refresh replaced.
  Future<void> _undoLast() async {
    final items = _undoable;
    if (items.isEmpty) return;
    setState(() => _undoable = const <SyncBackup>[]);
    var n = 0;
    for (final b in items) {
      if (LanSync.instance.restore(b)) n++;
    }
    if (!mounted) return;
    setState(() => _syncNote =
        n == 0 ? null : L.current.syncRestoreDone(items.first.documentName));
  }

  /// The one line a refresh leaves behind, in plain words.
  ///
  /// Never null for a refresh somebody asked for: a control that appears to do
  /// nothing is a control people press five times. A divergence outranks a
  /// count, because "both versions are here" is the sentence worth reading and
  /// "3 documents updated" is not, when one of the three was that.
  String? _noteFor(SyncRefreshResult r) {
    final t = L.of(context);
    switch (r.outcome) {
      case SyncRefreshOutcome.off:
        return null; // the button is not even shown
      case SyncRefreshOutcome.alone:
        return t.syncNoDevices;
      case SyncRefreshOutcome.failed:
        return t.syncFailedNote;
      case SyncRefreshOutcome.kept:
        return r.forks.length == 1
            ? t.syncKeptBoth(_documentName(r.forks.single.original))
            : t.syncKeptBothMany(r.forks.length);
      case SyncRefreshOutcome.updated:
        return t.syncUpdated(r.documents);
      case SyncRefreshOutcome.upToDate:
        return t.syncUpToDate;
    }
  }

  /// `Bracket.ptp` -> `Bracket`. The gallery never shows an extension and this
  /// sentence must not be the one place that does.
  static String _documentName(String path) {
    final dot = path.lastIndexOf('.');
    return dot <= 0 ? path : path.substring(0, dot);
  }

  /// The note the gallery is currently showing, or null for none.
  ///
  /// A divergence that arrived on its own — nobody pressed anything, the other
  /// device simply saved — outranks the last refresh's result, and stays until
  /// it is dismissed rather than being replaced by the next thing that
  /// happens. It is the only message here that is about the user's work.
  String? _currentNote() {
    // While it is running, say so. The refresh waits up to three seconds for
    // the other devices to answer, and three seconds of silence after a press
    // is the "it does nothing" this whole control exists to avoid.
    if (_refreshing) return L.of(context).syncChecking;
    final forks = LanSync.instance.recentForks.value;
    if (forks.isNotEmpty) {
      final t = L.of(context);
      return forks.length == 1
          ? t.syncKeptBoth(_documentName(forks.single.original))
          : t.syncKeptBothMany(forks.length);
    }
    return _syncNote;
  }

  void _dismissNote() {
    LanSync.instance.recentForks.value = const <SyncFork>[];
    setState(() {
      _syncNote = null;
      _undoable = const <SyncBackup>[];
    });
  }

  /// M261 — Settings. A real UIKit form sheet on the iPad; a Flutter dialog
  /// with the same sections everywhere else. [SettingsSheet.show] decides
  /// which, and refuses to stack a second one.
  Future<void> _showSettings() => SettingsSheet.show(context, widget.app);

  /// The "+" offers both document kinds. On iOS this is a REAL UIKit action
  /// sheet (native_menu), anchored to the button — the same native surface the
  /// gallery cards already use. Off iOS (and if the plugin is somehow absent) a
  /// Flutter popup with the identical two entries stands in, so desktop runs
  /// and the host test suite behave exactly as before.
  Future<void> _showNewMenu() async {
    final t = L.of(context);
    final box = context.findRenderObject();
    final headerRect = box is RenderBox
        ? box.localToGlobal(Offset.zero) & box.size
        : Rect.zero;
    final anchor = _globalRect(_plusKey) ?? headerRect;

    String? choice;
    if (NativeMenu.isSupported) {
      choice = await NativeMenu.menu(
          items: newDocMenuItems(t, canPaste: widget.app.canPaste),
          anchor: anchor,
          cancelLabel: t.cancel);
    } else {
      final ovl = overlayRect(context, anchor); // see overlayRect
      choice = await showMenu<String>(
        context: context,
        color: T.fly,
        position: RelativeRect.fromLTRB(
            ovl.right - 240, 68, 24, ovl.bottom),
        items: [
          PopupMenuItem(
            value: '2d',
            height: 40,
            child: Row(children: [
              iconWidget(sketch2dMenuIcon, 18),
              const SizedBox(width: 10),
              Text(t.galleryNew2dSketch, style: ts(12.5, T.text)),
            ]),
          ),
          PopupMenuItem(
            value: '3d',
            height: 40,
            child: Row(children: [
              iconWidget(part3dMenuIcon, 18),
              const SizedBox(width: 10),
              Text(t.galleryNew3dPart, style: ts(12.5, T.text)),
            ]),
          ),
          PopupMenuItem(
            value: 'asm',
            height: 40,
            child: Row(children: [
              iconWidget(assemblyMenuIcon, 18),
              const SizedBox(width: 10),
              Text(t.galleryNewAssembly, style: ts(12.5, T.text)),
            ]),
          ),
          PopupMenuItem(
            value: 'import',
            height: 40,
            child: Row(children: [
              iconWidget(part3dMenuIcon, 18),
              const SizedBox(width: 10),
              Text(t.openEllipsis, style: ts(12.5, T.text)),
            ]),
          ),
          if (widget.app.canPaste)
            PopupMenuItem(
              value: 'paste',
              height: 40,
              child: Row(children: [
                const Icon(Icons.content_paste_outlined, size: 18),
                const SizedBox(width: 10),
                Text(t.btnPaste, style: ts(12.5, T.text)),
              ]),
            ),
        ],
      );
    }
    if (!mounted) return;
    if (choice == '2d') {
      await _promptNewSketch();
    } else if (choice == '3d') {
      await _promptNewPart();
    } else if (choice == 'asm') {
      await _promptNewAssembly();
    } else if (choice == 'import') {
      await _importDocument();
    } else if (choice == 'paste') {
      await widget.app.paste(); // M345
    }
  }

  /// M177 — Open. One picker, four outcomes, decided by the file:
  ///
  ///   a .ptp/.pts from elsewhere  -> opened IN PLACE and remembered, so it is
  ///                                  in the gallery from now on and Ctrl+S
  ///                                  writes back to where it actually lives
  ///   a .ptp/.pts already in the app folder -> just opened
  ///   a STEP, DXF, STL, OBJ or 3MF -> converted into a new document here
  ///   anything else               -> said so plainly
  ///
  /// [AppState.openPath] owns that decision; this only picks the file.
  Future<void> _importDocument() async {
    final app = widget.app;
    // The list lives in doc_ref.dart next to openActionFor, so the picker
    // cannot offer a kind that Open then refuses.
    const kinds = kOpenableExtensions;
    try {
      // The NATIVE picker first, in open-in-place mode. The ordinary file
      // picker imports a COPY into tmp, which would make "save back to where
      // I opened it from" impossible — see DocumentOpen.swift. Where the
      // native side is unavailable (desktop, host tests, an older iOS) the
      // copy still opens: openPath adopts it into the app folder rather than
      // remembering a path that is about to vanish.
      //
      // Logged on BOTH sides of the call, and that is not noise. Presenting
      // the picker is a native call that can take the whole app down without
      // Dart ever running again — a bad content-type list raises an
      // Objective-C exception, and Swift cannot catch it. When that happened
      // the app's own log ended on an unrelated line and there was no way to
      // tell the picker from anything else the user had touched. These two
      // lines put the crash inside a bracket.
      // Ask what these resolve to BEFORE presenting. See
      // NativeMenu.probeContentTypes: a `dyn.` identifier means iOS has no
      // declaration for that extension, and that is what the picker dies on.
      final resolved = await NativeMenu.probeContentTypes(kinds);
      // milestone, not i: buffered logging is flushed every 400 ms, so after a
      // hard native kill the log's last line is whatever happened to be on
      // disk — NOT where the app died. See Log.milestone.
      Log.milestone(
          'doc',
          'open: presenting picker for ${kinds.join(",")}'
          '${resolved.isEmpty ? "" : " -> ${resolved.join(" ")}"}');
      final picked = await NativeMenu.openInPlace(
        extensions: kinds,
        anchor: _globalRect(_plusKey),
        // The desktop chooser's own chrome, in the user's language. iOS names
        // its picker itself and ignores these.
        openTitle: L.current.dlgOpenTitle,
        knownFilterName: L.current.filterOpenableDocuments,
        allFilesFilterName: L.current.filterAllFiles,
      );
      var path = picked?['path'];
      Log.milestone(
          'doc', 'open: picker returned ${path == null ? "nothing" : path}');
      // Only where NO platform chooser ran. On the desktop `openInPlace` is
      // the GTK/Win32 chooser (see native_menu/linux), so a null there means
      // the user cancelled — and putting a second picker up on a cancel is
      // the one thing worse than not having one.
      if (path == null && !NativeMenu.hasFileSurfaces) {
        final res = await FilePicker.platform
            .pickFiles(type: FileType.custom, allowedExtensions: kinds);
        path = res?.files.single.path;
      }
      if (path == null || !mounted) return;
      final name = await app.openPath(path, bookmark: picked?['bookmark']);
      if (name != null) Log.i('doc', 'opened "$name" from $path');
    } catch (e) {
      Log.w('import', 'open failed: $e');
      app.toast(L.current.msgCouldNotOpenFile);
    }
  }

  Future<void> _promptNewPart() async {
    final app = widget.app;
    final t = L.of(context);
    final name = await promptForText(
      context,
      title: t.dlgNewPart,
      initialValue: app.suggestedPartName(),
      placeholder: t.phPartName,
      confirmLabel: t.create,
      validate: (v) =>
          app.validateSketchName(v) ??
          (app.docNameExists(v.trim()) ? t.errNameTaken : null),
    );
    if (name == null) return;
    await app.createNamedPart(name);
  }

  Future<void> _promptNewAssembly() async {
    final app = widget.app;
    final t = L.of(context);
    final name = await promptForText(
      context,
      title: t.dlgNewAssembly,
      initialValue: app.suggestedAssemblyName(),
      placeholder: t.phAssemblyName,
      confirmLabel: t.create,
      validate: (v) =>
          app.validateSketchName(v) ??
          (app.docNameExists(v.trim()) ? t.errNameTaken : null),
    );
    if (name == null) return;
    await app.createNamedAssembly(name);
  }

  Future<void> _sendFile(String name, {required bool share}) async {
    final isPart = widget.app.isPartName(name);
    // Which branch this takes decides everything the user sees next, and it is
    // not visible from the channel trace. #12 was reported as "export does
    // nothing" with no way to tell whether the card was even classified as a
    // part, let alone whether a file came out.
    Log.i('gallery', '${share ? 'share' : 'export'} "$name" (part=$isPart)');
    String? path;
    if (isPart && !share) {
      // M289 — ask STL or STEP before the location, for part cards.
      final t = L.of(context);
      final box = context.findRenderObject();
      final anchor = box is RenderBox
          ? box.localToGlobal(Offset.zero) & box.size
          : Rect.zero;
      final items = [
        NativeMenuItem(id: 'stl', title: 'STL', symbol: 'doc'),
        NativeMenuItem(id: 'step', title: 'STEP', symbol: 'doc'),
      ];
      String? format;
      if (NativeMenu.isSupported) {
        format = await NativeMenu.menu(
            items: items, anchor: anchor, cancelLabel: t.cancel);
      } else {
        format = await showMenu<String>(
          context: context,
          color: T.fly,
          position: RelativeRect.fromRect(
              overlayRect(context, anchor),
              Offset.zero & MediaQuery.sizeOf(context)),
          items: [
            for (final item in items)
              PopupMenuItem<String>(
                value: item.id,
                child: Text(item.title),
              ),
          ],
        );
      }
      if (format == null || !mounted) return;
      path = switch (format) {
        'stl' => await widget.app.partExportStl(name),
        'step' => await widget.app.partExportStep(name),
        _ => null,
      };
    } else {
      path = isPart
          ? await widget.app.partExportStep(name)
          : await widget.app.sketchExportPath(name);
    }
    if (path == null || !mounted) {
      Log.w('gallery', 'nothing to send for "$name":'
          ' ${path == null ? 'no file was written' : 'view is gone'}');
      return;
    }
    // iPad refuses to present these sheets without a popover anchor.
    final anchor = _globalRect(_keyFor(name)) ??
        Rect.fromLTWH(MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 2, 1, 1);
    final saveTitle = L.current.dlgSaveCopyTitle;
    if (share) {
      await NativeMenu.shareFile(path, anchor: anchor, saveTitle: saveTitle);
    } else {
      await NativeMenu.exportFile(path, anchor: anchor, saveTitle: saveTitle);
    }
  }

  Future<void> _promptRename(String name) async {
    final app = widget.app;
    final t = L.of(context);
    final result = await promptForText(
      context,
      title: t.dlgRenameSketch,
      initialValue: name,
      placeholder: t.phSketchName,
      confirmLabel: t.rename,
      validate: (v) =>
          app.validateSketchName(v) ??
          (v.trim() != name && app.docNameExists(v.trim())
              ? t.errNameTaken
              : null),
    );
    if (result != null && result.trim() != name) {
      await app.renameDocument(name, result);
    }
  }

  Future<void> _confirmDelete(String name) async {
    final t = L.of(context);
    final ok = await confirmAction(
      context,
      title: t.dlgDeleteNamed(name),
      message: t.msgSketchDeleted,
      confirmLabel: t.delete,
    );
    if (ok) await widget.app.deleteDocument(name);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final t = L.of(context);
    // The gallery contents can change without HomeView being rebuilt from
    // scratch (rename, delete, duplicate), so re-measure after every build.
    _schedulePush();
    // M270 — the backdrop the user chose. `galleryPalette` is what the cards,
    // their titles and their dates read below: a LIGHT colour under a dark app
    // flips this screen's ink and nothing else, which is the whole reason the
    // setting is safe to offer.
    final backdrop = Backdrops.current.value;
    return Container(
      // Under the picture as well as instead of it: the ground is painted on
      // the first frame and a photograph is decoded on a later one, and
      // without this the gallery flashes white in between.
      color: galleryGround(backdrop, T.palette) ?? T.galleryBg,
      child: Stack(children: [
        if (backdrop.kind == BackdropKind.image) ...[
          Positioned.fill(
            child: Image.file(
              File(backdrop.imagePath),
              fit: BoxFit.cover,
              // A picture that has gone (deleted in Files, restored onto a new
              // device) leaves the palette's ground, not a broken-image glyph.
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          // THE SCRIM. See kBackdropScrim: a photograph has a thousand
          // luminances and the labels must not depend on which one they land
          // on. The picture reads through it; the gallery stays legible.
          Positioned.fill(
            child: ColoredBox(
                color: T.galleryBg.withValues(alpha: kBackdropScrim)),
          ),
        ],
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ---- gallery header: nothing but the new-sketch button ----
        // The "CAD" title is gone: the gallery IS the app's front page, a big
        // word above it only ate a card row. Padding is tightened to match,
        // since the header no longer has to make room for 32px type.
        // M261 — two buttons, two jobs, and the gap between them says which
        // is which. LEFT is the app (its appearance, its language, its
        // version); RIGHT is the document you are about to make. Settings on
        // the leading edge is where Shortcuts, Photos and Files put the
        // app-level control, and it is the half of the header that was empty.
        Padding(
          padding: const EdgeInsets.fromLTRB(_kPad, 12, _kPad, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _headerButton(
                id: 'settings',
                symbol: 'gearshape',
                fallbackSymbol: 'gear',
                icon: Icons.settings_outlined,
                label: t.settingsButton,
                onTap: _showSettings,
              ),
              Row(children: [
                // M418 — only where there is something to sync WITH. A button
                // that cannot do anything is worse than no button: it invites
                // a press and then has to explain itself.
                if (ShareCodes.current.value != null) ...[
                  _headerButton(
                    id: 'sync',
                    symbol: 'arrow.clockwise',
                    fallbackSymbol: 'arrow.2.circlepath',
                    icon: Icons.refresh,
                    label: t.syncNow,
                    onTap: _syncNow,
                  ),
                  const SizedBox(width: 10),
                ],
                _headerButton(
                  anchor: _plusKey,
                  id: 'new',
                  symbol: 'plus',
                  fallbackSymbol: 'plus',
                  icon: Icons.add,
                  label: t.galleryNew2dSketch,
                  onTap: _showNewMenu,
                ),
              ]),
            ],
          ),
        ),
        // M418/M417 — ONE line, and only when there is something to say.
        // Everything the mirror has to tell the user goes through here: what
        // the last refresh did, and — outranking it — a document that was
        // changed in two places and has been kept twice.
        if (_currentNote() != null)
          _SyncNote(
              text: _currentNote()!,
              onDismiss: _refreshing ? null : _dismissNote,
              undoLabel: _undoable.isEmpty ? null : L.of(context).syncUndo,
              onUndo: _undoable.isEmpty ? null : _undoLast),
        Expanded(
          child: app.saved.isEmpty
              ? const _EmptyState()
              // M418 — DRAG DOWN TO SYNC, which is the whole gesture on a
              // touch screen and needs no button to explain it. Wrapped
              // around the grid rather than the whole page so the header's
              // own buttons keep their hit area, and only where sharing is on
              // — a drag that cannot do anything should not spin.
              : ShareCodes.current.value == null
                  ? _buildGrid(app)
                  : RefreshIndicator(
                      onRefresh: _syncNow,
                      child: _buildGrid(app),
                    ),
        ),
        ]),
      ]),
    );
  }
}

class _Grid extends StatelessWidget {
  final AppState app;
  final GlobalKey scrollKey;
  final GlobalKey Function(String name) keyFor;
  final VoidCallback onLayoutChanged;

  /// Null on the iPad, where UIKit owns the long press. See _Card.
  final void Function(String name, Offset globalPosition)? onContextMenu;
  const _Grid({
    required this.app,
    required this.scrollKey,
    required this.keyFor,
    required this.onLayoutChanged,
    this.onContextMenu,
  });

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
      // Scrolling moves every card: the native hit rects must follow.
      return NotificationListener<ScrollNotification>(
        onNotification: (_) {
          onLayoutChanged();
          return false;
        },
        child: SingleChildScrollView(
          key: scrollKey,
          padding: const EdgeInsets.fromLTRB(_kPad, 4, _kPad, 30),
          child: Wrap(
            spacing: _kGap,
            runSpacing: _kGap,
            children: [
              for (final s in app.saved)
                SizedBox(
                  key: keyFor(s.name),
                  width: cardW,
                  child: _Card(
                    name: s.name,
                    date: _fmt(s.modified),
                    preview: s.preview,
                    thumbHeight: cardH,
                    kind: s.kind,
                    onTap: () => app.openDocument(s.name),
                    onContextMenu: onContextMenu == null
                        ? null
                        : (pos) => onContextMenu!(s.name, pos),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

/// One of the gallery header's two round buttons.
///
/// M261 — was `_PlusButton`, which drew the only one there was. There are two
/// now and they are the same object: same size, same plate, same hover, so the
/// header reads as a pair rather than as a button and something else that
/// happens to be round.
class _RoundButton extends StatefulWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  const _RoundButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });
  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    // M270 — the BACKDROP's palette, not the app's. Everything on this screen
    // sits on whatever the user chose, so everything on this screen has to be
    // legible against it.
    final g = galleryPalette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              // M367 — on the material where there is one. These two buttons
              // are a GlassToolBar on the iPad (M266: "the header buttons are
              // the app's own chrome"), and a painted circle beside a glass
              // ribbon is exactly the "they seem like flutter" the milestone
              // was filed about. The hover tint stays: it is the button's
              // response, not its surface.
              color: GlassPanel.isSupported
                  ? (_h ? g.galleryActionBgHover.withValues(alpha: 0.35) : null)
                  : (_h ? g.galleryActionBgHover : g.galleryActionBg),
              shape: BoxShape.circle,
              border:
                  GlassPanel.isSupported ? null : Border.all(color: g.cardBorder),
              boxShadow: [
                BoxShadow(
                    color: g.cardShadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            // The material goes UNDER the glyph and is clipped to the same
            // circle the button is. GlassPanel cuts its own corners, so a
            // radius of half the width is the circle.
            child: Stack(alignment: Alignment.center, children: [
              if (GlassPanel.isSupported)
                const Positioned.fill(child: GlassPanel(cornerRadius: 23)),
              Icon(widget.icon, color: g.text, size: 24),
            ]),
          ),
        ),
      ),
    );
  }
}

/// M418/M417 — the gallery's one sync sentence.
///
/// Deliberately a LINE and not a dialog. Everything it can say is either good
/// news or a fact about a document that is safely on disk; none of it is a
/// question, and none of it should stop somebody getting to their work. It
/// dismisses on a tap, because the one thing worse than a message nobody reads
/// is a message nobody can get rid of.
class _SyncNote extends StatelessWidget {
  final String text;

  /// Null while a refresh is running: there is nothing to dismiss yet, and a
  /// close cross on a progress message invites a press that cannot help.
  final VoidCallback? onDismiss;

  /// M421 — offered only when the last refresh actually replaced something.
  final String? undoLabel;
  final VoidCallback? onUndo;
  const _SyncNote(
      {required this.text, this.onDismiss, this.undoLabel, this.onUndo});

  @override
  Widget build(BuildContext context) {
    final g = galleryPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kPad, 0, _kPad, 10),
      child: GestureDetector(
        onTap: onDismiss,
        behavior: HitTestBehavior.opaque,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Row(children: [
            Flexible(
              child: Text(text,
                  style: ts(12.5, g.cardDate), overflow: TextOverflow.ellipsis),
            ),
            if (undoLabel != null && onUndo != null) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onUndo,
                behavior: HitTestBehavior.opaque,
                child: Text(undoLabel!,
                    style: ts(12.5, T.accent, w: FontWeight.w600)),
              ),
            ],
            if (onDismiss != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.close, size: 14, color: g.cardDate),
            ],
          ]),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    // Deliberately ONE line. The cube glyph and the "No sketches yet" heading
    // were decoration around a message that already says everything.
    return Center(
      child: Text(L.of(context).galleryEmpty,
          style: ts(13.5, galleryPalette.cardDate)),
    );
  }
}

class _Card extends StatefulWidget {
  final String name, date;
  final File? preview;
  final double thumbHeight;
  final String kind;
  final VoidCallback onTap;

  /// Off iOS: where the card's context menu should open. Null on the iPad,
  /// where the UIKit interaction owns the long press and this card must not
  /// compete with it — see [_HomeViewState._pushTargets].
  final void Function(Offset globalPosition)? onContextMenu;
  const _Card({
    required this.name,
    required this.date,
    required this.preview,
    required this.thumbHeight,
    required this.onTap,
    this.onContextMenu,
    this.kind = 'sketch',
  });
  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    final g = galleryPalette; // M270 — see _RoundButtonState
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      // A raw Listener for the RIGHT button, exactly as the model browser's
      // rows do it: a secondary click is not a gesture the arena arbitrates,
      // and routing it through one would make it compete with the card's tap.
      child: Listener(
        onPointerDown: (e) {
          final open = widget.onContextMenu;
          if (open != null &&
              e.kind == PointerDeviceKind.mouse &&
              e.buttons == kSecondaryMouseButton) {
            open(e.position);
          }
        },
        child: GestureDetector(
        onTap: widget.onTap,
        // Long press as well, for a touchscreen or a pen on a desktop: the
        // gesture the iPad uses, kept working where there is no UIKit menu to
        // own it.
        onLongPressStart: widget.onContextMenu == null
            ? null
            : (d) => widget.onContextMenu!(d.globalPosition),
        behavior: HitTestBehavior.opaque,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AnimatedScale(
            scale: _h ? 1.02 : 1.0,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: Container(
              height: widget.thumbHeight,
              decoration: BoxDecoration(
                color: g.galleryThumb,
                borderRadius: BorderRadius.circular(_kThumbRadius),
                border: Border.all(
                    color: _h ? g.cardHoverBorder : g.cardBorder,
                    width: _h ? 1.5 : 1),
                boxShadow: [
                  BoxShadow(
                      color: g.cardShadow, blurRadius: 10, offset: const Offset(0, 3)),
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
              style: ts(13.5, cardNameColor(g, widget.kind),
                  w: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(widget.date,
              textAlign: TextAlign.center,
              style: ts(11.5, g.cardDate)),
        ]),
        ),
      ),
    );
  }

  Widget _blank() => Center(
        child: Opacity(
          opacity: 0.5,
          child: iconWidget(
              switch (widget.kind) {
                'part' => partCubeIcon,
                kAssemblyDocKind => assemblyCubeIcon,
                _ => sketchCubeIcon,
              },
              30),
        ),
      );
}

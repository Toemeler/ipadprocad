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
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../icon_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../backdrop.dart';
import '../doc_ref.dart';
import '../l10n/l.dart';
import '../log.dart';
import '../svg_icons.dart';
import '../theme.dart';
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
List<List<NativeMenuItem>> sketchMenuGroups(AppL10n t) => [
      [
        NativeMenuItem(id: 'rename', title: t.rename, symbol: 'pencil'),
        NativeMenuItem(
            id: 'duplicate',
            title: t.duplicate,
            symbol: 'plus.square.on.square'),
        NativeMenuItem(
            id: 'export',
            title: t.exportEllipsis,
            symbol: 'square.and.arrow.down'),
        NativeMenuItem(
            id: 'share',
            title: t.shareEllipsis,
            symbol: 'square.and.arrow.up'),
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
List<NativeMenuItem> newDocMenuItems(AppL10n t) => [
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
List<String> exportFormatsFor(String kind) {
  final k = kind.toLowerCase();
  if (k.endsWith('.ptp') || k == 'part' || k == 'ptp') {
    return ['stl', 'step'];
  }
  if (k.endsWith('.pts') || k == 'sketch' || k == 'pts') {
    return ['dxf'];
  }
  return ['step'];
}

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

  @override
  void initState() {
    super.initState();
    NativeMenu.setSelectionHandler(NativeMenu.kGallery, _onMenuSelection);
    _schedulePush();
  }

  @override
  void dispose() {
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
        groups: sketchMenuGroups(L.of(context)),
      ));
    }
    final payload = jsonEncode([for (final t in targets) t.toMap()]);
    if (payload == _lastPayload) return;
    _lastPayload = payload;
    NativeMenu.setTargets(NativeMenu.kGallery, targets);
  }

  // ---- menu actions ----

  void _onMenuSelection(String sketch, String item) {
    if (!mounted) return;
    switch (item) {
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
          items: newDocMenuItems(t), anchor: anchor, cancelLabel: t.cancel);
    } else {
      choice = await showMenu<String>(
        context: context,
        color: T.fly,
        position: RelativeRect.fromLTRB(
            anchor.right - 240, 68, 24, anchor.bottom),
        items: [
          PopupMenuItem(
            value: '2d',
            height: 40,
            child: Row(children: [
              SvgPicture.string(themedIcon(sketch2dMenuIcon), width: 18, height: 18),
              const SizedBox(width: 10),
              Text(t.galleryNew2dSketch, style: ts(12.5, T.text)),
            ]),
          ),
          PopupMenuItem(
            value: '3d',
            height: 40,
            child: Row(children: [
              SvgPicture.string(themedIcon(part3dMenuIcon), width: 18, height: 18),
              const SizedBox(width: 10),
              Text(t.galleryNew3dPart, style: ts(12.5, T.text)),
            ]),
          ),
          PopupMenuItem(
            value: 'asm',
            height: 40,
            child: Row(children: [
              SvgPicture.string(themedIcon(assemblyMenuIcon),
                  width: 18, height: 18),
              const SizedBox(width: 10),
              Text(t.galleryNewAssembly, style: ts(12.5, T.text)),
            ]),
          ),
          PopupMenuItem(
            value: 'import',
            height: 40,
            child: Row(children: [
              SvgPicture.string(themedIcon(part3dMenuIcon), width: 18, height: 18),
              const SizedBox(width: 10),
              Text(t.openEllipsis, style: ts(12.5, T.text)),
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
          extensions: kinds, anchor: _globalRect(_plusKey));
      var path = picked?['path'];
      Log.milestone(
          'doc', 'open: picker returned ${path == null ? "nothing" : path}');
      if (path == null && !NativeMenu.isSupported) {
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
    final formats = exportFormatsFor(name);
    String? path;
    if (!share && formats.length > 1) {
      // M289 — ask which format before the location, for part cards
      // (and anything else that can write more than one).
      final t = L.of(context);
      final box = context.findRenderObject();
      final chooserAnchor = box is RenderBox
          ? box.localToGlobal(Offset.zero) & box.size
          : Rect.zero;
      final items = [
        for (final f in formats)
          NativeMenuItem(
            id: f,
            title: f.toUpperCase(),
            symbol: f == 'stl' ? 'doc' : 'cube',
          ),
      ];
      String? format;
      if (NativeMenu.isSupported) {
        format = await NativeMenu.menu(
            items: items, anchor: chooserAnchor, cancelLabel: t.cancel);
      } else {
        format = await showMenu<String>(
          context: context,
          color: T.fly,
          position: RelativeRect.fromRect(
              chooserAnchor, Offset.zero & MediaQuery.sizeOf(context)),
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
        'dxf' => await widget.app.sketchExportPath(name),
        _ => null,
      };
    } else {
      // Single format: go straight, respecting what the document can write.
      if (formats.contains('stl')) {
        path = await widget.app.partExportStl(name);
      } else if (formats.contains('step')) {
        path = await widget.app.partExportStep(name);
      } else {
        path = await widget.app.sketchExportPath(name);
      }
    }
    if (path == null || !mounted) return;
    // iPad refuses to present these sheets without a popover anchor.
    final anchor = _globalRect(_keyFor(name)) ??
        Rect.fromLTWH(MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 2, 1, 1);
    if (share) {
      await NativeMenu.shareFile(path, anchor: anchor);
    } else {
      await NativeMenu.exportFile(path, anchor: anchor);
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
              _headerButton(
                anchor: _plusKey,
                id: 'new',
                symbol: 'plus',
                fallbackSymbol: 'plus',
                icon: Icons.add,
                label: t.galleryNew2dSketch,
                onTap: _showNewMenu,
              ),
            ],
          ),
        ),
        Expanded(
          child: app.saved.isEmpty
              ? const _EmptyState()
              : _Grid(
                  app: app,
                  scrollKey: _scrollKey,
                  keyFor: _keyFor,
                  onLayoutChanged: _schedulePush,
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
  const _Grid({
    required this.app,
    required this.scrollKey,
    required this.keyFor,
    required this.onLayoutChanged,
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
              color: _h ? g.galleryActionBgHover : g.galleryActionBg,
              shape: BoxShape.circle,
              border: Border.all(color: g.cardBorder),
              boxShadow: [
                BoxShadow(
                    color: g.cardShadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: Icon(widget.icon, color: g.text, size: 24),
          ),
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
  const _Card({
    required this.name,
    required this.date,
    required this.preview,
    required this.thumbHeight,
    required this.onTap,
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
    );
  }

  Widget _blank() => Center(
        child: Opacity(
          opacity: 0.5,
          child: SvgPicture.string(
              themedIcon(switch (widget.kind) {
                'part' => partCubeIcon,
                kAssemblyDocKind => assemblyCubeIcon,
                _ => sketchCubeIcon,
              }),
              width: 30,
              height: 30),
        ),
      );
}

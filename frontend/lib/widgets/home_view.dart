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
import 'package:flutter_svg/flutter_svg.dart';
import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../doc_file.dart';
import '../l10n/l.dart';
import '../log.dart';
import '../svg_icons.dart';
import '../theme.dart';
import 'native_prompts.dart';

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
      // M117 — Open belongs HERE, next to the two ways of starting a
      // document, because that is what it is: a third way to get one. In the
      // ribbon it was a tool among modelling tools, which is the wrong shelf.
      //
      // M177 — and it is called "Open", not "Import STEP / DXF", because one
      // verb covers all of it: a Prototype document from anywhere on the iPad
      // opens in place, a STEP or DXF is converted. Which one happens follows
      // from the file, not from a menu the user has to get right first.
      NativeMenuItem(id: 'import', title: t.openEllipsis, symbol: 'folder'),
      // M234 — the language switch.
      //
      // It lives in the "+" menu because that is the app's only menu that
      // belongs to the APP rather than to a document: the gallery is the front
      // page, and this is the one control on it that is not about drawing.
      //
      // The entry names the language it switches TO, never the one that is
      // on. A row reading "Deutsch" while the app is already German is a
      // status line, and people tap status lines expecting something to
      // happen. `kLanguageMenuId` is matched against, never the title.
      NativeMenuItem(
          id: kLanguageMenuId,
          title: L.otherStrings.languageMenuItem,
          symbol: 'globe'),
    ];

/// The id the language row comes back as. A constant, because the row's
/// TITLE changes with the language and must never be what code matches on.
const String kLanguageMenuId = 'lang';

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
              SvgPicture.string(sketch2dMenuIcon, width: 18, height: 18),
              const SizedBox(width: 10),
              Text(t.galleryNew2dSketch, style: ts(12.5, T.text)),
            ]),
          ),
          PopupMenuItem(
            value: '3d',
            height: 40,
            child: Row(children: [
              SvgPicture.string(part3dMenuIcon, width: 18, height: 18),
              const SizedBox(width: 10),
              Text(t.galleryNew3dPart, style: ts(12.5, T.text)),
            ]),
          ),
          PopupMenuItem(
            value: 'import',
            height: 40,
            child: Row(children: [
              SvgPicture.string(part3dMenuIcon, width: 18, height: 18),
              const SizedBox(width: 10),
              Text(t.openEllipsis, style: ts(12.5, T.text)),
            ]),
          ),
          // M234 — the same language row the native sheet carries, so the
          // switch is reachable off iOS and in the host test suite too.
          PopupMenuItem(
            value: kLanguageMenuId,
            height: 40,
            child: Row(children: [
              const Icon(Icons.language, size: 18, color: T.text),
              const SizedBox(width: 10),
              Text(L.otherStrings.languageMenuItem, style: ts(12.5, T.text)),
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
    } else if (choice == 'import') {
      await _importDocument();
    } else if (choice == kLanguageMenuId) {
      // Applies on the next frame and is written to the settings file on the
      // way out; nothing is rebuilt, nothing is lost. See L.set.
      L.set(L.other);
    }
  }

  /// M177 — Open. One picker, four outcomes, decided by the file:
  ///
  ///   a .ptp/.pts from elsewhere  -> opened IN PLACE and remembered, so it is
  ///                                  in the gallery from now on and Ctrl+S
  ///                                  writes back to where it actually lives
  ///   a .ptp/.pts already in the app folder -> just opened
  ///   a STEP or DXF               -> converted into a new document here
  ///   anything else               -> said so plainly
  ///
  /// [AppState.openPath] owns that decision; this only picks the file.
  Future<void> _importDocument() async {
    final app = widget.app;
    const kinds = [kPartExt, kSketchExt, 'step', 'stp', 'dxf'];
    try {
      // The NATIVE picker first, in open-in-place mode. The ordinary file
      // picker imports a COPY into tmp, which would make "save back to where
      // I opened it from" impossible — see DocumentOpen.swift. Where the
      // native side is unavailable (desktop, host tests, an older iOS) the
      // copy still opens: openPath adopts it into the app folder rather than
      // remembering a path that is about to vanish.
      final picked = await NativeMenu.openInPlace(
          extensions: kinds, anchor: _globalRect(_plusKey));
      var path = picked?['path'];
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

  Future<void> _sendFile(String name, {required bool share}) async {
    // A part exports as STEP (its solids), a sketch as DXF.
    final path = widget.app.isPartName(name)
        ? await widget.app.partExportStep(name)
        : await widget.app.sketchExportPath(name);
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
    // The gallery contents can change without HomeView being rebuilt from
    // scratch (rename, delete, duplicate), so re-measure after every build.
    _schedulePush();
    return Container(
      color: T.galleryBg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ---- gallery header: nothing but the new-sketch button ----
        // The "CAD" title is gone: the gallery IS the app's front page, a big
        // word above it only ate a card row. Padding is tightened to match,
        // since the header no longer has to make room for 32px type.
        Padding(
          padding: const EdgeInsets.fromLTRB(_kPad, 12, _kPad, 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _PlusButton(key: _plusKey, onTap: _showNewMenu),
          ]),
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

class _PlusButton extends StatefulWidget {
  final VoidCallback onTap;
  const _PlusButton({super.key, required this.onTap});
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
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    // Deliberately ONE line. The cube glyph and the "No sketches yet" heading
    // were decoration around a message that already says everything.
    return Center(
      child: Text(L.of(context).galleryEmpty,
          style: ts(13.5, T.cardDate)),
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
                borderRadius: BorderRadius.circular(_kThumbRadius),
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
          child: SvgPicture.string(
              widget.kind == 'part' ? partCubeIcon : sketchCubeIcon,
              width: 30,
              height: 30),
        ),
      );
}

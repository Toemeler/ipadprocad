// iPadProCAD — home view (#home): a Procreate-style sketch gallery.
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

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:native_menu/native_menu.dart';

import '../app_state.dart';
import '../svg_icons.dart';
import '../theme.dart';

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
/// Top-level and const so tests can assert the contract without a device.
List<List<NativeMenuItem>> sketchMenuGroups() => const [
      [
        NativeMenuItem(id: 'rename', title: 'Rename', symbol: 'pencil'),
        NativeMenuItem(
            id: 'duplicate',
            title: 'Duplicate',
            symbol: 'plus.square.on.square'),
        NativeMenuItem(
            id: 'export', title: 'Export…', symbol: 'square.and.arrow.down'),
        NativeMenuItem(
            id: 'share', title: 'Share…', symbol: 'square.and.arrow.up'),
      ],
      [
        NativeMenuItem(
            id: 'delete', title: 'Delete', symbol: 'trash', destructive: true),
      ],
    ];

class HomeView extends StatefulWidget {
  final AppState app;
  const HomeView({super.key, required this.app});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final Map<String, GlobalKey> _cardKeys = {};
  final GlobalKey _scrollKey = GlobalKey();
  String? _lastPayload;
  bool _pushScheduled = false;

  @override
  void initState() {
    super.initState();
    NativeMenu.setSelectionHandler(_onMenuSelection);
    _schedulePush();
  }

  @override
  void dispose() {
    // Pushing an empty list REMOVES the interaction from the Flutter view, so
    // leaving the gallery cannot shadow the CAD viewport's own long press.
    NativeMenu.setSelectionHandler(null);
    NativeMenu.setTargets(const []);
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
        groups: sketchMenuGroups(),
      ));
    }
    final payload = jsonEncode([for (final t in targets) t.toMap()]);
    if (payload == _lastPayload) return;
    _lastPayload = payload;
    NativeMenu.setTargets(targets);
  }

  // ---- menu actions ----

  void _onMenuSelection(String sketch, String item) {
    if (!mounted) return;
    switch (item) {
      case 'rename':
        _promptRename(sketch);
        break;
      case 'duplicate':
        widget.app.duplicateSketch(sketch);
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

  Future<void> _sendFile(String name, {required bool share}) async {
    final path = await widget.app.sketchExportPath(name);
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
    final ctrl = TextEditingController(text: name);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void submit() {
            final v = ctrl.text.trim();
            final problem = app.validateSketchName(v) ??
                (v != name && app.sketchNameExists(v)
                    ? 'A sketch with that name already exists'
                    : null);
            if (problem != null) {
              setLocal(() => error = problem);
              return;
            }
            Navigator.of(ctx).pop(v);
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF292D33),
            title: Text('Rename sketch', style: ts(14, T.mbText)),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              style: ts(13, Colors.white),
              cursorColor: T.blue,
              decoration: InputDecoration(
                hintText: 'Sketch name',
                hintStyle: ts(13, T.mbDim),
                errorText: error,
                errorStyle: ts(11.5, const Color(0xFFE05A56)),
                enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: T.sep)),
                focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: T.blue)),
              ),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: ts(13, T.mbDim))),
              TextButton(
                  onPressed: submit,
                  child: Text('Rename', style: ts(13, T.blue))),
            ],
          );
        },
      ),
    );
    ctrl.dispose();
    if (result != null && result != name) {
      await app.renameSketch(name, result);
    }
  }

  Future<void> _confirmDelete(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF292D33),
        title: Text('Delete “$name”?', style: ts(14, T.mbText)),
        content: Text(
          'The sketch and everything in it are removed from this iPad. '
          'This can’t be undone.',
          style: ts(12.5, T.mbDim),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: ts(13, T.mbDim))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: ts(13, const Color(0xFFE05A56))),
          ),
        ],
      ),
    );
    if (ok == true) await widget.app.deleteSketch(name);
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
            _PlusButton(onTap: app.createNewSketch),
          ]),
        ),
        Expanded(
          child: app.saved.isEmpty
              ? _EmptyState(onNew: app.createNewSketch)
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
                    onTap: () => app.openSketch(s.name),
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
  const _PlusButton({required this.onTap});
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
  final VoidCallback onNew;
  const _EmptyState({required this.onNew});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Opacity(
          opacity: 0.5,
          child: SvgPicture.string(sketchCubeIcon, width: 54, height: 54),
        ),
        const SizedBox(height: 20),
        Text('No sketches yet',
            style: ts(18, T.cardName, w: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Tap  +  to start a new sketch',
            style: ts(13.5, T.cardDate)),
      ]),
    );
  }
}

class _Card extends StatefulWidget {
  final String name, date;
  final File? preview;
  final double thumbHeight;
  final VoidCallback onTap;
  const _Card({
    required this.name,
    required this.date,
    required this.preview,
    required this.thumbHeight,
    required this.onTap,
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
          child: SvgPicture.string(sketchCubeIcon, width: 30, height: 30),
        ),
      );
}

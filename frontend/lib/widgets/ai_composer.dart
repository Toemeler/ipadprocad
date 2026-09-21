import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_menu/native_menu.dart';

import '../ai/ai_controller.dart';
import '../ai/ai_trace.dart';
import '../app_state.dart';
import '../ios_design.dart';
import '../l10n/l.dart';
import '../theme.dart';
import 'ai_settings_sheet.dart';
import 'bottom_tabbar.dart';
import 'dialog_dock.dart';
import 'viewport_window.dart';

/// A document-bound discussion, deliberately separate from CAD tool sessions.
/// The controller owns drafts and transcripts so closing the panel or changing
/// documents cannot move a message into another document's conversation.
class AiComposer extends StatefulWidget {
  final AppState app;
  const AiComposer({super.key, required this.app});

  @override
  State<AiComposer> createState() => _AiComposerState();
}

class _AiComposerState extends State<AiComposer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  String? _sessionId;
  String? _notice;

  /// Messages the user asked to see in full — a long answer and the detail
  /// behind a changes row are both collapsed until then.
  final _expanded = <String>{};
  bool _attaching = false;

  AiController get ai => widget.app.ai;
  AppL10n get t => L.of(context);

  @override
  void initState() {
    super.initState();
    ai.addListener(_changed);
    _syncDraft();
  }

  @override
  void didUpdateWidget(AiComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.ai != ai) {
      oldWidget.app.ai.removeListener(_changed);
      ai.addListener(_changed);
      _syncDraft();
    }
  }

  void _syncDraft() {
    final session = ai.currentSession;
    if (_sessionId != session.id) _notice = null;
    _sessionId = session.id;
    if (_text.text != session.draft) {
      _text.value = TextEditingValue(
        text: session.draft,
        selection: TextSelection.collapsed(offset: session.draft.length),
      );
    }
  }

  void _changed() {
    if (!mounted) return;
    final follow = !_scroll.hasClients ||
        _scroll.position.maxScrollExtent - _scroll.offset < 80;
    setState(_syncDraft);
    if (follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    ai.removeListener(_changed);
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The one place a user-visible assistant error is set.
  ///
  /// Traced here rather than at each throw site: everything the panel refuses
  /// — an attachment over the limit, a draft past 12 000 characters, a paste
  /// that could not be read, a session that changed under an await — arrives
  /// through this method, and until M443 a report saying "it just showed me
  /// an error" carried neither the message nor which action produced it.
  void _showError(Object error) {
    AiTrace.record('ui.error', sessionId: _sessionIdOrNull, data: {
      'type': '${error.runtimeType}',
      if (error is AiException) 'code': error.code,
      'shown': error.toString(),
    });
    if (mounted) setState(() => _notice = error.toString());
  }

  /// The open session's id, without the side effect of creating one. Only for
  /// the trace: a recorder that manufactures a conversation is not a recorder.
  String? get _sessionIdOrNull {
    try {
      return ai.sessions.isEmpty ? null : ai.currentSession.id;
    } catch (_) {
      return null;
    }
  }

  bool _run(VoidCallback action) {
    try {
      action();
      return true;
    } catch (error) {
      _showError(error);
      return false;
    }
  }

  void _draftChanged(String value) {
    if (!_run(() => ai.updateDraft(value))) _syncDraft();
  }

  Future<void> _files() async {
    if (_attaching) return;
    final target = ai.currentSession.id;
    setState(() => _attaching = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
      );
      if (picked == null || !mounted) return;
      if (target != ai.currentSession.id) {
        setState(() => _notice = t.aiAttachmentSessionChanged);
        return;
      }
      for (final file in picked.files) {
        // Bound the read before loading the bytes; the attachment model then
        // applies the provider-independent content/type limits as well.
        if (file.size > AiAttachment.maxFileBytes) {
          setState(() => _notice = t.aiErrorSize);
          continue;
        }
        if (file.bytes == null &&
            file.path != null &&
            await File(file.path!).length() > AiAttachment.maxFileBytes) {
          if (mounted) setState(() => _notice = t.aiErrorSize);
          continue;
        }
        final bytes = file.bytes ??
            (file.path == null ? null : await File(file.path!).readAsBytes());
        if (!mounted) return;
        if (target != ai.currentSession.id) {
          setState(() => _notice = t.aiAttachmentSessionChanged);
          return;
        }
        if (bytes == null) {
          setState(() => _notice = t.aiAttachmentUnreadable);
          continue;
        }
        ai.addAttachment(AiAttachment.fromBytes(name: file.name, bytes: bytes));
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  Future<void> _paste({bool textFallback = false}) async {
    final target = ai.currentSession.id;
    try {
      if (await ai.pasteImage()) return;
      if (!mounted) return;
      if (target != ai.currentSession.id) {
        setState(() => _notice = t.aiAttachmentSessionChanged);
        return;
      }
      if (textFallback) {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (!mounted || data?.text == null) return;
        if (target != ai.currentSession.id) {
          setState(() => _notice = t.aiAttachmentSessionChanged);
          return;
        }
        final selection = _text.selection;
        final start = selection.isValid ? selection.start : _text.text.length;
        final end = selection.isValid ? selection.end : _text.text.length;
        final paste = data!.text!;
        final updated = _text.text.replaceRange(start, end, paste);
        ai.updateDraft(updated);
        _text.value = TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(offset: start + paste.length),
        );
      } else {
        setState(() => _notice = t.aiClipboardEmpty);
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _send() async {
    setState(() => _notice = null);
    try {
      await ai.send();
    } catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ai.isOpen) return const SizedBox.shrink();
    final viewport = DialogDock.viewport(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final bottom = math.max(
      12.0 + keyboard,
      BottomTabBar.floatingHeightFor(widget.app) + 12.0,
    );
    final narrow = viewport.width < 620;
    final right = narrow ? 12.0 : DialogDock.rightChrome + 12.0;
    final width = math.min(440.0, math.max(0.0, viewport.width - right - 12));
    final height = math.min(
      660.0,
      math.max(0.0, viewport.height - bottom - 12),
    );
    if (width < 100 || height < 80) return const SizedBox.shrink();
    return Positioned(
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: ViewportWindow(
        child: Semantics(
          container: true,
          label: t.aiTitle,
          child: Material(
            color: Colors.transparent,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: GlassPanel.isSupported ? null : T.fly,
                borderRadius: BorderRadius.circular(24),
                border:
                    GlassPanel.isSupported ? null : Border.all(color: T.sep),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .14),
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  if (GlassPanel.isSupported)
                    const Positioned.fill(child: GlassPanel(cornerRadius: 24)),
                  if (height < 360)
                    SingleChildScrollView(child: _body(compact: true))
                  else
                    _body(compact: false),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body({required bool compact}) => Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 18, right: 6, top: 6),
            child: Row(
              children: [
                Icon(CupertinoIcons.sparkles, size: 20, color: T.accent),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(t.aiTitle, style: IosText.headline.on(T.text)),
                ),
                _icon(
                  CupertinoIcons.slider_horizontal_3,
                  t.aiSettings,
                  () => showAiSettings(context, ai),
                ),
                _icon(CupertinoIcons.xmark, t.close, ai.close),
              ],
            ),
          ),
          // M444 — ONE row of chrome, not three.
          //
          // The session name, the document and the context count each had a
          // row of their own, which is three lines of furniture above an
          // answer that is meant to be two sentences. They are all still here
          // and all still reachable; they are just one line now, and the
          // document name — the thing that says WHICH part this is about — is
          // the part that stayed legible.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 6, 6),
            child: Row(
              children: [
                // ONE Expanded holds everything that may shrink. Mixing a
                // Spacer with two Flexible children put the trailing buttons
                // outside the row at large text scales — 70 px over, which the
                // compact-panel test caught.
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Icon(_documentIcon(ai.document.kind),
                          size: 13, color: T.dim),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          ai.document.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: IosText.caption1.on(T.dim),
                        ),
                      ),
                      Flexible(
                        child: CupertinoButton(
                          padding: const EdgeInsets.only(left: 8),
                          alignment: Alignment.centerLeft,
                          onPressed: ai.isBusy ? null : _sessions,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  ai.currentSession.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: IosText.caption1.on(T.dim),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(CupertinoIcons.chevron_down,
                                  size: 10, color: T.dim),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Shrinkable as well: at the largest text scale this label
                // is wide enough to push the row over on its own.
                Flexible(
                  child: CupertinoButton(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: const Size(32, 30),
                    onPressed: _contextDocuments,
                    child: Text(
                      t.aiContextCount(
                          ai.currentSession.contextDocumentIds.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IosText.caption1.on(T.accent),
                    ),
                  ),
                ),
                _icon(CupertinoIcons.square_pencil, t.aiNewSession,
                    ai.isBusy ? null : ai.newSession),
              ],
            ),
          ),
          if (ai.currentSession.contextDocumentIds.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                for (final document in ai.documents.where((document) =>
                    ai.currentSession.contextDocumentIds.contains(document.id)))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: IosColors.quaternarySystemFill,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(document.name,
                              style: IosText.caption1.on(T.text)),
                        ),
                        _icon(
                            CupertinoIcons.xmark_circle_fill,
                            t.aiRemoveContext,
                            () => ai.setContextDocument(document.id, false)),
                      ]),
                    ),
                  ),
              ]),
            ),
          Divider(height: 1, color: T.panelSep),
          if (compact)
            SizedBox(height: 160, child: _transcript())
          else
            Expanded(child: _transcript()),
          if (_notice != null || ai.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _notice ?? ai.error!,
                  style: IosText.footnote.on(T.err),
                ),
              ),
            ),
          _input(),
        ],
      );

  Widget _transcript() {
    final messages = ai.currentSession.messages;
    if (messages.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.aiWelcomeTitle, style: IosText.title3.on(T.text)),
            const SizedBox(height: 10),
            Text(t.aiWelcomeBody, style: IosText.subheadline.on(T.dim)),
            const SizedBox(height: 18),
            // Says what this session can actually do RIGHT NOW. It used to
            // be a fixed sentence promising that CAD editing was not
            // available, which stopped being true in M441 and would have gone
            // on reassuring the user of the opposite of the truth.
            Text(ai.canEditModel ? t.aiCanModel : t.aiAdviceOnly,
                style: IosText.footnote.on(T.dim)),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: messages.length + (ai.isBusy ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) return _activityLine();
        final message = messages[index];
        // M441 — what the APP did, which is neither party's words.
        if (message.role == 'tool') return _changes(message);
        return message.role == 'user' ? _asked(message) : _answered(message);
      },
    );
  }

  /// What the assistant is doing, in a few words.
  ///
  /// M444 — the user asked to stop reading and to be told what is happening.
  /// Every word of this comes from the app's OWN work, never from the model: a
  /// status the model narrates arrives only when the model does, and is one
  /// more thing it can get wrong.
  Widget _activityLine() {
    final activity = ai.activity;
    final label = switch (activity.work) {
      AiWork.thinking => t.aiWorkThinking,
      AiWork.reading => t.aiWorkReading,
      AiWork.measuring => t.aiWorkMeasuring,
      AiWork.sketching => t.aiWorkSketching,
      AiWork.building => t.aiWorkBuilding,
      AiWork.editing => t.aiWorkEditing,
      AiWork.looking => t.aiWorkLooking,
      AiWork.noting => t.aiWorkNoting,
      AiWork.working => t.aiWorkWorking,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            const CupertinoActivityIndicator(radius: 7),
            const SizedBox(width: 10),
            Flexible(
              child: Text('$label…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IosText.subheadline.on(T.text)),
            ),
            if (activity.total > 1) ...[
              const SizedBox(width: 8),
              Text(t.aiStepOf(activity.step, activity.total),
                  style: IosText.caption1.on(T.dim)),
            ],
          ],
        ),
      ),
    );
  }

  /// The user's own turn: quiet, because they already know what they said.
  Widget _asked(AiMessage message) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.attachments.isNotEmpty)
              _attachments(message.attachments, editable: false),
            if (message.text.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: IosColors.quaternarySystemFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(message.text,
                    style: IosText.footnote.on(T.dim)),
              ),
          ],
        ),
      );

  /// A reply that is nothing but a question, which the prompt asks for when
  /// the assistant needs something. Shown on its own and larger: the user
  /// wanted the question and nothing around it.
  bool _isQuestion(String text) =>
      text.endsWith('?') && text.length <= 200 && !text.contains('\n');

  /// The assistant's turn. Two short sentences is what the prompt asks for;
  /// anything longer is clamped behind [t.aiMore] rather than made the user's
  /// problem.
  Widget _answered(AiMessage message) {
    final text = aiReplyWithoutActions(message.text);
    if (text.isEmpty) return const SizedBox.shrink();
    final question = _isQuestion(text);
    final expanded = _expanded.contains(message.id);
    final long = text.length > 220;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            text,
            maxLines: long && !expanded ? 4 : null,
            style: question
                ? IosText.title3.on(T.text)
                : IosText.subheadline.on(T.text),
          ),
          if (long)
            CupertinoButton(
              padding: const EdgeInsets.only(top: 4),
              alignment: Alignment.centerLeft,
              onPressed: () => setState(() => expanded
                  ? _expanded.remove(message.id)
                  : _expanded.add(message.id)),
              child: Text(expanded ? t.aiLess : t.aiMore,
                  style: IosText.footnote.on(T.accent)),
            ),
        ],
      ),
    );
  }

  /// What the app did, as ONE line.
  ///
  /// M444 — this used to be a row per action with its full reason, which is
  /// the right record and the wrong default: the user asked for the work to
  /// happen in the background, not to be reported to them step by step. The
  /// line says how many changes landed and whether anything failed; the detail
  /// is one tap away and still complete, because a failure the user cannot
  /// read is a failure they cannot act on.
  Widget _changes(AiMessage message) {
    final report = AiActionReport.decode(message.text);
    if (report == null) return const SizedBox.shrink();
    final blocked = switch (report.blocked) {
      'noPart' => t.aiChangesNoPart,
      'editsDisabled' => t.aiChangesDisabled,
      _ => null,
    };
    if (blocked != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(blocked, style: IosText.footnote.on(T.dim)),
      );
    }
    // A block of pure reads changed nothing and is not worth a line at all.
    final changed = report.outcomes
        .where((o) => !kAiReadOnlyOps.contains(o.op))
        .length;
    final failed = report.outcomes.where((o) => !o.ok).toList();
    if (changed == 0 && failed.isEmpty) return const SizedBox.shrink();
    final expanded = _expanded.contains(message.id);
    final ok = failed.isEmpty && !report.reverted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
            onPressed: () => setState(() => expanded
                ? _expanded.remove(message.id)
                : _expanded.add(message.id)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(ok ? CupertinoIcons.check_mark : CupertinoIcons.xmark,
                    size: 13,
                    color: ok
                        ? CupertinoColors.systemGreen
                        : CupertinoColors.systemRed),
                const SizedBox(width: 8),
                Text(
                  report.reverted
                      ? t.aiChangesReverted
                      : t.aiChangeCount(report.applied),
                  style: IosText.footnote.on(T.dim),
                ),
                const SizedBox(width: 6),
                Icon(
                    expanded
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 10,
                    color: T.dim),
              ],
            ),
          ),
          // A failure is shown WITHOUT being asked for. The collapse is for
          // noise, and a refusal the user never sees is not noise.
          if (!expanded)
            for (final o in failed.take(2))
              Padding(
                padding: const EdgeInsets.only(left: 21, top: 2),
                child: Text('${o.op} — ${o.error}',
                    style: IosText.caption1.on(T.err)),
              ),
          if (expanded)
            for (final o in report.outcomes)
              Padding(
                padding: const EdgeInsets.only(left: 21, top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                        o.ok
                            ? CupertinoIcons.check_mark
                            : CupertinoIcons.xmark,
                        size: 11,
                        color: o.ok
                            ? CupertinoColors.systemGreen
                            : CupertinoColors.systemRed),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SelectableText(
                        o.error == null ? o.op : '${o.op} — ${o.error}',
                        style: IosText.caption1.on(T.text),
                      ),
                    ),
                  ],
                ),
              ),
          if (report.applied > 0 && expanded)
            CupertinoButton(
              padding: const EdgeInsets.only(left: 21, top: 2),
              alignment: Alignment.centerLeft,
              onPressed: widget.app.canUndoPart
                  ? () => unawaited(widget.app.undoPart())
                  : null,
              child: Text(t.aiUndoChanges, style: IosText.footnote),
            ),
        ],
      ),
    );
  }

  Widget _input() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (ai.currentSession.attachments.isNotEmpty)
              _attachments(ai.currentSession.attachments, editable: true),
            Container(
              decoration: BoxDecoration(
                color: IosColors.quaternarySystemFill,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Shortcuts(
                    shortcuts: const {
                      SingleActivator(LogicalKeyboardKey.keyV, control: true):
                          _AiPasteIntent(),
                      SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                          _AiPasteIntent(),
                      SingleActivator(LogicalKeyboardKey.enter, control: true):
                          _AiSendIntent(),
                      SingleActivator(LogicalKeyboardKey.enter, meta: true):
                          _AiSendIntent(),
                    },
                    child: Actions(
                      actions: {
                        _AiPasteIntent: CallbackAction<_AiPasteIntent>(
                          onInvoke: (_) {
                            unawaited(_paste(textFallback: true));
                            return null;
                          },
                        ),
                        _AiSendIntent: CallbackAction<_AiSendIntent>(
                          onInvoke: (_) {
                            if (!ai.isBusy) unawaited(_send());
                            return null;
                          },
                        ),
                      },
                      child: TextField(
                        key: const ValueKey('ai-draft'),
                        controller: _text,
                        focusNode: _focus,
                        minLines: 2,
                        maxLines: 5,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: IosText.subheadline.on(T.text),
                        onChanged: _draftChanged,
                        contentInsertionConfiguration:
                            ContentInsertionConfiguration(
                          allowedMimeTypes: const [
                            'image/png',
                            'image/jpeg',
                            'image/webp',
                          ],
                          onContentInserted: (content) {
                            final bytes = content.data;
                            if (bytes == null) return;
                            try {
                              final ext = content.mimeType.split('/').last;
                              ai.addAttachment(
                                AiAttachment.fromBytes(
                                  name: 'image.$ext',
                                  bytes: bytes,
                                ),
                              );
                            } catch (error) {
                              _showError(error);
                            }
                          },
                        ),
                        decoration: InputDecoration(
                          hintText: t.aiPromptPlaceholder,
                          hintStyle: IosText.subheadline.on(T.dim),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.fromLTRB(14, 12, 14, 6),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 0, 6, 4),
                    child: Row(
                      children: [
                        _icon(
                          CupertinoIcons.paperclip,
                          t.aiAttachFiles,
                          _attaching ? null : _files,
                        ),
                        _icon(
                          CupertinoIcons.doc_on_clipboard,
                          t.aiPasteImage,
                          _paste,
                        ),
                        Expanded(
                          child: Text(
                            ai.providerLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: IosText.caption1.on(T.dim),
                          ),
                        ),
                        if (_attaching)
                          const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: CupertinoActivityIndicator(radius: 8),
                          ),
                        _icon(
                          ai.isBusy
                              ? CupertinoIcons.stop_circle_fill
                              : CupertinoIcons.arrow_up_circle_fill,
                          ai.isBusy ? t.aiStop : t.aiSend,
                          ai.isBusy
                              ? ai.cancel
                              : (_text.text.trim().isNotEmpty ||
                                      ai.currentSession.attachments.isNotEmpty)
                                  ? _send
                                  : null,
                          accent: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              ai.providerStatus,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: IosText.caption2.on(T.dim),
            ),
          ],
        ),
      );

  Widget _attachments(List<AiAttachment> files, {required bool editable}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final file in files)
              Container(
                constraints: const BoxConstraints(maxWidth: 240),
                decoration: BoxDecoration(
                  color: IosColors.quaternarySystemFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: file.isImage
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(
                                file.bytes,
                                cacheWidth: 128,
                                cacheHeight: 128,
                                width: 36,
                                height: 36,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  CupertinoIcons.photo,
                                  color: T.dim,
                                  size: 24,
                                ),
                              ),
                            )
                          : Icon(CupertinoIcons.doc, color: T.dim, size: 24),
                    ),
                    Flexible(
                      child: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: IosText.caption1.on(T.text),
                      ),
                    ),
                    if (editable)
                      _icon(
                        CupertinoIcons.xmark_circle_fill,
                        t.aiRemoveAttachment,
                        () => ai.removeAttachment(file.id),
                      )
                    else
                      const SizedBox(width: 10),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _icon(
    IconData icon,
    String label,
    VoidCallback? action, {
    bool accent = false,
  }) =>
      Tooltip(
        message: label,
        child: Semantics(
          label: label,
          button: true,
          enabled: action != null,
          child: CupertinoButton(
            padding: const EdgeInsets.all(10),
            minimumSize: const Size(44, 44),
            onPressed: action == null ? null : () => _run(action),
            child: Icon(
              icon,
              size: accent ? 29 : 20,
              color: action == null
                  ? IosColors.quaternaryLabel
                  : accent
                      ? T.accent
                      : T.dim,
            ),
          ),
        ),
      );

  Future<void> _sessions() async {
    await _sheet(
      t.aiSessions,
      (sheetContext) => ListenableBuilder(
        listenable: ai,
        builder: (_, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(CupertinoIcons.plus),
              title: Text(t.aiNewSession),
              onTap: () {
                if (_run(ai.newSession)) Navigator.pop(sheetContext);
              },
            ),
            for (final session in ai.sessions)
              ListTile(
                leading: Icon(
                  session.id == ai.currentSession.id
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.chat_bubble,
                ),
                title: Text(
                  session.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  if (_run(() => ai.selectSession(session.id))) {
                    Navigator.pop(sheetContext);
                  }
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _icon(CupertinoIcons.pencil, t.aiRenameSession, () {
                      Navigator.pop(sheetContext);
                      _rename(session);
                    }),
                    _icon(CupertinoIcons.trash, t.aiDeleteSession, () {
                      Navigator.pop(sheetContext);
                      _delete(session);
                    }),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(CupertinoIcons.arrow_right_square),
              title: Text(t.aiContinueElsewhere),
              onTap: () {
                Navigator.pop(sheetContext);
                _continueElsewhere();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(AiSession session) async {
    final name = TextEditingController(text: session.name);
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(t.aiRenameSession),
        content: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: CupertinoTextField(
            controller: name,
            autofocus: true,
            maxLength: 80,
            placeholder: t.aiSessionName,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(t.cancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              if (name.text.trim().isNotEmpty)
                Navigator.pop(context, name.text.trim());
            },
            child: Text(t.aiSettingsSave),
          ),
        ],
      ),
    );
    // The route animates out before disposing its text field.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    if (result != null && mounted) ai.renameSession(session.id, result);
  }

  Future<void> _delete(AiSession session) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(t.aiDeleteSession),
        content: Text(t.aiDeleteSessionMessage(session.name)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) ai.deleteSession(session.id);
  }

  Future<void> _contextDocuments() => _sheet(
        t.aiContext,
        (sheetContext) => ListenableBuilder(
          listenable: ai,
          builder: (_, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  t.aiContextExplanation,
                  style: IosText.footnote.on(T.dim),
                ),
              ),
              for (final document in ai.documents)
                CheckboxListTile.adaptive(
                  title: Text(document.name),
                  subtitle: Text(_kindLabel(document.kind)),
                  value: document.id == ai.document.id ||
                      ai.currentSession.contextDocumentIds
                          .contains(document.id),
                  onChanged: document.id == ai.document.id
                      ? null
                      : (selected) => _run(() => ai.setContextDocument(
                          document.id, selected ?? false)),
                ),
            ],
          ),
        ),
      );

  Future<void> _continueElsewhere() => _sheet(
        t.aiContinueElsewhere,
        (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                t.aiContinueExplanation,
                style: IosText.footnote.on(T.dim),
              ),
            ),
            for (final document in ai.documents.where(
              (document) => document.id != ai.document.id,
            ))
              ListTile(
                leading: Icon(_documentIcon(document.kind)),
                title: Text(document.name),
                subtitle: Text(_kindLabel(document.kind)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  try {
                    await ai.continueInDocument(document.id);
                  } catch (error) {
                    _showError(error);
                  }
                },
              ),
          ],
        ),
      );

  Future<void> _sheet(String title, Widget Function(BuildContext) body) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: T.fly,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .75,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 6, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(title, style: IosText.headline.on(T.text)),
                      ),
                      _icon(
                        CupertinoIcons.xmark,
                        t.close,
                        () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                ),
                body(sheetContext),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _kindLabel(String kind) => switch (kind) {
        'part' => t.aiPart,
        'sketch' => t.aiSketch,
        'assembly' => t.aiAssembly,
        _ => t.aiWorkspace,
      };

  static IconData _documentIcon(String kind) => switch (kind) {
        'part' => CupertinoIcons.cube,
        'sketch' => CupertinoIcons.pencil_outline,
        'assembly' => CupertinoIcons.square_stack_3d_up,
        _ => CupertinoIcons.square_grid_2x2,
      };
}

class _AiPasteIntent extends Intent {
  const _AiPasteIntent();
}

class _AiSendIntent extends Intent {
  const _AiSendIntent();
}

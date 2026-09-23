import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show showDialog;

import '../ai/ai_controller.dart';
import '../ai/ai_backend.dart' show kDeepSeekDefaultModel;
import '../ios_design.dart';
import '../l10n/l.dart';
import '../desktop_radius.dart';

Future<void> showAiSettings(BuildContext context, AiController controller) =>
    showDialog<void>(
        context: context, builder: (_) => _AiSettings(controller: controller));

class _AiSettings extends StatefulWidget {
  const _AiSettings({required this.controller});
  final AiController controller;
  @override
  State<_AiSettings> createState() => _AiSettingsState();
}

class _AiSettingsState extends State<_AiSettings> {
  late AiProvider _provider = widget.controller.preferences.provider;
  late final _model =
      TextEditingController(text: widget.controller.preferences.model);
  final _key = TextEditingController();
  late bool _allowEdits = widget.controller.preferences.allowEdits;
  bool _hasKey = false;
  bool _saving = false;
  String? _error;
  int _probe = 0;
  AppL10n get t => L.of(context);
  static const _defaults = {
    AiProvider.gemini: 'gemini-3.8-flash',
    AiProvider.anthropic: 'claude-opus-5',
    AiProvider.deepseek: kDeepSeekDefaultModel
  };

  @override
  void initState() {
    super.initState();
    _checkKey();
  }

  Future<void> _checkKey() async {
    final probe = ++_probe;
    try {
      final exists = await widget.controller.hasKey(_provider);
      if (mounted && probe == _probe) setState(() => _hasKey = exists);
    } catch (error) {
      if (mounted && probe == _probe) setState(() => _error = error.toString());
    }
  }

  void _select(AiProvider? provider) {
    if (provider == null || provider == _provider) return;
    setState(() {
      _provider = provider;
      _key.clear();
      _hasKey = false;
      _error = null;
      _model.text = provider == widget.controller.preferences.provider
          ? widget.controller.preferences.model
          : _defaults[provider] ?? '';
    });
    _checkKey();
  }

  Future<void> _save({bool removeKey = false}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.configure(
          provider: _provider,
          model: _model.text,
          key: _key.text,
          removeKey: removeKey,
          allowEdits: _allowEdits);
      _key.clear();
      if (!mounted) return;
      if (removeKey) {
        await _checkKey();
      } else {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteHistory() async {
    final confirmed = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
              title: Text(t.aiSettingsDeleteHistory),
              content: Text(t.aiSettingsDeleteHistoryConfirm),
              actions: [
                CupertinoDialogAction(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(t.cancel)),
                CupertinoDialogAction(
                    isDestructiveAction: true,
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(t.aiSettingsDeleteHistory)),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.controller.deleteAllConversations();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _key.clear();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || widget.controller.anyRequestBusy;
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: MediaQuery.sizeOf(context).height * .88),
              child: CupertinoPopupSurface(
                  child: SafeArea(
                      top: false,
                      bottom: false,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(children: [
                                Expanded(
                                    child: Text(t.aiSettingsTitle,
                                        style: IosText.title2)),
                                CupertinoButton(
                                    padding: const EdgeInsets.all(8),
                                    onPressed: _saving
                                        ? null
                                        : () => Navigator.pop(context),
                                    child: Text(t.done))
                              ]),
                              const SizedBox(height: 12),
                              Text(t.aiSettingsProvider,
                                  style: IosText.subheadline),
                              const SizedBox(height: 8),
                              // Four providers do not fit across a phone as a
                              // segmented control, and the one that overflows
                              // is whichever the user happens to want. A wrap
                              // of buttons keeps every provider reachable at
                              // any width.
                              Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final entry in {
                                      AiProvider.apple: t.aiProviderApple,
                                      AiProvider.gemini: t.aiProviderGemini,
                                      AiProvider.anthropic: t.aiProviderClaude,
                                      AiProvider.deepseek: t.aiProviderDeepSeek,
                                    }.entries)
                                      CupertinoButton(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 8),
                                          borderRadius:
                                              BorderRadius.circular(desktopRadius(9)),
                                          color: entry.key == _provider
                                              ? CupertinoColors.activeBlue
                                              : CupertinoColors
                                                  .tertiarySystemFill
                                                  .resolveFrom(context),
                                          onPressed: busy
                                              ? null
                                              : () => _select(entry.key),
                                          child: Text(entry.value,
                                              style: TextStyle(
                                                  color: entry.key == _provider
                                                      ? CupertinoColors.white
                                                      : CupertinoColors.label
                                                          .resolveFrom(
                                                              context))))
                                  ]),
                              const SizedBox(height: 20),
                              if (_provider == AiProvider.apple) ...[
                                Text(t.aiSettingsAppleInfo,
                                    style: IosText.body),
                                const SizedBox(height: 12),
                                Text(widget.controller.providerStatus,
                                    style: IosText.footnote),
                              ] else ...[
                                Text(t.aiSettingsModel,
                                    style: IosText.subheadline),
                                const SizedBox(height: 8),
                                CupertinoTextField(
                                    controller: _model,
                                    enabled: !busy,
                                    placeholder: t.aiSettingsModelHint,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    maxLength: 100,
                                    padding: const EdgeInsets.all(12)),
                                const SizedBox(height: 16),
                                Text(t.aiSettingsKey,
                                    style: IosText.subheadline),
                                const SizedBox(height: 8),
                                CupertinoTextField(
                                    controller: _key,
                                    enabled: !busy,
                                    placeholder: t.aiSettingsKeyHint,
                                    obscureText: true,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    smartDashesType: SmartDashesType.disabled,
                                    smartQuotesType: SmartQuotesType.disabled,
                                    maxLength: 4096,
                                    padding: const EdgeInsets.all(12)),
                                const SizedBox(height: 8),
                                Text(
                                    _hasKey
                                        ? t.aiSettingsKeySaved
                                        : t.aiSettingsNoKey,
                                    style: IosText.footnote),
                                if (_hasKey)
                                  CupertinoButton(
                                      onPressed: busy
                                          ? null
                                          : () => _save(removeKey: true),
                                      child: Text(t.aiSettingsRemoveKey)),
                              ],
                              const SizedBox(height: 20),
                              Row(children: [
                                Expanded(
                                    child: Text(t.aiSettingsAllowEdits,
                                        style: IosText.subheadline)),
                                CupertinoSwitch(
                                    value: _allowEdits,
                                    onChanged: busy
                                        ? null
                                        : (v) =>
                                            setState(() => _allowEdits = v)),
                              ]),
                              const SizedBox(height: 4),
                              Text(t.aiSettingsAllowEditsInfo,
                                  style: IosText.footnote),
                              const SizedBox(height: 16),
                              Text(t.aiSettingsPrivacy,
                                  style: IosText.footnote),
                              if (_error != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Semantics(
                                        liveRegion: true,
                                        child: Text(_error!,
                                            style: const TextStyle(
                                                color: CupertinoColors
                                                    .systemRed)))),
                              const SizedBox(height: 20),
                              CupertinoButton.filled(
                                  onPressed: busy ? null : _save,
                                  child: _saving
                                      ? const CupertinoActivityIndicator()
                                      : Text(t.aiSettingsSave)),
                              CupertinoButton(
                                  onPressed: busy ? null : _deleteHistory,
                                  child: Text(t.aiSettingsDeleteHistory,
                                      style: const TextStyle(
                                          color: CupertinoColors.systemRed))),
                            ]),
                      ))),
            )));
  }
}

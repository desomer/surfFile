/// Carte interactive de clarification et collecte des réponses pour le chat Vibe.
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../ai/vibe_ask_user.dart';
import '../../../ai/vibe_speech_to_text.dart';

/// Carte interactive affichée quand Vibe demande des précisions.
class VibeAskUserCard extends StatefulWidget {
  /// Crée une carte de clarification liée à [request].
  const VibeAskUserCard({
    required this.request,
    required this.sending,
    required this.onSubmit,
    required this.onSkip,
    this.onAskMore,
    this.speechTranscriber,
    this.onSpeechError,
    super.key,
  });

  /// Questions et choix proposés par Vibe.
  final VibeAskUserRequest request;

  /// Désactive les contrôles pendant la génération.
  final bool sending;

  /// Transmet les réponses validées.
  final ValueChanged<Map<String, Object?>> onSubmit;

  /// Transmet la demande de poursuivre avec les valeurs par défaut.
  final VoidCallback onSkip;

  /// Transmet les réponses actuelles en demandant 2 à 4 questions complémentaires avant de générer.
  final ValueChanged<Map<String, Object?>>? onAskMore;

  /// Service optionnel de dictée vocale (Speech-to-Text) pour les champs texte.
  final VibeSpeechTranscriber? speechTranscriber;

  /// Callback optionnel notifié lorsqu'une erreur de microphone/transcription survient.
  final ValueChanged<String>? onSpeechError;

  @override
  State<VibeAskUserCard> createState() => _VibeAskUserCardState();
}

class _VibeAskUserCardState extends State<VibeAskUserCard> {
  final Map<String, String> _singleSelected = <String, String>{};
  final Map<String, Set<String>> _multiSelected = <String, Set<String>>{};
  final Map<String, bool> _boolValues = <String, bool>{};
  final Map<String, bool> _otherSelected = <String, bool>{};
  final Map<String, TextEditingController> _otherControllers =
      <String, TextEditingController>{};
  final Map<String, TextEditingController> _textControllers =
      <String, TextEditingController>{};
  String? _activeSpeechFieldKey;
  VibeSpeechSession? _activeSpeechSession;
  VibeSpeechState? _activeSpeechState;
  VoidCallback? _activeSpeechListener;

  @override
  void initState() {
    super.initState();
    _initFields();
  }

  @override
  void didUpdateWidget(VibeAskUserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request) {
      _disposeControllers();
      _singleSelected.clear();
      _multiSelected.clear();
      _boolValues.clear();
      _otherSelected.clear();
      _initFields();
    }
  }

  void _initFields() {
    for (final q in widget.request.questions) {
      switch (q.type) {
        case VibeAskUserFieldType.single:
          final initial = q.effectiveInitialAnswer() as String;
          if (q.options.contains(initial)) {
            _singleSelected[q.id] = initial;
            _otherSelected[q.id] = false;
            if (q.allowOther) {
              _otherControllers[q.id] = TextEditingController();
            }
          } else if (initial.isNotEmpty && q.allowOther) {
            _singleSelected[q.id] = q.options.isNotEmpty ? q.options.first : '';
            _otherSelected[q.id] = true;
            _otherControllers[q.id] = TextEditingController(text: initial);
          } else {
            _singleSelected[q.id] = q.options.isNotEmpty ? q.options.first : '';
            _otherSelected[q.id] = false;
            if (q.allowOther) {
              _otherControllers[q.id] = TextEditingController();
            }
          }
        case VibeAskUserFieldType.multi:
          final initialList = q.effectiveInitialAnswer() as List<String>;
          final selectedSet = <String>{
            for (final item in initialList)
              if (q.options.contains(item)) item,
          };
          final customItems = <String>[
            for (final item in initialList)
              if (!q.options.contains(item)) item,
          ];
          _multiSelected[q.id] = selectedSet;
          if (q.allowOther) {
            final hasCustom = customItems.isNotEmpty;
            _otherSelected[q.id] = hasCustom;
            _otherControllers[q.id] = TextEditingController(
              text: hasCustom ? customItems.join(', ') : '',
            );
          } else {
            _otherSelected[q.id] = false;
          }
        case VibeAskUserFieldType.boolean:
          _boolValues[q.id] = q.effectiveInitialAnswer() as bool;
        case VibeAskUserFieldType.text:
          _textControllers[q.id] = TextEditingController(
            text: q.effectiveInitialAnswer() as String,
          );
      }
    }
  }

  void _disposeControllers() {
    for (final controller in _otherControllers.values) {
      controller.dispose();
    }
    _otherControllers.clear();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers.clear();
  }

  @override
  void dispose() {
    _cancelActiveSpeech();
    _disposeControllers();
    super.dispose();
  }

  void _detachActiveSpeechListener() {
    final session = _activeSpeechSession;
    final listener = _activeSpeechListener;
    if (session != null && listener != null) {
      session.state.removeListener(listener);
    }
    _activeSpeechListener = null;
  }

  void _cancelActiveSpeech() {
    _detachActiveSpeechListener();
    final session = _activeSpeechSession;
    _activeSpeechSession = null;
    _activeSpeechFieldKey = null;
    _activeSpeechState = null;
    if (session != null) {
      unawaited(session.cancel());
    }
  }

  Future<void> _toggleFieldSpeech(
    String fieldKey,
    TextEditingController? controller,
  ) async {
    if (widget.sending || controller == null) return;
    final existing = _activeSpeechSession;
    if (existing != null) {
      if (_activeSpeechFieldKey == fieldKey) {
        if (_activeSpeechState == VibeSpeechState.listening) {
          await existing.stop();
        }
        return;
      }
      _cancelActiveSpeech();
    }

    try {
      final transcriber =
          widget.speechTranscriber ?? VibeSpeechTranscriber.instance;
      final session = await transcriber.startListening();
      if (!mounted) {
        await session.cancel();
        return;
      }
      void onStateChanged() {
        if (!mounted || !identical(_activeSpeechSession, session)) return;
        setState(() => _activeSpeechState = session.state.value);
      }

      _activeSpeechListener = onStateChanged;
      session.state.addListener(onStateChanged);
      setState(() {
        _activeSpeechFieldKey = fieldKey;
        _activeSpeechSession = session;
        _activeSpeechState = session.state.value;
      });

      final transcript = await session.result;
      if (!mounted || !identical(_activeSpeechSession, session)) return;
      _detachActiveSpeechListener();
      setState(() {
        _activeSpeechSession = null;
        _activeSpeechFieldKey = null;
        _activeSpeechState = null;
      });
      if (transcript.trim().isNotEmpty) {
        VibeSpeechTextInsertion.insertTranscript(controller, transcript);
      }
    } on FormatException catch (error) {
      if (!mounted) return;
      _detachActiveSpeechListener();
      setState(() {
        _activeSpeechSession = null;
        _activeSpeechFieldKey = null;
        _activeSpeechState = null;
      });
      widget.onSpeechError?.call(error.message);
    } catch (error) {
      if (!mounted) return;
      _detachActiveSpeechListener();
      setState(() {
        _activeSpeechSession = null;
        _activeSpeechFieldKey = null;
        _activeSpeechState = null;
      });
      widget.onSpeechError?.call('Dictée vocale impossible : $error');
    }
  }

  Widget _buildFieldMicSuffix({
    required BuildContext context,
    required Key buttonKey,
    required String fieldKey,
    required TextEditingController? controller,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isActive =
        _activeSpeechSession != null && _activeSpeechFieldKey == fieldKey;
    final state = isActive ? _activeSpeechState : null;
    final isListening = state == VibeSpeechState.listening;
    final isTranscribing = state == VibeSpeechState.transcribing;

    return IconButton(
      key: buttonKey,
      visualDensity: VisualDensity.compact,
      iconSize: 17,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      tooltip: isListening
          ? 'Arrêter la dictée (arrêt auto après silence)'
          : isTranscribing
          ? 'Transcription vocale en cours…'
          : 'Dicter au microphone',
      onPressed: widget.sending || isTranscribing
          ? null
          : () => _toggleFieldSpeech(fieldKey, controller),
      icon: isTranscribing
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              isListening
                  ? Icons.stop_circle_outlined
                  : Icons.mic_none_outlined,
              size: 17,
              color: isListening ? scheme.error : scheme.onSurfaceVariant,
            ),
    );
  }

  Map<String, Object?> _collectAnswers() {
    final answers = <String, Object?>{};
    for (final q in widget.request.questions) {
      switch (q.type) {
        case VibeAskUserFieldType.single:
          if (_otherSelected[q.id] ?? false) {
            final custom = _otherControllers[q.id]?.text.trim() ?? '';
            answers[q.id] = custom.isNotEmpty
                ? custom
                : q.effectiveInitialAnswer();
          } else {
            final chosen = _singleSelected[q.id] ?? '';
            answers[q.id] = chosen.isNotEmpty
                ? chosen
                : q.effectiveInitialAnswer();
          }
        case VibeAskUserFieldType.multi:
          final selectedSet = _multiSelected[q.id] ?? const <String>{};
          final items = <String>[
            for (final opt in q.options)
              if (selectedSet.contains(opt)) opt,
          ];
          if (_otherSelected[q.id] ?? false) {
            final custom = _otherControllers[q.id]?.text.trim() ?? '';
            if (custom.isNotEmpty && !items.contains(custom)) {
              items.add(custom);
            }
          }
          answers[q.id] = List<String>.unmodifiable(items);
        case VibeAskUserFieldType.boolean:
          answers[q.id] =
              _boolValues[q.id] ?? (q.effectiveInitialAnswer() as bool);
        case VibeAskUserFieldType.text:
          answers[q.id] = (_textControllers[q.id]?.text ?? '').trim();
      }
    }
    return answers;
  }

  void _handleSubmit() {
    if (widget.sending) return;
    widget.onSubmit(_collectAnswers());
  }

  void _handleAskMore() {
    if (widget.sending || widget.onAskMore == null) return;
    widget.onAskMore!(_collectAnswers());
  }

  Widget _buildQuestionControl(BuildContext context, VibeAskUserQuestion q) {
    final scheme = Theme.of(context).colorScheme;
    switch (q.type) {
      case VibeAskUserFieldType.single:
        final isOther = _otherSelected[q.id] ?? false;
        final currentOpt = _singleSelected[q.id];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (optIndex, opt) in q.options.indexed)
                  ChoiceChip(
                    key: ValueKey('vibe-ask-option-${q.id}-$optIndex'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(
                      opt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: !isOther && currentOpt == opt,
                    onSelected: widget.sending
                        ? null
                        : (_) => setState(() {
                            _otherSelected[q.id] = false;
                            _singleSelected[q.id] = opt;
                          }),
                  ),
                if (q.allowOther)
                  ChoiceChip(
                    key: ValueKey('vibe-ask-other-chip-${q.id}'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: const Text('Autre…', style: TextStyle(fontSize: 12)),
                    selected: isOther,
                    onSelected: widget.sending
                        ? null
                        : (selected) => setState(() {
                            _otherSelected[q.id] = selected;
                          }),
                  ),
              ],
            ),
            if (q.allowOther && isOther) ...[
              const SizedBox(height: 6),
              TextField(
                key: ValueKey('vibe-ask-other-input-${q.id}'),
                controller: _otherControllers[q.id],
                enabled: !widget.sending,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Préciser…',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  suffixIcon: _buildFieldMicSuffix(
                    context: context,
                    buttonKey: ValueKey('vibe-ask-other-mic-${q.id}'),
                    fieldKey: 'other:${q.id}',
                    controller: _otherControllers[q.id],
                  ),
                ),
              ),
            ],
          ],
        );
      case VibeAskUserFieldType.multi:
        final selectedSet = _multiSelected.putIfAbsent(q.id, () => <String>{});
        final isOther = _otherSelected[q.id] ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (optIndex, opt) in q.options.indexed)
                  FilterChip(
                    key: ValueKey('vibe-ask-option-${q.id}-$optIndex'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(
                      opt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: selectedSet.contains(opt),
                    onSelected: widget.sending
                        ? null
                        : (selected) => setState(() {
                            if (selected) {
                              selectedSet.add(opt);
                            } else {
                              selectedSet.remove(opt);
                            }
                          }),
                  ),
                if (q.allowOther)
                  FilterChip(
                    key: ValueKey('vibe-ask-other-chip-${q.id}'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: const Text('Autre…', style: TextStyle(fontSize: 12)),
                    selected: isOther,
                    onSelected: widget.sending
                        ? null
                        : (selected) => setState(() {
                            _otherSelected[q.id] = selected;
                          }),
                  ),
              ],
            ),
            if (q.allowOther && isOther) ...[
              const SizedBox(height: 6),
              TextField(
                key: ValueKey('vibe-ask-other-input-${q.id}'),
                controller: _otherControllers[q.id],
                enabled: !widget.sending,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Autre choix…',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  suffixIcon: _buildFieldMicSuffix(
                    context: context,
                    buttonKey: ValueKey('vibe-ask-other-mic-${q.id}'),
                    fieldKey: 'other:${q.id}',
                    controller: _otherControllers[q.id],
                  ),
                ),
              ),
            ],
          ],
        );
      case VibeAskUserFieldType.boolean:
        final value = _boolValues[q.id] ?? (q.effectiveInitialAnswer() as bool);
        return Row(
          children: [
            Expanded(
              child: Text(
                value ? 'Oui' : 'Non',
                style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
              ),
            ),
            Switch(
              key: ValueKey('vibe-ask-switch-${q.id}'),
              value: value,
              onChanged: widget.sending
                  ? null
                  : (next) => setState(() => _boolValues[q.id] = next),
            ),
          ],
        );
      case VibeAskUserFieldType.text:
        return TextField(
          key: ValueKey('vibe-ask-text-${q.id}'),
          controller: _textControllers[q.id],
          enabled: !widget.sending,
          style: const TextStyle(fontSize: 12.5),
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            suffixIcon: _buildFieldMicSuffix(
              context: context,
              buttonKey: ValueKey('vibe-ask-text-mic-${q.id}'),
              fieldKey: 'text:${q.id}',
              controller: _textControllers[q.id],
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (qIndex, q) in widget.request.questions.indexed) ...[
            if (qIndex > 0) const SizedBox(height: 10),
            Text(
              q.title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            if (q.description != null && q.description!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                q.description!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 6),
            _buildQuestionControl(context, q),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Tooltip(
                  message: 'Générer avec les valeurs par défaut',
                  child: TextButton(
                    key: const ValueKey('vibe-ask-user-skip'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: widget.sending ? null : widget.onSkip,
                    child: const Text('Passer'),
                  ),
                ),
                if (widget.onAskMore != null)
                  Tooltip(
                    message:
                        'Valider ces réponses et poser 2 à 4 questions complémentaires avant de générer',
                    child: OutlinedButton.icon(
                      key: const ValueKey('vibe-ask-user-more'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: widget.sending ? null : _handleAskMore,
                      icon: const Icon(Icons.add_comment_outlined, size: 15),
                      label: const Text('+ de questions'),
                    ),
                  ),
                FilledButton.icon(
                  key: const ValueKey('vibe-ask-user-submit'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: widget.sending ? null : _handleSubmit,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Générer'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

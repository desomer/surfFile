/// Carte interactive de clarification et collecte des réponses pour le chat Vibe.
library;

import 'package:material_ui/material_ui.dart';

import '../../../ai/vibe_ask_user.dart';

/// Carte interactive affichée quand Vibe demande des précisions.
class VibeAskUserCard extends StatefulWidget {
  /// Crée une carte de clarification liée à [request].
  const VibeAskUserCard({
    required this.request,
    required this.sending,
    required this.onSubmit,
    required this.onSkip,
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
    _disposeControllers();
    super.dispose();
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
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Préciser…',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
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
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Autre choix…',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
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
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

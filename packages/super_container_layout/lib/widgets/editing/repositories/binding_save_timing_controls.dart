/// Contrôles réutilisables de réglage du délai d'enregistrement des saisies liées ([BindingSaveTimingControls]).
///
/// Permet de configurer la temporisation anti-rebond (`100..2000 ms`, pas de `50 ms`)
/// via un curseur [EditorHistorySlider] et un badge numérique [EditorNumberField],
/// ainsi que le basculement vers l'enregistrement uniquement à la perte de focus.
library;

import 'package:material_ui/material_ui.dart';

import '../../../theme/appearance.dart';
import '../components/shared/editor_number_field.dart';
import '../history/editor_history.dart';

/// Panneau de réglages du délai anti-rebond et du mode « perte de focus »
/// pour les liaisons texte bidirectionnelles (`JsonTextControllerBinding`).
class BindingSaveTimingControls extends StatelessWidget {
  /// Crée les contrôles de temporisation d'enregistrement.
  const BindingSaveTimingControls({
    required this.debounceMs,
    required this.saveOnBlurOnly,
    required this.onDebounceMsChanged,
    required this.onSaveOnBlurOnlyChanged,
    this.onReset,
    this.keyPrefix = 'binding-save-timing',
    super.key,
  });

  /// Délai anti-rebond courant en millisecondes (`100..2000`).
  final int debounceMs;

  /// Indique si l'enregistrement est différé jusqu'à la perte de focus.
  final bool saveOnBlurOnly;

  /// Callback invoqué lors de la modification du délai (en ms).
  final ValueChanged<int> onDebounceMsChanged;

  /// Callback invoqué lors du changement de mode « perte de focus ».
  final ValueChanged<bool> onSaveOnBlurOnlyChanged;

  /// Callback optionnel de réinitialisation vers les valeurs par défaut (`350 ms`, `false`).
  final VoidCallback? onReset;

  /// Préfixe des [ValueKey] exposées pour les tests et l'accessibilité.
  final String keyPrefix;

  static const int _divisions =
      (Appearance.maxBindingDebounceMs - Appearance.minBindingDebounceMs) ~/
      Appearance.bindingDebounceStepMs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clamped = debounceMs.clamp(
      Appearance.minBindingDebounceMs,
      Appearance.maxBindingDebounceMs,
    );
    void handleValueChanged(double next) => onDebounceMsChanged(
      next.round().clamp(
        Appearance.minBindingDebounceMs,
        Appearance.maxBindingDebounceMs,
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: ValueKey('$keyPrefix-blur-only'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Enregistrer uniquement à la perte de focus'),
          subtitle: const Text(
            'Désactive la sauvegarde automatique pendant la frappe et '
            'enregistre dès que le champ perd le focus.',
          ),
          value: saveOnBlurOnly,
          onChanged: onSaveOnBlurOnlyChanged,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Délai après la dernière frappe',
                style: TextStyle(
                  fontSize: 12,
                  color: saveOnBlurOnly
                      ? scheme.onSurface.withValues(alpha: 0.38)
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
            EditorNumberField(
              key: ValueKey('$keyPrefix-number'),
              value: clamped.toDouble(),
              min: Appearance.minBindingDebounceMs.toDouble(),
              max: Appearance.maxBindingDebounceMs.toDouble(),
              integer: true,
              unit: 'ms',
              label: 'Délai après la dernière frappe',
              onChanged: saveOnBlurOnly ? null : handleValueChanged,
            ),
          ],
        ),
        EditorHistorySlider(
          sliderKey: ValueKey('$keyPrefix-slider'),
          showValue: false,
          integer: true,
          divisions: _divisions,
          min: Appearance.minBindingDebounceMs.toDouble(),
          max: Appearance.maxBindingDebounceMs.toDouble(),
          value: clamped.toDouble(),
          onChanged: saveOnBlurOnly ? null : handleValueChanged,
        ),
        if (onReset != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: ValueKey('$keyPrefix-reset'),
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text(
                'Par défaut (${Appearance.defaultBindingDebounceMs} ms)',
              ),
            ),
          ),
      ],
    );
  }
}

/// Contenu de la boîte de dialogue de réglage global du délai d'enregistrement.
class BindingSaveTimingDialogContent extends StatelessWidget {
  /// Crée le panneau de dialogue pour [appearance] et [onClose].
  const BindingSaveTimingDialogContent({
    required this.appearance,
    required this.onClose,
    super.key,
  });

  /// Contrôleur global d'apparence mis à jour en direct.
  final ValueNotifier<Appearance> appearance;

  /// Callback de fermeture du panneau.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('binding-save-timing-dialog'),
    type: MaterialType.card,
    elevation: 8,
    borderRadius: BorderRadius.circular(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: ValueListenableBuilder<Appearance>(
        valueListenable: appearance,
        builder: (context, current, _) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Enregistrement des saisies',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('binding-save-timing-close'),
                    tooltip: 'Fermer',
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              BindingSaveTimingControls(
                keyPrefix: 'global-save-timing',
                debounceMs: current.bindingDebounceMs,
                saveOnBlurOnly: current.bindingSaveOnBlurOnly,
                onDebounceMsChanged: (ms) => appearance.value = current
                    .copyWith(bindingDebounceMs: ms),
                onSaveOnBlurOnlyChanged: (blurOnly) => appearance.value =
                    current.copyWith(bindingSaveOnBlurOnly: blurOnly),
                onReset: () => appearance.value = current.copyWith(
                  bindingDebounceMs: Appearance.defaultBindingDebounceMs,
                  bindingSaveOnBlurOnly: false,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Ouvre la boîte de dialogue globale du mode édition permettant de régler
/// le délai anti-rebond et le mode « perte de focus » sur [appearance].
Future<void> showBindingSaveTimingDialog(
  BuildContext context,
  ValueNotifier<Appearance> appearance,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    child: BindingSaveTimingDialogContent(
      appearance: appearance,
      onClose: () => Navigator.of(dialogContext).pop(),
    ),
  ),
);

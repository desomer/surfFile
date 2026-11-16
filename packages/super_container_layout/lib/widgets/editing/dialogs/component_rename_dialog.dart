/// Boîte de dialogue « Renommer le composant » ([ComponentRenameDialog]).
///
/// Permet de modifier le nom d'instance d'un composant et, lorsque l'instance
/// possède un identifiant stable, de déclarer son usage ([ComponentUsage]) :
/// texte d'explication traduit (avec clé de traduction), données dynamiques
/// ou statiques, saisie, action, structure, décoration ou retour d'état.
library;

import 'package:material_ui/material_ui.dart';

import '../../../models/component_usage.dart';
import 'editor_dialog.dart';

/// Résultat validé de [ComponentRenameDialog].
@immutable
class ComponentRenameResult {
  /// Crée un résultat avec le nom [label] (déjà nettoyé) et l'[usage] choisi.
  const ComponentRenameResult({required this.label, this.usage});

  /// Nouveau nom d'instance, sans espaces superflus.
  final String label;

  /// Usage déclaré, ou `null` lorsqu'il n'est pas défini.
  final ComponentUsage? usage;
}

/// Affiche la boîte de dialogue de renommage d'un composant.
///
/// Le champ d'usage n'est proposé que si [showUsage] est vrai.
Future<ComponentRenameResult?> showComponentRenameDialog({
  required BuildContext context,
  required String initialLabel,
  ComponentUsage? initialUsage,
  bool showUsage = true,
  BuildContext? target,
}) => showEditorDialog<ComponentRenameResult>(
  context: context,
  target: target ?? context,
  builder: (_) => ComponentRenameDialog(
    initialLabel: initialLabel,
    initialUsage: initialUsage,
    showUsage: showUsage,
  ),
);

/// Formulaire de renommage d'un composant et de déclaration de son usage.
class ComponentRenameDialog extends StatefulWidget {
  /// Crée le formulaire initialisé avec [initialLabel] et [initialUsage].
  const ComponentRenameDialog({
    required this.initialLabel,
    this.initialUsage,
    this.showUsage = true,
    super.key,
  });

  /// Nom courant de l'instance.
  final String initialLabel;

  /// Usage courant de l'instance.
  final ComponentUsage? initialUsage;

  /// Affiche le choix de l'usage.
  final bool showUsage;

  @override
  State<ComponentRenameDialog> createState() => _ComponentRenameDialogState();
}

class _ComponentRenameDialogState extends State<ComponentRenameDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _translationKey;
  late ComponentUsageKind? _kind;
  late bool _translationKeyEdited;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.initialLabel);
    _kind = widget.initialUsage?.kind;
    final key = widget.initialUsage?.translationKey;
    _translationKey = TextEditingController(text: key ?? '');
    _translationKeyEdited =
        key != null &&
        key != ComponentUsage.suggestTranslationKey(widget.initialLabel);
  }

  @override
  void dispose() {
    _label.dispose();
    _translationKey.dispose();
    super.dispose();
  }

  bool get _needsTranslationKey => _kind == ComponentUsageKind.explanation;

  void _followLabel() {
    if (_translationKeyEdited) return;
    _translationKey.text = ComponentUsage.suggestTranslationKey(_label.text);
  }

  void _selectKind(ComponentUsageKind? kind) {
    setState(() => _kind = kind);
    if (_needsTranslationKey && _translationKey.text.trim().isEmpty) {
      _translationKeyEdited = false;
      _followLabel();
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final kind = _kind;
    final usage = !widget.showUsage
        ? widget.initialUsage
        : kind == null
        ? null
        : ComponentUsage(
            kind: kind,
            translationKey: kind == ComponentUsageKind.explanation
                ? _translationKey.text.trim()
                : null,
          );
    Navigator.of(
      context,
    ).pop(ComponentRenameResult(label: _label.text.trim(), usage: usage));
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    return AlertDialog(
      title: const Text('Renommer le composant'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('style-menu-rename-input'),
                controller: _label,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Le nom ne peut pas être vide.'
                    : null,
                onChanged: (_) => _followLabel(),
                onFieldSubmitted: (_) => _save(),
              ),
              if (widget.showUsage) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<ComponentUsageKind?>(
                  key: const ValueKey('style-menu-usage'),
                  initialValue: kind,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Usage',
                    helperText: kind?.description,
                    helperMaxLines: 2,
                  ),
                  items: [
                    const DropdownMenuItem<ComponentUsageKind?>(
                      value: null,
                      child: Text('Non défini'),
                    ),
                    for (final value in ComponentUsageKind.values)
                      DropdownMenuItem<ComponentUsageKind?>(
                        key: ValueKey('style-menu-usage-${value.name}'),
                        value: value,
                        child: Row(
                          children: [
                            Icon(value.icon, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                value.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: _selectKind,
                ),
                if (_needsTranslationKey) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('style-menu-usage-translation-key'),
                    controller: _translationKey,
                    decoration: const InputDecoration(
                      labelText: 'Clé de traduction',
                      helperText: 'Format ARB, ex. homeTitle',
                    ),
                    validator: ComponentUsage.translationKeyError,
                    onChanged: (value) => _translationKeyEdited =
                        value.trim().isNotEmpty &&
                        value != ComponentUsage.suggestTranslationKey(
                          _label.text,
                        ),
                    onFieldSubmitted: (_) => _save(),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey('style-menu-rename-save'),
          onPressed: _save,
          child: const Text('Renommer'),
        ),
      ],
    );
  }
}

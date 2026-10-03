import 'package:material_ui/material_ui.dart';

/// Liste des raccourcis clavier et souris de l'explorateur (F1).
class ShortcutsHelpDialog extends StatelessWidget {
  const ShortcutsHelpDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => const ShortcutsHelpDialog(),
  );

  static const sections = <(String, List<(String, String)>)>[
    (
      'Sélection',
      [
        ('Clic', 'Sélectionner un élément'),
        ('Ctrl + clic', 'Ajouter ou retirer un élément'),
        ('Maj + clic', 'Sélectionner une plage'),
        ('Ctrl + Maj + clic', 'Ajouter une plage'),
        ('Glisser', 'Sélection par cadre (Ctrl : inverser)'),
        ('↑ ↓ ← →', 'Se déplacer (Maj : étendre)'),
        ('Début / Fin', 'Premier / dernier élément'),
        ('Page préc. / suiv.', 'Sauter d’une page'),
        ('Lettres', 'Aller à l’élément qui commence ainsi'),
        ('Ctrl + A', 'Tout sélectionner'),
        ('Ctrl + Maj + A / Échap', 'Tout désélectionner'),
        ('Ctrl + I', 'Inverser la sélection'),
      ],
    ),
    (
      'Navigation',
      [
        ('Entrée / double-clic', 'Ouvrir'),
        ('Retour arrière / Alt + ←', 'Dossier précédent'),
        ('Alt + →', 'Dossier suivant'),
        ('Alt + ↑', 'Dossier parent'),
        ('F5 / Ctrl + R', 'Actualiser'),
        ('Espace', 'Aperçu'),
        ('Ctrl + D', 'Ajouter / retirer le dossier des favoris'),
        ('Ctrl + Maj + F', 'Afficher / masquer la barre de filtres'),
      ],
    ),
    (
      'Fichiers',
      [
        ('Ctrl + C / Ctrl + X', 'Copier / couper'),
        ('Ctrl + V', 'Coller dans le dossier affiché'),
        ('F2', 'Renommer'),
        ('Suppr', 'Mettre à la corbeille'),
        ('Maj + Suppr', 'Supprimer définitivement'),
        ('Ctrl + Maj + N', 'Nouveau dossier'),
        ('F1', 'Cette aide'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AlertDialog(
      key: const ValueKey('shortcuts-help'),
      title: const Text('Raccourcis'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (title, shortcuts) in sections) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                ),
                for (final (keys, description) in shortcuts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 190,
                          child: Text(
                            keys,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(child: Text(description)),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

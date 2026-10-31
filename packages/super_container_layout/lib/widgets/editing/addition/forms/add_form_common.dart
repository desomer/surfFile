import 'package:material_ui/material_ui.dart';

/// Parses a decimal number from form input supporting both `.` and `,`.
double? parseAddFormDouble(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

/// Shared state mixin managing revision-keyed form rebuilds after an advanced
/// editor dialog returns an updated draft.
mixin DraftAddFormStateMixin<T extends StatefulWidget> on State<T> {
  int _revision = 0;

  Future<void> openAdvancedDraftEditor<C>(
    Future<C?> Function() showEditor,
    ValueChanged<C> onChanged,
  ) async {
    final result = await showEditor();
    if (result == null || !mounted) return;
    setState(() => _revision++);
    onChanged(result);
  }

  Widget buildRevisionSubtree(Widget child) =>
      KeyedSubtree(key: ValueKey(_revision), child: child);
}

/// Titled card container used to group fields inside component add forms.
class AddFormSectionCard extends StatelessWidget {
  const AddFormSectionCard({
    required this.title,
    required this.child,
    super.key,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

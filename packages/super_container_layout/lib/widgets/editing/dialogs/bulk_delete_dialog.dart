/// Boîte de dialogue de suppression par lot avec sélection des cibles et confirmation ([BulkDeleteDialog]).
///
/// Permet de sélectionner une ou plusieurs cibles ([BulkDeleteTarget] : pages et
/// Shells, styles, repositories JSON, providers/datasources/SuperBackend, thème
/// et réglages globaux), d'utiliser l'option rapide « Tout sélectionner », de
/// visualiser les avertissements de dépendances puis de confirmer explicitement
/// la suppression sur les cibles choisies.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../models/registry.dart';
import '../../../services/appearance/appearance_codec.dart';
import '../../../services/appearance/bulk_delete_service.dart';
import '../../../services/pages/editor_page_router.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../../theme/appearance.dart';
import '../history/editor_history.dart';
import 'editor_dialog.dart';
import 'editor_dialog_header.dart';

/// Dialogue interactif de suppression ciblée par lot.
class BulkDeleteDialog extends StatefulWidget {
  /// Crée le dialogue de suppression par lot.
  const BulkDeleteDialog({
    required this.appearance,
    this.codec = const AppearanceCodec(),
    this.registry,
    this.pageRouting,
    this.repositoryStore,
    this.history,
    super.key,
  });

  /// Contrôleur d'apparence à inspecter et modifier.
  final ValueNotifier<Appearance> appearance;

  /// Codec utilisé pour réinitialiser les réglages par défaut.
  final AppearanceCodec codec;

  /// Registre optionnel des composants pour la suppression propre des pages/Shells.
  final Registry? registry;

  /// Routeur optionnel pour resynchroniser la navigation après suppression de pages.
  final EditorPageRouter? pageRouting;

  /// Store optionnel des repositories JSON, providers, datasources et SuperBackend.
  final JsonRepositoryStore? repositoryStore;

  /// Historique optionnel pour grouper la mutation d'apparence en une transaction.
  final EditorHistoryController? history;

  /// Ouvre [BulkDeleteDialog] et retourne le résultat de suppression ou `null` si annulé.
  static Future<BulkDeleteResult?> show(
    BuildContext context, {
    required ValueNotifier<Appearance> appearance,
    AppearanceCodec codec = const AppearanceCodec(),
    Registry? registry,
    EditorPageRouter? pageRouting,
    JsonRepositoryStore? repositoryStore,
    EditorHistoryController? history,
  }) async {
    final result = await showEditorDialog<BulkDeleteResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BulkDeleteDialog(
        appearance: appearance,
        codec: codec,
        registry: registry,
        pageRouting: pageRouting,
        repositoryStore: repositoryStore,
        history: history,
      ),
    );
    if (result != null && result.hasAnyChange && context.mounted) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(_resultSummaryMessage(result))),
          );
      }
    }
    return result;
  }

  static String _resultSummaryMessage(BulkDeleteResult result) {
    final parts = <String>[
      if (result.deletedPages > 0)
        '${result.deletedPages} page${result.deletedPages > 1 ? 's' : ''}',
      if (result.deletedShells > 0)
        '${result.deletedShells} Shell${result.deletedShells > 1 ? 's' : ''}',
      if (result.deletedComponents > 0)
        '${result.deletedComponents} composant${result.deletedComponents > 1 ? 's' : ''}',
      if (result.deletedStyles > 0)
        '${result.deletedStyles} style${result.deletedStyles > 1 ? 's' : ''}',
      if (result.deletedRepositories > 0)
        '${result.deletedRepositories} repository${result.deletedRepositories > 1 ? 's' : ''}',
      if (result.deletedProviders > 0)
        '${result.deletedProviders} provider${result.deletedProviders > 1 ? 's' : ''}',
      if (result.deletedDatasources > 0)
        '${result.deletedDatasources} datasource${result.deletedDatasources > 1 ? 's' : ''}',
      if (result.clearedBackendCollections > 0)
        '${result.clearedBackendCollections} collection${result.clearedBackendCollections > 1 ? 's' : ''} SuperBackend',
      if (result.clearedDebugEntries > 0)
        '${result.clearedDebugEntries} log${result.clearedDebugEntries > 1 ? 's' : ''} de debug',
      if (result.resetThemeAndGlobal) 'thème et réglages réinitialisés',
    ];
    if (parts.isEmpty) return 'Suppression terminée.';
    return 'Suppression effectuée : ${parts.join(', ')}.';
  }

  @override
  State<BulkDeleteDialog> createState() => _BulkDeleteDialogState();
}

class _BulkDeleteDialogState extends State<BulkDeleteDialog> {
  BulkDeleteInspection? _inspection;
  final Set<BulkDeleteTarget> _selected = <BulkDeleteTarget>{};
  bool _loading = true;
  bool _executing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInspection();
  }

  Future<void> _loadInspection() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inspection = await BulkDeleteService.inspect(
        appearanceController: widget.appearance,
        codec: widget.codec,
        registry: widget.registry,
        repositoryStore: widget.repositoryStore,
      );
      if (!mounted) return;
      setState(() {
        _inspection = inspection;
        _selected.removeWhere((target) => !inspection.hasDataFor(target));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible d’analyser les éléments : $error';
      });
    }
  }

  void _toggleAll() {
    final inspection = _inspection;
    if (inspection == null || _executing) return;
    final available = inspection.availableTargets;
    setState(() {
      _error = null;
      if (_selected.length == available.length && available.isNotEmpty) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(available);
      }
    });
  }

  void _toggleTarget(BulkDeleteTarget target, bool? checked) {
    if (_executing) return;
    setState(() {
      _error = null;
      if (checked == true) {
        _selected.add(target);
      } else {
        _selected.remove(target);
      }
    });
  }

  Future<void> _confirmAndExecute() async {
    final inspection = _inspection;
    if (inspection == null || _selected.isEmpty || _executing) return;
    final orderedTargets = [
      for (final target in BulkDeleteTarget.values)
        if (_selected.contains(target)) target,
    ];
    final dependencies = inspection.analyzeDependencies(_selected);

    final confirmed = await showEditorDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (confirmContext) {
        final scheme = Theme.of(confirmContext).colorScheme;
        return AlertDialog(
          key: const ValueKey('bulk-delete-confirm-dialog'),
          icon: Icon(
            Icons.warning_amber_rounded,
            color: scheme.error,
            size: 28,
          ),
          title: const Text('Confirmer la suppression'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Les éléments suivants vont être définitivement supprimés ou réinitialisés :',
                  ),
                  const SizedBox(height: 12),
                  for (final target in orderedTargets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _iconFor(target),
                            size: 18,
                            color: scheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  target.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  inspection.summaryFor(target),
                                  style: Theme.of(confirmContext)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (dependencies.hasWarnings) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: const ValueKey('bulk-delete-confirm-dependencies'),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: scheme.error.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dépendances détectées',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: scheme.onErrorContainer,
                            ),
                          ),
                          const SizedBox(height: 4),
                          for (final msg in dependencies.messages)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '• $msg',
                                style: Theme.of(confirmContext)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.onErrorContainer),
                              ),
                            ),
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
              key: const ValueKey('bulk-delete-confirm-cancel'),
              onPressed: () => Navigator.of(confirmContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('bulk-delete-confirm-submit'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(confirmContext).pop(true),
              child: const Text('Confirmer la suppression'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _executing = true;
      _error = null;
    });

    try {
      final result = await BulkDeleteService.execute(
        appearanceController: widget.appearance,
        targets: Set<BulkDeleteTarget>.of(_selected),
        codec: widget.codec,
        registry: widget.registry,
        pageRouting: widget.pageRouting,
        repositoryStore: widget.repositoryStore,
        history: widget.history,
        force: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _executing = false;
        _error = 'Échec de la suppression : $error';
      });
    }
  }

  static IconData _iconFor(BulkDeleteTarget target) => switch (target) {
    BulkDeleteTarget.pagesAndShells => Icons.web_stories_outlined,
    BulkDeleteTarget.styles => Icons.palette_outlined,
    BulkDeleteTarget.repositories => Icons.storage_outlined,
    BulkDeleteTarget.providersAndDatasources => Icons.cloud_sync_outlined,
    BulkDeleteTarget.debugLogs => Icons.bug_report_outlined,
    BulkDeleteTarget.themeAndGlobal => Icons.tune_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = math.min(
      560.0,
      math.max(280.0, MediaQuery.sizeOf(context).width - 80),
    );
    final inspection = _inspection;
    final available = inspection?.availableTargets ?? const <BulkDeleteTarget>{};
    final bool? selectAllState = available.isEmpty || _selected.isEmpty
        ? false
        : (_selected.length == available.length ? true : null);
    final dependencies = inspection?.analyzeDependencies(_selected);

    return AlertDialog(
      key: const ValueKey('bulk-delete-dialog'),
      title: EditorDialogHeader(
        label: 'Tout supprimer',
        actions: [
          IconButton(
            key: const ValueKey('bulk-delete-close'),
            tooltip: 'Fermer',
            icon: const Icon(Icons.close, size: 18),
            onPressed: _executing ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Sélectionnez les éléments de l’application à supprimer ou réinitialiser.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: CheckboxListTile(
                        key: const ValueKey('bulk-delete-select-all'),
                        tristate: true,
                        value: selectAllState,
                        enabled: available.isNotEmpty && !_executing,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        title: const Text(
                          'Tout sélectionner',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          available.isEmpty
                              ? 'Aucun élément à supprimer actuellement'
                              : '${_selected.length} / ${available.length} cible${available.length > 1 ? 's' : ''} disponible${available.length > 1 ? 's' : ''}',
                        ),
                        onChanged: available.isEmpty || _executing
                            ? null
                            : (_) => _toggleAll(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final target in BulkDeleteTarget.values) ...[
                      Builder(
                        builder: (context) {
                          final hasData =
                              inspection?.hasDataFor(target) ?? false;
                          final checked = _selected.contains(target);
                          final summary = inspection?.summaryFor(target) ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Material(
                              color: checked
                                  ? scheme.errorContainer.withValues(
                                      alpha: 0.16,
                                    )
                                  : Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: checked
                                      ? scheme.error.withValues(alpha: 0.5)
                                      : scheme.outlineVariant.withValues(
                                          alpha: 0.5,
                                        ),
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: CheckboxListTile(
                                key: ValueKey(
                                  'bulk-delete-target-${target.name}',
                                ),
                                value: checked,
                                enabled: hasData && !_executing,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                activeColor: scheme.error,
                                checkColor: scheme.onError,
                                secondary: Icon(
                                  _iconFor(target),
                                  size: 20,
                                  color: hasData
                                      ? (checked
                                            ? scheme.error
                                            : scheme.onSurfaceVariant)
                                      : scheme.outline,
                                ),
                                title: Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      target.label,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: hasData
                                            ? scheme.onSurface
                                            : scheme.onSurfaceVariant
                                                  .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: hasData
                                            ? (checked
                                                  ? scheme.error.withValues(
                                                      alpha: 0.14,
                                                    )
                                                  : scheme.surfaceContainerHigh)
                                            : scheme.surfaceContainerLowest,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        summary,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: hasData
                                                  ? (checked
                                                        ? scheme.error
                                                        : scheme
                                                              .onSurfaceVariant)
                                                  : scheme.outline,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Text(
                                  target.description,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                                onChanged: hasData && !_executing
                                    ? (val) => _toggleTarget(target, val)
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    if (dependencies != null && dependencies.hasWarnings) ...[
                      const SizedBox(height: 8),
                      Container(
                        key: const ValueKey('bulk-delete-dependencies-warning'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.tertiaryContainer.withValues(
                            alpha: 0.45,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: scheme.tertiary.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.link_off_outlined,
                                  size: 18,
                                  color: scheme.onTertiaryContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Dépendances détectées',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onTertiaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            for (final message in dependencies.messages)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  '• $message',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onTertiaryContainer,
                                      ),
                                ),
                              ),
                            if (dependencies.suggestProvidersAndDatasources ||
                                dependencies.suggestPagesAndShells) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (dependencies
                                          .suggestProvidersAndDatasources &&
                                      (inspection?.hasDataFor(
                                            BulkDeleteTarget
                                                .providersAndDatasources,
                                          ) ??
                                          false))
                                    ActionChip(
                                      key: const ValueKey(
                                        'bulk-delete-include-providers',
                                      ),
                                      avatar: const Icon(
                                        Icons.add_circle_outline,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Inclure Providers & Datasources',
                                      ),
                                      onPressed: _executing
                                          ? null
                                          : () => setState(
                                              () => _selected.add(
                                                BulkDeleteTarget
                                                    .providersAndDatasources,
                                              ),
                                            ),
                                    ),
                                  if (dependencies.suggestPagesAndShells &&
                                      (inspection?.hasDataFor(
                                            BulkDeleteTarget.pagesAndShells,
                                          ) ??
                                          false))
                                    ActionChip(
                                      key: const ValueKey(
                                        'bulk-delete-include-pages',
                                      ),
                                      avatar: const Icon(
                                        Icons.add_circle_outline,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'Inclure Pages & Shells',
                                      ),
                                      onPressed: _executing
                                          ? null
                                          : () => setState(
                                              () => _selected.add(
                                                BulkDeleteTarget.pagesAndShells,
                                              ),
                                            ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        key: const ValueKey('bulk-delete-error'),
                        style: TextStyle(color: scheme.error),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('bulk-delete-cancel'),
          onPressed: _executing ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          key: const ValueKey('bulk-delete-submit'),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _loading || _executing || _selected.isEmpty
              ? null
              : _confirmAndExecute,
          icon: _executing
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onError,
                  ),
                )
              : const Icon(Icons.delete_sweep_outlined, size: 18),
          label: const Text('Supprimer la sélection…'),
        ),
      ],
    );
  }
}

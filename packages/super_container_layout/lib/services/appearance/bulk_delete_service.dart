/// Service d'inspection et de suppression ciblée par lot ([BulkDeleteService]).
///
/// Permet d'inventorier les pages/shells, styles, repositories JSON,
/// providers/datasources/SuperBackend et réglages globaux, d'analyser les
/// dépendances croisées avant confirmation et d'exécuter la suppression
/// sélectionnée de manière cohérente avec [EditorPageGraph], [EditorPageRouter],
/// [EditorHistoryController] et [JsonRepositoryStore].
library;

import 'package:flutter/foundation.dart';

import '../../models/editor_page_config.dart';
import '../../models/registry.dart';
import '../../theme/appearance.dart';
import '../../widgets/components/super_layout/layout_selection.dart';
import '../../widgets/editing/history/editor_history.dart';
import '../diagnostics/debug_entry.dart';
import '../pages/editor_page_graph.dart';
import '../pages/editor_page_router.dart';
import '../repositories/json_repository_store.dart';
import 'appearance_codec.dart';
import 'appearance_store.dart';

/// Cible supprimable ou réinitialisable depuis le dialogue de suppression par lot.
enum BulkDeleteTarget {
  /// Pages du catalogue, contenu de la page racine ('/') et mises en page partagées (Shells).
  pagesAndShells(
    label: 'Pages, racine « / » & Shells',
    description:
        'Supprime les pages du catalogue, les Shells partagés ainsi que tout le contenu de la page racine (composants, dispositions, comportements et usages).',
  ),

  /// Styles enregistrés dans l'apparence (cartes, états, fond).
  styles(
    label: 'Styles',
    description:
        'Supprime tous les styles personnalisés (cartes, surcharges d’état et fond).',
  ),

  /// Repositories JSON fichiers, schémas JSON et attributs calculés associés.
  repositories(
    label: 'Repositories JSON',
    description:
        'Supprime les fichiers de repositories, leurs schémas JSON et attributs calculés.',
  ),

  /// Providers HTTP, datasources éditeur et collections locales SuperBackend.
  providersAndDatasources(
    label: 'Providers, Datasources & SuperBackend',
    description:
        'Supprime les Data Providers, Datasources de l’éditeur et collections locales SuperBackend.',
  ),

  /// Journaux et erreurs capturés en mémoire dans le panneau de diagnostic.
  debugLogs(
    label: 'Logs de debug',
    description:
        'Vide le tampon en mémoire des journaux et erreurs affichés dans le diagnostic.',
  ),

  /// Thème et réglages globaux (mode, accent, opacités, fenêtre, responsive).
  themeAndGlobal(
    label: 'Thème & réglages globaux',
    description:
        'Réinitialise le mode clair/sombre, la couleur d’accent, les opacités, la fenêtre et le responsive.',
  );

  const BulkDeleteTarget({required this.label, required this.description});

  /// Libellé court affiché dans l'interface.
  final String label;

  /// Description détaillée de la portée de suppression.
  final String description;
}

/// Analyse des dépendances impactées par un sous-ensemble de [BulkDeleteTarget].
@immutable
class BulkDeleteDependencies {
  /// Crée un résumé des dépendances détectées pour la sélection courante.
  const BulkDeleteDependencies({
    this.boundRepositoryNames = const [],
    this.providerUsedRepositoryNames = const [],
    this.datasourceUsedRepositoryNames = const [],
    this.behaviorUsedProviderIds = const [],
    this.behaviorUsedDatasourceIds = const [],
    this.suggestPagesAndShells = false,
    this.suggestProvidersAndDatasources = false,
  });

  /// Noms des repositories sélectionnés encore référencés par des liaisons conservées.
  final List<String> boundRepositoryNames;

  /// Noms des repositories sélectionnés encore utilisés par un provider conservé.
  final List<String> providerUsedRepositoryNames;

  /// Noms des repositories sélectionnés encore utilisés par une datasource conservée.
  final List<String> datasourceUsedRepositoryNames;

  /// Identifiants des providers sélectionnés encore lancés par un comportement conservé.
  final List<String> behaviorUsedProviderIds;

  /// Identifiants des datasources sélectionnées encore lancées par un comportement conservé.
  final List<String> behaviorUsedDatasourceIds;

  /// Indique s'il est pertinent de proposer d'inclure [BulkDeleteTarget.pagesAndShells].
  final bool suggestPagesAndShells;

  /// Indique s'il est pertinent de proposer d'inclure [BulkDeleteTarget.providersAndDatasources].
  final bool suggestProvidersAndDatasources;

  /// Indique si au moins une dépendance croisée a été détectée.
  bool get hasWarnings =>
      boundRepositoryNames.isNotEmpty ||
      providerUsedRepositoryNames.isNotEmpty ||
      datasourceUsedRepositoryNames.isNotEmpty ||
      behaviorUsedProviderIds.isNotEmpty ||
      behaviorUsedDatasourceIds.isNotEmpty;

  /// Retourne la liste des messages d'avertissement lisibles pour l'utilisateur.
  List<String> get messages => [
    if (boundRepositoryNames.isNotEmpty)
      '${boundRepositoryNames.length} repository(ies) encore lié(s) dans '
          'l’interface (${boundRepositoryNames.join(', ')}) : leurs liaisons '
          'deviendront inactives.',
    if (providerUsedRepositoryNames.isNotEmpty)
      '${providerUsedRepositoryNames.length} repository(ies) encore utilisé(s) '
          'par des Data Providers conservés (${providerUsedRepositoryNames.join(', ')}).',
    if (datasourceUsedRepositoryNames.isNotEmpty)
      '${datasourceUsedRepositoryNames.length} repository(ies) encore utilisé(s) '
          'par des Datasources conservées (${datasourceUsedRepositoryNames.join(', ')}).',
    if (behaviorUsedProviderIds.isNotEmpty)
      '${behaviorUsedProviderIds.length} Data Provider(s) encore déclenché(s) '
          'par des comportements conservés (${behaviorUsedProviderIds.join(', ')}).',
    if (behaviorUsedDatasourceIds.isNotEmpty)
      '${behaviorUsedDatasourceIds.length} Datasource(s) encore déclenchée(s) '
          'par des comportements conservés (${behaviorUsedDatasourceIds.join(', ')}).',
  ];
}

/// État instantané des éléments supprimables dans l'application courante.
@immutable
class BulkDeleteInspection {
  /// Crée un instantané d'inspection.
  const BulkDeleteInspection({
    required this.appearance,
    required this.pageCount,
    required this.shellCount,
    required this.componentCount,
    required this.behaviorCount,
    required this.styleCount,
    required this.fileRepositories,
    required this.registeredRepositoryCount,
    required this.editableProviderIds,
    required this.editableDatasourceIds,
    required this.superBackendCollections,
    required this.superBackendRowCount,
    required this.debugEntryCount,
    required this.debugErrorCount,
    required this.hasCustomThemeOrGlobal,
    this.registry,
    this.repositoryStore,
  });

  /// Apparence inspectée.
  final Appearance appearance;

  /// Registre optionnel utilisé pour simuler la suppression des pages/shells.
  final Registry? registry;

  /// Store optionnel de repositories.
  final JsonRepositoryStore? repositoryStore;

  /// Nombre de pages dans [EditorPageCatalog.pages].
  final int pageCount;

  /// Nombre de mises en page partagées dans [EditorPageCatalog.shells].
  final int shellCount;

  /// Nombre total de composants configurés dans [Appearance.components] (page racine incluse).
  final int componentCount;

  /// Nombre total de comportements configurés dans [Appearance.behaviors].
  final int behaviorCount;

  /// Nombre de styles dans [Appearance.styles].
  final int styleCount;

  /// Repositories fichiers supprimables (`(name, id)`).
  final List<JsonRepositoryEntry> fileRepositories;

  /// Nombre de repositories enregistrés par le code hôte (non supprimables).
  final int registeredRepositoryCount;

  /// Identifiants des Data Providers éditeur supprimables.
  final List<String> editableProviderIds;

  /// Identifiants des Datasources éditeur supprimables.
  final List<String> editableDatasourceIds;

  /// Noms des collections non vides dans [SuperBackend].
  final List<String> superBackendCollections;

  /// Nombre total de lignes dans [SuperBackend].
  final int superBackendRowCount;

  /// Nombre total d'entrées dans [debugEntries].
  final int debugEntryCount;

  /// Nombre d'erreurs dans [debugEntries].
  final int debugErrorCount;

  /// Indique si au moins un réglage thème/global diffère des valeurs par défaut.
  final bool hasCustomThemeOrGlobal;

  /// Nombre d'éléments supprimables pour une cible donnée.
  int countFor(BulkDeleteTarget target) => switch (target) {
    BulkDeleteTarget.pagesAndShells =>
      pageCount +
          shellCount +
          componentCount +
          behaviorCount +
          appearance.usages.length,
    BulkDeleteTarget.styles => styleCount,
    BulkDeleteTarget.repositories => fileRepositories.length,
    BulkDeleteTarget.providersAndDatasources =>
      editableProviderIds.length +
          editableDatasourceIds.length +
          superBackendCollections.length,
    BulkDeleteTarget.debugLogs => debugEntryCount,
    BulkDeleteTarget.themeAndGlobal => hasCustomThemeOrGlobal ? 1 : 0,
  };

  /// Indique si la cible possède au moins un élément à supprimer ou réinitialiser.
  bool hasDataFor(BulkDeleteTarget target) => countFor(target) > 0;

  /// Retourne toutes les cibles qui contiennent actuellement des données.
  Set<BulkDeleteTarget> get availableTargets => {
    for (final target in BulkDeleteTarget.values)
      if (hasDataFor(target)) target,
  };

  /// Résumé court et lisible des éléments présents pour [target].
  String summaryFor(BulkDeleteTarget target) => switch (target) {
    BulkDeleteTarget.pagesAndShells =>
      countFor(BulkDeleteTarget.pagesAndShells) == 0
          ? 'Aucune page ni contenu'
          : [
              if (pageCount > 0) '$pageCount page${pageCount > 1 ? 's' : ''}',
              if (shellCount > 0)
                '$shellCount Shell${shellCount > 1 ? 's' : ''}',
              if (componentCount > 0)
                '$componentCount composant${componentCount > 1 ? 's' : ''}',
              if (behaviorCount > 0)
                '$behaviorCount comportement${behaviorCount > 1 ? 's' : ''}',
            ].join(', '),
    BulkDeleteTarget.styles =>
      styleCount == 0
          ? 'Aucun style'
          : '$styleCount style${styleCount > 1 ? 's' : ''}',
    BulkDeleteTarget.repositories =>
      fileRepositories.isEmpty
          ? (registeredRepositoryCount > 0
                ? 'Aucun repository fichier ($registeredRepositoryCount fourni(s) par le code)'
                : 'Aucun repository')
          : '${fileRepositories.length} repository${fileRepositories.length > 1 ? 's' : ''}'
                '${registeredRepositoryCount > 0 ? ' (+ $registeredRepositoryCount code)' : ''}',
    BulkDeleteTarget.providersAndDatasources =>
      editableProviderIds.isEmpty &&
              editableDatasourceIds.isEmpty &&
              superBackendCollections.isEmpty
          ? 'Aucun provider, datasource ni table locale'
          : [
              if (editableProviderIds.isNotEmpty)
                '${editableProviderIds.length} provider${editableProviderIds.length > 1 ? 's' : ''}',
              if (editableDatasourceIds.isNotEmpty)
                '${editableDatasourceIds.length} datasource${editableDatasourceIds.length > 1 ? 's' : ''}',
              if (superBackendCollections.isNotEmpty)
                '${superBackendCollections.length} collection${superBackendCollections.length > 1 ? 's' : ''} ($superBackendRowCount ligne${superBackendRowCount > 1 ? 's' : ''})',
            ].join(', '),
    BulkDeleteTarget.debugLogs =>
      debugEntryCount == 0
          ? 'Aucun log'
          : debugErrorCount > 0
          ? '$debugEntryCount entrée${debugEntryCount > 1 ? 's' : ''} ($debugErrorCount erreur${debugErrorCount > 1 ? 's' : ''})'
          : '$debugEntryCount entrée${debugEntryCount > 1 ? 's' : ''}',
    BulkDeleteTarget.themeAndGlobal =>
      hasCustomThemeOrGlobal
          ? 'Réglages personnalisés détectés'
          : 'Déjà aux valeurs par défaut',
  };

  /// Analyse les dépendances croisées pour la sélection [selected].
  BulkDeleteDependencies analyzeDependencies(Set<BulkDeleteTarget> selected) {
    if (selected.isEmpty) return const BulkDeleteDependencies();

    final remainingAppearance = BulkDeleteService.computeNextAppearance(
      current: appearance,
      targets: selected.intersection({
        BulkDeleteTarget.pagesAndShells,
        BulkDeleteTarget.styles,
      }),
      registry: registry,
    );

    final boundRepos = <String>[];
    final providerRepos = <String>[];
    final datasourceRepos = <String>[];
    var suggestPages = false;
    var suggestProviders = false;

    if (selected.contains(BulkDeleteTarget.repositories)) {
      final store = repositoryStore;
      final deletingProviders = selected.contains(
        BulkDeleteTarget.providersAndDatasources,
      );
      final deletingPages = selected.contains(BulkDeleteTarget.pagesAndShells);
      for (final entry in fileRepositories) {
        final stillBoundInRemaining =
            remainingAppearance.usesRepository(entry.id) ||
            (!deletingPages && (store?.isRepositoryBound(entry.id) ?? false));
        if (stillBoundInRemaining) {
          boundRepos.add(entry.name);
          if (!deletingPages &&
              hasDataFor(BulkDeleteTarget.pagesAndShells) &&
              appearance.usesRepository(entry.id)) {
            suggestPages = true;
          }
        }
        if (!deletingProviders && store != null) {
          if (store.providers.usesRepository(entry.id)) {
            providerRepos.add(entry.name);
            suggestProviders = true;
          }
          if (store.datasources.usesRepository(entry.id)) {
            datasourceRepos.add(entry.name);
            suggestProviders = true;
          }
        }
      }
    }

    final behaviorProviders = <String>[];
    final behaviorDatasources = <String>[];
    if (selected.contains(BulkDeleteTarget.providersAndDatasources)) {
      final deletingPages = selected.contains(BulkDeleteTarget.pagesAndShells);
      for (final id in editableProviderIds) {
        if (remainingAppearance.usesProvider(id)) {
          behaviorProviders.add(id);
          if (!deletingPages &&
              hasDataFor(BulkDeleteTarget.pagesAndShells) &&
              appearance.usesProvider(id)) {
            suggestPages = true;
          }
        }
      }
      for (final id in editableDatasourceIds) {
        if (remainingAppearance.usesDatasource(id)) {
          behaviorDatasources.add(id);
          if (!deletingPages &&
              hasDataFor(BulkDeleteTarget.pagesAndShells) &&
              appearance.usesDatasource(id)) {
            suggestPages = true;
          }
        }
      }
    }

    return BulkDeleteDependencies(
      boundRepositoryNames: List.unmodifiable(boundRepos),
      providerUsedRepositoryNames: List.unmodifiable(providerRepos),
      datasourceUsedRepositoryNames: List.unmodifiable(datasourceRepos),
      behaviorUsedProviderIds: List.unmodifiable(behaviorProviders),
      behaviorUsedDatasourceIds: List.unmodifiable(behaviorDatasources),
      suggestPagesAndShells: suggestPages,
      suggestProvidersAndDatasources: suggestProviders,
    );
  }
}

/// Résultat quantifié d'une exécution de [BulkDeleteService.execute].
@immutable
class BulkDeleteResult {
  /// Crée un résultat de suppression.
  const BulkDeleteResult({
    this.deletedPages = 0,
    this.deletedShells = 0,
    this.deletedComponents = 0,
    this.deletedStyles = 0,
    this.deletedRepositories = 0,
    this.deletedProviders = 0,
    this.deletedDatasources = 0,
    this.clearedBackendCollections = 0,
    this.clearedBackendRows = 0,
    this.clearedDebugEntries = 0,
    this.resetThemeAndGlobal = false,
  });

  /// Nombre de pages supprimées.
  final int deletedPages;

  /// Nombre de Shells supprimés.
  final int deletedShells;

  /// Nombre de composants supprimés (pages du catalogue et page racine).
  final int deletedComponents;

  /// Nombre de styles supprimés.
  final int deletedStyles;

  /// Nombre de repositories fichiers supprimés.
  final int deletedRepositories;

  /// Nombre de Data Providers éditeur supprimés.
  final int deletedProviders;

  /// Nombre de Datasources éditeur supprimées.
  final int deletedDatasources;

  /// Nombre de collections SuperBackend vidées.
  final int clearedBackendCollections;

  /// Nombre total de lignes supprimées dans SuperBackend.
  final int clearedBackendRows;

  /// Nombre d'entrées supprimées du tampon de logs de debug.
  final int clearedDebugEntries;

  /// Indique si le thème et les réglages globaux ont été réinitialisés.
  final bool resetThemeAndGlobal;

  /// Indique si au moins une modification a été effectuée.
  bool get hasAnyChange =>
      deletedPages > 0 ||
      deletedShells > 0 ||
      deletedComponents > 0 ||
      deletedStyles > 0 ||
      deletedRepositories > 0 ||
      deletedProviders > 0 ||
      deletedDatasources > 0 ||
      clearedBackendCollections > 0 ||
      clearedDebugEntries > 0 ||
      resetThemeAndGlobal;
}

/// Service centralisant l'inspection et la suppression ciblée de l'application.
abstract final class BulkDeleteService {
  static bool _hasCustomThemeOrGlobal(
    Appearance appearance,
    AppearanceCodec codec,
  ) {
    final defaults = codec.defaults;
    if (appearance.mode != defaults.mode ||
        appearance.accent != defaults.accent ||
        appearance.backgroundOpacity != defaults.backgroundOpacity ||
        appearance.windowOpacity != defaults.windowOpacity ||
        appearance.windowEffect != defaults.windowEffect ||
        appearance.bindingDebounceMs != defaults.bindingDebounceMs ||
        appearance.bindingSaveOnBlurOnly != defaults.bindingSaveOnBlurOnly ||
        appearance.responsiveLayout != defaults.responsiveLayout) {
      return true;
    }
    final strippedCurrent = appearance.copyWith(
      styles: const {},
      components: const {},
      behaviors: const {},
      usages: const {},
      pageCatalog: const EditorPageCatalog.empty(),
    );
    final strippedDefaults = defaults.copyWith(
      styles: const {},
      components: const {},
      behaviors: const {},
      usages: const {},
      pageCatalog: const EditorPageCatalog.empty(),
    );
    return !mapEquals(
      codec.toCompactJson(strippedCurrent),
      codec.toCompactJson(strippedDefaults),
    );
  }

  /// Calcule la nouvelle [Appearance] après application des cibles [targets].
  static Appearance computeNextAppearance({
    required Appearance current,
    required Set<BulkDeleteTarget> targets,
    AppearanceCodec codec = const AppearanceCodec(),
    Registry? registry,
  }) {
    var next = current;

    if (targets.contains(BulkDeleteTarget.pagesAndShells)) {
      if (registry != null) {
        for (final page in next.pageCatalog.pages) {
          next = EditorPageGraph.removal(
            appearance: next,
            registry: registry,
            pageId: page.id,
          ).appearance;
        }
        for (final shell in next.pageCatalog.shells) {
          next = EditorPageGraph.removeShell(
            appearance: next,
            registry: registry,
            shellId: shell.id,
          ).appearance;
        }
      }
      // Vide également tout le contenu de la page racine ('/' : mainLayout, root, etc.).
      next = next.copyWith(
        components: const {},
        behaviors: const {},
        usages: const {},
        pageCatalog: const EditorPageCatalog.empty(),
      );
    }

    if (targets.contains(BulkDeleteTarget.styles)) {
      next = next.copyWith(styles: const {});
    }

    if (targets.contains(BulkDeleteTarget.themeAndGlobal)) {
      next = codec.defaults.copyWith(
        styles: next.styles,
        components: next.components,
        behaviors: next.behaviors,
        usages: next.usages,
        pageCatalog: next.pageCatalog,
      );
    }

    return next;
  }

  /// Inspecte les cibles disponibles et leurs compteurs sans rien modifier.
  static Future<BulkDeleteInspection> inspect({
    required ValueNotifier<Appearance> appearanceController,
    AppearanceCodec codec = const AppearanceCodec(),
    Registry? registry,
    JsonRepositoryStore? repositoryStore,
  }) async {
    if (appearanceController is PersistentAppearanceController &&
        appearanceController.hasUnloadedCatalogPages) {
      await appearanceController.ensureAllPagesLoaded();
    }
    final appearance = appearanceController.value;

    var fileRepositories = const <JsonRepositoryEntry>[];
    var registeredRepositoryCount = 0;
    var editableProviderIds = const <String>[];
    var editableDatasourceIds = const <String>[];
    var backendCollections = const <String>[];
    var backendRows = 0;

    if (repositoryStore != null) {
      final hasDirectory = await repositoryStore.directory.exists();
      if (hasDirectory) {
        final entries = await repositoryStore.catalog();
        fileRepositories = [
          for (final entry in entries)
            if (!repositoryStore.isRegisteredRepository(entry.id)) entry,
        ];
        registeredRepositoryCount = entries.length - fileRepositories.length;
      }

      await repositoryStore.providers.ensureLoaded();
      await repositoryStore.datasources.ensureLoaded();

      editableProviderIds = [
        for (final provider in repositoryStore.providers.providers)
          if (repositoryStore.providers.isEditable(provider.id)) provider.id,
      ];
      editableDatasourceIds = [
        for (final datasource in repositoryStore.datasources.datasources)
          if (repositoryStore.datasources.isEditable(datasource.id))
            datasource.id,
      ];

      if (repositoryStore.hasSuperBackendData) {
        await repositoryStore.superBackend.init();
        final cols = await repositoryStore.superBackend.listCollections();
        backendCollections = cols;
        for (final col in cols) {
          backendRows += await repositoryStore.superBackend.count(col);
        }
      }
    }

    final behaviorCount = appearance.behaviors.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );
    final debugErrorCount = debugEntries
        .where((entry) => entry.type == DebugEntryType.error)
        .length;

    return BulkDeleteInspection(
      appearance: appearance,
      registry: registry,
      repositoryStore: repositoryStore,
      pageCount: appearance.pageCatalog.pages.length,
      shellCount: appearance.pageCatalog.shells.length,
      componentCount: appearance.components.length,
      behaviorCount: behaviorCount,
      styleCount: appearance.styles.length,
      fileRepositories: List.unmodifiable(fileRepositories),
      registeredRepositoryCount: registeredRepositoryCount,
      editableProviderIds: List.unmodifiable(editableProviderIds),
      editableDatasourceIds: List.unmodifiable(editableDatasourceIds),
      superBackendCollections: List.unmodifiable(backendCollections),
      superBackendRowCount: backendRows,
      debugEntryCount: debugEntries.length,
      debugErrorCount: debugErrorCount,
      hasCustomThemeOrGlobal: _hasCustomThemeOrGlobal(appearance, codec),
    );
  }

  /// Exécute la suppression des cibles [targets].
  static Future<BulkDeleteResult> execute({
    required ValueNotifier<Appearance> appearanceController,
    required Set<BulkDeleteTarget> targets,
    AppearanceCodec codec = const AppearanceCodec(),
    Registry? registry,
    EditorPageRouter? pageRouting,
    JsonRepositoryStore? repositoryStore,
    EditorHistoryController? history,
    bool force = true,
  }) async {
    if (targets.isEmpty) return const BulkDeleteResult();

    if (targets.contains(BulkDeleteTarget.pagesAndShells) &&
        appearanceController is PersistentAppearanceController &&
        appearanceController.hasUnloadedCatalogPages) {
      await appearanceController.ensureAllPagesLoaded();
    }

    final initialAppearance = appearanceController.value;
    final deletedPages = targets.contains(BulkDeleteTarget.pagesAndShells)
        ? initialAppearance.pageCatalog.pages.length
        : 0;
    final deletedShells = targets.contains(BulkDeleteTarget.pagesAndShells)
        ? initialAppearance.pageCatalog.shells.length
        : 0;
    final deletedComponents = targets.contains(BulkDeleteTarget.pagesAndShells)
        ? initialAppearance.components.length
        : 0;
    final deletedStyles = targets.contains(BulkDeleteTarget.styles)
        ? initialAppearance.styles.length
        : 0;
    final resetThemeAndGlobal = targets.contains(
      BulkDeleteTarget.themeAndGlobal,
    );

    final wasOnCatalogPage =
        targets.contains(BulkDeleteTarget.pagesAndShells) &&
        pageRouting != null &&
        pageRouting.pageAt(
              pageRouting.router.routeInformationProvider.value.uri,
              catalog: initialAppearance.pageCatalog,
            ) !=
            null;

    if (resetThemeAndGlobal) {
      codec.resetAdditional();
    }

    final nextAppearance = computeNextAppearance(
      current: initialAppearance,
      targets: targets,
      codec: codec,
      registry: registry,
    );

    if (nextAppearance != initialAppearance) {
      history?.beginTransaction();
      try {
        appearanceController.value = nextAppearance;
      } finally {
        history?.commitTransaction();
      }
      if (targets.contains(BulkDeleteTarget.pagesAndShells)) {
        LayoutSelection.clearAll();
        if (pageRouting != null) {
          pageRouting.synchronize(nextAppearance.pageCatalog);
          if (wasOnCatalogPage) {
            pageRouting.openLocation('/');
          }
        }
      }
      if (appearanceController is PersistentAppearanceController) {
        await appearanceController.flush();
      }
    }

    var deletedProviders = 0;
    var deletedDatasources = 0;
    var clearedBackendCollections = 0;
    var clearedBackendRows = 0;
    var deletedRepositories = 0;

    if (targets.contains(BulkDeleteTarget.providersAndDatasources) &&
        repositoryStore != null) {
      await repositoryStore.datasources.ensureLoaded();
      await repositoryStore.providers.ensureLoaded();

      final datasourceIds = [
        for (final ds in repositoryStore.datasources.datasources)
          if (repositoryStore.datasources.isEditable(ds.id)) ds.id,
      ];
      for (final id in datasourceIds) {
        await repositoryStore.datasources.delete(
          id,
          appearance: nextAppearance,
          force: force,
        );
        deletedDatasources++;
      }

      final providerIds = [
        for (final provider in repositoryStore.providers.providers)
          if (repositoryStore.providers.isEditable(provider.id)) provider.id,
      ];
      for (final id in providerIds) {
        await repositoryStore.providers.delete(
          id,
          appearance: nextAppearance,
          force: force,
        );
        deletedProviders++;
      }

      if (repositoryStore.hasSuperBackendData) {
        await repositoryStore.superBackend.init();
        final collections = await repositoryStore.superBackend.listCollections();
        for (final collection in collections) {
          clearedBackendRows += await repositoryStore.superBackend.clearCollection(
            collection,
          );
          clearedBackendCollections++;
        }
      }
    }

    if (targets.contains(BulkDeleteTarget.repositories) &&
        repositoryStore != null &&
        await repositoryStore.directory.exists()) {
      final entries = await repositoryStore.catalog();
      final fileEntries = [
        for (final entry in entries)
          if (!repositoryStore.isRegisteredRepository(entry.id)) entry,
      ];
      for (final entry in fileEntries) {
        await repositoryStore.delete(
          entry.name,
          appearance: nextAppearance,
          force: force,
        );
        deletedRepositories++;
      }
    }

    var clearedDebugEntries = 0;
    if (targets.contains(BulkDeleteTarget.debugLogs)) {
      clearedDebugEntries = debugEntries.length;
      clearDebugEntries();
    }

    return BulkDeleteResult(
      deletedPages: deletedPages,
      deletedShells: deletedShells,
      deletedComponents: deletedComponents,
      deletedStyles: deletedStyles,
      deletedRepositories: deletedRepositories,
      deletedProviders: deletedProviders,
      deletedDatasources: deletedDatasources,
      clearedBackendCollections: clearedBackendCollections,
      clearedBackendRows: clearedBackendRows,
      clearedDebugEntries: clearedDebugEntries,
      resetThemeAndGlobal: resetThemeAndGlobal,
    );
  }
}

/// Service d'import/export JSON ([AppearanceTransfer]) et d'application incrémentale Vibe IA (`applyVibe`).
///
/// Permet d'exporter ou d'importer indépendamment les groupes Styles et Dispositions
/// ([TransferGroup]) et de fusionner les patches JSON générés par l'assistant IA.
library;

import 'dart:convert';

import '../../models/component_config.dart';
import '../../models/component_usage.dart';
import '../../models/json_numbers.dart';
import '../../models/json_syntax.dart';
import '../../models/native_component_config.dart';
import '../../models/scaffold_page_config.dart';
import '../../models/super_conditional_config.dart';
import '../../models/super_layout_config.dart';
import '../../models/super_list_view_config.dart';
import '../../models/super_tab_config.dart';
import '../../models/super_table_config.dart';
import '../../models/super_tree_view_config.dart';

import 'appearance_codec.dart';
import '../../theme/appearance.dart';
import '../../theme/container_style.dart';

/// Catégorie de données sélectionnable lors d'un import ou d'un export JSON (Styles ou Dispositions).
enum TransferGroup {
  styles('Styles'),
  layouts('Dispositions');

  const TransferGroup(this.label);
  final String label;
}

/// Transfers generic groups through the application's injected codec.
class AppearanceTransfer {
  const AppearanceTransfer._();
  static const format = 'super_container_layout.appearance';
  static TransferGroup _groupOf(String key) =>
      key == 'components' || key == 'pageCatalog' || key == 'usages'
      ? TransferGroup.layouts
      : TransferGroup.styles;

  static String export(
    Appearance appearance,
    Set<TransferGroup> groups, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    if (groups.isEmpty) {
      throw ArgumentError.value(groups, 'groups', 'No groups selected.');
    }
    final rawCodecData = codec.toTransferJson(appearance)..remove('version');
    return const JsonEncoder.withIndent('  ').convert(
      JsonNumbers.normalizeMap({
        'format': codec.format,
        'version': codec.schemaVersion,
        'groups': [
          for (final group in TransferGroup.values)
            if (groups.contains(group)) group.name,
        ],
        'data': {
          for (final entry in rawCodecData.entries)
            if (groups.contains(_groupOf(entry.key))) entry.key: entry.value,
        },
      }),
    );
  }

  static ({Map<String, Object?> data, int version}) _document(
    String text,
    AppearanceCodec codec,
  ) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Le texte n’est pas un JSON valide.');
    }
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid appearance export.');
    }
    final isPatch =
        json['vibe'] == true || json['merge'] == true || json['mode'] == 'vibe';
    final version = json.containsKey('version')
        ? json['version']
        : (isPatch ? codec.schemaVersion : null);
    if (version is! int) throw const FormatException('Invalid export version.');
    if (json.containsKey('format')) {
      if ((json['format'] != codec.format &&
              json['format'] != AppearanceTransfer.format) ||
          json['data'] is! Map<String, dynamic>) {
        throw const FormatException(
          'Invalid appearance export format or data.',
        );
      }
      if (json.containsKey('groups')) {
        final groups = json['groups'];
        if (groups is! List ||
            groups.isEmpty ||
            groups.any((v) => !TransferGroup.values.any((g) => g.name == v))) {
          throw const FormatException('Invalid export groups.');
        }
      }
      return (
        data: codec.normalizeTransfer(
          json['data'] as Map<String, dynamic>,
          version,
        ),
        version: version,
      );
    }
    return (
      data: codec.normalizeTransfer({...json}..remove('version'), version),
      version: version,
    );
  }

  static Set<TransferGroup> groupsIn(
    String text, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    final data = _document(text, codec).data;
    final known = {...codec.toJson(codec.defaults).keys}..remove('version');
    final groups = <TransferGroup>{
      for (final key in data.keys)
        if (known.contains(key)) _groupOf(key),
    };
    if (groups.isEmpty) {
      throw const FormatException('No styles or layouts found.');
    }
    return groups;
  }

  static Appearance import(
    Appearance current,
    String text,
    Set<TransferGroup> groups, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    final selected = groups.intersection(groupsIn(text, codec: codec));
    if (selected.isEmpty) {
      throw const FormatException('No selected groups to import.');
    }
    final document = _document(text, codec);
    final dataMap = <String, dynamic>{
      for (final e in document.data.entries) e.key: e.value,
    };

    final isMerge =
        dataMap['vibe'] == true ||
        dataMap['merge'] == true ||
        dataMap['mode'] == 'vibe';
    if (isMerge) {
      final filtered = <String, dynamic>{
        for (final entry in dataMap.entries)
          if (entry.key == 'vibe' ||
              entry.key == 'merge' ||
              selected.contains(_groupOf(entry.key)))
            entry.key: entry.value,
      };
      final patched = codec.patchFromJson(current, filtered);
      final encoded = codec.encode(patched);
      final result = codec.decode(encoded);
      validateComponentRegions(result, previous: current);
      codec.restoreAdditional(encoded);
      return result;
    }

    final merged = codec.toJson(current);
    for (final entry in dataMap.entries) {
      if (entry.key == 'version' ||
          entry.key == 'vibe' ||
          entry.key == 'merge') {
        continue;
      }
      if (merged.containsKey(entry.key) &&
          selected.contains(_groupOf(entry.key))) {
        merged[entry.key] = codec.mergeTransferValue(
          entry.key,
          merged[entry.key],
          entry.value,
          document.version,
        );
      }
    }
    for (final key in codec.additionalKeys) {
      if (dataMap.containsKey(key) && selected.contains(_groupOf(key))) {
        merged[key] = dataMap[key];
      }
    }
    final documentText = jsonEncode(JsonNumbers.normalizeMap(merged));
    final result = codec.decode(documentText);
    validateComponentRegions(result, previous: current);
    codec.restoreAdditional(documentText);
    return result;
  }

  /// Valide les contraintes de régions des composants natifs (`Card`,
  /// `ApplicationBar`, `BottomAppBar`, `BottomNavigationBar`, `NavigationRail`,
  /// `Expansible`, `Menu`, `Scaffold`) et de `SuperTab` dynamique dans [next].
  ///
  /// Lorsque [previous] est fourni, seuls les composants ajoutés, modifiés ou
  /// nouvellement typés par rapport à [previous] sont vérifiés. Lève une
  /// [FormatException] explicite en cas de région inconnue, obligatoire
  /// désactivée ou monoenfant surchargée (`single: true`).
  static void validateComponentRegions(
    Appearance next, {
    Appearance? previous,
  }) {
    final violations = findComponentRegionViolations(next, previous: previous);
    if (violations.isNotEmpty) {
      throw FormatException(violations.values.first);
    }
  }

  /// Identifie tous les composants de [next] dont le contrat de régions est violé.
  ///
  /// Retourne une map `componentId -> message d'erreur` (vide lorsque tout est valide).
  static Map<String, String> findComponentRegionViolations(
    Appearance next, {
    Appearance? previous,
  }) {
    final violations = <String, String>{};
    final nextTypes = _collectPlacedSlotTypes(next);
    final previousTypes = previous == null
        ? const <String, String>{}
        : _collectPlacedSlotTypes(previous);
    final nextPageIds = {for (final page in next.pageCatalog.pages) page.id};
    final previousPageIds = previous == null
        ? const <String>{}
        : {for (final page in previous.pageCatalog.pages) page.id};

    for (final entry in next.components.entries) {
      final id = entry.key;
      final config = entry.value;
      final changed =
          previous == null ||
          previous.components[id] != config ||
          nextTypes[id] != previousTypes[id] ||
          (nextPageIds.contains(id) && !previousPageIds.contains(id));
      if (!changed) continue;

      if (config is SuperTabConfig) {
        if (config.mode == SuperTabMode.dynamic &&
            config.tabSlotIds.length > 1) {
          violations[id] =
              'Composant "$id" (SuperTab dynamique) : la région "tabs" '
              'n’accepte qu’un seul onglet gabarit maximum '
              '(${config.tabSlotIds.length} fournis : '
              '${config.tabSlotIds.join(', ')}).';
        }
        continue;
      }

      final NativeComponentConfig native;
      final String? kind;
      if (config is ScaffoldPageConfig) {
        native = config.native;
        kind = 'Scaffold';
      } else if (config is NativeComponentConfig) {
        native = config;
        kind = _resolveNativeKind(
          id: id,
          config: config,
          placedType: nextTypes[id] ?? previousTypes[id],
          previousConfig: previous?.components[id],
          pageIds: nextPageIds,
        );
      } else {
        continue;
      }

      if (kind == null) continue;
      final contract = _nativeRegionContracts[kind];
      if (contract == null) continue;

      final referencedRegions = <String>{
        ...native.placements.keys,
        ...native.regions.keys,
        ...native.regionAxes.keys,
        ...native.regionFlows.keys,
        ...native.regionSizes.keys,
      };
      var reported = false;
      for (final region in referencedRegions) {
        if (!contract.regions.contains(region)) {
          final allowed = contract.regions.map((r) => '"$r"').join(', ');
          violations[id] =
              'Composant "$id" ($kind) : région inconnue "$region" '
              '(régions autorisées : $allowed).';
          reported = true;
          break;
        }
      }
      if (reported) continue;
      for (final requiredRegion in contract.requiredRegions) {
        if (native.regions[requiredRegion] == false) {
          violations[id] =
              'Composant "$id" ($kind) : la région obligatoire '
              '"$requiredRegion" ne peut pas être désactivée.';
          reported = true;
          break;
        }
      }
      if (reported) continue;
      for (final singleRegion in contract.singleRegions) {
        final slots = native.slotsOf(singleRegion);
        if (slots.length > 1) {
          final hint = contract.singleHints[singleRegion];
          violations[id] =
              'Composant "$id" ($kind) : la région "$singleRegion" n’accepte '
              'qu’un seul enfant maximum (${slots.length} fournis : '
              '${slots.join(', ')}).${hint == null ? '' : ' $hint'}';
          break;
        }
      }
    }
    return violations;
  }

  /// Identifie les entrées de `styles` dans [next] qui ciblent un composant
  /// `Layout` (`SuperLayout`, type `"registry:Layout"`) dépourvu de surface visuelle.
  ///
  /// Lorsque [previous] est fourni, ne signale que les entrées ajoutées ou
  /// modifiées par rapport à [previous] (ou les composants dont le placement est
  /// devenu `registry:Layout` alors qu'un style non défaut existe déjà pour eux),
  /// ainsi que les identifiants explicitement listés dans [patchedStyleIds].
  /// Retourne une map `styleId -> message d'erreur` actionnable.
  static Map<String, String> findIneffectiveLayoutStyleViolations(
    Appearance next, {
    Appearance? previous,
    Set<String>? patchedStyleIds,
  }) {
    final placedInfo = _collectPlacedSlotInfo(next);
    final previousPlacedInfo = previous == null
        ? null
        : _collectPlacedSlotInfo(previous);
    final treeOrTableItemIds = <String>{
      for (final config in next.components.values)
        if (config is SuperTreeViewConfig && config.itemId != null)
          config.itemId!
        else if (config is SuperTableConfig && config.itemId != null)
          config.itemId!,
    };

    const surfaceTypes = <String>{
      'IterableContent',
      'Card',
      'ListView',
      'TreeView',
      'Table',
    };

    final candidateIds = <String>{
      ...?patchedStyleIds,
      for (final entry in next.styles.entries)
        if (previous == null ||
            previous.styles[entry.key] != entry.value ||
            placedInfo.shortTypes[entry.key] !=
                previousPlacedInfo?.shortTypes[entry.key])
          entry.key,
    };

    final violations = <String, String>{};
    for (final id in candidateIds) {
      if (id == 'background' || id.endsWith(':item')) continue;
      if (treeOrTableItemIds.contains(id)) continue;

      final style = next.styles[id];
      if (style == null || style == const ContainerStyle()) continue;

      final shortTypes = placedInfo.shortTypes[id] ?? const <String>{};
      if (shortTypes.any(surfaceTypes.contains)) continue;

      final isPlacedLayout = shortTypes.contains('Layout');
      final isUnplacedRootLayout =
          shortTypes.isEmpty && next.components[id] is SuperLayoutConfig;
      if (!isPlacedLayout && !isUnplacedRootLayout) continue;

      if (isUnplacedRootLayout && id == 'mainLayout') {
        violations[id] =
            'Style "$id" ignoré au rendu : "mainLayout" est un SuperLayout '
            'structurel sans surface visuelle. Utilise styles["background"] '
            'pour le fond global ou place une "registry:Card" / '
            '"registry:IterableContent" dans "mainLayout".';
      } else {
        final parents = placedInfo.parentIds[id] ?? const <String>[];
        final parentHint = parents.isEmpty
            ? 'son conteneur parent'
            : parents.map((p) => '"$p"').join(', ');
        violations[id] =
            'Style "$id" ignoré au rendu : "$id" est un composant '
            '"registry:Layout" purement structurel sans surface visuelle. '
            'Pour appliquer ce style (couleur, bordure, arrondi, paddingInsets), '
            'remplace son type de placement dans $parentHint par '
            '"registry:IterableContent" (en réémettant tous les placements de ce parent '
            'et en conservant "$id" en "type": "layout" dans "components"), '
            'ou enveloppe "$id" dans une "registry:Card".';
      }
    }
    return violations;
  }

  static ({
    Map<String, Set<String>> shortTypes,
    Map<String, List<String>> parentIds,
  })
  _collectPlacedSlotInfo(Appearance appearance) {
    final shortTypes = <String, Set<String>>{};
    final parentIds = <String, List<String>>{};

    void record(String parentId, Map<String, String> slotTypes) {
      for (final entry in slotTypes.entries) {
        final short = _canonicalSlotShortType(entry.value);
        if (short != null) {
          shortTypes.putIfAbsent(entry.key, () => <String>{}).add(short);
        }
        final parents = parentIds.putIfAbsent(entry.key, () => <String>[]);
        if (!parents.contains(parentId)) {
          parents.add(parentId);
        }
      }
    }

    for (final entry in appearance.components.entries) {
      final parentId = entry.key;
      final config = entry.value;
      switch (config) {
        case final SuperLayoutConfig layout:
          record(parentId, layout.slotTypes);
        case final SuperListViewConfig list:
          record(parentId, list.template.slotTypes);
        case final SuperTabConfig tab:
          record(parentId, tab.slotTypes);
        case final SuperConditionalConfig cond:
          record(parentId, cond.slotTypes);
        case final SuperTreeViewConfig tree:
          record(parentId, tree.slotTypes);
        case final SuperTableConfig table:
          record(parentId, table.slotTypes);
        case final NativeComponentConfig native:
          record(parentId, native.slotTypes);
        case final ScaffoldPageConfig scaffold:
          record(parentId, scaffold.native.slotTypes);
        default:
          break;
      }
    }
    return (shortTypes: shortTypes, parentIds: parentIds);
  }

  static String? _canonicalSlotShortType(String rawType) {
    var trimmed = rawType.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('component:')) {
      trimmed = 'registry:${trimmed.substring('component:'.length)}';
    } else if (trimmed.startsWith('factory:')) {
      trimmed = 'registry:${trimmed.substring('factory:'.length)}';
    }
    final normalized = JsonComponentType.normalize(trimmed);
    return JsonComponentType.shortName(normalized);
  }

  static const Map<String, _NativeRegionContract> _nativeRegionContracts = {
    'Card': _NativeRegionContract(
      regions: {'child'},
      requiredRegions: {'child'},
      singleRegions: {'child'},
      singleHints: {
        'child':
            'Place un seul enfant dans "child" (par exemple un '
            '"registry:Layout" contenant ces composants) ou utilise '
            '"registry:IterableContent".',
      },
    ),
    'ApplicationBar': _NativeRegionContract(
      regions: {'leading', 'title', 'actions', 'bottom', 'flexibleSpace'},
      singleRegions: {'leading', 'bottom', 'flexibleSpace'},
    ),
    'BottomAppBar': _NativeRegionContract(regions: {'left', 'center', 'right'}),
    'BottomNavigationBar': _NativeRegionContract(regions: {'destinations'}),
    'NavigationRail': _NativeRegionContract(regions: {'destinations'}),
    'Expansible': _NativeRegionContract(
      regions: {'header', 'body'},
      requiredRegions: {'header', 'body'},
    ),
    'Menu': _NativeRegionContract(
      regions: {'header', 'body'},
      requiredRegions: {'header', 'body'},
    ),
    'Scaffold': _NativeRegionContract(
      regions: {
        'appBar',
        'body',
        'drawer',
        'endDrawer',
        'bottomNavigationBar',
        'floatingActionButton',
        'bottomSheet',
      },
      requiredRegions: {'body'},
    ),
  };

  static Map<String, String> _collectPlacedSlotTypes(Appearance appearance) {
    final types = <String, String>{};
    for (final config in appearance.components.values) {
      final Map<String, String> slotTypes = switch (config) {
        final SuperLayoutConfig layout => layout.slotTypes,
        final SuperListViewConfig list => list.template.slotTypes,
        final SuperTabConfig tab => tab.slotTypes,
        final SuperConditionalConfig cond => cond.slotTypes,
        final SuperTreeViewConfig tree => tree.slotTypes,
        final SuperTableConfig table => table.slotTypes,
        final NativeComponentConfig native => native.slotTypes,
        final ScaffoldPageConfig scaffold => scaffold.native.slotTypes,
        _ => const <String, String>{},
      };
      for (final entry in slotTypes.entries) {
        types.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return types;
  }

  static bool _hasNativeRegionKey(
    NativeComponentConfig config,
    String region,
  ) =>
      config.placements.containsKey(region) ||
      config.regions.containsKey(region) ||
      config.regionAxes.containsKey(region) ||
      config.regionFlows.containsKey(region) ||
      config.regionSizes.containsKey(region);

  static String? _canonicalNativeKind(String rawType) {
    var trimmed = rawType.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('component:')) {
      trimmed = 'registry:${trimmed.substring('component:'.length)}';
    } else if (trimmed.startsWith('factory:')) {
      trimmed = 'registry:${trimmed.substring('factory:'.length)}';
    }
    final normalized = JsonComponentType.normalize(trimmed);
    final short = JsonComponentType.shortName(normalized);
    return _nativeRegionContracts.containsKey(short) ? short : null;
  }

  static String? _resolveNativeKind({
    required String id,
    required NativeComponentConfig config,
    required String? placedType,
    required ComponentConfig? previousConfig,
    required Set<String> pageIds,
  }) {
    if (placedType != null) {
      return _canonicalNativeKind(placedType);
    }
    if (pageIds.contains(id)) {
      return 'Scaffold';
    }
    if (_hasNativeRegionKey(config, 'child') ||
        (previousConfig is NativeComponentConfig &&
            _hasNativeRegionKey(previousConfig, 'child'))) {
      return 'Card';
    }
    if (id == 'root') {
      return 'Scaffold';
    }
    return null;
  }

  /// Applies an incremental GenUI-style surface update onto [current].
  ///
  /// Les propositions d'usages (`usages`) ne s'appliquent qu'aux composants
  /// sans liaison de données : lorsque la configuration résultante d'un
  /// composant référence une liaison ([ComponentConfig.referencedBindings]),
  /// son usage actuel est conservé tel quel (ajout, modification et
  /// suppression ignorés). Supprimer un composant retire toujours son usage.
  static Appearance applyVibe(
    Appearance current,
    String text, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Le texte n’est pas un JSON valide.');
    }
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid appearance export.');
    }
    return applyVibeMap(current, raw, codec: codec);
  }

  /// Applique directement un patch GenUI [raw] déjà décodé sur [current].
  ///
  /// Utilisé notamment pour le rendu incrémental en streaming afin d'éviter
  /// une sérialisation intermédiaire superflue à chaque palier du flux.
  static Appearance applyVibeMap(
    Appearance current,
    Map<String, dynamic> raw, {
    AppearanceCodec codec = const AppearanceCodec(),
    bool normalizeRoundTrip = true,
    bool logErrors = true,
  }) {
    final payload = raw['data'] is Map<String, dynamic>
        ? <String, dynamic>{
            ...(raw['data'] as Map<String, dynamic>),
            'merge': true,
          }
        : <String, dynamic>{...raw, 'merge': true};
    if (!normalizeRoundTrip) {
      final version = raw['version'] is int
          ? raw['version'] as int
          : codec.schemaVersion;
      final normalized = codec.normalizeTransfer(payload, version);
      final filtered = <String, dynamic>{
        for (final entry in normalized.entries)
          if (entry.key == 'vibe' ||
              entry.key == 'merge' ||
              _groupOf(entry.key) == TransferGroup.styles ||
              _groupOf(entry.key) == TransferGroup.layouts)
            entry.key: entry.value,
      };
      final patched = codec.patchFromJson(
        current,
        filtered,
        logErrors: logErrors,
      );
      final result = _keepBoundUsages(current, patched);
      validateComponentRegions(result, previous: current);
      return result;
    }
    final next = import(current, jsonEncode(payload), const {
      TransferGroup.styles,
      TransferGroup.layouts,
    }, codec: codec);
    return _keepBoundUsages(current, next);
  }

  /// Applique de manière tolérante chaque entrée valide d'un patch GenUI [raw] sur [current].
  ///
  /// Isole individuellement les entrées invalides (décodage JSON ou violations de contrats
  /// de régions Material) dans [PartialPatchResult.rejectedEntries] tout en conservant
  /// tous les autres composants, styles, comportements et usages valides.
  static PartialPatchResult applyVibeMapPartial(
    Appearance current,
    Map<String, dynamic> raw, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    final payload = raw['data'] is Map<String, dynamic>
        ? <String, dynamic>{
            ...(raw['data'] as Map<String, dynamic>),
            'merge': true,
          }
        : <String, dynamic>{...raw, 'merge': true};

    final filtered = <String, dynamic>{};
    final preRejected = <PatchRejectedEntry>[];
    final knownTransferKeys = {
      ...codec.toJson(codec.defaults).keys,
      'vibe',
      'merge',
    }..remove('version');

    for (final entry in payload.entries) {
      final key = entry.key;
      if (key == 'version') continue;
      if (!knownTransferKeys.contains(key)) {
        preRejected.add(
          PatchRejectedEntry(
            section: 'root',
            key: key,
            message: 'Unknown export preference: $key.',
            rawValue: entry.value,
          ),
        );
        continue;
      }
      if (key == 'vibe' ||
          key == 'merge' ||
          _groupOf(key) == TransferGroup.styles ||
          _groupOf(key) == TransferGroup.layouts) {
        filtered[key] = entry.value;
      }
    }

    final partial = codec.patchFromJsonPartial(current, filtered);
    var appearance = partial.appearance;
    final applied = Map<String, dynamic>.of(partial.appliedPatch);
    final rejected = <PatchRejectedEntry>[
      ...preRejected,
      ...partial.rejectedEntries,
    ];

    final rawComponents = filtered['components'] is Map
        ? filtered['components'] as Map
        : null;
    final violations = findComponentRegionViolations(
      appearance,
      previous: current,
    );
    if (violations.isNotEmpty) {
      final adjustedComponents = Map<String, ComponentConfig>.of(
        appearance.components,
      );
      final appliedComponents = applied['components'] is Map<String, Object?>
          ? Map<String, Object?>.of(
              applied['components'] as Map<String, Object?>,
            )
          : <String, Object?>{};

      for (final entry in violations.entries) {
        final id = entry.key;
        final previousConfig = current.components[id];
        if (previousConfig != null) {
          adjustedComponents[id] = previousConfig;
        } else {
          adjustedComponents.remove(id);
        }
        appliedComponents.remove(id);
        rejected.add(
          PatchRejectedEntry(
            section: 'components',
            key: id,
            message: entry.value,
            rawValue: rawComponents?[id],
          ),
        );
      }

      appearance = appearance.copyWith(components: adjustedComponents);
      // Si le changement d'un parent (slotTypes) provoque encore une violation sur un enfant inchangé :
      final residual = findComponentRegionViolations(
        appearance,
        previous: current,
      );
      if (residual.isNotEmpty) {
        for (final id in residual.keys) {
          adjustedComponents.remove(id);
          appliedComponents.remove(id);
        }
        appearance = appearance.copyWith(components: adjustedComponents);
      }

      if (appliedComponents.isEmpty) {
        applied.remove('components');
      } else {
        applied['components'] = appliedComponents;
      }
    }

    appearance = _keepBoundUsages(current, appearance);
    return PartialPatchResult(
      appearance: appearance,
      appliedPatch: applied,
      rejectedEntries: List<PatchRejectedEntry>.unmodifiable(rejected),
    );
  }

  /// Rétablit dans [next] l'usage de [current] de chaque composant lié à des
  /// données dont l'usage a changé.
  static Appearance _keepBoundUsages(Appearance current, Appearance next) {
    final usages = Map<String, ComponentUsage>.of(next.usages);
    var restored = false;
    for (final id in {...current.usages.keys, ...next.usages.keys}) {
      final before = current.usages[id];
      if (before == next.usages[id] ||
          (next.components[id]?.referencedBindings.isEmpty ?? true)) {
        continue;
      }
      restored = true;
      if (before == null) {
        usages.remove(id);
      } else {
        usages[id] = before;
      }
    }
    return restored ? next.copyWith(usages: usages) : next;
  }

  /// Exports the flat GenUI JSON representation for AI or transfer.
  static String exportAi(
    Appearance appearance, {
    Set<TransferGroup> groups = const {
      TransferGroup.styles,
      TransferGroup.layouts,
    },
    AppearanceCodec codec = const AppearanceCodec(),
  }) => export(appearance, groups, codec: codec);

  /// Exporte une représentation JSON GenUI plate, compacte et minifiée pour l'IA.
  ///
  /// Inclut les `usages` déclarés (groupe Dispositions) : l'IA s'en inspire et
  /// peut en proposer pour les composants sans liaison de données.
  static String exportCompactAi(
    Appearance appearance, {
    Set<TransferGroup> groups = const {
      TransferGroup.styles,
      TransferGroup.layouts,
    },
    AppearanceCodec codec = const AppearanceCodec(),
  }) {
    if (groups.isEmpty) {
      throw ArgumentError.value(groups, 'groups', 'No groups selected.');
    }
    final rawCompact = codec.toCompactJson(appearance)..remove('version');
    return jsonEncode(
      JsonNumbers.normalizeMap({
        for (final entry in rawCompact.entries)
          if (groups.contains(_groupOf(entry.key))) entry.key: entry.value,
      }),
    );
  }
}

class _NativeRegionContract {
  const _NativeRegionContract({
    required this.regions,
    this.requiredRegions = const <String>{},
    this.singleRegions = const <String>{},
    this.singleHints = const <String, String>{},
  });

  final Set<String> regions;
  final Set<String> requiredRegions;
  final Set<String> singleRegions;
  final Map<String, String> singleHints;
}

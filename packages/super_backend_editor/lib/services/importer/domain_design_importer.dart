/// Importateur de spécifications Design de domaines fonctionnels
/// ([DomainDesignImporter], [SpecForgeCatalogDomainSummary]) depuis un bundle
/// portable `.domain-design.json` ou directement depuis un espace de travail
/// `super_spec_forge` (`<workspace>/domains/catalog.json`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:super_schema_dsl/super_schema_dsl.dart';

import '../../models/domain_design_spec.dart';
import '../../models/json_value_utils.dart';
import 'catalog_json_schema_synthesizer.dart';

final RegExp _validDslIdentifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$');

const Set<String> _supportedContractDslTypes = <String>{
  'model',
  'part',
  'component',
  'createxdto',
  'updatexdto',
  'xresponsedto',
  'xlistitemdto',
  'xquerydto',
  'eventxpayloaddto',
  'eventxenvelopedto',
  'flatfile',
};

const Map<String, ImportedTechStackSummary> _builtinTechStackPresets =
    <String, ImportedTechStackSummary>{
      'stack_ts_nestjs': ImportedTechStackSummary(
        id: 'stack_ts_nestjs',
        code: 'ts-nestjs',
        name: 'TypeScript / NestJS',
        description:
            'Backend TypeScript 5 / Node.js LTS avec NestJS, domaine pur DDD '
            '(Neverthrow), persistance MongoDB/Mongoose et tests Vitest/Jest.',
      ),
    };

String _toPascalCaseAscii(String raw) {
  const accentMap = <String, String>{
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'æ': 'ae',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ñ': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'ö': 'o',
    'œ': 'oe',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ÿ': 'y',
    'À': 'A',
    'Á': 'A',
    'Â': 'A',
    'Ä': 'A',
    'Æ': 'Ae',
    'Ç': 'C',
    'È': 'E',
    'É': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'Î': 'I',
    'Ï': 'I',
    'Ô': 'O',
    'Ö': 'O',
    'Œ': 'Oe',
    'Ù': 'U',
    'Û': 'U',
    'Ü': 'U',
  };
  final folded = StringBuffer();
  for (final rune in raw.trim().runes) {
    final ch = String.fromCharCode(rune);
    folded.write(accentMap[ch] ?? ch);
  }
  final parts = folded
      .toString()
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((p) => p.isNotEmpty);
  final out = StringBuffer();
  for (final part in parts) {
    out.write(part[0].toUpperCase());
    if (part.length > 1) out.write(part.substring(1));
  }
  final result = out.toString();
  if (result.isEmpty) return 'Model';
  return RegExp(r'^[0-9]').hasMatch(result) ? 'M$result' : result;
}

String _technicalNameForDslEntry(String rawName) {
  final trimmed = rawName.trim();
  if (trimmed.isEmpty) return 'Model';
  return _validDslIdentifierPattern.hasMatch(trimmed)
      ? trimmed
      : _toPascalCaseAscii(trimmed);
}

/// Résumé léger d'un domaine fonctionnel découvert dans un catalogue
/// `super_spec_forge` (`<workspace>/domains/catalog.json`).
@immutable
class SpecForgeCatalogDomainSummary {
  /// Crée un résumé immuable de domaine issu d'un catalogue `super_spec_forge`.
  SpecForgeCatalogDomainSummary({
    required this.id,
    required this.domainCode,
    required this.name,
    this.description = '',
    this.isActive = true,
    this.modelsCount = 0,
    this.useCasesCount = 0,
    List<ImportedSnapshotMeta> snapshots = const <ImportedSnapshotMeta>[],
  }) : snapshots = List<ImportedSnapshotMeta>.unmodifiable(snapshots);

  /// Identifiant technique du domaine dans `super_spec_forge`.
  final String id;

  /// Code canonique du domaine en `kebab-case`.
  final String domainCode;

  /// Nom métier affiché du domaine.
  final String name;

  /// Description fonctionnelle du domaine.
  final String description;

  /// Indique si le domaine est actif.
  final bool isActive;

  /// Nombre de modèles persistants (`model`) déclarés à l'état courant.
  final int modelsCount;

  /// Nombre de Use Cases applicatifs déclarés à l'état courant.
  final int useCasesCount;

  /// Jalons d'itération (`iterationSnapshots`) disponibles pour ce domaine.
  final List<ImportedSnapshotMeta> snapshots;

  /// Vérifie les invariants du résumé de domaine.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('SpecForgeCatalogDomainSummary.id requis.');
    }
    if (domainCode.trim().isEmpty) {
      throw const FormatException(
        'SpecForgeCatalogDomainSummary.domainCode requis.',
      );
    }
    if (name.trim().isEmpty) {
      throw const FormatException('SpecForgeCatalogDomainSummary.name requis.');
    }
    if (modelsCount < 0 || useCasesCount < 0) {
      throw const FormatException(
        'Les compteurs de SpecForgeCatalogDomainSummary doivent être positifs.',
      );
    }
    for (final snapshot in snapshots) {
      snapshot.validate();
    }
  }

  /// Retourne une copie modifiée.
  SpecForgeCatalogDomainSummary copyWith({
    String? id,
    String? domainCode,
    String? name,
    String? description,
    bool? isActive,
    int? modelsCount,
    int? useCasesCount,
    List<ImportedSnapshotMeta>? snapshots,
  }) => SpecForgeCatalogDomainSummary(
    id: id ?? this.id,
    domainCode: domainCode ?? this.domainCode,
    name: name ?? this.name,
    description: description ?? this.description,
    isActive: isActive ?? this.isActive,
    modelsCount: modelsCount ?? this.modelsCount,
    useCasesCount: useCasesCount ?? this.useCasesCount,
    snapshots: snapshots ?? this.snapshots,
  );

  /// Sérialise ce résumé en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'domainCode': domainCode,
    'name': name,
    'description': description,
    'isActive': isActive,
    'modelsCount': modelsCount,
    'useCasesCount': useCasesCount,
    'snapshots': <Map<String, Object?>>[
      for (final snap in snapshots) snap.toJson(),
    ],
  };

  /// Désérialise un résumé depuis JSON.
  factory SpecForgeCatalogDomainSummary.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('SpecForgeCatalogDomainSummary invalide.');
    }
    int parseCount(Object? v) => switch (v) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s.trim()) ?? 0,
      _ => 0,
    };
    final code = (raw['domainCode'] as String?)?.trim() ?? '';
    final rawId = (raw['id'] as String?)?.trim() ?? '';
    final rawName = (raw['name'] as String?)?.trim() ?? '';
    final summary = SpecForgeCatalogDomainSummary(
      id: rawId.isNotEmpty ? rawId : code,
      domainCode: code,
      name: rawName.isNotEmpty ? rawName : code,
      description: (raw['description'] as String?) ?? '',
      isActive: raw['isActive'] as bool? ?? true,
      modelsCount: parseCount(raw['modelsCount']),
      useCasesCount: parseCount(raw['useCasesCount']),
      snapshots: <ImportedSnapshotMeta>[
        if (raw['snapshots'] case final List list)
          for (final item in list) ImportedSnapshotMeta.fromJson(item),
      ],
    );
    summary.validate();
    return summary;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpecForgeCatalogDomainSummary &&
          other.id == id &&
          other.domainCode == domainCode &&
          other.name == name &&
          other.description == description &&
          other.isActive == isActive &&
          other.modelsCount == modelsCount &&
          other.useCasesCount == useCasesCount &&
          listEquals(other.snapshots, snapshots);

  @override
  int get hashCode => Object.hash(
    id,
    domainCode,
    name,
    description,
    isActive,
    modelsCount,
    useCasesCount,
    Object.hashAll(snapshots),
  );
}

/// Service d'import de [DomainDesignSpec] depuis un bundle JSON portable ou un
/// espace de travail `super_spec_forge` (`domains/catalog.json`).
class DomainDesignImporter {
  /// Crée une instance sans état de l'importateur Design.
  const DomainDesignImporter();

  /// Identifiant de format du fichier `domains/catalog.json` de `super_spec_forge`.
  static const String specForgeCatalogFormat =
      'super_spec_forge.domain_catalog';

  /// Analyse une chaîne JSON de bundle `.domain-design.json` en [DomainDesignSpec].
  DomainDesignSpec parseBundleJsonString(String jsonContent) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonContent);
    } on FormatException catch (e) {
      throw FormatException(
        'Contenu JSON du bundle Design invalide : ${e.message}',
      );
    }
    if (decoded is! Map) {
      throw const FormatException(
        'Le bundle .domain-design.json doit avoir un objet JSON à la racine.',
      );
    }
    return parseBundleMap(freezeJsonMap(decoded));
  }

  /// Convertit et valide un objet JSON de bundle `.domain-design.json` en [DomainDesignSpec].
  DomainDesignSpec parseBundleMap(Map<String, Object?> raw) {
    final parsed = DomainDesignSpec.fromJson(raw);
    return _ensureSchemasSynthesizedIfMissing(parsed);
  }

  /// Charge et valide un fichier bundle `.domain-design.json` depuis le disque.
  Future<DomainDesignSpec> importFromBundleFile(File file) async {
    if (!await file.exists()) {
      throw FileSystemException('Fichier bundle Design introuvable', file.path);
    }
    final content = await file.readAsString();
    return parseBundleJsonString(content);
  }

  /// Inspecte un espace de travail `super_spec_forge` (`<dir>/domains/catalog.json`
  /// ou `<dir>/catalog.json`) et retourne les domaines disponibles avec leurs jalons.
  Future<List<SpecForgeCatalogDomainSummary>> inspectSpecForgeWorkspace(
    Directory workspaceOrDomainsDir,
  ) async {
    final catalogFile = await _resolveCatalogFile(workspaceOrDomainsDir);
    if (catalogFile == null) {
      return const <SpecForgeCatalogDomainSummary>[];
    }
    final rawMap = await _readCatalogMapFromFile(catalogFile);
    return inspectCatalogMap(rawMap);
  }

  /// Extrait les résumés de domaines et jalons depuis la structure JSON brute de `catalog.json`.
  List<SpecForgeCatalogDomainSummary> inspectCatalogMap(
    Map<String, Object?> catalogRaw,
  ) {
    final dataMap = _unwrapCatalogData(catalogRaw);
    final rawDomains = dataMap['domains'];
    if (rawDomains is! List || rawDomains.isEmpty) {
      return const <SpecForgeCatalogDomainSummary>[];
    }

    final summaries = <SpecForgeCatalogDomainSummary>[];
    for (final rawDom in rawDomains) {
      if (rawDom is! Map) continue;
      final domMap = freezeJsonMap(rawDom);
      final domainCode = (domMap['domainCode'] as String?)?.trim() ?? '';
      final rawId = (domMap['id'] as String?)?.trim() ?? '';
      if (domainCode.isEmpty && rawId.isEmpty) continue;
      final effectiveId = rawId.isNotEmpty ? rawId : domainCode;
      final effectiveCode = domainCode.isNotEmpty ? domainCode : effectiveId;
      final rawName = (domMap['name'] as String?)?.trim() ?? '';

      final modelsCount = _countModelsInRawContracts(domMap['contracts']);
      final orch = domMap['useCaseOrchestration'];
      final useCasesCount = (orch is Map && orch['useCases'] is List)
          ? (orch['useCases'] as List).length
          : 0;

      final snapshots = <ImportedSnapshotMeta>[];
      if (domMap['iterationSnapshots'] case final List rawSnaps) {
        for (final snap in rawSnaps) {
          if (snap is Map) {
            snapshots.add(ImportedSnapshotMeta.fromJson(snap));
          }
        }
      }

      final summary = SpecForgeCatalogDomainSummary(
        id: effectiveId,
        domainCode: effectiveCode,
        name: rawName.isNotEmpty ? rawName : effectiveCode,
        description: (domMap['description'] as String?) ?? '',
        isActive: domMap['isActive'] as bool? ?? true,
        modelsCount: modelsCount,
        useCasesCount: useCasesCount,
        snapshots: snapshots,
      );
      summary.validate();
      summaries.add(summary);
    }
    return List<SpecForgeCatalogDomainSummary>.unmodifiable(summaries);
  }

  /// Importe directement une [DomainDesignSpec] depuis le dossier d'un espace
  /// de travail `super_spec_forge` (`<workspaceDirectory>/domains/catalog.json`
  /// ou `<workspaceDirectory>/catalog.json`).
  Future<DomainDesignSpec> importFromSpecForgeWorkspace({
    required Directory workspaceDirectory,
    required String domainIdOrCode,
    String? snapshotId,
    DateTime? importedAt,
  }) async {
    final catalogFile = await _resolveCatalogFile(workspaceDirectory);
    if (catalogFile == null) {
      throw FileSystemException(
        'Fichier domains/catalog.json introuvable dans le workspace',
        workspaceDirectory.path,
      );
    }
    final rawMap = await _readCatalogMapFromFile(catalogFile);
    return importFromCatalogMap(
      rawMap,
      domainIdOrCode: domainIdOrCode,
      snapshotId: snapshotId,
      importedAt: importedAt,
    );
  }

  /// Convertit un domaine (état courant ou jalon [snapshotId]) issu d'une carte
  /// JSON brute `catalog.json` en [DomainDesignSpec] complète, en purgeant tout
  /// secret et en synthétisant les JSON Schemas Draft 2020-12.
  DomainDesignSpec importFromCatalogMap(
    Map<String, Object?> catalogRaw, {
    required String domainIdOrCode,
    String? snapshotId,
    DateTime? importedAt,
  }) {
    final needle = domainIdOrCode.trim();
    if (needle.isEmpty) {
      throw const FormatException('domainIdOrCode ne peut pas être vide.');
    }

    final dataMap = _unwrapCatalogData(catalogRaw);
    final domainMap = _findDomainMap(dataMap['domains'], needle);
    if (domainMap == null) {
      throw FormatException(
        'Domaine introuvable dans domains/catalog.json : « $needle ».',
      );
    }

    final cleanSnapshotId = snapshotId?.trim();
    final hasSnapshot = cleanSnapshotId != null && cleanSnapshotId.isNotEmpty;
    Map<String, Object?>? snapshotMap;
    ImportedSnapshotMeta? snapshotMeta;
    if (hasSnapshot) {
      snapshotMap = _findSnapshotMap(
        domainMap['iterationSnapshots'],
        cleanSnapshotId,
      );
      if (snapshotMap == null) {
        throw FormatException(
          'Snapshot « $cleanSnapshotId » introuvable dans le domaine « $needle ».',
        );
      }
      snapshotMeta = ImportedSnapshotMeta.fromJson(snapshotMap);
    }

    final domainId = (domainMap['id'] as String?)?.trim() ?? '';
    final domainCode = (domainMap['domainCode'] as String?)?.trim() ?? '';
    final effectiveDomainId = domainId.isNotEmpty ? domainId : domainCode;
    final rawDomainStackId = (domainMap['techStackId'] as String?)?.trim();
    final effectiveStackId =
        (rawDomainStackId != null && rawDomainStackId.isNotEmpty)
        ? rawDomainStackId
        : snapshotMeta?.techStackId;
    final resolvedTechStack = _resolveTechStackSummary(
      effectiveStackId,
      dataMap['techStacks'],
    );

    final identity = ImportedDomainIdentity(
      id: effectiveDomainId,
      domainCode: domainCode,
      name: (domainMap['name'] as String?)?.trim() ?? domainCode,
      description: (domainMap['description'] as String?) ?? '',
      isActive: domainMap['isActive'] as bool? ?? true,
      techStackId: effectiveStackId,
      techStack: resolvedTechStack,
    );

    final environments = _extractDomainEnvironments(
      dataMap['environments'],
      effectiveDomainId,
    );
    final systems = _extractDomainSystems(
      dataMap['microservices'] ?? dataMap['systems'],
      effectiveDomainId,
    );
    final configurations = _extractMaskedConfigurations(
      dataMap['configurationEntries'] ?? dataMap['configurations'],
      effectiveDomainId,
    );

    final strictObjects = _resolveStrictObjectsPreference(dataMap, domainMap);

    final (:resolvedVos, :fallbackSharedVos) = _resolveCatalogValueObjects(
      domainMap: domainMap,
      sharedValueObjectsRaw: dataMap['sharedValueObjects'],
      snapshotMap: snapshotMap,
    );

    final importedValueObjects = <ImportedValueObjectSpec>[
      for (final vo in resolvedVos)
        ImportedValueObjectSpec.fromJson(<String, Object?>{
          'id': vo.id,
          'scope': vo.scope,
          'spec': vo.spec,
          'jsonSchema': CatalogJsonSchemaSynthesizer.buildValueObjectSchema(
            voSpec: vo.spec,
            technicalName: vo.technicalName,
            scope: vo.scope,
            availableValueObjects: resolvedVos,
            fallbackValueObjects: fallbackSharedVos,
            strictObjects: strictObjects,
          ),
        }),
    ];

    final (:dslSource, :rawContracts) = snapshotMap != null
        ? _extractSnapshotContracts(snapshotMap)
        : _extractCurrentContracts(domainMap['contracts']);

    final importedContracts = <ImportedContractEntry>[
      for (final item in rawContracts)
        ImportedContractEntry(
          entryId: item.entryId,
          name: item.name,
          technicalName: item.technicalName,
          groupName: item.groupName,
          dslType: item.dslType,
          title: item.title,
          version: item.version,
          states: item.states,
          objectSpecJson: item.objectSpec,
          jsonSchema: CatalogJsonSchemaSynthesizer.buildContractObjectSchema(
            contract: item,
            allContracts: rawContracts,
            availableValueObjects: resolvedVos,
            fallbackValueObjects: fallbackSharedVos,
            strictObjects: strictObjects,
          ),
          domainLayerJson: item.domainLayer,
        ),
    ];

    final orchMap = domainMap['useCaseOrchestration'] is Map
        ? freezeJsonMap(domainMap['useCaseOrchestration'] as Map)
        : const <String, Object?>{};
    final cartography = freezeJsonMapList(orchMap['cartography']);
    final importedUseCases = _extractAndSynthesizeUseCases(
      orchMap: orchMap,
      snapshotMap: snapshotMap,
    );
    final importedSagas = _extractSagas(
      orchMap: orchMap,
      snapshotMap: snapshotMap,
    );

    final spec = DomainDesignSpec(
      exportedAt: (importedAt ?? DateTime.now()).toUtc(),
      sourceKind: hasSnapshot
          ? DesignSourceKind.snapshot
          : DesignSourceKind.workspaceCatalog,
      snapshotMeta: snapshotMeta,
      domain: identity,
      environments: environments,
      systems: systems,
      configurations: configurations,
      valueObjects: importedValueObjects,
      dslSource: dslSource,
      contractEntries: importedContracts,
      cartography: cartography,
      useCases: importedUseCases,
      sagas: importedSagas,
    );
    spec.validate();
    return spec;
  }

  static Future<File?> _resolveCatalogFile(Directory dir) async {
    final sep = Platform.pathSeparator;
    final directAsFile = File(dir.path);
    if (dir.path.toLowerCase().endsWith('.json') &&
        await directAsFile.exists()) {
      return directAsFile;
    }
    final nested = File('${dir.path}${sep}domains${sep}catalog.json');
    if (await nested.exists()) return nested;
    final flat = File('${dir.path}${sep}catalog.json');
    if (await flat.exists()) return flat;
    return null;
  }

  static Future<Map<String, Object?>> _readCatalogMapFromFile(File file) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException catch (e) {
      throw FormatException('JSON invalide dans ${file.path} : ${e.message}');
    }
    if (decoded is! Map) {
      throw FormatException('${file.path} doit contenir un objet JSON.');
    }
    return freezeJsonMap(decoded);
  }

  static Map<String, Object?> _unwrapCatalogData(
    Map<String, Object?> catalogRaw,
  ) {
    final format = (catalogRaw['format'] as String?)?.trim();
    if (format != null &&
        format.isNotEmpty &&
        format != specForgeCatalogFormat) {
      throw FormatException(
        'Format de catalogue super_spec_forge inconnu : $format '
        '(attendu : $specForgeCatalogFormat).',
      );
    }
    if (catalogRaw['data'] is Map) {
      return freezeJsonMap(catalogRaw['data'] as Map);
    }
    return freezeJsonMap(catalogRaw);
  }

  static Map<String, Object?>? _findDomainMap(
    Object? rawDomains,
    String needle,
  ) {
    if (rawDomains is! List) return null;
    for (final item in rawDomains) {
      if (item is! Map) continue;
      final id = (item['id'] as String?)?.trim() ?? '';
      final code = (item['domainCode'] as String?)?.trim() ?? '';
      if (id == needle || code == needle) {
        return freezeJsonMap(item);
      }
    }
    final lower = needle.toLowerCase();
    for (final item in rawDomains) {
      if (item is! Map) continue;
      final id = (item['id'] as String?)?.trim().toLowerCase() ?? '';
      final code = (item['domainCode'] as String?)?.trim().toLowerCase() ?? '';
      if (id == lower || code == lower) {
        return freezeJsonMap(item);
      }
    }
    return null;
  }

  static Map<String, Object?>? _findSnapshotMap(
    Object? rawSnapshots,
    String snapshotId,
  ) {
    if (rawSnapshots is! List) return null;
    for (final item in rawSnapshots) {
      if (item is! Map) continue;
      if ((item['id'] as String?)?.trim() == snapshotId) {
        return freezeJsonMap(item);
      }
    }
    return null;
  }

  static ImportedTechStackSummary? _resolveTechStackSummary(
    String? techStackId,
    Object? rawTechStacks,
  ) {
    if (techStackId == null || techStackId.isEmpty) return null;
    if (rawTechStacks is List) {
      for (final item in rawTechStacks) {
        if (item is! Map) continue;
        final id = (item['id'] as String?)?.trim() ?? '';
        final code = (item['code'] as String?)?.trim() ?? '';
        if (id == techStackId || code == techStackId) {
          return ImportedTechStackSummary.fromJson(item);
        }
      }
    }
    for (final preset in _builtinTechStackPresets.values) {
      if (preset.id == techStackId || preset.code == techStackId) {
        return preset;
      }
    }
    return null;
  }

  static List<ImportedEnvironmentSpec> _extractDomainEnvironments(
    Object? rawEnvs,
    String domainId,
  ) {
    if (rawEnvs is! List) return const <ImportedEnvironmentSpec>[];
    final out = <ImportedEnvironmentSpec>[];
    for (final item in rawEnvs) {
      if (item is! Map) continue;
      if ((item['domainId'] as String?)?.trim() != domainId) continue;
      out.add(ImportedEnvironmentSpec.fromJson(item));
    }
    return out;
  }

  static List<ImportedSystemSpec> _extractDomainSystems(
    Object? rawSystems,
    String domainId,
  ) {
    if (rawSystems is! List) return const <ImportedSystemSpec>[];
    final out = <ImportedSystemSpec>[];
    for (final item in rawSystems) {
      if (item is! Map) continue;
      if ((item['domainId'] as String?)?.trim() != domainId) continue;
      out.add(ImportedSystemSpec.fromJson(item));
    }
    return out;
  }

  static List<ImportedConfigurationSpec> _extractMaskedConfigurations(
    Object? rawConfigs,
    String domainId,
  ) {
    if (rawConfigs is! List) return const <ImportedConfigurationSpec>[];
    final out = <ImportedConfigurationSpec>[];
    for (final item in rawConfigs) {
      if (item is! Map) continue;
      if ((item['domainId'] as String?)?.trim() != domainId) continue;
      final rawType = (item['entryType'] as String?)?.trim();
      final isSecret = rawType == 'secret' || item['isSecret'] == true;
      // Retrait strict de `encryptedValue` et de toute `plainValue` secrète.
      final sanitized = <String, Object?>{
        'id': item['id'],
        'domainId': item['domainId'],
        'environmentId': item['environmentId'],
        if (item['microserviceId'] != null)
          'microserviceId': item['microserviceId'],
        'configKey': item['configKey'],
        'entryType': isSecret ? 'secret' : 'plainVariable',
        if (!isSecret) 'plainValue': item['plainValue']?.toString() ?? '',
        'isInitialized': item['isInitialized'] as bool? ?? true,
        'description': item['description'] ?? '',
      };
      out.add(ImportedConfigurationSpec.fromJson(sanitized));
    }
    return out;
  }

  static bool _resolveStrictObjectsPreference(
    Map<String, Object?> dataMap,
    Map<String, Object?> domainMap,
  ) {
    final prefs =
        domainMap['modelPreferences'] ??
        dataMap['businessObjectModelPreferences'] ??
        dataMap['modelPreferences'];
    if (prefs is Map) {
      final strictness = (prefs['schemaStrictness'] as String?)
          ?.trim()
          .toLowerCase();
      if (strictness == 'open' || strictness == 'permissive') {
        return false;
      }
    }
    return true;
  }

  static ({
    List<CatalogResolvedVoEntry> resolvedVos,
    List<CatalogResolvedVoEntry> fallbackSharedVos,
  })
  _resolveCatalogValueObjects({
    required Map<String, Object?> domainMap,
    required Object? sharedValueObjectsRaw,
    required Map<String, Object?>? snapshotMap,
  }) {
    if (snapshotMap != null) {
      final snapVos = <CatalogResolvedVoEntry>[];
      final rawSnapVos = snapshotMap['valueObjects'];
      final Iterable<Object?> items = switch (rawSnapVos) {
        Map m => m.values,
        List l => l,
        _ => const <Object?>[],
      };
      for (final item in items) {
        if (item is! Map) continue;
        final specMap = item['spec'] is Map
            ? freezeJsonMap(item['spec'] as Map)
            : freezeJsonMap(item);
        final rawScope =
            (item['scope'] as String?)?.trim().toLowerCase() ?? 'domain';
        final scope = rawScope.contains('shared') ? 'shared' : 'domain';
        final voEntry = _toResolvedVoEntry(
          specMap,
          scope: scope,
          explicitId: item['id'] as String?,
        );
        if (voEntry != null) snapVos.add(voEntry);
      }
      return (
        resolvedVos: snapVos,
        fallbackSharedVos: const <CatalogResolvedVoEntry>[],
      );
    }

    final resolved = <CatalogResolvedVoEntry>[];
    final fallbackShared = <CatalogResolvedVoEntry>[];
    final seenTechLower = <String>{};

    if (domainMap['valueObjects'] case final List domVos) {
      for (final rawVo in domVos) {
        if (rawVo is! Map) continue;
        final entry = _toResolvedVoEntry(freezeJsonMap(rawVo), scope: 'domain');
        if (entry != null) {
          seenTechLower.add(entry.technicalName.toLowerCase());
          resolved.add(entry);
        }
      }
    }

    if (sharedValueObjectsRaw case final List sharedVos) {
      for (final rawVo in sharedVos) {
        if (rawVo is! Map) continue;
        final entry = _toResolvedVoEntry(freezeJsonMap(rawVo), scope: 'shared');
        if (entry == null) continue;
        fallbackShared.add(entry);
        // Le domaine prime sur le Shared Kernel en cas d'homonyme insensible à la casse.
        if (seenTechLower.add(entry.technicalName.toLowerCase())) {
          resolved.add(entry);
        }
      }
    }

    return (resolvedVos: resolved, fallbackSharedVos: fallbackShared);
  }

  static CatalogResolvedVoEntry? _toResolvedVoEntry(
    Map<String, Object?> specMap, {
    required String scope,
    String? explicitId,
  }) {
    final rawTech = (specMap['technicalName'] as String?)?.trim() ?? '';
    final rawName = (specMap['name'] as String?)?.trim() ?? '';
    final rawId = (explicitId ?? (specMap['id'] as String?))?.trim() ?? '';
    if (rawTech.isEmpty && rawName.isEmpty && rawId.isEmpty) return null;
    final effectiveTech = rawTech.isNotEmpty
        ? rawTech
        : _toPascalCaseAscii(rawName.isNotEmpty ? rawName : rawId);
    final effectiveId = rawId.isNotEmpty
        ? rawId
        : 'vo_${effectiveTech.toLowerCase()}';
    return CatalogResolvedVoEntry(
      id: effectiveId,
      technicalName: effectiveTech,
      scope: scope,
      spec: specMap,
    );
  }

  static int _countModelsInRawContracts(Object? rawContracts) {
    if (rawContracts is! Map) return 0;
    if (rawContracts['entries'] case final List entries) {
      return entries
          .whereType<Map>()
          .where((e) => ((e['dslType'] ?? e['type']) ?? 'model') == 'model')
          .length;
    }
    if (rawContracts['nodes'] case final List groups) {
      var count = 0;
      for (final grp in groups) {
        if (grp is! Map || grp['children'] is! List) continue;
        for (final child in grp['children'] as List) {
          if (child is Map && child['type'] == 'model') {
            count++;
          }
        }
      }
      return count;
    }
    final source = (rawContracts['source'] as String?) ?? '';
    if (source.trim().isNotEmpty) {
      try {
        final parser = Yaml2JsonSchemasParser(
          externalTypes: _supportedContractDslTypes,
        );
        final parsed = parser.model('contracts', source);
        var count = 0;
        for (final grp in parsed.nodes) {
          for (final child in grp.children) {
            if (child.type == 'model') count++;
          }
        }
        return count;
      } on Object {
        return 0;
      }
    }
    return 0;
  }

  static ({String dslSource, List<CatalogRawContractItem> rawContracts})
  _extractCurrentContracts(Object? rawContracts) {
    if (rawContracts is! Map) {
      return (dslSource: '', rawContracts: const <CatalogRawContractItem>[]);
    }
    final contractsMap = freezeJsonMap(rawContracts);
    final dslSource =
        (contractsMap['source'] ?? contractsMap['dslSource']) as String? ?? '';
    final detailsMap = contractsMap['details'] is Map
        ? contractsMap['details'] as Map
        : const <Object?, Object?>{};
    final objectsMap = contractsMap['objects'] is Map
        ? contractsMap['objects'] as Map
        : const <Object?, Object?>{};
    final domainLayersMap = contractsMap['domainLayers'] is Map
        ? contractsMap['domainLayers'] as Map
        : const <Object?, Object?>{};

    final items = <CatalogRawContractItem>[];
    final rawNodes = contractsMap['nodes'];

    if (rawNodes is List) {
      for (final rawGroup in rawNodes) {
        if (rawGroup is! Map) continue;
        final groupName = (rawGroup['name'] as String?)?.trim() ?? 'models';
        final children = rawGroup['children'];
        if (children is! List) continue;
        for (final rawNode in children) {
          if (rawNode is! Map) continue;
          final entryId = (rawNode['id'] as String?)?.trim() ?? '';
          final nodeName = (rawNode['name'] as String?)?.trim() ?? '';
          final dslType = (rawNode['type'] as String?)?.trim() ?? 'model';
          if (entryId.isEmpty || nodeName.isEmpty) continue;
          items.add(
            _buildContractItemFromMaps(
              entryId: entryId,
              nodeName: nodeName,
              groupName: groupName.isEmpty ? 'models' : groupName,
              dslType: dslType.isEmpty ? 'model' : dslType,
              detailRaw: detailsMap[entryId],
              objectRaw: objectsMap[entryId],
              domainLayerRaw: domainLayersMap[entryId],
            ),
          );
        }
      }
    } else if (dslSource.trim().isNotEmpty) {
      final parser = Yaml2JsonSchemasParser(
        externalTypes: _supportedContractDslTypes,
      );
      final parsed = parser.model('contracts', dslSource);
      for (final group in parsed.nodes) {
        for (final node in group.children) {
          items.add(
            _buildContractItemFromMaps(
              entryId: node.id,
              nodeName: node.name,
              groupName: group.name,
              dslType: node.type,
              detailRaw: detailsMap[node.id] ?? detailsMap[node.path],
              objectRaw: objectsMap[node.id],
              domainLayerRaw: domainLayersMap[node.id],
            ),
          );
        }
      }
    }

    return (dslSource: dslSource, rawContracts: items);
  }

  static CatalogRawContractItem _buildContractItemFromMaps({
    required String entryId,
    required String nodeName,
    required String groupName,
    required String dslType,
    required Object? detailRaw,
    required Object? objectRaw,
    required Object? domainLayerRaw,
  }) {
    final detailMap = detailRaw is Map
        ? freezeJsonMap(detailRaw)
        : const <String, Object?>{};
    final title = (detailMap['title'] as String?) ?? '';
    final rawVersion = (detailMap['version'] as String?)?.trim() ?? '';
    final version = rawVersion.isEmpty ? '0.0.1' : rawVersion;

    final states = <String, String>{};
    if (detailMap['states'] case final Map rawStates) {
      for (final e in rawStates.entries) {
        if (e.value != null) {
          states['${e.key}'] = '${e.value}';
        }
      }
    }

    final technicalName = _technicalNameForDslEntry(nodeName);
    final effectiveObjName = title.trim().isNotEmpty ? title.trim() : nodeName;
    final baseObj = objectRaw is Map
        ? freezeJsonMap(objectRaw)
        : const <String, Object?>{};
    final rawObjId = (baseObj['id'] as String?)?.trim();
    final objectId = (rawObjId != null && rawObjId.isNotEmpty)
        ? rawObjId
        : entryId;

    final normalizedObjSpec = freezeJsonMap(<String, Object?>{
      ...baseObj,
      'id': objectId,
      'name': effectiveObjName,
      'technicalName': technicalName,
    });

    final domainLayer = domainLayerRaw is Map
        ? freezeJsonMap(domainLayerRaw)
        : const <String, Object?>{};

    return CatalogRawContractItem(
      entryId: entryId,
      objectId: objectId,
      name: nodeName,
      technicalName: technicalName,
      groupName: groupName,
      dslType: dslType,
      title: title,
      version: version,
      states: Map<String, String>.unmodifiable(states),
      objectSpec: normalizedObjSpec,
      domainLayer: domainLayer,
    );
  }

  static ({String dslSource, List<CatalogRawContractItem> rawContracts})
  _extractSnapshotContracts(Map<String, Object?> snapshotMap) {
    final rawModels = snapshotMap['models'];
    final Iterable<Object?> artifacts = switch (rawModels) {
      Map m => m.values,
      List l => l,
      _ => const <Object?>[],
    };

    final byGroup = <String, List<CatalogRawContractItem>>{};
    final items = <CatalogRawContractItem>[];

    for (final rawArt in artifacts) {
      if (rawArt is! Map) continue;
      final artMap = freezeJsonMap(rawArt);
      final entryId = (artMap['entryId'] as String?)?.trim() ?? '';
      final name = (artMap['name'] as String?)?.trim() ?? '';
      if (entryId.isEmpty || name.isEmpty) continue;
      final groupName = (artMap['groupName'] as String?)?.trim() ?? 'models';
      final dslType = (artMap['dslType'] as String?)?.trim() ?? 'model';
      final title = (artMap['title'] as String?) ?? '';
      final rawVersion = (artMap['version'] as String?)?.trim() ?? '';
      final objMap = artMap['objectSpec'] is Map
          ? freezeJsonMap(artMap['objectSpec'] as Map)
          : const <String, Object?>{};
      final rawTech = (objMap['technicalName'] as String?)?.trim() ?? '';
      final technicalName = rawTech.isNotEmpty
          ? rawTech
          : _technicalNameForDslEntry(name);
      final rawObjId = (objMap['id'] as String?)?.trim();
      final objectId = (rawObjId != null && rawObjId.isNotEmpty)
          ? rawObjId
          : entryId;
      final normalizedObj = freezeJsonMap(<String, Object?>{
        ...objMap,
        'id': objectId,
        'technicalName': technicalName,
      });
      final domainLayer = artMap['domainLayerSpec'] is Map
          ? freezeJsonMap(artMap['domainLayerSpec'] as Map)
          : (artMap['domainLayer'] is Map
                ? freezeJsonMap(artMap['domainLayer'] as Map)
                : const <String, Object?>{});

      final item = CatalogRawContractItem(
        entryId: entryId,
        objectId: objectId,
        name: name,
        technicalName: technicalName,
        groupName: groupName.isEmpty ? 'models' : groupName,
        dslType: dslType.isEmpty ? 'model' : dslType,
        title: title,
        version: rawVersion.isEmpty ? '0.0.1' : rawVersion,
        states: const <String, String>{},
        objectSpec: normalizedObj,
        domainLayer: domainLayer,
      );
      items.add(item);
      byGroup
          .putIfAbsent(item.groupName, () => <CatalogRawContractItem>[])
          .add(item);
    }

    if (items.isEmpty) {
      return (dslSource: '', rawContracts: const <CatalogRawContractItem>[]);
    }

    final sourceBuf = StringBuffer();
    for (final groupEntry in byGroup.entries) {
      sourceBuf.writeln('${groupEntry.key}:');
      for (final art in groupEntry.value) {
        sourceBuf.writeln('  ${art.name}: ${art.dslType}');
      }
    }
    return (dslSource: sourceBuf.toString(), rawContracts: items);
  }

  static List<ImportedUseCaseSpec> _extractAndSynthesizeUseCases({
    required Map<String, Object?> orchMap,
    required Map<String, Object?>? snapshotMap,
  }) {
    final Object? rawSource = snapshotMap != null
        ? snapshotMap['useCases']
        : orchMap['useCases'];
    final Iterable<Object?> items = switch (rawSource) {
      Map m => m.values,
      List l => l,
      _ => const <Object?>[],
    };

    final out = <ImportedUseCaseSpec>[];
    for (final rawUc in items) {
      if (rawUc is! Map) continue;
      final ucMap = freezeJsonMap(rawUc);
      final specMap = ucMap['spec'] is Map
          ? freezeJsonMap(ucMap['spec'] as Map)
          : ucMap;
      final rawName = (specMap['name'] as String?)?.trim() ?? '';
      final rawCode = (specMap['code'] as String?)?.trim() ?? '';
      final baseName = rawName.isNotEmpty
          ? rawName
          : (rawCode.isNotEmpty ? rawCode : 'UseCase');
      final businessGoal = (specMap['businessGoal'] as String?) ?? '';

      final inputSchema =
          ucMap['inputJsonSchema'] is Map &&
              (ucMap['inputJsonSchema'] as Map).isNotEmpty
          ? freezeJsonMap(ucMap['inputJsonSchema'] as Map)
          : CatalogJsonSchemaSynthesizer.buildUseCaseFieldsSchema(
              title: '${baseName}Input',
              rawFields: specMap['triggerInputs'],
              description: businessGoal,
            );
      final outputSchema =
          ucMap['outputJsonSchema'] is Map &&
              (ucMap['outputJsonSchema'] as Map).isNotEmpty
          ? freezeJsonMap(ucMap['outputJsonSchema'] as Map)
          : CatalogJsonSchemaSynthesizer.buildUseCaseFieldsSchema(
              title: '${baseName}Output',
              rawFields: specMap['outputs'],
            );

      out.add(
        ImportedUseCaseSpec.fromJson(<String, Object?>{
          'spec': specMap,
          'inputJsonSchema': inputSchema,
          'outputJsonSchema': outputSchema,
        }),
      );
    }
    return out;
  }

  static List<ImportedSagaSpec> _extractSagas({
    required Map<String, Object?> orchMap,
    required Map<String, Object?>? snapshotMap,
  }) {
    final Object? rawSource = snapshotMap != null
        ? snapshotMap['sagas']
        : orchMap['sagas'];
    final Iterable<Object?> items = switch (rawSource) {
      Map m => m.values,
      List l => l,
      _ => const <Object?>[],
    };
    final out = <ImportedSagaSpec>[];
    for (final rawSaga in items) {
      if (rawSaga is Map) {
        out.add(ImportedSagaSpec.fromJson(rawSaga));
      }
    }
    return out;
  }

  static DomainDesignSpec _ensureSchemasSynthesizedIfMissing(
    DomainDesignSpec spec,
  ) {
    final needsVoSynthesis = spec.valueObjects.any(
      (vo) => vo.jsonSchema.isEmpty && vo.specJson.isNotEmpty,
    );
    final needsContractSynthesis = spec.contractEntries.any(
      (c) => c.jsonSchema.isEmpty && c.objectSpecJson.isNotEmpty,
    );
    final needsUcSynthesis = spec.useCases.any(
      (uc) =>
          (uc.inputJsonSchema.isEmpty || uc.outputJsonSchema.isEmpty) &&
          uc.specJson.isNotEmpty,
    );
    if (!needsVoSynthesis && !needsContractSynthesis && !needsUcSynthesis) {
      return spec;
    }

    final resolvedVos = <CatalogResolvedVoEntry>[
      for (final vo in spec.valueObjects)
        CatalogResolvedVoEntry(
          id: vo.id,
          technicalName: vo.technicalName,
          scope: vo.scope,
          spec: vo.specJson,
        ),
    ];
    final rawContracts = <CatalogRawContractItem>[
      for (final c in spec.contractEntries)
        CatalogRawContractItem(
          entryId: c.entryId,
          objectId:
              (c.objectSpecJson['id'] as String?)?.trim().isNotEmpty == true
              ? (c.objectSpecJson['id'] as String).trim()
              : c.entryId,
          name: c.name,
          technicalName: c.technicalName,
          groupName: c.groupName,
          dslType: c.dslType,
          title: c.title,
          version: c.version,
          states: c.states,
          objectSpec: c.objectSpecJson,
          domainLayer: c.domainLayerJson,
        ),
    ];

    final updatedVos = needsVoSynthesis
        ? <ImportedValueObjectSpec>[
            for (final vo in spec.valueObjects)
              if (vo.jsonSchema.isEmpty && vo.specJson.isNotEmpty)
                vo.copyWith(
                  jsonSchema:
                      CatalogJsonSchemaSynthesizer.buildValueObjectSchema(
                        voSpec: vo.specJson,
                        technicalName: vo.technicalName,
                        scope: vo.scope,
                        availableValueObjects: resolvedVos,
                      ),
                )
              else
                vo,
          ]
        : spec.valueObjects;

    final updatedContracts = needsContractSynthesis
        ? <ImportedContractEntry>[
            for (var i = 0; i < spec.contractEntries.length; i++)
              if (spec.contractEntries[i].jsonSchema.isEmpty &&
                  spec.contractEntries[i].objectSpecJson.isNotEmpty)
                spec.contractEntries[i].copyWith(
                  jsonSchema:
                      CatalogJsonSchemaSynthesizer.buildContractObjectSchema(
                        contract: rawContracts[i],
                        allContracts: rawContracts,
                        availableValueObjects: resolvedVos,
                      ),
                )
              else
                spec.contractEntries[i],
          ]
        : spec.contractEntries;

    final updatedUseCases = needsUcSynthesis
        ? <ImportedUseCaseSpec>[
            for (final uc in spec.useCases)
              if ((uc.inputJsonSchema.isEmpty || uc.outputJsonSchema.isEmpty) &&
                  uc.specJson.isNotEmpty)
                uc.copyWith(
                  inputJsonSchema: uc.inputJsonSchema.isNotEmpty
                      ? uc.inputJsonSchema
                      : CatalogJsonSchemaSynthesizer.buildUseCaseFieldsSchema(
                          title: '${uc.name}Input',
                          rawFields: uc.specJson['triggerInputs'],
                          description: uc.businessGoal,
                        ),
                  outputJsonSchema: uc.outputJsonSchema.isNotEmpty
                      ? uc.outputJsonSchema
                      : CatalogJsonSchemaSynthesizer.buildUseCaseFieldsSchema(
                          title: '${uc.name}Output',
                          rawFields: uc.specJson['outputs'],
                        ),
                )
              else
                uc,
          ]
        : spec.useCases;

    return spec.copyWith(
      valueObjects: updatedVos,
      contractEntries: updatedContracts,
      useCases: updatedUseCases,
    );
  }
}

/// Modèles immuables d'analyse différentielle lors des ré-imports Design
/// incrémentaux ([DomainDesignDiff], [DesignDiffEntry]) et journal d'historique
/// des imports ([DomainImportHistoryRecord]).
library;

import 'package:flutter/foundation.dart';

import 'domain_design_spec.dart';
import 'json_value_utils.dart';

/// Nature du changement détecté entre deux versions d'un artefact Design.
enum DesignDiffChangeKind {
  /// Nouvel artefact absent de la version précédente.
  added('Ajouté'),

  /// Artefact existant dont la version ou le contenu a évolué.
  modified('Modifié'),

  /// Artefact supprimé de la nouvelle spécification Design.
  removed('Supprimé'),

  /// Artefact strictement identique.
  unchanged('Inchangé');

  const DesignDiffChangeKind(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise une nature de changement depuis JSON.
  static DesignDiffChangeKind fromJson(Object? raw) {
    if (raw is String) {
      for (final kind in DesignDiffChangeKind.values) {
        if (kind.name == raw.trim()) return kind;
      }
    }
    throw FormatException('Type de changement Design inconnu : $raw');
  }
}

/// Catégorie d'artefact concernée par une entrée de diff Design.
enum DesignDiffItemCategory {
  /// Identité et stack technique du domaine.
  domainMeta('Métadonnées du domaine'),

  /// Environnement logique.
  environment('Environnement'),

  /// Système, microservice ou application externe.
  system('Système / Service'),

  /// Variable de configuration ou secret déclaré.
  configuration('Configuration'),

  /// Value Object (`domain` ou `shared`).
  valueObject('Value Object'),

  /// Modèle métier ou contrat DTO / message.
  contract('Modèle / Contrat'),

  /// Use Case applicatif CQRS.
  useCase('Use Case CQRS'),

  /// Saga d'orchestration ou de chorégraphie.
  saga('Saga');

  const DesignDiffItemCategory(this.label);

  /// Libellé lisible en français.
  final String label;

  /// Désérialise une catégorie d'artefact depuis JSON.
  static DesignDiffItemCategory fromJson(Object? raw) {
    if (raw is String) {
      for (final cat in DesignDiffItemCategory.values) {
        if (cat.name == raw.trim()) return cat;
      }
    }
    throw FormatException('Catégorie de diff Design inconnue : $raw');
  }
}

/// Ligne unitaire d'un rapport de comparaison [DomainDesignDiff].
@immutable
class DesignDiffEntry {
  /// Crée une entrée immuable de diff Design.
  DesignDiffEntry({
    required this.category,
    required this.changeKind,
    required this.itemId,
    required this.itemName,
    this.previousVersion,
    this.nextVersion,
    List<String> details = const <String>[],
  }) : details = List<String>.unmodifiable(details);

  /// Catégorie d'artefact comparée.
  final DesignDiffItemCategory category;

  /// Nature du changement (`added`, `modified`, `removed`, `unchanged`).
  final DesignDiffChangeKind changeKind;

  /// Identifiant stable de l'artefact.
  final String itemId;

  /// Nom lisible ou technique de l'artefact.
  final String itemName;

  /// Version précédente éventuelle (`x.y.z`).
  final String? previousVersion;

  /// Nouvelle version éventuelle (`x.y.z`).
  final String? nextVersion;

  /// Détails lisibles des différences détectées.
  final List<String> details;

  /// Vérifie les invariants de l'entrée de diff.
  void validate() {
    if (itemId.trim().isEmpty) {
      throw const FormatException('DesignDiffEntry.itemId requis.');
    }
    if (itemName.trim().isEmpty) {
      throw const FormatException('DesignDiffEntry.itemName requis.');
    }
  }

  /// Retourne une copie modifiée.
  DesignDiffEntry copyWith({
    DesignDiffItemCategory? category,
    DesignDiffChangeKind? changeKind,
    String? itemId,
    String? itemName,
    String? previousVersion,
    bool clearPreviousVersion = false,
    String? nextVersion,
    bool clearNextVersion = false,
    List<String>? details,
  }) => DesignDiffEntry(
    category: category ?? this.category,
    changeKind: changeKind ?? this.changeKind,
    itemId: itemId ?? this.itemId,
    itemName: itemName ?? this.itemName,
    previousVersion: clearPreviousVersion
        ? null
        : (previousVersion ?? this.previousVersion),
    nextVersion: clearNextVersion ? null : (nextVersion ?? this.nextVersion),
    details: details ?? this.details,
  );

  /// Sérialise l'entrée de diff en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'category': category.name,
    'changeKind': changeKind.name,
    'itemId': itemId,
    'itemName': itemName,
    if (previousVersion != null && previousVersion!.trim().isNotEmpty)
      'previousVersion': previousVersion,
    if (nextVersion != null && nextVersion!.trim().isNotEmpty)
      'nextVersion': nextVersion,
    if (details.isNotEmpty) 'details': details,
  };

  /// Désérialise une entrée de diff depuis JSON.
  factory DesignDiffEntry.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DesignDiffEntry invalide.');
    }
    final prev = (raw['previousVersion'] as String?)?.trim();
    final next = (raw['nextVersion'] as String?)?.trim();
    final item = DesignDiffEntry(
      category: DesignDiffItemCategory.fromJson(raw['category']),
      changeKind: DesignDiffChangeKind.fromJson(raw['changeKind']),
      itemId: (raw['itemId'] as String?)?.trim() ?? '',
      itemName: (raw['itemName'] as String?)?.trim() ?? '',
      previousVersion: (prev == null || prev.isEmpty) ? null : prev,
      nextVersion: (next == null || next.isEmpty) ? null : next,
      details: parseCleanStringList(raw['details']),
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesignDiffEntry &&
          other.category == category &&
          other.changeKind == changeKind &&
          other.itemId == itemId &&
          other.itemName == itemName &&
          other.previousVersion == previousVersion &&
          other.nextVersion == nextVersion &&
          listEquals(other.details, details);

  @override
  int get hashCode => Object.hash(
    category,
    changeKind,
    itemId,
    itemName,
    previousVersion,
    nextVersion,
    Object.hashAll(details),
  );
}

/// Rapport complet de comparaison entre deux versions d'une [DomainDesignSpec].
@immutable
class DomainDesignDiff {
  /// Crée un rapport de diff Design immuable.
  DomainDesignDiff({
    required this.domainCode,
    DateTime? computedAt,
    List<DesignDiffEntry> entries = const <DesignDiffEntry>[],
  }) : computedAt = (computedAt ??
               DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
           .toUtc(),
       entries = List<DesignDiffEntry>.unmodifiable(entries);

  /// Code canonique du domaine comparé.
  final String domainCode;

  /// Horodatage UTC du calcul différentiel.
  final DateTime computedAt;

  /// Entrées détaillées du rapport différentiel.
  final List<DesignDiffEntry> entries;

  /// Vrai si au moins une entrée n'est pas [DesignDiffChangeKind.unchanged].
  bool get hasChanges =>
      entries.any((e) => e.changeKind != DesignDiffChangeKind.unchanged);

  /// Nombre d'éléments ajoutés.
  int get addedCount =>
      entries.where((e) => e.changeKind == DesignDiffChangeKind.added).length;

  /// Nombre d'éléments modifiés.
  int get modifiedCount => entries
      .where((e) => e.changeKind == DesignDiffChangeKind.modified)
      .length;

  /// Nombre d'éléments supprimés.
  int get removedCount =>
      entries.where((e) => e.changeKind == DesignDiffChangeKind.removed).length;

  /// Nombre d'éléments inchangés.
  int get unchangedCount => entries
      .where((e) => e.changeKind == DesignDiffChangeKind.unchanged)
      .length;

  /// Retourne les entrées appartenant à [category] (avec filtrage optionnel des inchangés).
  List<DesignDiffEntry> entriesForCategory(
    DesignDiffItemCategory category, {
    bool excludeUnchanged = false,
  }) => entries
      .where(
        (e) =>
            e.category == category &&
            (!excludeUnchanged ||
                e.changeKind != DesignDiffChangeKind.unchanged),
      )
      .toList(growable: false);

  /// Vérifie les invariants du rapport différentiel.
  void validate() {
    if (domainCode.trim().isEmpty) {
      throw const FormatException('DomainDesignDiff.domainCode requis.');
    }
    for (final entry in entries) {
      entry.validate();
    }
  }

  /// Retourne une copie modifiée.
  DomainDesignDiff copyWith({
    String? domainCode,
    DateTime? computedAt,
    List<DesignDiffEntry>? entries,
  }) => DomainDesignDiff(
    domainCode: domainCode ?? this.domainCode,
    computedAt: computedAt ?? this.computedAt,
    entries: entries ?? this.entries,
  );

  /// Sérialise le rapport différentiel en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'domainCode': domainCode,
    'computedAt': computedAt.toUtc().toIso8601String(),
    'entries': <Map<String, Object?>>[
      for (final entry in entries) entry.toJson(),
    ],
  };

  /// Désérialise un rapport différentiel depuis JSON.
  factory DomainDesignDiff.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainDesignDiff invalide.');
    }
    final diff = DomainDesignDiff(
      domainCode: (raw['domainCode'] as String?)?.trim() ?? '',
      computedAt: parseUtcDateTimeOrEpoch(raw['computedAt']),
      entries: <DesignDiffEntry>[
        if (raw['entries'] case final List list)
          for (final item in list) DesignDiffEntry.fromJson(item),
      ],
    );
    diff.validate();
    return diff;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainDesignDiff &&
          other.domainCode == domainCode &&
          other.computedAt == computedAt &&
          listEquals(other.entries, entries);

  @override
  int get hashCode =>
      Object.hash(domainCode, computedAt, Object.hashAll(entries));
}

/// Enregistrement immuable consigné dans `import_history.json` à chaque import ou ré-import Design.
@immutable
class DomainImportHistoryRecord {
  /// Crée un enregistrement d'historique d'import immuable.
  DomainImportHistoryRecord({
    required this.id,
    DateTime? importedAt,
    this.sourceKind = DesignSourceKind.current,
    required this.sourceLabel,
    this.snapshotIteration,
    this.addedCount = 0,
    this.modifiedCount = 0,
    this.removedCount = 0,
    this.notes = '',
  }) : importedAt = (importedAt ??
               DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
           .toUtc();

  /// Identifiant unique de l'événement d'import.
  final String id;

  /// Horodatage UTC de l'import.
  final DateTime importedAt;

  /// Nature de la source importée (`current`, `snapshot`, `workspaceCatalog`).
  final DesignSourceKind sourceKind;

  /// Libellé lisible de la source (chemin de fichier, nom du jalon, workspace).
  final String sourceLabel;

  /// Numéro d'itération du snapshot le cas échéant.
  final int? snapshotIteration;

  /// Nombre d'éléments ajoutés lors de cet import.
  final int addedCount;

  /// Nombre d'éléments modifiés lors de cet import.
  final int modifiedCount;

  /// Nombre d'éléments supprimés lors de cet import.
  final int removedCount;

  /// Notes libres associées à l'import.
  final String notes;

  /// Vérifie les invariants de l'enregistrement d'historique.
  void validate() {
    if (id.trim().isEmpty) {
      throw const FormatException('DomainImportHistoryRecord.id requis.');
    }
    if (sourceLabel.trim().isEmpty) {
      throw const FormatException(
        'DomainImportHistoryRecord.sourceLabel requis.',
      );
    }
    if (snapshotIteration != null && snapshotIteration! < 1) {
      throw const FormatException(
        'DomainImportHistoryRecord.snapshotIteration doit être >= 1.',
      );
    }
    if (addedCount < 0 || modifiedCount < 0 || removedCount < 0) {
      throw const FormatException(
        'Les compteurs de diff d’un import ne peuvent pas être négatifs.',
      );
    }
  }

  /// Retourne une copie modifiée.
  DomainImportHistoryRecord copyWith({
    String? id,
    DateTime? importedAt,
    DesignSourceKind? sourceKind,
    String? sourceLabel,
    int? snapshotIteration,
    bool clearSnapshotIteration = false,
    int? addedCount,
    int? modifiedCount,
    int? removedCount,
    String? notes,
  }) => DomainImportHistoryRecord(
    id: id ?? this.id,
    importedAt: importedAt ?? this.importedAt,
    sourceKind: sourceKind ?? this.sourceKind,
    sourceLabel: sourceLabel ?? this.sourceLabel,
    snapshotIteration: clearSnapshotIteration
        ? null
        : (snapshotIteration ?? this.snapshotIteration),
    addedCount: addedCount ?? this.addedCount,
    modifiedCount: modifiedCount ?? this.modifiedCount,
    removedCount: removedCount ?? this.removedCount,
    notes: notes ?? this.notes,
  );

  /// Sérialise l'enregistrement en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'importedAt': importedAt.toUtc().toIso8601String(),
    'sourceKind': sourceKind.name,
    'sourceLabel': sourceLabel,
    if (snapshotIteration != null) 'snapshotIteration': snapshotIteration,
    'addedCount': addedCount,
    'modifiedCount': modifiedCount,
    'removedCount': removedCount,
    if (notes.isNotEmpty) 'notes': notes,
  };

  /// Désérialise un enregistrement d'historique depuis JSON.
  factory DomainImportHistoryRecord.fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('DomainImportHistoryRecord invalide.');
    }
    int parseCount(Object? v) => switch (v) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s.trim()) ?? 0,
      _ => 0,
    };

    final rawSnapIter = raw['snapshotIteration'];
    final parsedSnapIter = switch (rawSnapIter) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s.trim()),
      _ => null,
    };

    final item = DomainImportHistoryRecord(
      id: (raw['id'] as String?)?.trim() ?? '',
      importedAt: parseUtcDateTimeOrEpoch(raw['importedAt']),
      sourceKind: DesignSourceKind.fromJson(raw['sourceKind']),
      sourceLabel: (raw['sourceLabel'] as String?)?.trim() ?? '',
      snapshotIteration: parsedSnapIter,
      addedCount: parseCount(raw['addedCount']),
      modifiedCount: parseCount(raw['modifiedCount']),
      removedCount: parseCount(raw['removedCount']),
      notes: (raw['notes'] as String?) ?? '',
    );
    item.validate();
    return item;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainImportHistoryRecord &&
          other.id == id &&
          other.importedAt == importedAt &&
          other.sourceKind == sourceKind &&
          other.sourceLabel == sourceLabel &&
          other.snapshotIteration == snapshotIteration &&
          other.addedCount == addedCount &&
          other.modifiedCount == modifiedCount &&
          other.removedCount == removedCount &&
          other.notes == notes;

  @override
  int get hashCode => Object.hash(
    id,
    importedAt,
    sourceKind,
    sourceLabel,
    snapshotIteration,
    addedCount,
    modifiedCount,
    removedCount,
    notes,
  );
}

/// États d'avancement ([ContractStatus]) et étapes du cycle de vie ([ContractStage])
/// partagés par les contrats, Value Objects, Use Cases et Sagas.
library;

/// Avancement d'une étape d'un artefact de conception.
enum ContractStatus {
  /// Étape non démarrée.
  pending,

  /// Étape en cours de réalisation.
  inProgress,

  /// Étape finalisée.
  done,
}

/// Retourne le statut suivant dans le cycle `À faire → En cours → Terminé → À faire`.
ContractStatus nextContractStatus(ContractStatus? current) => switch (current) {
  null || ContractStatus.pending => ContractStatus.inProgress,
  ContractStatus.inProgress => ContractStatus.done,
  ContractStatus.done => ContractStatus.pending,
};

/// Étapes représentées par les quatre indicateurs d'avancement.
enum ContractStage {
  /// Conception fonctionnelle et structurelle.
  design,

  /// Validation métier et règles de cohérence.
  validation,

  /// Génération ou implémentation du code.
  code,

  /// Livraison et intégration.
  delivery,
}

/// Sérialise une table d'états d'avancement en objet JSON (`stage -> status`).
Map<String, String> contractStatesToJson(
  Map<ContractStage, ContractStatus> states,
) => <String, String>{
  for (final entry in states.entries) entry.key.name: entry.value.name,
};

/// Désérialise une table d'états d'avancement depuis un objet JSON.
///
/// Lorsque [strict] vaut `true`, toute structure non-objet ou toute clé/valeur
/// d'énumération inconnue lève une [FormatException]. Lorsque [strict] vaut
/// `false`, les valeurs absentes ou inconnues sont ignorées sans erreur.
Map<ContractStage, ContractStatus> parseContractStatesJson(
  Object? raw, {
  bool strict = false,
}) {
  if (raw is! Map) {
    if (strict) {
      throw const FormatException('État de contrat invalide.');
    }
    return const <ContractStage, ContractStatus>{};
  }
  final parsed = <ContractStage, ContractStatus>{};
  for (final entry in raw.entries) {
    final stage = ContractStage.values
        .where((s) => s.name == entry.key)
        .firstOrNull;
    final status = ContractStatus.values
        .where((s) => s.name == entry.value)
        .firstOrNull;
    if (stage == null || status == null) {
      if (strict) {
        throw const FormatException('État de contrat invalide.');
      }
      continue;
    }
    parsed[stage] = status;
  }
  if (parsed.isEmpty) {
    return const <ContractStage, ContractStatus>{};
  }
  return Map<ContractStage, ContractStatus>.unmodifiable(parsed);
}

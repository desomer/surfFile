/// Sections Markdown partagées entre les différents générateurs de prompts IA
/// (contexte du domaine et couche Domain).
library;

import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../../models/business_object_spec.dart';
import '../../../models/company_glossary.dart';
import '../../../models/domain_catalog.dart';
import '../../../models/domain_layer_spec.dart';
import '../../../models/value_object_spec.dart';
import 'prompt_generator_models.dart';

/// Écrit les blocs Markdown réutilisés par plusieurs types de prompts.
abstract final class PromptMarkdownSections {
  /// Rédige la section « Contexte du Domaine Fonctionnel ».
  static void writeDomainContextSection(
    StringBuffer buf,
    FunctionalDomain domain,
    CompanyGlossary? glossary,
    BusinessObjectModelPreferences? modelPreferences,
  ) {
    buf
      ..writeln('## 2. Contexte du Domaine Fonctionnel')
      ..writeln('- **Domaine** : ${domain.name} (`${domain.domainCode}`)');
    if (domain.description.trim().isNotEmpty) {
      buf.writeln(
        '- **Responsabilité du domaine** : ${domain.description.trim()}',
      );
    }
    if (glossary != null && glossary.terms.isNotEmpty) {
      final sample = glossary.terms.take(15).toList(growable: false);
      buf.writeln('- **Glossaire d’entreprise (extrait pertinent)** :');
      for (final t in sample) {
        buf.writeln(
          '  - **${t.term}**${t.definition.trim().isEmpty ? '' : ' : ${t.definition.trim()}'}',
        );
      }
    }
    if (modelPreferences != null) {
      buf.writeln('- **Conventions de modélisation** :');
      for (final line in modelPreferences.toPromptDirective().split('\n')) {
        if (line.trim().isNotEmpty) {
          buf.writeln('  ${line.trim()}');
        }
      }
    }
    buf.writeln();
  }

  /// Rédige les comportements hexagonaux détaillés d'un objet métier.
  static void writeDomainLayerBehaviorsSection(
    StringBuffer buf,
    BusinessObjectSpec objectSpec,
    HexagonalDomainLayerSpec layerSpec,
  ) {
    buf.writeln(
      '## 4. Comportements de la Couche Domain (Architecture Hexagonale)',
    );
    if (layerSpec.isEmpty) {
      buf
        ..writeln(
          '_Aucun comportement détaillé additionnel dans la fiche Couche Domain : implémente l’encapsulation métier, la validation des attributs/états et l’égalité structurelle adaptées à `${objectSpec.technicalName}`._',
        )
        ..writeln();
      return;
    }

    if (layerSpec.invariants.isNotEmpty) {
      buf.writeln('### 4.1 Invariants (`Invariants`)');
      for (final inv in layerSpec.invariants) {
        buf.writeln(
          '- **${inv.code.isEmpty ? inv.title : '${inv.code} · ${inv.title}'}**'
          '${inv.expression.isEmpty ? '' : ' — `${inv.expression}`'}'
          '${inv.violationError.isEmpty ? '' : ' (erreur : `${inv.violationError}`)'}',
        );
        for (final r in inv.rules) {
          buf.writeln('  - $r');
        }
      }
      buf.writeln();
    }

    if (layerSpec.factories.isNotEmpty) {
      buf.writeln('### 4.2 Fabriques Métier (`Factory`)');
      for (final f in layerSpec.factories) {
        buf.writeln(
          '- `${f.effectiveMethodSignature}` — ${f.effectiveTitle}'
          '${f.initialState.isEmpty ? '' : ' (état initial : `${f.initialState}`)'}'
          '${f.emittedEvents.isEmpty ? '' : ' → émet ${f.emittedEvents.map((e) => '`$e`').join(', ')}'}',
        );
        for (final r in f.effectiveRules) {
          buf.writeln('  - $r');
        }
      }
      buf.writeln();
    }

    if (layerSpec.stateChanges.isNotEmpty) {
      buf.writeln('### 4.3 Mutations d’État (`State changing`)');
      for (final sc in layerSpec.stateChanges) {
        buf.writeln(
          '- `${sc.effectiveMethodSignature}` — ${sc.effectiveTitle}'
          '${sc.emittedEvents.isEmpty ? '' : ' → émet ${sc.emittedEvents.map((e) => '`$e`').join(', ')}'}'
          '${sc.domainErrors.isEmpty ? '' : ' (erreurs : ${sc.domainErrors.join(', ')})'}',
        );
        for (final r in sc.effectiveRules) {
          buf.writeln('  - $r');
        }
      }
      buf.writeln();
    }

    if (layerSpec.queries.isNotEmpty) {
      buf.writeln('### 4.4 Calculs & Prédicats Purs (`Query`)');
      for (final q in layerSpec.queries) {
        buf.writeln(
          '- `${q.name}(${q.parameters.join(', ')}) -> ${q.returnType}` — ${q.title.isEmpty ? q.name : q.title}'
          '${q.formula.isEmpty ? '' : ' (`${q.formula}`)'}',
        );
        for (final r in q.rules) {
          buf.writeln('  - $r');
        }
      }
      buf.writeln();
    }

    if (layerSpec.policyServices.isNotEmpty) {
      buf.writeln('### 4.5 Politiques & Services Métier (`Policy Services`)');
      for (final p in layerSpec.policyServices) {
        buf.writeln('- `${p.effectiveMethodSignature}` — ${p.effectiveTitle}');
        for (final r in p.effectiveRules) {
          buf.writeln('  - $r');
        }
      }
      buf.writeln();
    }

    if (layerSpec.domainEvents.isNotEmpty) {
      buf.writeln('### 4.6 Événements du Domaine (`Domain events`)');
      for (final evt in layerSpec.domainEvents) {
        buf.writeln(
          '- **${evt.name}** (${evt.effectiveTitle})'
          '${evt.trigger.isEmpty ? '' : ' — déclenché par `${evt.trigger}`'}'
          '${evt.payloadFields.isEmpty ? '' : ' · payload : `${evt.payloadFields.join(', ')}`'}',
        );
      }
      buf.writeln();
    }
  }

  /// Rédige la spécification des Value Objects (Architecture Hexagonale)
  /// référencés par un modèle pour le prompt d'implémentation Domain.
  static void writeReferencedValueObjectsSection(
    StringBuffer buf,
    List<ResolvedValueObject> valueObjects, {
    String heading = '### 3.3 Value Objects Référencés (Architecture Hexagonale)',
  }) {
    if (valueObjects.isEmpty) return;
    buf
      ..writeln(heading)
      ..writeln(
        'Chaque Value Object ci-dessous DOIT être implémenté en objet immuable auto-validé (factory `create()`, égalité structurelle `equals()`) dans le dossier `value-objects/` (ou importé du Shared Kernel si portée `Shared Kernel`) :',
      )
      ..writeln();

    for (final item in valueObjects) {
      final vo = item.spec;
      buf.writeln(
        '- **`${vo.technicalName}`** (${vo.name} · ${vo.kind.label} · portée : `${item.scope.label}` · v${vo.version})',
      );
      if (vo.description.isNotEmpty) {
        buf.writeln('  - Rôle : ${vo.description}');
      }
      if (vo.isScalar) {
        final summary = vo.schemaConstraints.formatSummary();
        buf.writeln(
          '  - Primitif encapsulé : `${vo.primitiveType.dslKeyword}`'
          '${summary.isEmpty ? '' : ' · contraintes JSON Schema : $summary'}',
        );
        if (vo.enumValues.isNotEmpty) {
          buf.writeln('  - Valeurs autorisées : `${vo.enumValues.join('`, `')}`');
        }
        if (vo.normalizationRules.isNotEmpty) {
          buf.writeln(
            '  - Normalisation avant validation : `${vo.normalizationRules.join('`, `')}`',
          );
        }
      } else {
        buf.writeln('  - Champs immuables :');
        for (final f in vo.fields) {
          final typeStr = f.type == BusinessAttributeType.valueObject
              ? 'VO:${f.valueObjectId}'
              : f.type.dslKeyword;
          buf.writeln(
            '    - `${f.name}` (`$typeStr`${f.required ? ', requis' : ''})'
            '${f.description.isEmpty ? '' : ' — ${f.description}'}',
          );
        }
        if (vo.crossFieldRules.isNotEmpty) {
          buf.writeln(
            '  - Règles inter-champs : ${vo.crossFieldRules.join(' ; ')}',
          );
        }
      }
      if (vo.constraints.isNotEmpty) {
        buf.writeln('  - Invariants : ${vo.constraints}');
      }
      if (vo.validExamples.isNotEmpty) {
        buf.writeln(
          '  - Exemples valides : ${vo.validExamples.map((e) => '`${e.value}`').join(', ')}',
        );
      }
      if (vo.invalidExamples.isNotEmpty) {
        buf.writeln(
          '  - Contre-exemples à rejeter : ${vo.invalidExamples.map((e) => '`${e.value}`${e.reason.isEmpty ? '' : ' (${e.reason})'}').join(' ; ')}',
        );
      }
    }
    buf.writeln();
  }

  /// Rédige la matrice de tests unitaires TDD pour les Value Objects référencés.
  static void writeReferencedValueObjectsTddSection(
    StringBuffer buf,
    List<ResolvedValueObject> valueObjects,
  ) {
    if (valueObjects.isEmpty) return;
    buf
      ..writeln('\n### 2.5 Tests Unitaires des Value Objects Référencés')
      ..writeln(
        'Vérifie pour chaque Value Object l’immuabilité, l’égalité structurelle (`equals()`), la normalisation et le rejet métier via `create()` :',
      );
    for (final item in valueObjects) {
      final vo = item.spec;
      buf.writeln(
        '- **`${vo.technicalName}`** (${vo.kind.label} · ${item.scope.label}) :',
      );
      if (vo.validExamples.isNotEmpty) {
        for (final ex in vo.validExamples) {
          buf.writeln(
            '  - ✅ Valide : `${ex.value}`'
            '${ex.reason.isEmpty ? '' : ' — ${ex.reason}'}',
          );
        }
      } else {
        buf.writeln('  - ✅ Cas nominal valide + égalité entre deux instances identiques.');
      }
      if (vo.invalidExamples.isNotEmpty) {
        for (final ex in vo.invalidExamples) {
          buf.writeln(
            '  - ❌ Invalide : `${ex.value}` → rejet attendu'
            '${ex.reason.isEmpty ? '' : ' (${ex.reason})'}',
          );
        }
      }
      if (vo.normalizationRules.isNotEmpty) {
        buf.writeln(
          '  - 🧹 Normalisation vérifiée : ${vo.normalizationRules.join(', ')}.',
        );
      }
      if (vo.crossFieldRules.isNotEmpty) {
        buf.writeln(
          '  - ⚖️ Règles inter-champs vérifiées : ${vo.crossFieldRules.join(' ; ')}.',
        );
      }
    }
    buf.writeln();
  }

  /// Rédige les consignes de mapping Persistance ↔ Value Objects (déballage / reconstitution).
  static void writePersistenceValueObjectsMappingSection(
    StringBuffer buf,
    List<ResolvedValueObject> valueObjects, {
    String heading = '### 3.3 Mapping Persistance ↔ Value Objects',
  }) {
    if (valueObjects.isEmpty) return;
    buf
      ..writeln(heading)
      ..writeln(
        'Le mapper Domain ↔ Infrastructure DOIT sérialiser/désérialiser explicitement les Value Objects référencés (déballage primitif pour les scalaires, sous-document/colonnes dédiées pour les composites, et reconstitution via factory/reconstitute) :',
      );
    for (final item in valueObjects) {
      final vo = item.spec;
      if (vo.isScalar) {
        buf.writeln(
          '- **`${vo.technicalName}`** (Scalaire `${vo.primitiveType.dslKeyword}` · ${item.scope.label}) : déballage en primitif `${vo.primitiveType.dslKeyword}` côté persistance, reconstitution via `${vo.technicalName}.create(...)` / `reconstitute(...)`.',
        );
      } else {
        final fieldNames = vo.fields.map((f) => '`${f.name}`').join(', ');
        buf.writeln(
          '- **`${vo.technicalName}`** (Composite · ${item.scope.label}) : mapping bidirectionnel des champs $fieldNames en sous-document ou colonnes dédiées, reconstitution immuable via `${vo.technicalName}.create(...)` / `reconstitute(...)`.',
        );
      }
    }
    buf.writeln();
  }

  /// Ajoute en fin de prompt la section d'extension de la stack technique,
  /// de la structure des dossiers cible, des consignes spécifiques à la partie
  /// et au sous-rôle, puis la section globale **Documentation IA** tout à la fin.
  static void writeTechStackExtensionSection(
    StringBuffer buf, {
    required FunctionalDomain domain,
    required BuildTechStackSection section,
    required BuildHexaPromptRole role,
    required BuildTechStackProfile? techStack,
  }) {
    if (techStack == null) return;
    final subRole = role.toStackSubRole;
    if (!techStack.hasExtensionContentFor(section, subRole)) {
      return;
    }

    final stackText = BuildTechStackProfile.resolvePlaceholders(
      techStack.technicalStack.trim(),
      domain.domainCode,
    );
    final foldersText = techStack.resolveFolderStructureFor(
      domain.domainCode,
      section: section,
      subRole: subRole,
    );
    final roleExt = BuildTechStackProfile.resolvePlaceholders(
      techStack.extensionFor(section, subRole),
      domain.domainCode,
    );
    final aiDocText = techStack.resolveAiDocumentation(domain.domainCode);

    if (stackText.isNotEmpty || foldersText.isNotEmpty || roleExt.isNotEmpty) {
      buf
        ..writeln()
        ..writeln(
          '## Extension Stack Technique & Structure des Dossiers (${techStack.name})',
        );

      if (stackText.isNotEmpty) {
        buf
          ..writeln()
          ..writeln('### Stack technique')
          ..writeln(stackText);
      }

      if (foldersText.isNotEmpty) {
        buf
          ..writeln()
          ..writeln('### Structure des dossiers cible')
          ..writeln('```text')
          ..writeln(foldersText)
          ..writeln('```');
      }

      if (roleExt.isNotEmpty) {
        buf
          ..writeln()
          ..writeln(
            '### Consignes spécifiques — ${section.label} (${subRole.label})',
          )
          ..writeln(roleExt);
      }
    }

    if (aiDocText.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('## Documentation IA')
        ..writeln(aiDocText);
    }
  }
}

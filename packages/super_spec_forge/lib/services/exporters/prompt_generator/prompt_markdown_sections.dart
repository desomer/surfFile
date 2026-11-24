/// Sections Markdown partagées entre les différents générateurs de prompts IA
/// (contexte du domaine et couche Domain).
library;

import '../../../models/build_tech_stack_profile.dart';
import '../../../models/business_object_model_preferences.dart';
import '../../../models/business_object_spec.dart';
import '../../../models/company_glossary.dart';
import '../../../models/domain_catalog.dart';
import '../../../models/domain_layer_spec.dart';
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

  /// Ajoute en fin de prompt la section d'extension de la stack technique,
  /// de la structure des dossiers cible et des consignes spécifiques au rôle.
  static void writeTechStackExtensionSection(
    StringBuffer buf, {
    required FunctionalDomain domain,
    required BuildHexaPromptRole role,
    required BuildTechStackProfile? techStack,
  }) {
    if (techStack == null || !techStack.hasExtensionContentForRole(role.name)) {
      return;
    }

    final stackText = techStack.technicalStack.trim();
    final foldersText = techStack.resolveFolderStructure(
      domain.domainCode,
      roleName: role.name,
    );
    final roleExt = techStack.roleExtensionForName(role.name);

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
        ..writeln('### Consignes spécifiques — ${role.label}')
        ..writeln(roleExt);
    }
  }
}

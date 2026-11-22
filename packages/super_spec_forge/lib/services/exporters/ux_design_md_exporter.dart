/// Exportateur de la charte visuelle `DESIGN.md` ([UxDesignMdExporter]) compatible avec `super_container_layout`.
library;

import 'package:super_container_layout/super_container_layout.dart';

import '../../models/spec_forge_project.dart';
import '../../models/ux/ux_navigation_spec.dart';

/// Génère un fichier `DESIGN.md` normalisé (frontmatter YAML + corps Markdown)
/// depuis l'identité visuelle et le shell UX d'un [SpecForgeProject].
abstract final class UxDesignMdExporter {
  /// Exporte la charte de design système du [project] au format `DESIGN.md`.
  static String export(SpecForgeProject project) {
    final nav = project.uxSpec.navigation;
    final seed = nav.visualTheme;
    final accentHex = UxVisualThemeSeed.normalizeAccentHex(seed.accentHex);
    final isDark = seed.themeMode == 'dark';
    final effectiveMode = isDark ? 'dark' : 'light';
    final slug = DesignMdParser.slugify(project.name);

    final canvasHex = isDark ? '#0F172A' : '#F8FAFC';
    final surfaceHex = isDark ? '#1E293B' : '#FFFFFF';
    final textHex = isDark ? '#F8FAFC' : '#0F172A';
    final mutedHex = isDark ? '#94A3B8' : '#64748B';
    final borderHex = isDark ? '#334155' : '#E2E8F0';

    final description = project.vision.valueProposition.trim().isNotEmpty
        ? project.vision.valueProposition.trim()
        : (project.vision.ideaSummary.trim().isNotEmpty
              ? project.vision.ideaSummary.trim()
              : project.initialIdea.trim());

    final tagline =
        'Charte Material 3 ${seed.density.label} • ${nav.shellPattern.label} • ${seed.fontFamily}';

    final spacingScale = switch (seed.density) {
      UxDensityProfile.compact =>
        'Grille Desktop compacte : zones `12 px`, cartes `16 px`, composants internes `8 px`, lignes de listes `52 px`, lignes de tableaux `36 px`.',
      UxDensityProfile.comfortable =>
        'Grille équilibrée : zones `16 px`, cartes `20 px`, composants internes `12 px`, lignes de listes `56 px`, lignes de tableaux `40 px`.',
      UxDensityProfile.spacious =>
        'Grille aérée : zones `20 px`, cartes `24 px`, composants internes `12 px`, lignes de listes `60 px`, lignes de tableaux `40 px`.',
    };

    final radiusText = seed.cardRadius == seed.cardRadius.roundToDouble()
        ? '${seed.cardRadius.toInt()}'
        : '${seed.cardRadius}';
    final innerRadius = (seed.cardRadius - 4).clamp(6.0, 12.0);
    final innerRadiusText = innerRadius == innerRadius.roundToDouble()
        ? '${innerRadius.toInt()}'
        : '$innerRadius';

    final body = StringBuffer()
      ..writeln('# ${project.name} — DESIGN.md')
      ..writeln()
      ..writeln('## 1. Identité visuelle & Atmosphère')
      ..writeln()
      ..writeln(description)
      ..writeln()
      ..writeln(
        '- **Système de surface** : `${seed.surfaceSystem}` (langage visuel unifié sur l’ensemble des vues).',
      )
      ..writeln(
        '- **Mode lumineux cible** : `${seed.themeMode}` (aperçu de référence `$effectiveMode`, adaptation automatique clair/sombre via les rôles `theme:*`).',
      )
      ..writeln(
        '- **Profil de densité** : ${seed.density.label} (`${seed.density.name}`).',
      )
      ..writeln()
      ..writeln('## 2. Palette chromatique & Rôles Material 3')
      ..writeln()
      ..writeln(
        'La graine chromatique primaire est `$accentHex`. Dans `super_container_layout`, privilégier systématiquement les références dynamiques `theme:*` :',
      )
      ..writeln()
      ..writeln('| Rôle d’interface | Token Material 3 | Aperçu de référence |')
      ..writeln('|---|---|---|')
      ..writeln('| **Marque / Action primaire** | `theme:primary` / `theme:onPrimary` | `$accentHex` |')
      ..writeln('| **Fond global (`background`)** | `theme:surfaceContainerLowest` (`padding: 0`) | `$canvasHex` |')
      ..writeln('| **Cartes & Panneaux (`Card`)** | `theme:surface` | `$surfaceHex` |')
      ..writeln('| **Texte principal** | `theme:onSurface` | `$textHex` |')
      ..writeln('| **Texte secondaire / Métadonnées** | `theme:onSurfaceVariant` | `$mutedHex` |')
      ..writeln('| **Bordures subtiles (`1 px`)** | `theme:outlineVariant` | `$borderHex` |')
      ..writeln('| **Sélection Maître / Détail** | `theme:secondaryContainer` | — |')
      ..writeln('| **Actions destructrices & Erreurs** | `theme:errorContainer` / `theme:onErrorContainer` | — |')
      ..writeln()
      ..writeln('## 3. Typographie & Hiérarchie')
      ..writeln()
      ..writeln('- **Famille principale** : `${seed.fontFamily}`.')
      ..writeln('- **Titre d’écran / KPI majeur** : `22–24 px`, `semibold`, `theme:onSurface`.')
      ..writeln('- **Titre de carte / section / AppBar** : `16–18 px`, `semibold`, `theme:onSurface`.')
      ..writeln('- **Corps, champs & cellules** : `13–14 px`, `normal` / `medium`, `theme:onSurface`.')
      ..writeln('- **Métadonnées & unités** : `11–12 px`, `normal`, `theme:onSurfaceVariant`.')
      ..writeln('- **Atomicité stricte** : un attribut métier par `SuperValue` avec sa propriété `label` dédiée (aucune concaténation `Clé : Valeur` dans `text`).')
      ..writeln()
      ..writeln('## 4. Densité spatiale, Surfaces & Rayons')
      ..writeln()
      ..writeln('- $spacingScale')
      ..writeln('- **Rayon des cartes principales (`Card`)** : `$radiusText px` avec filet `borderWidth: 1` en `theme:outlineVariant`.')
      ..writeln('- **Rayons concentriques internes (lignes de listes, boutons, champs)** : `$innerRadiusText px`.')
      ..writeln('- **Loi de proximité** : le `padding` intérieur d’une carte reste toujours supérieur ou égal au `spacing` entre ses éléments.')
      ..writeln()
      ..writeln('## 5. Architecture Shell & Navigation')
      ..writeln()
      ..writeln('- **Pattern de coque applicative** : ${nav.shellPattern.label} (`${nav.shellPattern.name}`).')
      ..writeln('- **Barre supérieure (`ApplicationBar`)** : ${nav.hasAppBar ? 'Oui' : 'Non'}.')
      ..writeln('- **Fil d’Ariane (`Breadcrumbs`)** : ${nav.hasBreadcrumbs ? 'Oui' : 'Non'}.')
      ..writeln('- **Recherche globale** : ${nav.hasGlobalSearch ? 'Oui' : 'Non'}.');

    if (nav.routes.isNotEmpty) {
      body
        ..writeln()
        ..writeln('### Routes principales déclarées');
      for (final route in nav.routes) {
        body.writeln(
          '- `${route.path}` — **${route.title}** (`${route.pageType.name}`)',
        );
      }
    }

    body
      ..writeln()
      ..writeln('## 6. Ton éditorial, Micro-copie & Garde-fous UX')
      ..writeln();
    if (seed.uxVoiceGuidelines.trim().isNotEmpty) {
      body
        ..writeln(seed.uxVoiceGuidelines.trim())
        ..writeln();
    }
    body
      ..writeln('- **Hiérarchie d’engagement** : un seul bouton `filled` (`primary`) maximum par écran ; actions secondaires en `tonal` ou `outlined`.')
      ..writeln('- **États vides actionnables** : formuler un message explicite orienté métier accompagné d’un appel à l’action clair.')
      ..writeln('- **Actions sensibles** : exiger une confirmation explicite avant toute suppression ou transition irréversible.');

    return DesignMdParser.composeDesignMarkdown(
      markdown: body.toString(),
      id: 'custom:$slug',
      name: project.name,
      slug: slug,
      category: 'productivity-saas',
      tagline: tagline,
      description: _singleLine(description, maxChars: 220),
      mode: effectiveMode,
      accent: accentHex,
      canvasColor: canvasHex,
      surfaceColor: surfaceHex,
      textColor: textHex,
      mutedTextColor: mutedHex,
      borderColor: borderHex,
      cardRadius: seed.cardRadius,
      surfaceSystem: seed.surfaceSystem,
      fontFamily: seed.fontFamily,
      tags: <String>[
        'spec-forge',
        nav.shellPattern.name,
        seed.density.name,
        seed.surfaceSystem,
      ],
    );
  }

  static String _singleLine(String input, {int maxChars = 220}) {
    final collapsed = input.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= maxChars) return collapsed;
    return '${collapsed.substring(0, maxChars - 1).trimRight()}…';
  }
}

/// Catalogue immuable de systèmes de design ([DesignSystemCatalog]) pour l'assistant Vibe IA.
///
/// Définit les catégories ([DesignSystemCategory]), les aperçus de palette
/// ([DesignSystemPalettePreview]) et les 24 préréglages intégrés ([DesignSystemPreset])
/// inspirés des chartes `DESIGN.md` modernes. Interagit avec [DesignMdParser] pour
/// nettoyer ou importer des fichiers `DESIGN.md` externes, avec [DesignSystem] pour
/// le moteur de rendu de surface, et alimente la galerie visuelle ainsi que `VibeChatDialog`.
library;

import 'package:flutter/foundation.dart' show FlutterError, listEquals;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:material_ui/material_ui.dart'
    show Brightness, Color, IconData, Icons, ThemeMode, immutable;

import '../theme/design_system.dart';
import 'design_md_parser.dart';

/// Catégorie thématique regroupant les préréglages de systèmes de design dans la galerie Vibe IA.
enum DesignSystemCategory {
  /// Applications métiers, espaces collaboratifs et logiciels SaaS B2B.
  productivitySaas(
    id: 'productivity-saas',
    label: 'Productivité & SaaS',
    englishLabel: 'Productivity & SaaS',
    icon: Icons.dashboard_customize_outlined,
  ),

  /// Environnements de développement, terminaux, cloud et observabilité.
  developerTools(
    id: 'developer-tools',
    label: 'Outils Développeur',
    englishLabel: 'Developer Tools & IDEs',
    icon: Icons.terminal_outlined,
  ),

  /// Assistants conversationnels, plateformes LLM et orchestrateurs d'agents IA.
  aiPlatforms(
    id: 'ai-platforms',
    label: 'IA & LLM',
    englishLabel: 'AI & LLM Platforms',
    icon: Icons.auto_awesome_outlined,
  ),

  /// Services financiers, paiements, banques en ligne et trésorerie.
  fintech(
    id: 'fintech',
    label: 'Fintech & Banque',
    englishLabel: 'Fintech & Banking',
    icon: Icons.account_balance_wallet_outlined,
  ),

  /// Studios graphiques, outils de prototypage et systèmes d'interface créatifs.
  designCreative(
    id: 'design-creative',
    label: 'Design & Créatif',
    englishLabel: 'Design & Creative',
    icon: Icons.palette_outlined,
  ),

  /// Plateformes éditoriales, streaming, e-commerce et réservation grand public.
  mediaRetail(
    id: 'media-retail',
    label: 'Média & Retail',
    englishLabel: 'Media & Retail',
    icon: Icons.storefront_outlined,
  ),

  /// Esthétiques spéciales, neumorphiques ou rétro-informatiques.
  specialRetro(
    id: 'special-retro',
    label: 'Spécial & Rétro',
    englishLabel: 'Special & Retro',
    icon: Icons.auto_fix_high_outlined,
  ),

  /// Fichiers `DESIGN.md` importés ou collés par l'utilisateur.
  custom(
    id: 'custom',
    label: 'Importés',
    englishLabel: 'Custom DESIGN.md',
    icon: Icons.upload_file_outlined,
  );

  /// Crée une catégorie de système de design avec ses libellés localisés et son icône.
  const DesignSystemCategory({
    required this.id,
    required this.label,
    required this.englishLabel,
    required this.icon,
  });

  /// Identifiant kebab-case stable utilisé dans les métadonnées `DESIGN.md`.
  final String id;

  /// Libellé français affiché dans l'interface de sélection.
  final String label;

  /// Libellé anglais utilisé pour la recherche bilingue et l'interopérabilité `DESIGN.md`.
  final String englishLabel;

  /// Icône Material associée à la catégorie dans la barre latérale ou les filtres.
  final IconData icon;

  /// Résout une catégorie à partir d'un identifiant, d'un nom d'énumération ou de mots-clés.
  ///
  /// Retourne [fallback] ([DesignSystemCategory.custom] par défaut, ou
  /// [DesignSystemCategory.productivitySaas] pour un terme métier générique) lorsqu'aucune
  /// correspondance directe n'est trouvée.
  static DesignSystemCategory fromId(
    String? raw, {
    DesignSystemCategory fallback = DesignSystemCategory.custom,
  }) {
    if (raw == null) return fallback;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return fallback;
    final normalized = _normalizeSearchText(trimmed);

    for (final category in DesignSystemCategory.values) {
      if (normalized == _normalizeSearchText(category.id) ||
          normalized == _normalizeSearchText(category.name) ||
          normalized == _normalizeSearchText(category.label) ||
          normalized == _normalizeSearchText(category.englishLabel)) {
        return category;
      }
    }

    if (_containsAny(normalized, const [
      'custom',
      'import',
      'externe',
      'external',
      'perso',
    ])) {
      return DesignSystemCategory.custom;
    }
    if (_containsAny(normalized, const [
      'dev',
      'ide',
      'code',
      'terminal',
      'cli',
      'infra',
      'observab',
      'debug',
    ])) {
      return DesignSystemCategory.developerTools;
    }
    if (_containsAny(normalized, const [
      'ai',
      'ia',
      'llm',
      'agent',
      'ml',
      'prompt',
      'assistant',
    ])) {
      return DesignSystemCategory.aiPlatforms;
    }
    if (_containsAny(normalized, const [
      'fintech',
      'finance',
      'bank',
      'banque',
      'payment',
      'paiement',
      'wallet',
      'treasury',
    ])) {
      return DesignSystemCategory.fintech;
    }
    if (_containsAny(normalized, const [
      'design',
      'creativ',
      'studio',
      'canvas',
      'prototyp',
    ])) {
      return DesignSystemCategory.designCreative;
    }
    if (_containsAny(normalized, const [
      'media',
      'retail',
      'commerce',
      'shop',
      'music',
      'audio',
      'editorial',
      'magazine',
      'news',
      'travel',
    ])) {
      return DesignSystemCategory.mediaRetail;
    }
    if (_containsAny(normalized, const [
      'retro',
      'special',
      'neumorph',
      'vintage',
      'classic',
      'pixel',
      'brutal',
      '98',
      '95',
    ])) {
      return DesignSystemCategory.specialRetro;
    }
    if (_containsAny(normalized, const [
      'saas',
      'productiv',
      'workspace',
      'collab',
      'crm',
      'erp',
      'project',
      'enterprise',
      'b2b',
    ])) {
      return DesignSystemCategory.productivitySaas;
    }
    return fallback;
  }
}

/// Aperçu synthétique immuable des jetons visuels d'un [DesignSystemPreset].
///
/// Utilisé pour dessiner les miniatures d'interface, afficher les pastilles de couleurs
/// et synchroniser rapidement le mode clair/sombre ainsi que la couleur d'accentuation.
@immutable
class DesignSystemPalettePreview {
  /// Crée un aperçu de palette et de géométrie pour un système de design.
  const DesignSystemPalettePreview({
    required this.mode,
    required this.accent,
    required this.canvas,
    required this.surface,
    required this.textPrimary,
    required this.textMuted,
    required this.border,
    this.cardRadius = 12.0,
    this.surfaceSystem = DesignSystem.material,
    this.fontHint = 'Sans-serif',
  });

  /// Mode lumineux cible ([ThemeMode.light] ou [ThemeMode.dark]).
  final ThemeMode mode;

  /// Couleur d'accentuation principale (marque et actions primaires).
  final Color accent;

  /// Couleur d'arrière-plan global de la page (`canvas`).
  final Color canvas;

  /// Couleur des cartes, panneaux ou conteneurs surélevés (`surface`).
  final Color surface;

  /// Couleur du texte principal à fort contraste.
  final Color textPrimary;

  /// Couleur du texte secondaire, des légendes et métadonnées.
  final Color textMuted;

  /// Couleur des bordures fines et séparateurs structurels.
  final Color border;

  /// Rayon d'arrondi représentatif des cartes en pixels logiques.
  final double cardRadius;

  /// Système de rendu de surface associé ([DesignSystem.material], [DesignSystem.neumorphism], [DesignSystem.liquidGlass]).
  final DesignSystem surfaceSystem;

  /// Indication typographique affichée dans la carte d'aperçu.
  final String fontHint;

  /// Indique si la palette cible un thème sombre ([ThemeMode.dark]).
  bool get isDark => mode == ThemeMode.dark;

  /// Luminosité Flutter correspondante ([Brightness.dark] ou [Brightness.light]).
  Brightness get brightness => isDark ? Brightness.dark : Brightness.light;

  /// Échantillons ordonnés (`canvas`, `surface`, `accent`, `textPrimary`, `border`) en liste non modifiable.
  List<Color> get swatches =>
      List<Color>.unmodifiable([canvas, surface, accent, textPrimary, border]);

  /// Formate [color] en code hexadécimal `#RRGGBB` majuscule à 6 chiffres.
  static String colorToHex(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).toUpperCase().padLeft(6, '0')}';
  }

  /// Retourne une copie de cet aperçu de palette avec les champs remplacés.
  DesignSystemPalettePreview copyWith({
    ThemeMode? mode,
    Color? accent,
    Color? canvas,
    Color? surface,
    Color? textPrimary,
    Color? textMuted,
    Color? border,
    double? cardRadius,
    DesignSystem? surfaceSystem,
    String? fontHint,
  }) => DesignSystemPalettePreview(
    mode: mode ?? this.mode,
    accent: accent ?? this.accent,
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    textPrimary: textPrimary ?? this.textPrimary,
    textMuted: textMuted ?? this.textMuted,
    border: border ?? this.border,
    cardRadius: cardRadius ?? this.cardRadius,
    surfaceSystem: surfaceSystem ?? this.surfaceSystem,
    fontHint: fontHint ?? this.fontHint,
  );

  /// Compare deux aperçus de palette valeur par valeur.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesignSystemPalettePreview &&
          mode == other.mode &&
          accent == other.accent &&
          canvas == other.canvas &&
          surface == other.surface &&
          textPrimary == other.textPrimary &&
          textMuted == other.textMuted &&
          border == other.border &&
          cardRadius == other.cardRadius &&
          surfaceSystem == other.surfaceSystem &&
          fontHint == other.fontHint;

  /// Code de hachage cohérent avec [operator ==].
  @override
  int get hashCode => Object.hash(
    mode,
    accent,
    canvas,
    surface,
    textPrimary,
    textMuted,
    border,
    cardRadius,
    surfaceSystem,
    fontHint,
  );
}

/// Définition immuable d'un système de design sélectionnable dans l'assistant Vibe IA.
///
/// Peut référencer un guide embarqué dans les assets du package via [assetSlug]
/// ou transporter directement un contenu Markdown importé via [inlineMarkdown].
@immutable
class DesignSystemPreset {
  /// Crée un préréglage de système de design en protégeant [tags] par `List.unmodifiable`.
  DesignSystemPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.tagline,
    required this.description,
    required this.palette,
    this.assetSlug,
    this.inlineMarkdown,
    List<String> tags = const [],
  }) : tags = List<String>.unmodifiable(tags);

  const DesignSystemPreset._builtIn({
    required this.id,
    required this.name,
    required this.category,
    required this.tagline,
    required this.description,
    required this.palette,
    required String this.assetSlug,
    this.tags = const [],
  }) : inlineMarkdown = null;

  /// Identifiant unique du préréglage (ex. `'linear'` ou `'custom:mon-design'`).
  final String id;

  /// Nom affiché du système de design (ex. `'Linear'`, `'Stripe'`).
  final String name;

  /// Catégorie fonctionnelle ou esthétique du préréglage.
  final DesignSystemCategory category;

  /// Accroche courte résumant la personnalité visuelle sur la carte d'aperçu.
  final String tagline;

  /// Description détaillée de l'atmosphère, de la hiérarchie et des usages recommandés.
  final String description;

  /// Aperçu des couleurs, du mode lumineux, du rayon et du système de surface.
  final DesignSystemPalettePreview palette;

  /// Slug du fichier Markdown embarqué sous `assets/design_systems/<assetSlug>.md`.
  final String? assetSlug;

  /// Contenu Markdown complet lorsqu'il s'agit d'un `DESIGN.md` importé ou collé.
  final String? inlineMarkdown;

  /// Liste non modifiable de mots-clés facilitant la recherche dans la galerie.
  final List<String> tags;

  /// Indique si ce préréglage provient d'un import personnalisé plutôt que du catalogue intégré.
  bool get isCustom =>
      category == DesignSystemCategory.custom || inlineMarkdown != null;

  /// Chemins d'assets candidats testés dans l'[AssetBundle] pour charger le fichier `DESIGN.md`.
  List<String> get candidateAssetPaths {
    final slug = assetSlug?.trim();
    if (slug == null || slug.isEmpty) return const [];
    return List<String>.unmodifiable([
      'assets/design_systems/$slug.md',
      'packages/super_container_layout/assets/design_systems/$slug.md',
    ]);
  }

  /// Indique si ce préréglage correspond à la requête plein texte [query] (insensible à la casse et aux accents).
  bool matchesQuery(String query) {
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty) return true;

    final tokens = normalizedQuery
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return true;

    final modeKeywords = palette.isDark
        ? 'dark sombre nuit fonce'
        : 'light clair jour lumineux';
    final haystack = _normalizeSearchText(
      [
        name,
        id,
        tagline,
        description,
        category.label,
        category.englishLabel,
        palette.fontHint,
        palette.surfaceSystem.name,
        palette.surfaceSystem.label,
        ...tags,
        modeKeywords,
      ].join(' '),
    );

    for (final token in tokens) {
      if (!haystack.contains(token)) {
        return false;
      }
    }
    return true;
  }

  /// Retourne une copie immuable de ce préréglage avec les propriétés modifiées.
  DesignSystemPreset copyWith({
    String? id,
    String? name,
    DesignSystemCategory? category,
    String? tagline,
    String? description,
    DesignSystemPalettePreview? palette,
    String? assetSlug,
    bool clearAssetSlug = false,
    String? inlineMarkdown,
    bool clearInlineMarkdown = false,
    List<String>? tags,
  }) => DesignSystemPreset(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    tagline: tagline ?? this.tagline,
    description: description ?? this.description,
    palette: palette ?? this.palette,
    assetSlug: clearAssetSlug ? null : (assetSlug ?? this.assetSlug),
    inlineMarkdown: clearInlineMarkdown
        ? null
        : (inlineMarkdown ?? this.inlineMarkdown),
    tags: tags ?? this.tags,
  );

  /// Compare deux préréglages de système de design valeur par valeur.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesignSystemPreset &&
          id == other.id &&
          name == other.name &&
          category == other.category &&
          tagline == other.tagline &&
          description == other.description &&
          palette == other.palette &&
          assetSlug == other.assetSlug &&
          inlineMarkdown == other.inlineMarkdown &&
          listEquals(tags, other.tags);

  /// Code de hachage cohérent avec [operator ==].
  @override
  int get hashCode => Object.hash(
    id,
    name,
    category,
    tagline,
    description,
    palette,
    assetSlug,
    inlineMarkdown,
    Object.hashAll(tags),
  );
}

/// Catalogue central des 24 systèmes de design intégrés et chargeur mis en cache des fichiers `DESIGN.md`.
abstract final class DesignSystemCatalog {
  static final Map<String, String> _rootBundleCache = <String, String>{};
  static final Map<String, Future<String>> _inFlightRootLoads =
      <String, Future<String>>{};

  /// Liste constante des 24 préréglages `DESIGN.md` embarqués dans `super_container_layout`.
  static const List<DesignSystemPreset> builtInPresets = <DesignSystemPreset>[
    // -------------------------------------------------------------------------
    // 1–4 : Productivité & SaaS
    // -------------------------------------------------------------------------
    DesignSystemPreset._builtIn(
      id: 'linear',
      name: 'Linear',
      category: DesignSystemCategory.productivitySaas,
      tagline: 'Précision sombre ultra-dense et bordures hairline indigo',
      description:
          'Interface SaaS sombre axée sur la vélocité clavier, les contrastes '
          'graphite subtils, les séparateurs de 1px et un accent indigo électrique.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.dark,
        accent: Color(0xFF5E6AD2),
        canvas: Color(0xFF08090A),
        surface: Color(0xFF111215),
        textPrimary: Color(0xFFF7F8F8),
        textMuted: Color(0xFF8A8F98),
        border: Color(0xFF23252A),
        cardRadius: 8,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Inter / JetBrains Mono',
      ),
      assetSlug: 'linear',
      tags: <String>[
        'linear',
        'saas',
        'productivité',
        'issue tracker',
        'graphite',
        'indigo',
        'dense',
        'clavier',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'notion',
      name: 'Notion',
      category: DesignSystemCategory.productivitySaas,
      tagline:
          'Papier chaud minimaliste, calme éditorial et clarté documentaire',
      description:
          'Espace de travail clair aux tons ivoire et encre chaude, privilégiant '
          'la lisibilité, la respiration typographique et des bordures très discrètes.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.light,
        accent: Color(0xFF2383E2),
        canvas: Color(0xFFFFFFFF),
        surface: Color(0xFFF7F6F3),
        textPrimary: Color(0xFF37352F),
        textMuted: Color(0xFF787774),
        border: Color(0xFFE9E9E7),
        cardRadius: 8,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Georgia / Inter',
      ),
      assetSlug: 'notion',
      tags: <String>[
        'notion',
        'wiki',
        'notes',
        'docs',
        'éditorial',
        'papier',
        'minimal',
        'saas',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'cal',
      name: 'Cal.com',
      category: DesignSystemCategory.productivitySaas,
      tagline: 'Monochrome franc à contraste net pour la planification moderne',
      description:
          'Esthétique utilitaire claire à boutons anthracite pleins, grilles '
          'structurées sur fond gris perle et hiérarchie typographique affirmée.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.light,
        accent: Color(0xFF111827),
        canvas: Color(0xFFF3F4F6),
        surface: Color(0xFFFFFFFF),
        textPrimary: Color(0xFF111827),
        textMuted: Color(0xFF6B7280),
        border: Color(0xFFE5E7EB),
        cardRadius: 10,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Inter / Cascadia Mono',
      ),
      assetSlug: 'cal',
      tags: <String>[
        'cal',
        'calendrier',
        'scheduling',
        'booking',
        'monochrome',
        'saas',
        'b2b',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'airtable',
      name: 'Airtable',
      category: DesignSystemCategory.productivitySaas,
      tagline: 'Bases de données relationnelles claires, badges vifs et grilles nettes',
      description:
          'Système SaaS lumineux conçu pour les tables riches, vues Kanban, '
          'filtres multi-critères et statuts colorés parfaitement lisibles.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.light,
        accent: Color(0xFF166EE1),
        canvas: Color(0xFFF9FAFB),
        surface: Color(0xFFFFFFFF),
        textPrimary: Color(0xFF1D1F25),
        textMuted: Color(0xFF616670),
        border: Color(0xFFE2E5E9),
        cardRadius: 10,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Inter / Consolas',
      ),
      assetSlug: 'airtable',
      tags: <String>[
        'airtable',
        'tableur',
        'database',
        'crm',
        'grille',
        'badges',
        'productivité',
      ],
    ),

    // -------------------------------------------------------------------------
    // 5–9 : Outils Développeur
    // -------------------------------------------------------------------------
    DesignSystemPreset._builtIn(
      id: 'vercel',
      name: 'Vercel Geist',
      category: DesignSystemCategory.developerTools,
      tagline: 'Noir absolu OLED, rigueur suisse et métriques monospace Geist',
      description:
          'Design system industriel sur noir pur `#000000`, bordures carbone '
          '`#262626`, rayons serrés de 6px et accent bleu déploiement.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.dark,
        accent: Color(0xFF0070F3),
        canvas: Color(0xFF000000),
        surface: Color(0xFF0A0A0A),
        textPrimary: Color(0xFFEDEDED),
        textMuted: Color(0xFF888888),
        border: Color(0xFF262626),
        cardRadius: 6,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Geist / Geist Mono',
      ),
      assetSlug: 'vercel',
      tags: <String>[
        'vercel',
        'geist',
        'nextjs',
        'cloud',
        'noir',
        'oled',
        'monospace',
        'devops',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'cursor',
      name: 'Cursor',
      category: DesignSystemCategory.developerTools,
      tagline: 'IDE natif IA en carbone profond, panneaux dockés et focus code',
      description:
          'Palette d’éditeur de code moderne aux surfaces anthracite étagées, '
          'typographie technique compacte et surbrillances bleu cobalt.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.dark,
        accent: Color(0xFF3B82F6),
        canvas: Color(0xFF0C0C0D),
        surface: Color(0xFF161618),
        textPrimary: Color(0xFFECECEE),
        textMuted: Color(0xFF8E8E93),
        border: Color(0xFF27272A),
        cardRadius: 8,
        surfaceSystem: DesignSystem.material,
        fontHint: 'JetBrains Mono / Inter',
      ),
      assetSlug: 'cursor',
      tags: <String>[
        'cursor',
        'ide',
        'éditeur',
        'code',
        'ia',
        'développeur',
        'terminal',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'raycast',
      name: 'Raycast',
      category: DesignSystemCategory.developerTools,
      tagline: 'Verre fumé translucide, reflets subtils et accent corail vif',
      description:
          'Lanceur desktop haut de gamme exploitant le rendu Liquid Glass sombre, '
          'les bordures lumineuses semi-transparentes et des listes ultra-réactives.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.dark,
        accent: Color(0xFFFF6363),
        canvas: Color(0xFF0D0E11),
        surface: Color(0xFF18191F),
        textPrimary: Color(0xFFF5F5F7),
        textMuted: Color(0xFF9A9AA1),
        border: Color(0xFF2E3039),
        cardRadius: 14,
        surfaceSystem: DesignSystem.liquidGlass,
        fontHint: 'Inter / Cascadia Mono',
      ),
      assetSlug: 'raycast',
      tags: <String>[
        'raycast',
        'launcher',
        'palette de commandes',
        'glass',
        'liquid glass',
        'macos',
        'corail',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'supabase',
      name: 'Supabase',
      category: DesignSystemCategory.developerTools,
      tagline: 'Console backend ardoise sombre et vert émeraude Postgres',
      description:
          'Tableau de bord technique lisible combinant surfaces carbone mat, '
          'schémas SQL/JSON structurés et indicateurs vert néon maîtrisés.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.dark,
        accent: Color(0xFF3ECF8E),
        canvas: Color(0xFF121212),
        surface: Color(0xFF1C1C1C),
        textPrimary: Color(0xFFEDEDED),
        textMuted: Color(0xFF8F8F8F),
        border: Color(0xFF2E2E2E),
        cardRadius: 8,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Inter / JetBrains Mono',
      ),
      assetSlug: 'supabase',
      tags: <String>[
        'supabase',
        'postgres',
        'backend',
        'database',
        'émeraude',
        'vert',
        'console',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'sentry',
      name: 'Sentry',
      category: DesignSystemCategory.developerTools,
      tagline:
          'Observabilité nocturne prune profonde et télémétrie haute densité',
      description:
          'Interface de monitoring et diagnostic aux nuances aubergine sombre, '
          'conçue pour faire ressortir traces, graphiques d’erreurs et alertes.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.dark,
        accent: Color(0xFF6C5FC7),
        canvas: Color(0xFF181225),
        surface: Color(0xFF221A33),
        textPrimary: Color(0xFFF5F3F7),
        textMuted: Color(0xFFA69EB8),
        border: Color(0xFF362B4D),
        cardRadius: 10,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Rubik / JetBrains Mono',
      ),
      assetSlug: 'sentry',
      tags: <String>[
        'sentry',
        'monitoring',
        'logs',
        'apm',
        'observabilité',
        'violet',
        'analytics',
      ],
    ),

    // -------------------------------------------------------------------------
    // 10–12 : IA & LLM
    // -------------------------------------------------------------------------
    DesignSystemPreset._builtIn(
      id: 'claude',
      name: 'Claude',
      category: DesignSystemCategory.aiPlatforms,
      tagline: 'Parchemin parcheminé chaleureux, typographie littéraire et terracotta',
      description:
          'Esthétique humaniste et apaisante sur fond crème sableux `#FAF9F5`, '
          'alliant titres éditoriaux sérifés et ponctuations terre cuite.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.light,
        accent: Color(0xFFD97757),
        canvas: Color(0xFFFAF9F5),
        surface: Color(0xFFF0EEE6),
        textPrimary: Color(0xFF141413),
        textMuted: Color(0xFF6B6963),
        border: Color(0xFFE3E0D6),
        cardRadius: 12,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Georgia / Inter',
      ),
      assetSlug: 'claude',
      tags: <String>[
        'claude',
        'anthropic',
        'ia',
        'llm',
        'terracotta',
        'crème',
        'serif',
        'chaleureux',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'ollama',
      name: 'Ollama',
      category: DesignSystemCategory.aiPlatforms,
      tagline:
          'Pureté locale en noir sur blanc, minimalisme brutalement simple',
      description:
          'Interface IA épurée sans distraction superflue : fond blanc franc, '
          'surfaces gris très pâle, commandes monospace et boutons encre noire.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.light,
        accent: Color(0xFF171717),
        canvas: Color(0xFFFFFFFF),
        surface: Color(0xFFF9F9F9),
        textPrimary: Color(0xFF111111),
        textMuted: Color(0xFF737373),
        border: Color(0xFFE5E5E5),
        cardRadius: 12,
        surfaceSystem: DesignSystem.material,
        fontHint: 'JetBrains Mono / Inter',
      ),
      assetSlug: 'ollama',
      tags: <String>[
        'ollama',
        'local ai',
        'llm',
        'minimal',
        'monochrome',
        'blanc',
        'sobre',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'voltagent',
      name: 'VoltAgent',
      category: DesignSystemCategory.aiPlatforms,
      tagline: 'Cockpit cybernétique d’orchestration d’agents et télémétrie émeraude',
      description:
          'Console sombre d’observabilité multi-agents à angles vifs de 6px, '
          'fond obsidienne `#050505` et signaux d’exécution vert impulsion.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.dark,
        accent: Color(0xFF10B981),
        canvas: Color(0xFF050505),
        surface: Color(0xFF0F1110),
        textPrimary: Color(0xFFF3F4F6),
        textMuted: Color(0xFF71717A),
        border: Color(0xFF1F2924),
        cardRadius: 6,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Geist Mono / Geist',
      ),
      assetSlug: 'voltagent',
      tags: <String>[
        'voltagent',
        'agents',
        'workflow',
        'orchestration',
        'ia',
        'émeraude',
        'télémétrie',
      ],
    ),

    // -------------------------------------------------------------------------
    // 13–16 : Fintech & Banque
    // -------------------------------------------------------------------------
    DesignSystemPreset._builtIn(
      id: 'stripe',
      name: 'Stripe',
      category: DesignSystemCategory.fintech,
      tagline:
          'Rigueur financière lumineuse, ardoise marine et indigo signature',
      description:
          'Référence des tableaux de bord de paiement : fond porcelaine bleuté '
          '`#F6F9FC`, cartes blanches nettes, chiffres tabulaires et accent `#635BFF`.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.light,
        accent: Color(0xFF635BFF),
        canvas: Color(0xFFF6F9FC),
        surface: Color(0xFFFFFFFF),
        textPrimary: Color(0xFF0A2540),
        textMuted: Color(0xFF425466),
        border: Color(0xFFE3E8EE),
        cardRadius: 12,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Inter / JetBrains Mono',
      ),
      assetSlug: 'stripe',
      tags: <String>[
        'stripe',
        'fintech',
        'paiement',
        'facturation',
        'analytics',
        'indigo',
        'finance',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'mercury',
      name: 'Mercury',
      category: DesignSystemCategory.fintech,
      tagline:
          'Banque privée nocturne aux tons saphir feutrés et calme exécutif',
      description:
          'Interface de trésorerie sombre haut de gamme mêlant bleu nuit profond, '
          'typographie aérée et indicateurs financiers d’une grande sobriété.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.dark,
        accent: Color(0xFF5266EB),
        canvas: Color(0xFF0D0E17),
        surface: Color(0xFF151726),
        textPrimary: Color(0xFFF4F5FA),
        textMuted: Color(0xFF8F94B2),
        border: Color(0xFF252840),
        cardRadius: 12,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Inter / Consolas',
      ),
      assetSlug: 'mercury',
      tags: <String>[
        'mercury',
        'banque',
        'trésorerie',
        'fintech',
        'startup',
        'bleu nuit',
        'premium',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'wise',
      name: 'Wise',
      category: DesignSystemCategory.fintech,
      tagline: 'Vert forêt profond, montants expressifs et cartes généreusement arrondies',
      description:
          'Charte internationale franche et directe combinant surfaces claires, '
          'typographie audacieuse à fort impact et rayon convivial de 16px.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.light,
        accent: Color(0xFF163300),
        canvas: Color(0xFFF2F5F7),
        surface: Color(0xFFFFFFFF),
        textPrimary: Color(0xFF0E0F0C),
        textMuted: Color(0xFF454745),
        border: Color(0xFFDCE0DF),
        cardRadius: 16,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Inter / Sans franc',
      ),
      assetSlug: 'wise',
      tags: <String>[
        'wise',
        'devises',
        'transfert',
        'fintech',
        'vert',
        'international',
        'banque',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'revolut',
      name: 'Revolut',
      category: DesignSystemCategory.fintech,
      tagline: 'Néo-banque sombre sculpturale à cartes modulaires de 18px',
      description:
          'Expérience super-app financière moderne : contrastes profonds, '
          'widgets empilés aux coins doux et bleu électrique haute visibilité.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.dark,
        accent: Color(0xFF0075EB),
        canvas: Color(0xFF0B0D12),
        surface: Color(0xFF161922),
        textPrimary: Color(0xFFF7F8FA),
        textMuted: Color(0xFF8B93A7),
        border: Color(0xFF242938),
        cardRadius: 18,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Inter / Sans néo-banque',
      ),
      assetSlug: 'revolut',
      tags: <String>[
        'revolut',
        'néo-banque',
        'crypto',
        'cartes',
        'fintech',
        'bleu',
        'modulaire',
      ],
    ),

    // -------------------------------------------------------------------------
    // 17–19 : Design & Créatif
    // -------------------------------------------------------------------------
    DesignSystemPreset._builtIn(
      id: 'apple',
      name: 'Apple Studio',
      category: DesignSystemCategory.designCreative,
      tagline:
          'Aluminium clair `#F5F5F7`, respiration généreuse et bleu système',
      description:
          'Harmonie inspirée des Human Interface Guidelines : hiérarchie limpide, '
          'cartes blanches à rayon de 18px, marges amples et précision optique.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.light,
        accent: Color(0xFF0071E3),
        canvas: Color(0xFFF5F5F7),
        surface: Color(0xFFFFFFFF),
        textPrimary: Color(0xFF1D1D1F),
        textMuted: Color(0xFF6E6E73),
        border: Color(0xFFE5E5EA),
        cardRadius: 18,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Segoe UI / Inter',
      ),
      assetSlug: 'apple',
      tags: <String>[
        'apple',
        'hig',
        'cupertino',
        'studio',
        'macos',
        'ios',
        'minimal',
        'premium',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'figma',
      name: 'Figma',
      category: DesignSystemCategory.designCreative,
      tagline:
          'Inspecteur d’interface précis, canevas neutre et bleu de sélection',
      description:
          'Système d’outil créatif productif équilibrant panneaux latéraux '
          'compacts, contrôles alignés au pixel près et bleu actif `#0D99FF`.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.light,
        accent: Color(0xFF0D99FF),
        canvas: Color(0xFFF5F5F5),
        surface: Color(0xFFFFFFFF),
        textPrimary: Color(0xFF1E1E1E),
        textMuted: Color(0xFF757575),
        border: Color(0xFFE6E6E6),
        cardRadius: 8,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Inter / JetBrains Mono',
      ),
      assetSlug: 'figma',
      tags: <String>[
        'figma',
        'design',
        'inspecteur',
        'canevas',
        'ui',
        'prototypage',
        'créatif',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'framer',
      name: 'Framer',
      category: DesignSystemCategory.designCreative,
      tagline: 'Scène noire dramatique, grilles Bento audacieuses et bleu néon',
      description:
          'Esthétique studio web contemporaine sur noir pur `#000000`, gros '
          'titres expressifs, cartes sombres `#111111` et accent `#0099FF`.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.dark,
        accent: Color(0xFF0099FF),
        canvas: Color(0xFF000000),
        surface: Color(0xFF111111),
        textPrimary: Color(0xFFFFFFFF),
        textMuted: Color(0xFF888888),
        border: Color(0xFF222222),
        cardRadius: 14,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Inter / Display Bold',
      ),
      assetSlug: 'framer',
      tags: <String>[
        'framer',
        'bento',
        'showcase',
        'studio',
        'web',
        'créatif',
        'noir',
      ],
    ),

    // -------------------------------------------------------------------------
    // 20–22 : Média & Retail
    // -------------------------------------------------------------------------
    DesignSystemPreset._builtIn(
      id: 'airbnb',
      name: 'Airbnb',
      category: DesignSystemCategory.mediaRetail,
      tagline: 'Hospitalité lumineuse, cartes visuelles aérées et rose Rausch',
      description:
          'Design grand public chaleureux mettant en valeur les visuels, '
          'les filtres par puces arrondies, la clarté tarifaire et l’accent `#FF385C`.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.light,
        accent: Color(0xFFFF385C),
        canvas: Color(0xFFFFFFFF),
        surface: Color(0xFFF7F7F7),
        textPrimary: Color(0xFF222222),
        textMuted: Color(0xFF6A6A6A),
        border: Color(0xFFDDDDDD),
        cardRadius: 16,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Plus Jakarta Sans',
      ),
      assetSlug: 'airbnb',
      tags: <String>[
        'airbnb',
        'marketplace',
        'catalogue',
        'voyage',
        'retail',
        'cartes',
        'corail',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'spotify',
      name: 'Spotify',
      category: DesignSystemCategory.mediaRetail,
      tagline: 'Scène média immersive en charbon `#121212` et vert pulsation',
      description:
          'Interface de streaming dense optimisée pour les bibliothèques, '
          'listes de lecture, cartes d’albums et contrôles persistants.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.dark,
        accent: Color(0xFF1DB954),
        canvas: Color(0xFF121212),
        surface: Color(0xFF181818),
        textPrimary: Color(0xFFFFFFFF),
        textMuted: Color(0xFFB3B3B3),
        border: Color(0xFF282828),
        cardRadius: 10,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Plus Jakarta Sans',
      ),
      assetSlug: 'spotify',
      tags: <String>[
        'spotify',
        'musique',
        'audio',
        'streaming',
        'média',
        'vert',
        'playlist',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'wired',
      name: 'WIRED Editorial',
      category: DesignSystemCategory.mediaRetail,
      tagline: 'Grille presse radicale à angles droits 0px, filets noirs et rouge vif',
      description:
          'Mise en page magazine néo-brutaliste à contraste maximal : filets '
          'noirs francs `#000000`, aucun arrondi (`0px`) et titres éditoriaux serrés.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.light,
        accent: Color(0xFFE51212),
        canvas: Color(0xFFFFFFFF),
        surface: Color(0xFFF4F4F4),
        textPrimary: Color(0xFF000000),
        textMuted: Color(0xFF525252),
        border: Color(0xFF000000),
        cardRadius: 0,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Georgia / Consolas',
      ),
      assetSlug: 'wired',
      tags: <String>[
        'wired',
        'éditorial',
        'presse',
        'magazine',
        'brutaliste',
        'sharp',
        'rouge',
      ],
    ),

    // -------------------------------------------------------------------------
    // 23–24 : Spécial & Rétro
    // -------------------------------------------------------------------------
    DesignSystemPreset._builtIn(
      id: 'neumorphic-soft',
      name: 'Soft Neumorphism',
      category: DesignSystemCategory.specialRetro,
      tagline:
          'Relief tactile extrudé à ombres jumelles sur porcelaine bleutée',
      description:
          'Exploite nativement le moteur `DesignSystem.neumorphism` avec une '
          'teinte uniforme `#E6E9EF`, des rayons doux de 20px et un accent lavande.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.light,
        accent: Color(0xFF5B67CA),
        canvas: Color(0xFFE6E9EF),
        surface: Color(0xFFE6E9EF),
        textPrimary: Color(0xFF2D3748),
        textMuted: Color(0xFF718096),
        border: Color(0xFFD1D9E6),
        cardRadius: 20,
        surfaceSystem: DesignSystem.neumorphism,
        fontHint: 'Nunito / Sans doux',
      ),
      assetSlug: 'neumorphic-soft',
      tags: <String>[
        'neumorphism',
        'neumorphisme',
        'tactile',
        'soft ui',
        'relief',
        'haptique',
      ],
    ),
    DesignSystemPreset._builtIn(
      id: 'retro-desktop',
      name: 'Retro Classic 98',
      category: DesignSystemCategory.specialRetro,
      tagline: 'Bureau sarcelle `#008080`, fenêtres gris mastic et barres bleu marine',
      description:
          'Hommage nostalgique aux interfaces Windows 95/98 : coins stricts '
          'à `0px`, panneaux biseautés `#D4D0C8` et bandeaux de titre `#000080`.',
      palette: DesignSystemPalettePreview(
        mode: ThemeMode.light,
        accent: Color(0xFF000080),
        canvas: Color(0xFF008080),
        surface: Color(0xFFD4D0C8),
        textPrimary: Color(0xFF000000),
        textMuted: Color(0xFF404040),
        border: Color(0xFF000000),
        cardRadius: 0,
        surfaceSystem: DesignSystem.material,
        fontHint: 'Tahoma / Consolas',
      ),
      assetSlug: 'retro-desktop',
      tags: <String>[
        'retro',
        'windows 98',
        'win95',
        'classic',
        'pixel',
        'nostalgie',
        'vintage',
      ],
    ),
  ];

  /// Recherche un préréglage par son identifiant [id] parmi [customPresets] puis [builtInPresets].
  static DesignSystemPreset? byId(
    String id, {
    Iterable<DesignSystemPreset> customPresets = const [],
  }) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return null;

    for (final preset in customPresets) {
      if (preset.id == trimmed) return preset;
    }
    for (final preset in builtInPresets) {
      if (preset.id == trimmed) return preset;
    }

    final lower = trimmed.toLowerCase();
    for (final preset in customPresets) {
      if (preset.id.toLowerCase() == lower) return preset;
    }
    for (final preset in builtInPresets) {
      if (preset.id.toLowerCase() == lower) return preset;
    }
    return null;
  }

  /// Charge le document `DESIGN.md` associé à [preset] depuis son contenu en ligne ou depuis [bundle].
  ///
  /// Met en cache les lectures issues de [rootBundle] et déduplique les chargements concurrents.
  /// Lève une [FlutterError] explicite si le fichier d'asset est introuvable ou vide.
  static Future<String> loadMarkdown(
    DesignSystemPreset preset, {
    AssetBundle? bundle,
  }) async {
    final inline = preset.inlineMarkdown;
    if (inline != null && inline.trim().isNotEmpty) {
      return DesignMdParser.extractBodyOrFull(inline);
    }

    final paths = preset.candidateAssetPaths;
    if (paths.isEmpty) {
      throw FlutterError(
        'Le système de design "${preset.id}" ne définit ni contenu inlineMarkdown '
        'ni assetSlug rechargeable.',
      );
    }

    final effectiveBundle = bundle ?? rootBundle;
    final isRoot = identical(effectiveBundle, rootBundle);
    final cacheKey = preset.assetSlug!.trim();

    if (isRoot) {
      final cached = _rootBundleCache[cacheKey];
      if (cached != null) return cached;
      final inFlight = _inFlightRootLoads[cacheKey];
      if (inFlight != null) return inFlight;
    }

    Future<String> loadFromCandidates() async {
      FlutterError? lastError;
      for (final assetPath in paths) {
        try {
          final raw = await effectiveBundle.loadString(assetPath);
          final cleaned = DesignMdParser.extractBodyOrFull(raw);
          if (cleaned.isNotEmpty) {
            if (isRoot) {
              _rootBundleCache[cacheKey] = cleaned;
            }
            return cleaned;
          }
          lastError = FlutterError('L’asset "$assetPath" est vide.');
        } on FlutterError catch (error) {
          lastError = error;
        }
      }
      throw FlutterError(
        'Impossible de charger le guide DESIGN.md du préréglage "${preset.id}" '
        'depuis ${paths.map((path) => '"$path"').join(' ou ')}.'
        '${lastError == null ? '' : ' $lastError'}',
      );
    }

    if (!isRoot) {
      return loadFromCandidates();
    }

    final future = loadFromCandidates();
    _inFlightRootLoads[cacheKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightRootLoads[cacheKey], future)) {
        _inFlightRootLoads.remove(cacheKey);
      }
    }
  }

  /// Vide le cache mémoire des documents `DESIGN.md` chargés depuis [rootBundle] (utile en test).
  static void clearCache() {
    _rootBundleCache.clear();
    _inFlightRootLoads.clear();
  }
}

bool _containsAny(String text, List<String> needles) {
  for (final needle in needles) {
    if (needle.length <= 3) {
      if (RegExp('\\b${RegExp.escape(needle)}\\b').hasMatch(text)) {
        return true;
      }
    } else if (text.contains(needle)) {
      return true;
    }
  }
  return false;
}

String _normalizeSearchText(String input) {
  final lower = input.trim().toLowerCase();
  if (lower.isEmpty) return '';
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(switch (char) {
      'à' || 'á' || 'â' || 'ä' || 'ã' || 'å' => 'a',
      'ç' => 'c',
      'è' || 'é' || 'ê' || 'ë' => 'e',
      'ì' || 'í' || 'î' || 'ï' => 'i',
      'ñ' => 'n',
      'ò' || 'ó' || 'ô' || 'ö' || 'õ' => 'o',
      'ù' || 'ú' || 'û' || 'ü' => 'u',
      'ý' || 'ÿ' => 'y',
      'œ' => 'oe',
      'æ' => 'ae',
      _ => char,
    });
  }
  return buffer.toString();
}

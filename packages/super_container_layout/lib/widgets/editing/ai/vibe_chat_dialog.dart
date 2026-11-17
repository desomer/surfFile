/// Interface de chat IA (« Vibe ») pour la génération et la modification incrémentale d'écrans ([VibeChatDialog]).
///
/// Met en cache les guides `SCREEN_JSON_AI_GUIDE.md`, `REPOSITORY_JSON_AI_GUIDE.md`,
/// `SCREEN_DESIGN_AI_GUIDE.md` et le référentiel `DESIGN.md` actif ([DesignSystemPreset],
/// [VibeChatDialog.warmUp]), assemble un instantané JSON compact (global ou ciblé sur un
/// [VibeChatScope]) enrichi du contexte du [JsonRepositoryStore] actif, diffuse la réponse en
/// direct via [streamGemini] ([VibeAiSpeedMode]) ou [callGemini], propose au besoin un
/// questionnaire de clarification interactif ([VibeAskUserRequest]), et applique les mutations
/// de repositories ([VibeRepositoryTurnTransaction]) ainsi que le patch via `AppearanceTransfer.applyVibe`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:material_ui/material_ui.dart';

import '../../../ai/call_gemini.dart';
import '../../../ai/design_system_catalog.dart';
import '../../../ai/vibe_ask_user.dart';
import '../../../ai/vibe_stream_parser.dart';
import '../../../models/native_component_config.dart';
import '../../../models/registry.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_conditional_config.dart';
import '../../../models/super_tab_config.dart';
import '../../../services/appearance/appearance_codec.dart';
import '../../../services/appearance/appearance_store.dart';
import '../../../services/appearance/appearance_transfer.dart';
import '../../../services/pages/editor_page_router.dart';
import '../../../services/repositories/json_repository_scope.dart';
import '../../../services/repositories/json_repository_store.dart';
import '../../../super_app.dart';
import '../../../theme/appearance.dart';
import '../dialogs/editor_dialog.dart';
import '../history/editor_history.dart';
import '../slots/editor_context_menu.dart';
import 'design_system_catalog_dialog.dart';
import 'design_system_preview_card.dart';
import 'vibe_chat_message.dart';
import 'vibe_chat_widgets.dart';
import 'vibe_prompt_builder.dart';
import 'vibe_repository_applier.dart';
import 'vibe_scope_helpers.dart';
import 'vibe_work_highlight.dart';
import '../../appearance/appearance_scope.dart';

export '../../../ai/call_gemini.dart' show GeminiStreamEvent, VibeAiSpeedMode;
export '../../../ai/design_md_parser.dart';
export '../../../ai/design_system_catalog.dart';
export '../../../ai/vibe_ask_user.dart'
    show
        VibeAskUserFieldType,
        VibeAskUserQuestion,
        VibeAskUserRequest,
        VibeQuestioningLevel;
export '../../../ai/vibe_chat_attachment.dart';
export '../../../ai/vibe_stream_parser.dart' show VibeStreamSnapshot;
export 'design_system_catalog_dialog.dart';
export 'design_system_preview_card.dart';
export 'vibe_ask_user_card.dart' show VibeAskUserCard;
export 'vibe_chat_message.dart' show VibeChatMessage;
export '../slots/editor_context_menu.dart' show VibeChatScope;

/// Panneau et boîte de dialogue de chat avec l'IA Vibe pour créer ou modifier l'interface en langage naturel.
class VibeChatDialog extends StatefulWidget {
  /// Crée un panneau de chat Vibe IA connecté à [controller] et [codec].
  const VibeChatDialog({
    required this.controller,
    required this.codec,
    required this.onClose,
    required this.onDrag,
    required this.generate,
    this.streamGenerate,
    this.initialSpeedMode = VibeAiSpeedMode.fast,
    this.initialQuestioningLevel = VibeQuestioningLevel.balanced,
    this.onQuestioningLevelChanged,
    this.scope,
    this.onScopeChanged,
    this.pickAttachments,
    this.pasteAttachments,
    this.readClipboardText,
    this.validateAppearance,
    this.registry,
    this.repositoryStore,
    this.pageRouting,
    this.initialDesignSystem,
    this.onDesignSystemChanged,
    this.customDesignSystems = const [],
    this.onCustomDesignSystemsChanged,
    this.customDesignGuide,
    this.replaceDefaultDesignGuide = false,
    this.expanded,
    this.onExpandedChanged,
    super.key,
  });

  /// Active la journalisation multi-blocs détaillée des prompts, réponses brutes et patches JSON.
  ///
  /// Désactivé par défaut afin d'éviter le blocage de l'isolate UI sur les charges JSON volumineuses.
  static bool verboseLogging = false;

  /// Instructions système invariantes transmises au modèle GenUI pour le chat Vibe IA.
  static const String defaultSystemInstruction = '''
Tu es l’assistant de création d’écrans de super_container_layout. Réponds en français.
Utilise exclusivement le guide de modélisation JSON, le guide de Design System et l’état actuel de l’application fournis.
Applique systématiquement les règles du Design System (surfaces sémantiques theme:*, hiérarchie typographique, grille d'espacement 4/8px, ergonomie Desktop productive, discipline des boutons d'action et micro-interactions) sauf consigne esthétique explicite contraire de l'utilisateur ; si des règles de design spécifiques à l'application sont fournies, elles prévalent sur le Design System générique.
Renvoie uniquement un objet JSON en plaçant impérativement la clé "message" EN PREMIER (avant "askUser" et "vibe") pour permettre l'affichage instantané en streaming, selon l'un des 3 modes suivants :
1. Création ou modification directe de l'écran : renvoie {"message":"résumé bref en français","vibe":{...}}. Le champ "vibe" doit contenir un patch JSON plat (modèle GenUI : "components", "styles", "behaviors", "usages", "pageCatalog") accepté par AppearanceTransfer.applyVibe.
2. Question pure ou demande d'information sans modification de l'écran : renvoie {"message":"réponse claire en français","vibe":null} (ou omets le champ "vibe") sans modifier l'écran.
3. Clarification interactive ("askUser") selon le NIVEAU DE QUESTIONNEMENT indiqué dans le contexte du tour : renvoie {"message":"courte introduction en français","askUser":{"questions":[{"id":"...","title":"...","type":"single|multi|boolean|text","options":["..."],"default":...}]},"vibe":null}.
Ordre d'émission obligatoire dans "vibe" pour la construction de l'IHM en streaming live :
- Ordonne les clés de "vibe" dans cet ordre : d'abord "pageCatalog" et les réglages globaux de thème s'ils changent, puis "styles", puis "components", puis "behaviors" et "usages".
- Dans "components", émets toujours les conteneurs de haut en bas (Top-Down) : d'abord la page ou le conteneur racine avec ses "placements", "slotTypes" et "slotLabels", puis chaque sous-conteneur/zone dans l'ordre visuel de lecture, et enfin les composants feuilles placés dans chaque zone, afin que l'utilisateur voie la structure et les zones se construire en direct.
Règles pour "repositories" (création et mise à jour des repositories JSON) :
- Lorsqu'une section REPOSITORIES DISPONIBLES (JSON) est fournie dans le contexte du tour, tu peux créer de nouveaux repositories ou mettre à jour/peupler des repositories existants via la clé optionnelle "repositories" placée après "message" et avant "vibe" : {"message":"...","repositories":{"<idOuAlias>":{"name":"...","mode":"merge","data":{...}}},"vibe":{...}} (ou "vibe": null si la demande ne modifie que les données des repositories sans changer l'écran). Si aucune section REPOSITORIES DISPONIBLES (JSON) n'est présente dans le contexte, n'émets pas la clé "repositories".
- Respecte impérativement l'ordre d'émission live : "message" -> "repositories" -> "vibe", afin que les repositories soient créés et peuplés avant l'instanciation des composants liés.
- Réutilise systématiquement les identifiants ("id") existants de REPOSITORIES DISPONIBLES lorsqu'un repository correspond au domaine métier. Pour tout nouveau repository, choisis un alias snake_case (^[a-z0-9_]{1,32}\$, sans inventer d'ID de 32 caractères hexadécimaux) et utilise directement cet alias dans les bindings "<alias>:chemin" (ou {"repositoryId":"<alias>","path":"chemin"}) de "vibe".
- Chemins de liaison dans une liste/table/onglet dynamique (mode « hérité de la liste englobante ») : écris TOUJOURS le chemin complet depuis la racine du repository avec joker(s) [?] (ex: "deals[?].title", "clients[?].nom", "clients[?].commandes[?].ref"), même si repositoryId est omis ; n'écris JAMAIS un nom de champ nu comme "title" ou "nom" (sauf dans un SuperTreeView), sinon il est lu à la racine du document et affiche vide.
- Héritage strictement descendant (Pattern Maître / Détail) : l'héritage de repositoryId ne se propage JAMAIS horizontalement vers une branche sœur (ex: du panneau west vers la fiche détaillée en center). Tout composant hors de la liste source (SuperValue, KPI, sous-liste, Chart) DOIT déclarer explicitement son préfixe "<repoId>:..." ou "<alias>:..." (ou {"repositoryId":"...","path":"..."}) afin que le runtime synchronise sa sélection [?].
- Dans chaque entrée de "repositories", "data" doit être un objet JSON {...} à la racine, et aucune clé JSON stockée ne doit jamais débuter par "@" (préfixe strictement réservé aux attributs calculés en lecture seule) ni contenir ".", "[", "]", "?" ou espace.
Règles pour "askUser" :
- Quelle que soit l'étape (création initiale, ajout, modification d'un écran existant ou d'un scope ciblé), applique systématiquement le NIVEAU DE QUESTIONNEMENT défini par le slider dans le contexte du tour courant, sans restreindre les questions à la première étape (seul le niveau 0/Aucun ou le tour d'application immédiate des réponses qui viennent d'être fournies désactive "askUser").
- Fournis toujours des valeurs "default" pertinentes sur chaque question posée.
Priorité absolue — Respect strict de la règle d'atomicité lors de chaque génération de layout, fiche ou formulaire :
- Ne concatène jamais un libellé et une donnée dans le "text" d'un même SuperValue (ex: jamais "Statut : En cours"), ni plusieurs attributs métier dans un seul composant.
- En mode visualisation ("mode": "display"), un SuperValue possède nativement "label" et une valeur ("text" ou "binding") : préfère systématiquement 1 seul SuperValue avec "label" + "text" (usage "dynamicData") ou "binding" plutôt que 2 SuperValue séparés, SAUF si le label requiert un style ou une disposition fortement personnalisés (auquel cas décompose en 1 SuperValue étiquette fixe avec usage "explanation" + "translationKey", et 1 SuperValue distinct pour la valeur avec usage "dynamicData" ou "binding").
- Évite tout placeholder de texte libre multiligne (textarea / maxLines > 1) pour représenter des listes ou récapitulatifs métier (affaires, contrats, interlocuteurs, etc., même si la demande mentionne « résumé », « récapitulatif » ou « notes ») : utilise systématiquement des cartes, des champs unitaires SuperValue atomiques, une SuperListView ou un tableau SuperTable.
Par défaut, ne mets pas de padding (ni paddingInsets) sur styles["background"] (laisse padding à 0 par défaut, sauf demande explicite) : avec les composants Flutter (Scaffold, ApplicationBar, NavigationRail, BottomAppBar, SuperLayout), ce n'est pas nécessaire ; règle l'espacement éventuel dans les zones des layouts (zoneFlows) ou les cartes.
Réutilise les identifiants des conteneurs de l'état actuel, y compris ceux dont la configuration est encore celle par défaut. Les identifiants du guide (comme "contA") sont des exemples, pas des racines d'écran implicites.
Tout nouveau composant doit être rattaché par les placements à un conteneur existant ou à une page déclarée dans pageCatalog. Créer un layout isolé ne l'affiche pas.
Si une opération crée une page, son chemin doit commencer par un seul "/", être différent de "/" et ne contenir ni espace, ni "?", ni "#"; ne termine pas le chemin par "/".
Si la conversation mentionne une erreur sur une réponse précédente, identifie la cause indiquée et corrige-la sans reproduire la même erreur.
Ne renvoie aucun Markdown ni texte hors du JSON. Utilise systématiquement le niveau du slider de questionnement ("NIVEAU DE QUESTIONNEMENT") à chaque étape pour déterminer le recours à "askUser".''';

  static const List<String> _guideAssets = [
    'SCREEN_JSON_AI_GUIDE.md',
    'packages/super_container_layout/SCREEN_JSON_AI_GUIDE.md',
  ];

  static const List<String> _repositoryGuideAssets = [
    'REPOSITORY_JSON_AI_GUIDE.md',
    'packages/super_container_layout/REPOSITORY_JSON_AI_GUIDE.md',
  ];

  static const List<String> _designGuideAssets = [
    'SCREEN_DESIGN_AI_GUIDE.md',
    'packages/super_container_layout/SCREEN_DESIGN_AI_GUIDE.md',
  ];

  static String? _cachedRootBundleGuide;
  static Future<String>? _inFlightRootBundleGuide;
  static String? _cachedRootBundleRepositoryGuide;
  static Future<String?>? _inFlightRootBundleRepositoryGuide;
  static String? _cachedRootBundleDesignGuide;
  static Future<String?>? _inFlightRootBundleDesignGuide;

  /// Contrôleur réactif de l'apparence courante à lire et mettre à jour.
  final ValueNotifier<Appearance> controller;

  /// Codec de sérialisation GenUI utilisé pour exporter l'état et appliquer le patch.
  final AppearanceCodec codec;

  /// Callback déclenché à la fermeture du panneau de chat.
  final VoidCallback onClose;

  /// Callback déclenché lors du déplacement de l'en-tête du panneau.
  final ValueChanged<Offset> onDrag;

  /// Générateur asynchrone complet (rétrocompatible avec les appelants et tests existants).
  final Future<String> Function(String prompt) generate;

  /// Générateur optionnel en flux SSE incrémental ([GeminiStreamEvent]).
  final Stream<GeminiStreamEvent> Function(
    String prompt, {
    String? systemInstruction,
    String? staticGuide,
    List<VibeChatAttachment> attachments,
    VibeAiSpeedMode speedMode,
  })?
  streamGenerate;

  /// Mode de vitesse initial sélectionné à l'ouverture du panneau ([VibeAiSpeedMode.fast] par défaut).
  final VibeAiSpeedMode initialSpeedMode;

  /// Niveau initial de questionnement préalable ([VibeQuestioningLevel.balanced] par défaut).
  final VibeQuestioningLevel initialQuestioningLevel;

  /// Callback optionnel notifié lorsque l'utilisateur ajuste le niveau de questionnement via le slider.
  final ValueChanged<VibeQuestioningLevel>? onQuestioningLevelChanged;

  /// Périmètre restreint optionnel limitant les modifications de l'IA à un sous-arbre.
  final VibeChatScope? scope;

  /// Callback notifié lorsque l'utilisateur efface ou modifie la restriction de [scope].
  final ValueChanged<VibeChatScope?>? onScopeChanged;

  /// Sélecteur personnalisé optionnel de pièces jointes (fichiers images ou texte).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  /// Lecteur personnalisé optionnel du presse-papiers pour les pièces jointes.
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;

  /// Lecteur personnalisé optionnel du texte du presse-papiers pour l'import de chartes `DESIGN.md`.
  final Future<String?> Function()? readClipboardText;

  /// Validation supplémentaire optionnelle de l'[Appearance] générée (ex. routes de pages).
  final void Function(Appearance appearance)? validateAppearance;

  /// Registre optionnel fournissant les composants instanciés et leurs configurations par défaut.
  final Registry? registry;

  /// Store optionnel de repositories JSON exposé au modèle et mis à jour lors de la génération.
  ///
  /// Lorsqu'il est omis, celui du [JsonRepositoryScope] ou du [SuperApp] englobant est utilisé s'il existe.
  final JsonRepositoryStore? repositoryStore;

  /// Routeur dynamique optionnel permettant de basculer en direct sur toute nouvelle page créée.
  ///
  /// Lorsqu'il est omis, celui du [SuperApp] englobant est utilisé automatiquement s'il existe.
  final EditorPageRouter? pageRouting;

  /// Système de design `DESIGN.md` initialement actif à l'ouverture (`null` pour Material 3 par défaut).
  final DesignSystemPreset? initialDesignSystem;

  /// Callback optionnel notifié lorsque l'utilisateur sélectionne ou réinitialise le système `DESIGN.md` actif.
  final ValueChanged<DesignSystemPreset?>? onDesignSystemChanged;

  /// Préréglages `DESIGN.md` personnalisés déjà importés dans la session courante.
  final List<DesignSystemPreset> customDesignSystems;

  /// Callback optionnel notifié lorsque la liste des préréglages `DESIGN.md` personnalisés est mise à jour.
  final ValueChanged<List<DesignSystemPreset>>? onCustomDesignSystemsChanged;

  /// Directives de design personnalisées fournies par l'application hôte.
  ///
  /// Par défaut ([replaceDefaultDesignGuide] à `false`), ces règles viennent compléter
  /// et surcharger ponctuellement le guide `SCREEN_DESIGN_AI_GUIDE.md` embarqué.
  final String? customDesignGuide;

  /// Lorsque `true` et que [customDesignGuide] est non vide, remplace intégralement
  /// le guide `SCREEN_DESIGN_AI_GUIDE.md` par défaut au lieu de le compléter.
  final bool replaceDefaultDesignGuide;

  /// Indique si le wizard est affiché en grand format centré (`true`, phases de questions)
  /// ou réduit en bas à droite (`false`, phase de construction par l'IA).
  final bool? expanded;

  /// Callback notifié lorsque le wizard s'agrandit (phase de questions) ou se réduit (phase de construction).
  final ValueChanged<bool>? onExpandedChanged;

  /// Assemble le guide statique complet envoyé au modèle à partir du guide JSON
  /// technique [screenGuide], du guide optionnel de modélisation des repositories
  /// [repositoryGuide], du guide de Design System par défaut [defaultDesignGuide],
  /// d'un éventuel référentiel `DESIGN.md` actif ([selectedDesignSystemMarkdown] /
  /// [selectedDesignSystemName]) et des règles de l'application hôte [customDesignGuide].
  static String composeStaticGuide({
    required String screenGuide,
    String? repositoryGuide,
    String? defaultDesignGuide,
    String? selectedDesignSystemMarkdown,
    String? selectedDesignSystemName,
    String? customDesignGuide,
    bool replaceDefaultDesignGuide = false,
  }) {
    final trimmedScreen = screenGuide.trim();
    final trimmedRepository = repositoryGuide?.trim() ?? '';
    final trimmedDefaultDesign = defaultDesignGuide?.trim() ?? '';
    final trimmedSelectedDesign = selectedDesignSystemMarkdown?.trim() ?? '';
    final trimmedSelectedName = selectedDesignSystemName?.trim() ?? '';
    final trimmedCustomDesign = customDesignGuide?.trim() ?? '';
    final buffer = StringBuffer(trimmedScreen);

    if (trimmedRepository.isNotEmpty) {
      buffer
        ..write('\n\n---\n\nGUIDE DE MODÉLISATION DES REPOSITORIES :\n')
        ..write(trimmedRepository);
    }

    final includeDefault =
        trimmedDefaultDesign.isNotEmpty &&
        !(replaceDefaultDesignGuide && trimmedCustomDesign.isNotEmpty);
    if (includeDefault) {
      buffer
        ..write('\n\n---\n\nGUIDE DE DESIGN SYSTEM :\n')
        ..write(trimmedDefaultDesign);
    }
    if (trimmedSelectedDesign.isNotEmpty) {
      final activeName = trimmedSelectedName.isNotEmpty
          ? trimmedSelectedName
          : 'DESIGN.md';
      buffer
        ..write(
          '\n\n---\n\nSYSTÈME DE DESIGN ACTIF ($activeName — PRIORITÉ ESTHÉTIQUE ABSOLUE) :\n'
          'L’utilisateur a sélectionné le référentiel DESIGN.md ci-dessous. Applique impérativement son identité visuelle complète :\n'
          '- Mode lumineux ("mode": "light" | "dark"), couleur graine ("accent") et couleurs hexadécimales #RRGGBB exactes des surfaces ("background", cartes, panneaux, lignes de collection, états "hover" et "selected"), textes et boutons : ces couleurs et tokens prévalent sur les couleurs "theme:*" génériques du guide par défaut.\n'
          '- Géométrie des surfaces : rayons d’arrondi ("radius"), bordures ("borderWidth", "borderColor"), élévations ("elevation", "shadowOpacity") et système de rendu ("designSystem": "material" | "liquidGlass" | "neumorphism").\n'
          '- Hiérarchie typographique ("fontSize", "fontWeight", "fontFamily") et style des actions ("SuperAction" avec contraste AA garanti).\n'
          '- Conserve en revanche strictement toutes les règles structurelles du moteur super_container_layout (atomicité obligatoire 1 SuperValue étiquette "explanation" + 1 SuperValue valeur "dynamicData"/binding, interdiction des textarea fourre-tout, règles d’or autoSides et rattachement placements).\n\n',
        )
        ..write(trimmedSelectedDesign);
    }
    if (trimmedCustomDesign.isNotEmpty) {
      final heading = includeDefault
          ? 'RÈGLES DE DESIGN SPÉCIFIQUES À L’APPLICATION (PRIORITAIRES) :'
          : 'GUIDE DE DESIGN SYSTEM DE L’APPLICATION :';
      buffer
        ..write('\n\n---\n\n$heading\n')
        ..write(trimmedCustomDesign);
    }
    return buffer.toString();
  }

  static Future<String> _loadScreenGuideFromBundle(AssetBundle bundle) async {
    final isRoot = identical(bundle, rootBundle);
    if (isRoot) {
      final cached = _cachedRootBundleGuide;
      if (cached != null) return cached;
      final inFlight = _inFlightRootBundleGuide;
      if (inFlight != null) return inFlight;
    }

    Future<String> load() async {
      FlutterError? lastError;
      for (final asset in _guideAssets) {
        try {
          final guide = await bundle.loadString(asset);
          if (guide.trim().isNotEmpty) {
            if (isRoot) {
              _cachedRootBundleGuide = guide;
            }
            return guide;
          }
          lastError = FlutterError('Asset "$asset" is empty.');
        } on FlutterError catch (error) {
          lastError = error;
        }
      }
      throw FlutterError(
        'Unable to load the Vibe screen guide from '
        '${_guideAssets.map((asset) => '"$asset"').join(' or ')}.'
        '${lastError == null ? '' : ' $lastError'}',
      );
    }

    if (!isRoot) {
      return load();
    }
    final future = load();
    _inFlightRootBundleGuide = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightRootBundleGuide, future)) {
        _inFlightRootBundleGuide = null;
      }
    }
  }

  static Future<String?> _loadRepositoryGuideFromBundle(
    AssetBundle bundle,
  ) async {
    final isRoot = identical(bundle, rootBundle);
    if (isRoot) {
      final cached = _cachedRootBundleRepositoryGuide;
      if (cached != null) return cached;
      final inFlight = _inFlightRootBundleRepositoryGuide;
      if (inFlight != null) return inFlight;
    }

    Future<String?> load() async {
      for (final asset in _repositoryGuideAssets) {
        try {
          final guide = await bundle.loadString(asset);
          if (guide.trim().isNotEmpty) {
            if (isRoot) {
              _cachedRootBundleRepositoryGuide = guide;
            }
            return guide;
          }
        } on FlutterError {
          // Continue vers le chemin de package ou repli gracieux sur les bundles de test minimaux.
        }
      }
      return null;
    }

    if (!isRoot) {
      return load();
    }
    final future = load();
    _inFlightRootBundleRepositoryGuide = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightRootBundleRepositoryGuide, future)) {
        _inFlightRootBundleRepositoryGuide = null;
      }
    }
  }

  static Future<String?> _loadDesignGuideFromBundle(AssetBundle bundle) async {
    final isRoot = identical(bundle, rootBundle);
    if (isRoot) {
      final cached = _cachedRootBundleDesignGuide;
      if (cached != null) return cached;
      final inFlight = _inFlightRootBundleDesignGuide;
      if (inFlight != null) return inFlight;
    }

    Future<String?> load() async {
      for (final asset in _designGuideAssets) {
        try {
          final guide = await bundle.loadString(asset);
          if (guide.trim().isNotEmpty) {
            if (isRoot) {
              _cachedRootBundleDesignGuide = guide;
            }
            return guide;
          }
        } on FlutterError {
          // Continue vers le chemin de package ou repli gracieux sur les bundles de test minimaux.
        }
      }
      return null;
    }

    if (!isRoot) {
      return load();
    }
    final future = load();
    _inFlightRootBundleDesignGuide = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightRootBundleDesignGuide, future)) {
        _inFlightRootBundleDesignGuide = null;
      }
    }
  }

  /// Charge et assemble le guide statique complet (`SCREEN_JSON_AI_GUIDE.md` +
  /// `REPOSITORY_JSON_AI_GUIDE.md` éventuel + `SCREEN_DESIGN_AI_GUIDE.md` +
  /// [designSystemPreset] éventuel + [customDesignGuide] éventuel) depuis [bundle].
  static Future<String> loadStaticGuide(
    AssetBundle bundle, {
    DesignSystemPreset? designSystemPreset,
    String? customDesignGuide,
    bool replaceDefaultDesignGuide = false,
  }) async {
    final trimmedCustom = customDesignGuide?.trim() ?? '';
    final skipDefaultDesign =
        replaceDefaultDesignGuide && trimmedCustom.isNotEmpty;
    final screenGuide = await _loadScreenGuideFromBundle(bundle);
    final repositoryGuide = await _loadRepositoryGuideFromBundle(bundle);
    final defaultDesignGuide = skipDefaultDesign
        ? null
        : await _loadDesignGuideFromBundle(bundle);
    final selectedDesignSystemMarkdown = designSystemPreset == null
        ? null
        : await DesignSystemCatalog.loadMarkdown(
            designSystemPreset,
            bundle: bundle,
          );
    return composeStaticGuide(
      screenGuide: screenGuide,
      repositoryGuide: repositoryGuide,
      defaultDesignGuide: defaultDesignGuide,
      selectedDesignSystemMarkdown: selectedDesignSystemMarkdown,
      selectedDesignSystemName: designSystemPreset?.name,
      customDesignGuide: customDesignGuide,
      replaceDefaultDesignGuide: replaceDefaultDesignGuide,
    );
  }

  /// Précharge en mémoire les guides `SCREEN_JSON_AI_GUIDE.md`,
  /// `REPOSITORY_JSON_AI_GUIDE.md`, `SCREEN_DESIGN_AI_GUIDE.md`
  /// et le référentiel [designSystemPreset] éventuel depuis [bundle], puis préchauffe
  /// silencieusement la connexion TLS ainsi que le cache de contexte Gemini pour [speedMode].
  static Future<void> warmUp(
    AssetBundle bundle, {
    VibeAiSpeedMode speedMode = VibeAiSpeedMode.fast,
    DesignSystemPreset? designSystemPreset,
    String? customDesignGuide,
    bool replaceDefaultDesignGuide = false,
  }) async {
    try {
      final isWidgetTestBinding = WidgetsBinding.instance.runtimeType
          .toString()
          .contains('TestWidgetsFlutterBinding');
      final hasDotenvKey =
          dotenv.isInitialized &&
          (dotenv.env['GEMINI_API_KEY'] ?? '').trim().isNotEmpty;
      if (isWidgetTestBinding &&
          !hasDotenvKey &&
          identical(bundle, rootBundle)) {
        return;
      }
      final guide = await loadStaticGuide(
        bundle,
        designSystemPreset: designSystemPreset,
        customDesignGuide: customDesignGuide,
        replaceDefaultDesignGuide: replaceDefaultDesignGuide,
      );
      if (isWidgetTestBinding && !hasDotenvKey) {
        return;
      }
      await warmUpGemini(
        systemInstruction: defaultSystemInstruction,
        staticGuide: guide,
        speedMode: speedMode,
      );
    } catch (_) {
      // Le préchauffage est purement opportuniste et ne lève jamais d'exception.
    }
  }

  /// Opens the Vibe AI chat targeted at [scope]: reuses the active
  /// `StyleEditBanner` panel when mounted, or falls back to an editor dialog.
  static Future<void> showScoped(
    BuildContext context,
    VibeChatScope scope, {
    String? customDesignGuide,
    bool? replaceDefaultDesignGuide,
  }) async {
    if (VibeChatScope.onOpenRequested case final handler? when handler(scope)) {
      return;
    }
    final appearance = AppearanceScope.controllerOf(context);
    if (appearance == null) return;
    final codec = AppearanceServicesScope.codecOf(context);
    final app = SuperApp.maybeOf(context);
    final registry = app?.registry;
    final repositoryStore =
        app?.repositoryStore ??
        context.getInheritedWidgetOfExactType<JsonRepositoryScope>()?.store;
    final effectiveCustomDesignGuide =
        customDesignGuide ?? app?.customDesignGuide;
    final effectiveReplaceDefaultDesignGuide =
        replaceDefaultDesignGuide ?? (app?.replaceDefaultDesignGuide ?? false);
    var expanded = true;
    await showEditorDialog<void>(
      context: context,
      target: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final screen = MediaQuery.sizeOf(dialogContext);
          final width = expanded
              ? (screen.width <= 520
                    ? screen.width
                    : (screen.width * 0.88).roundToDouble())
              : 440.0;
          final height = expanded
              ? (screen.height <= 360
                    ? screen.height
                    : (screen.height * 0.88).roundToDouble())
              : 600.0;
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: expanded
                ? const EdgeInsets.all(20)
                : const EdgeInsets.only(
                    right: 16,
                    bottom: 16,
                    left: 16,
                    top: 16,
                  ),
            alignment: expanded ? Alignment.center : Alignment.bottomRight,
            child: SizedBox(
              width: width,
              height: height,
              child: VibeChatDialog(
                controller: appearance,
                codec: codec,
                registry: registry,
                repositoryStore: repositoryStore,
                scope: scope,
                customDesignGuide: effectiveCustomDesignGuide,
                replaceDefaultDesignGuide: effectiveReplaceDefaultDesignGuide,
                expanded: expanded,
                onExpandedChanged: (next) {
                  if (expanded == next) return;
                  setDialogState(() => expanded = next);
                },
                onClose: () => Navigator.of(dialogContext).pop(),
                onDrag: (_) {},
                generate: callGemini,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Returns the direct child slot IDs placed inside [component], optionally
  /// restricted to [onlyZoneId].
  /// Returns the direct parent component IDs in [current] that place
  /// [scope.canonicalComponentId], plus [scope.canonicalParentComponentId] if
  /// specified.
  static Set<String> parentIdsOfScope(Appearance current, VibeChatScope scope) {
    return VibeScopeHelpers.parentIdsOfScope(current, scope);
  }

  /// Root component IDs of the effective modifiable scope: the parent
  /// container(s) of [scope.canonicalComponentId] when present, together with
  /// [scope.canonicalComponentId] itself.
  /// Filters an incoming GenUI [patch] so that only changes belonging to
  /// [scope] and its parent container's subtree are kept.
  ///
  /// Out-of-scope edits (ancestors above the parent, unrelated branches,
  /// global theme properties, `pageCatalog`) are stripped automatically.
  static Map<String, dynamic> filterPatchToScope(
    Appearance current,
    Map<String, dynamic> patch,
    VibeChatScope scope,
  ) => VibeScopeHelpers.filterPatchToScope(current, patch, scope);

  /// Exporte un instantané JSON compact et minifié du sous-arbre de [scope]
  /// (incluant son conteneur parent et ses enfants) depuis [appearance] pour le prompt IA.
  static String exportScopedAi(
    Appearance appearance,
    VibeChatScope scope, {
    AppearanceCodec codec = const AppearanceCodec(),
  }) => VibeScopeHelpers.exportScopedAi(appearance, scope, codec: codec);

  @override
  State<VibeChatDialog> createState() => _VibeChatDialogState();
}

class _VibeChatDialogState extends State<VibeChatDialog> {
  static const String _initialGreetingText =
      'Décris l’écran à créer ou les changements souhaités.';
  static const int _maxConversationEntries = 8;

  final _input = TextEditingController();
  final _pendingAttachments = <VibeChatAttachment>[];
  final _messages = <VibeChatMessage>[
    const VibeChatMessage(text: _initialGreetingText, isUser: false),
  ];
  final ValueNotifier<VibeStreamSnapshot?> _streamingSnapshot =
      ValueNotifier<VibeStreamSnapshot?>(null);
  VibeStreamSnapshot? _pendingSnapshot;
  _LiveTurnSession? _activeTurnSession;
  JsonRepositoryStore? _ambientRepositoryStore;
  bool _frameSnapshotScheduled = false;
  bool _didWarmUpDependencies = false;
  bool _sending = false;
  String? _lastFailedResponse;
  String? _attachmentError;
  late VibeChatScope? _scope = widget.scope;
  late VibeAiSpeedMode _speedMode = widget.initialSpeedMode;
  late VibeQuestioningLevel _questioningLevel = widget.initialQuestioningLevel;
  late DesignSystemPreset? _selectedDesignSystem = widget.initialDesignSystem;
  late List<DesignSystemPreset> _customDesignSystems =
      List<DesignSystemPreset>.of(widget.customDesignSystems);
  late bool _expanded = widget.expanded ?? true;

  bool get _isAfterAskUserReply {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (msg.isUser) {
        return msg.promptText != null;
      }
    }
    return false;
  }

  bool get _usesStreamingGenerator =>
      widget.streamGenerate != null || identical(widget.generate, callGemini);

  Appearance get _currentAppearance =>
      widget.registry?.appearanceSnapshot(widget.controller.value) ??
      widget.controller.value;

  static bool get _isWidgetTestBinding => WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  JsonRepositoryStore? _resolveRepositoryStore() {
    if (widget.repositoryStore != null) {
      return widget.repositoryStore;
    }
    final superApp = context
        .getInheritedWidgetOfExactType<SuperAppScope>()
        ?.app;
    if (_isWidgetTestBinding &&
        superApp != null &&
        superApp.repositoryStore == null) {
      final scoped = context
          .getInheritedWidgetOfExactType<JsonRepositoryScope>()
          ?.store;
      if (scoped == null) return null;
      try {
        if (scoped.directory.path ==
            JsonRepositoryStore.defaultStore().directory.path) {
          return null;
        }
      } on FileSystemException {
        return null;
      }
      return scoped;
    }
    return context.getInheritedWidgetOfExactType<JsonRepositoryScope>()?.store ??
        _ambientRepositoryStore ??
        superApp?.repositoryStore;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ambientRepositoryStore =
        JsonRepositoryScope.maybeOf(context) ??
        SuperApp.maybeOf(context)?.repositoryStore;
    if (!_didWarmUpDependencies && _usesStreamingGenerator) {
      _didWarmUpDependencies = true;
      unawaited(
        VibeChatDialog.warmUp(
          DefaultAssetBundle.of(context),
          speedMode: _speedMode,
          designSystemPreset: _selectedDesignSystem,
          customDesignGuide: widget.customDesignGuide,
          replaceDefaultDesignGuide: widget.replaceDefaultDesignGuide,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(VibeChatDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      _scope = widget.scope;
    }
    final presetChanged =
        oldWidget.initialDesignSystem != widget.initialDesignSystem;
    if (presetChanged) {
      _selectedDesignSystem = widget.initialDesignSystem;
    }
    if (!listEquals(
      oldWidget.customDesignSystems,
      widget.customDesignSystems,
    )) {
      _customDesignSystems = List<DesignSystemPreset>.of(
        widget.customDesignSystems,
      );
    }
    final designChanged =
        presetChanged ||
        oldWidget.customDesignGuide != widget.customDesignGuide ||
        oldWidget.replaceDefaultDesignGuide != widget.replaceDefaultDesignGuide;
    if (oldWidget.initialSpeedMode != widget.initialSpeedMode ||
        designChanged) {
      if (oldWidget.initialSpeedMode != widget.initialSpeedMode) {
        _speedMode = widget.initialSpeedMode;
      }
      if (_usesStreamingGenerator) {
        unawaited(
          VibeChatDialog.warmUp(
            DefaultAssetBundle.of(context),
            speedMode: _speedMode,
            designSystemPreset: _selectedDesignSystem,
            customDesignGuide: widget.customDesignGuide,
            replaceDefaultDesignGuide: widget.replaceDefaultDesignGuide,
          ),
        );
      }
    }
    if (oldWidget.initialQuestioningLevel != widget.initialQuestioningLevel) {
      _questioningLevel = widget.initialQuestioningLevel;
    }
    if (widget.expanded != null &&
        widget.expanded != oldWidget.expanded &&
        widget.expanded != _expanded) {
      _expanded = widget.expanded!;
    }
  }

  void _setExpanded(bool expanded) {
    if (_expanded == expanded) return;
    if (mounted) {
      setState(() => _expanded = expanded);
    } else {
      _expanded = expanded;
    }
    widget.onExpandedChanged?.call(expanded);
  }

  void _syncExpansionFromSnapshot(VibeStreamSnapshot snapshot) {
    if (snapshot.hasVibeObject || snapshot.hasRepositoriesObject) {
      _setExpanded(false);
    } else if (snapshot.hasAskUserObject) {
      _setExpanded(true);
    }
  }

  void _setSpeedMode(VibeAiSpeedMode mode) {
    if (_speedMode == mode || _sending) return;
    setState(() => _speedMode = mode);
    if (_usesStreamingGenerator) {
      unawaited(
        VibeChatDialog.warmUp(
          DefaultAssetBundle.of(context),
          speedMode: mode,
          designSystemPreset: _selectedDesignSystem,
          customDesignGuide: widget.customDesignGuide,
          replaceDefaultDesignGuide: widget.replaceDefaultDesignGuide,
        ),
      );
    }
  }

  void _setQuestioningLevel(VibeQuestioningLevel level) {
    if (_questioningLevel == level || _sending) return;
    setState(() => _questioningLevel = level);
    widget.onQuestioningLevelChanged?.call(level);
  }

  void _publishStreamSnapshot(VibeStreamSnapshot snapshot) {
    if (!_frameSnapshotScheduled) {
      _streamingSnapshot.value = snapshot;
      _syncExpansionFromSnapshot(snapshot);
      _applyLivePreviewFromSnapshot(snapshot);
      _frameSnapshotScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _frameSnapshotScheduled = false;
        if (!mounted || !_sending) return;
        final pending = _pendingSnapshot;
        if (pending != null) {
          _pendingSnapshot = null;
          _streamingSnapshot.value = pending;
          _syncExpansionFromSnapshot(pending);
          _applyLivePreviewFromSnapshot(pending);
        }
      });
    } else {
      _pendingSnapshot = snapshot;
    }
  }

  void _setPreviewAppearance(Appearance appearance) {
    final controller = widget.controller;
    if (controller is PersistentAppearanceController) {
      controller.setPreviewValue(appearance);
    } else {
      controller.value = appearance;
    }
  }

  void _syncStreamingWorkHighlight(
    _LiveTurnSession session,
    VibeStreamSnapshot snapshot,
  ) {
    const highlightSections = <String>{
      'components',
      'styles',
      'behaviors',
      'usages',
    };
    final entryKey = snapshot.activeEntryKey;
    final section = snapshot.activeSection;
    if (entryKey == null ||
        entryKey.isEmpty ||
        section == null ||
        !highlightSections.contains(section)) {
      VibeWorkHighlightController.instance.clearStreamingTargets();
      return;
    }
    final activeScope = _scope;
    if (activeScope != null) {
      final allowed = VibeScopeHelpers.existingSubtreeIds(
        session.lastPreviewAppearance,
        activeScope,
      );
      if (entryKey != activeScope.canonicalComponentId &&
          !allowed.contains(entryKey)) {
        VibeWorkHighlightController.instance.clearStreamingTargets();
        return;
      }
    }
    VibeWorkHighlightController.instance.setStreamingTargets([entryKey]);
  }

  void _pulseAppearanceDiff(
    _LiveTurnSession session,
    Appearance nextAppearance,
  ) {
    final diff = VibeAppearanceDiff.compute(
      session.lastPreviewAppearance,
      nextAppearance,
    );
    session.lastPreviewAppearance = nextAppearance;
    if (!diff.isEmpty) {
      VibeWorkHighlightController.instance.pulseTargets(
        addedIds: diff.addedIds,
        modifiedIds: diff.modifiedIds,
      );
    }
  }

  void _applyLivePreviewFromSnapshot(VibeStreamSnapshot snapshot) {
    final session = _activeTurnSession;
    if (session == null ||
        session.livePreviewDisabled ||
        snapshot.hasAskUserObject) {
      return;
    }
    _syncStreamingWorkHighlight(session, snapshot);

    if (session.repoTransaction != null &&
        (snapshot.partialRepositoriesPatch != null ||
            session.repoTransaction!.aliasToActualId.isNotEmpty)) {
      final hasNewRepoRev =
          snapshot.partialRepositoriesPatch != null &&
          snapshot.repositoriesRevision >
              session.lastAppliedRepositoriesRevision;
      final hasNewPatchRev =
          snapshot.partialVibePatch != null &&
          snapshot.patchRevision > session.lastAppliedPatchRevision;
      if (!hasNewRepoRev && !hasNewPatchRev) {
        return;
      }
      final capturedRepoPatch = snapshot.partialRepositoriesPatch;
      final capturedRepoRev = snapshot.repositoriesRevision;
      final capturedVibePatch = snapshot.partialVibePatch;
      final capturedPatchRev = snapshot.patchRevision;

      session.liveRepoQueue = session.liveRepoQueue
          .then((_) async {
            if (!mounted ||
                session.livePreviewDisabled ||
                !identical(_activeTurnSession, session)) {
              return;
            }
            final repoTx = session.repoTransaction!;
            if (capturedRepoPatch != null &&
                capturedRepoRev > session.lastAppliedRepositoriesRevision) {
              session.lastAppliedRepositoriesRevision = capturedRepoRev;
              try {
                await repoTx.applyRepositoriesPatch(capturedRepoPatch);
              } on FormatException {
                // Ignoré pendant le flux incrémental jusqu'à la validation finale.
              } on ArgumentError {
                // Ignoré pendant le flux incrémental.
              } on StateError {
                // Ignoré pendant le flux incrémental.
              }
            }
            if (!mounted ||
                session.livePreviewDisabled ||
                !identical(_activeTurnSession, session)) {
              return;
            }
            if (capturedVibePatch != null &&
                capturedPatchRev > session.lastAppliedPatchRevision) {
              session.lastAppliedPatchRevision = capturedPatchRev;
              final rewritten = repoTx.rewriteVibePatchBindings(
                capturedVibePatch,
              );
              _applyVibePatchPreview(session, rewritten);
            }
          })
          .catchError((Object _) {});
      return;
    }

    if (snapshot.patchRevision <= session.lastAppliedPatchRevision) {
      return;
    }
    session.lastAppliedPatchRevision = snapshot.patchRevision;
    final rawPatch = snapshot.partialVibePatch;
    if (rawPatch == null) return;
    _applyVibePatchPreview(session, rawPatch);
  }

  void _applyVibePatchPreview(
    _LiveTurnSession session,
    Map<String, dynamic> rawPatch,
  ) {
    final activeScope = _scope;
    final effectivePatch = activeScope == null
        ? rawPatch
        : VibeChatDialog.filterPatchToScope(
            session.baseAppearance,
            rawPatch,
            activeScope,
          );
    if (!_hasPatchChanges(effectivePatch)) return;

    try {
      final previewAppearance = AppearanceTransfer.applyVibeMap(
        session.baseAppearance,
        effectivePatch,
        codec: widget.codec,
        normalizeRoundTrip: false,
      );
      widget.validateAppearance?.call(previewAppearance);
      _setPreviewAppearance(previewAppearance);
      _pulseAppearanceDiff(session, previewAppearance);
      session.hasAppliedLivePreview = true;
      if (activeScope == null) {
        _maybeNavigateToNewLivePage(session, previewAppearance);
      }
    } on FormatException {
      // Les erreurs transitoires d'entrées partielles sont ignorées jusqu'à la validation finale.
    } on ArgumentError {
      // Ignoré pendant le flux incrémental.
    } on StateError {
      // Ignoré pendant le flux incrémental.
    }
  }

  void _maybeNavigateToNewLivePage(
    _LiveTurnSession session,
    Appearance appearance,
  ) {
    final routing = session.pageRouting;
    if (routing == null) return;
    final addedPages = [
      for (final page in appearance.pageCatalog.pages)
        if (!session.initialPageIds.contains(page.id)) page,
    ];
    if (addedPages.isEmpty) return;

    final homeId = appearance.pageCatalog.homePageId;
    final targetPage =
        addedPages.where((page) => page.id == homeId).firstOrNull ??
        addedPages.first;
    if (session.liveNavigatedPageId == targetPage.id) return;

    try {
      routing.synchronize(appearance.pageCatalog);
      final requiredParams = routing.parametersOf(targetPage);
      final params = requiredParams.isEmpty
          ? const <String, String>{}
          : targetPage.defaultParameters;
      final location = routing.locationFor(targetPage, params);
      session.liveNavigatedPageId = targetPage.id;
      routing.router.go(location);
    } on FormatException {
      // Chemin ou paramètres par défaut incomplets : pas de navigation forcée.
    }
  }

  void _rollbackLivePreview(_LiveTurnSession session) {
    session.lastAppliedPatchRevision = 0;
    session.lastPreviewAppearance = session.baseAppearance;
    VibeWorkHighlightController.instance.clearAll();
    if (session.hasAppliedLivePreview ||
        !identical(widget.controller.value, session.rawInitialAppearance)) {
      try {
        _setPreviewAppearance(session.rawInitialAppearance);
      } catch (_) {
        // Ignore en cas de contrôleur déjà disposé.
      }
      session.hasAppliedLivePreview = false;
    }
    if (session.liveNavigatedPageId != null) {
      final routing = session.pageRouting;
      final previousLocation = session.initialRouteLocation;
      session.liveNavigatedPageId = null;
      if (routing != null) {
        try {
          routing.synchronize(session.rawInitialAppearance.pageCatalog);
          final currentLocation = routing
              .router
              .routeInformationProvider
              .value
              .uri
              .toString();
          if (previousLocation != null &&
              previousLocation.isNotEmpty &&
              currentLocation != previousLocation) {
            routing.router.go(previousLocation);
          }
        } catch (_) {
          // Ignore lors de la restauration de route.
        }
      }
    }
  }

  Future<void> _rollbackTurnSession(_LiveTurnSession session) async {
    session.livePreviewDisabled = true;
    try {
      await session.liveRepoQueue;
    } catch (_) {
      // Ignore les erreurs éventuelles de la file live.
    }
    _rollbackLivePreview(session);
    try {
      await session.repoTransaction?.rollback();
    } catch (_) {
      // Ignore en cas de store indisponible lors de l'annulation.
    }
    session.lastAppliedRepositoriesRevision = 0;
  }

  void _clearScope() {
    setState(() => _scope = null);
    widget.onScopeChanged?.call(null);
  }

  Future<void> _openDesignSystemCatalog() async {
    if (_sending) return;
    final bundle = DefaultAssetBundle.of(context);
    final result = await DesignSystemCatalogDialog.show(
      context,
      initialPreset: _selectedDesignSystem,
      customPresets: _customDesignSystems,
      isScoped: _scope != null,
      pickMarkdownFiles: widget.pickAttachments,
      readClipboardText: widget.readClipboardText,
      assetBundle: bundle,
    );
    if (!mounted || result == null) return;

    final customsChanged = !listEquals(
      _customDesignSystems,
      result.updatedCustomPresets,
    );
    final presetChanged = _selectedDesignSystem != result.preset;

    if (customsChanged || presetChanged) {
      setState(() {
        if (customsChanged) {
          _customDesignSystems = List<DesignSystemPreset>.of(
            result.updatedCustomPresets,
          );
        }
        if (presetChanged) {
          _selectedDesignSystem = result.preset;
        }
      });
      if (customsChanged) {
        widget.onCustomDesignSystemsChanged?.call(
          List<DesignSystemPreset>.unmodifiable(_customDesignSystems),
        );
      }
      if (presetChanged) {
        widget.onDesignSystemChanged?.call(result.preset);
        if (_usesStreamingGenerator) {
          unawaited(
            VibeChatDialog.warmUp(
              bundle,
              speedMode: _speedMode,
              designSystemPreset: result.preset,
              customDesignGuide: widget.customDesignGuide,
              replaceDefaultDesignGuide: widget.replaceDefaultDesignGuide,
            ),
          );
        }
      }
    }

    final selectedPreset = result.preset;
    if (result.applyThemeTokensNow &&
        selectedPreset != null &&
        _scope == null) {
      final current = widget.controller.value;
      final palette = selectedPreset.palette;
      if (current.mode != palette.mode || current.accent != palette.accent) {
        final history = EditorHistoryScope.controllerOf(context);
        history?.beginTransaction();
        try {
          widget.controller.value = current.copyWith(
            mode: palette.mode,
            accent: palette.accent,
          );
        } finally {
          history?.commitTransaction();
        }
      }
    }

    if (result.triggerImmediateRestyle && selectedPreset != null) {
      await _restyleWithSelectedDesignSystem();
    }
  }

  void _clearDesignSystem() {
    if (_sending || _selectedDesignSystem == null) return;
    setState(() => _selectedDesignSystem = null);
    widget.onDesignSystemChanged?.call(null);
    if (_usesStreamingGenerator) {
      unawaited(
        VibeChatDialog.warmUp(
          DefaultAssetBundle.of(context),
          speedMode: _speedMode,
          customDesignGuide: widget.customDesignGuide,
          replaceDefaultDesignGuide: widget.replaceDefaultDesignGuide,
        ),
      );
    }
  }

  Future<void> _restyleWithSelectedDesignSystem() async {
    final preset = _selectedDesignSystem;
    if (preset == null || _sending) return;

    _setExpanded(false);
    setState(() {
      _attachmentError = null;
      for (var i = 0; i < _messages.length; i++) {
        final msg = _messages[i];
        if (msg.askUser != null &&
            msg.askUserAnswers == null &&
            !msg.askUserDismissed) {
          _messages[i] = msg.copyWith(askUserDismissed: true);
        }
      }
    });

    final activeScope = _scope;
    final palette = preset.palette;
    final modeName = palette.isDark ? 'dark' : 'light';
    final accentHex = DesignSystemPalettePreview.colorToHex(palette.accent);
    final canvasHex = DesignSystemPalettePreview.colorToHex(palette.canvas);
    final surfaceHex = DesignSystemPalettePreview.colorToHex(palette.surface);
    final textHex = DesignSystemPalettePreview.colorToHex(palette.textPrimary);
    final mutedHex = DesignSystemPalettePreview.colorToHex(palette.textMuted);
    final borderHex = DesignSystemPalettePreview.colorToHex(palette.border);
    final radiusValue = palette.cardRadius;
    final surfaceSystemName = palette.surfaceSystem.name;

    final displayUserText = activeScope == null
        ? 'Restyler l’écran selon le Design System ${preset.name}.'
        : 'Restyler ${activeScope.displayLabel} selon le Design System ${preset.name}.';

    final promptOverride = activeScope == null
        ? 'RESTYLAGE COMPLET SELON LE SYSTÈME DE DESIGN "${preset.name}" :\n'
              'Ne pose pas de questionnaire "askUser" : génère directement le patch "vibe".\n'
              'Restyle intégralement l’écran actuel conformément au référentiel DESIGN.md actif ("${preset.name}") :\n'
              '- Mets à jour "mode": "$modeName" et "accent": "$accentHex".\n'
              '- Mets à jour "styles" : "background" ("color": "$canvasHex") ainsi que toutes les surfaces de cartes, panneaux, en-têtes et lignes de collection ("color": "$surfaceHex", états "hover" et "selected" cohérents, "radius": $radiusValue, "borderWidth" et "borderColor": "$borderHex", "elevation", "shadowOpacity" et "designSystem": "$surfaceSystemName").\n'
              '- Harmonise la typographie ("fontFamily", "fontSize", "fontWeight") et les couleurs des composants existants SuperValue (texte primaire "$textHex", secondaire "$mutedHex"), SuperAction (variantes, rayons et contraste AA sur "$accentHex") et SuperIndicator.\n'
              '- Préserve à 100 % la structure métier existante : conserve tous les identifiants de composants, placements, liaisons de données (bindings), usages, comportements (behaviors) et pages (pageCatalog).'
        : 'RESTYLAGE DU PÉRIMÈTRE "${activeScope.displayLabel}" SELON LE SYSTÈME DE DESIGN "${preset.name}" :\n'
              'Ne pose pas de questionnaire "askUser" : génère directement le patch "vibe".\n'
              'Restyle uniquement le périmètre ciblé "${activeScope.displayLabel}" (id: "${activeScope.canonicalComponentId}") et son sous-arbre autorisé conformément au référentiel DESIGN.md actif ("${preset.name}") :\n'
              '- Mets à jour uniquement les styles de conteneurs du périmètre (couleurs de surface "$surfaceHex", états "hover" et "selected", "radius": $radiusValue, "borderWidth", "borderColor": "$borderHex", "elevation" et "designSystem": "$surfaceSystemName").\n'
              '- Harmonise la typographie et les couleurs des composants SuperValue (texte primaire "$textHex", secondaire "$mutedHex"), SuperAction et SuperIndicator appartenant à ce périmètre.\n'
              '- Ne modifie aucune propriété globale de thème ("mode", "accent", styles["background"]) ni "pageCatalog".\n'
              '- Préserve à 100 % les identifiants de composants, placements, liaisons de données (bindings), usages et comportements (behaviors) existants.';

    await _runGenerationTurn(
      displayUserText: displayUserText,
      promptOverride: promptOverride,
    );
  }

  @override
  void dispose() {
    if (_activeTurnSession != null) {
      VibeWorkHighlightController.instance.clearStreamingTargets();
    }
    _pendingSnapshot = null;
    _streamingSnapshot.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _attachFromPicker() async {
    if (_sending) return;
    setState(() => _attachmentError = null);
    try {
      final picker = widget.pickAttachments ?? VibeChatAttachment.pickFiles;
      final picked = await picker();
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _pendingAttachments.addAll(picked);
        _attachmentError = null;
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _attachmentError = error.message);
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(
          () => _attachmentError = 'Lecture impossible : ${error.message}',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _attachmentError =
              'Impossible d’importer le fichier : ${_describeErrorCause(error)}',
        );
      }
    }
  }

  Future<void> _attachFromClipboard() async {
    if (_sending) return;
    setState(() => _attachmentError = null);
    try {
      final paster =
          widget.pasteAttachments ?? VibeChatAttachment.fromClipboard;
      final pasted = await paster();
      if (!mounted) return;
      if (pasted.isEmpty) {
        setState(
          () => _attachmentError =
              'Aucun fichier ou texte trouvé dans le presse-papiers.',
        );
        return;
      }
      setState(() {
        _pendingAttachments.addAll(pasted);
        _attachmentError = null;
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _attachmentError = error.message);
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(
          () => _attachmentError = 'Lecture impossible : ${error.message}',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _attachmentError =
              'Impossible de coller depuis le presse-papiers : '
              '${_describeErrorCause(error)}',
        );
      }
    }
  }

  void _removePendingAttachment(int index) {
    if (_sending || index < 0 || index >= _pendingAttachments.length) return;
    setState(() {
      _pendingAttachments.removeAt(index);
      _attachmentError = null;
    });
  }

  String _describeErrorCause(Object error) {
    if (error is FormatException) {
      final offset = error.offset;
      final source = error.source;
      if (offset != null && source is String && source.isNotEmpty) {
        final start = (offset - 40).clamp(0, source.length);
        final end = (offset + 40).clamp(0, source.length);
        final snippet = source.substring(start, end).replaceAll('\n', ' ');
        return '${error.message} (offset $offset, près de "$snippet")';
      }
      return error.message;
    }
    if (error is ArgumentError) {
      final name = error.name;
      final message = error.message?.toString() ?? error.toString();
      return name != null && name.isNotEmpty ? '$name : $message' : message;
    }
    if (error is StateError) {
      return error.message;
    }
    if (error is FlutterError) {
      return error.message;
    }
    return '$error';
  }

  Future<void> _send() async {
    final request = _input.text.trim();
    final attachments = List<VibeChatAttachment>.unmodifiable(
      _pendingAttachments,
    );
    if ((request.isEmpty && attachments.isEmpty) || _sending) return;
    _input.clear();
    if (_questioningLevel == VibeQuestioningLevel.none) {
      _setExpanded(false);
    }
    setState(() {
      _pendingAttachments.clear();
      _attachmentError = null;
      for (var i = 0; i < _messages.length; i++) {
        final msg = _messages[i];
        if (msg.askUser != null &&
            msg.askUserAnswers == null &&
            !msg.askUserDismissed) {
          _messages[i] = msg.copyWith(askUserDismissed: true);
        }
      }
    });
    await _runGenerationTurn(
      displayUserText: request,
      attachments: attachments,
    );
  }

  Future<void> _submitAskUser(
    int messageIndex,
    Map<String, Object?> answers, {
    required bool usedDefaults,
  }) async {
    if (_sending || messageIndex < 0 || messageIndex >= _messages.length) {
      return;
    }
    final target = _messages[messageIndex];
    final request = target.askUser;
    if (request == null ||
        target.askUserAnswers != null ||
        target.askUserDismissed) {
      return;
    }
    final normalizedAnswers = Map<String, Object?>.unmodifiable(answers);
    _setExpanded(false);
    setState(() {
      _messages[messageIndex] = target.copyWith(
        askUserAnswers: normalizedAnswers,
        askUserUsedDefaults: usedDefaults,
      );
    });
    final summary = request.formatDisplaySummary(
      normalizedAnswers,
      usedDefaults: usedDefaults,
    );
    final displaySummary =
        '${usedDefaults ? 'Valeurs par défaut retenues' : 'Choix validés'} :\n$summary';
    final promptReply = request.formatPromptReply(
      normalizedAnswers,
      usedDefaults: usedDefaults,
    );
    await _runGenerationTurn(
      displayUserText: displaySummary,
      promptOverride: promptReply,
    );
  }

  Future<void> _runGenerationTurn({
    required String displayUserText,
    String? promptOverride,
    List<VibeChatAttachment> attachments = const [],
  }) async {
    final history = EditorHistoryScope.controllerOf(context);
    final resolvedPageRouting =
        widget.pageRouting ?? SuperApp.maybeOf(context)?.pageRouting;
    final resolvedRepositoryStore = _resolveRepositoryStore();
    final rawInitialAppearance = widget.controller.value;
    final baseAppearance = _currentAppearance;
    final initialInstantiatedIds = widget.registry == null
        ? null
        : Set<String>.unmodifiable(widget.registry!.instantiatedComponentIds);
    final session = _LiveTurnSession(
      rawInitialAppearance: rawInitialAppearance,
      baseAppearance: baseAppearance,
      initialInstantiatedIds: initialInstantiatedIds,
      pageRouting: resolvedPageRouting,
      initialRouteLocation: resolvedPageRouting
          ?.router
          .routeInformationProvider
          .value
          .uri
          .toString(),
      initialPageIds: {
        for (final page in baseAppearance.pageCatalog.pages) page.id,
      },
      repoTransaction: resolvedRepositoryStore == null
          ? null
          : VibeRepositoryTurnTransaction(resolvedRepositoryStore),
    );

    _lastFailedResponse = null;
    _activeTurnSession = session;
    setState(() {
      _sending = true;
      _messages.add(
        VibeChatMessage(
          text: displayUserText,
          promptText: promptOverride,
          isUser: true,
          attachments: attachments,
        ),
      );
    });

    debugPrint(
      '[Vibe IA] Nouvelle demande utilisateur : "$displayUserText" '
      '(pièces jointes: ${attachments.map((a) => a.name).toList()})',
    );
    history?.beginTransaction();
    try {
      final guide = await _loadGuide(context);
      final repositoriesContext = resolvedRepositoryStore == null
          ? null
          : await VibeRepositoryPromptFormatter.formatStoreContext(
              resolvedRepositoryStore,
            );
      final turnPrompt = _buildTurnPrompt(
        appearanceOverride: session.baseAppearance,
        instantiatedIdsOverride: session.initialInstantiatedIds,
        repositoriesContext: repositoriesContext,
      );
      final generated = await _generateAndApply(
        turnPrompt,
        systemGuide: guide,
        session: session,
        attachments: attachments,
      );
      final hasMutations =
          generated.appearance != null || generated.repositoriesUpdated;
      if (hasMutations) {
        _setExpanded(false);
        if (generated.appearance case final appearance?) {
          widget.controller.value = appearance;
          _pulseAppearanceDiff(session, appearance);
          if (_scope == null) {
            _maybeNavigateToNewLivePage(session, appearance);
          }
          debugPrint(
            '[Vibe IA] Apparence mise à jour avec succès '
            '(composants: ${appearance.components.length}, '
            'styles: ${appearance.styles.length}, '
            'pages: ${appearance.pageCatalog.pages.length}'
            '${generated.repositoriesUpdated ? ', repositories mis à jour' : ''}).',
          );
        } else {
          _rollbackLivePreview(session);
          debugPrint('[Vibe IA] Repositories JSON mis à jour avec succès.');
        }
        if (session.repoTransaction?.buildHistoryCallbacks()
            case final repoCallbacks?) {
          history?.addTransactionSideEffect(
            undo: repoCallbacks.undo,
            redo: repoCallbacks.redo,
          );
        }
      } else {
        await _rollbackTurnSession(session);
        if (generated.askUser case final askUser?) {
          _setExpanded(true);
          debugPrint(
            '[Vibe IA] Questionnaire de clarification reçu '
            '(${askUser.questions.length} question(s)).',
          );
        } else {
          debugPrint(
            '[Vibe IA] Réponse textuelle affichée sans modification d’apparence.',
          );
        }
      }
      final summary = generated.result['message'];
      final fallbackText = generated.askUser != null && !hasMutations
          ? 'Précise tes préférences :'
          : 'Modifications appliquées.';
      _appendMessage(
        summary is String && summary.trim().isNotEmpty
            ? summary.trim()
            : fallbackText,
        askUser: !hasMutations ? generated.askUser : null,
      );
    } on FormatException catch (error, stackTrace) {
      await _rollbackTurnSession(session);
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed (FormatException): $cause\n'
        'Source: ${error.source ?? "n/a"} (offset: ${error.offset ?? "n/a"})\n'
        '$stackTrace',
      );
      _appendMessage(
        'Réponse Vibe invalide : $cause',
        failedResponse: _lastFailedResponse,
      );
    } on ArgumentError catch (error, stackTrace) {
      await _rollbackTurnSession(session);
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed (ArgumentError): $cause\n$stackTrace',
      );
      _appendMessage(
        'Modification refusée : $cause',
        failedResponse: _lastFailedResponse,
      );
    } on StateError catch (error, stackTrace) {
      await _rollbackTurnSession(session);
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed (StateError): $cause\n$stackTrace',
      );
      _appendMessage(
        'Modification impossible : $cause',
        failedResponse: _lastFailedResponse,
      );
    } on FlutterError catch (error, stackTrace) {
      await _rollbackTurnSession(session);
      final cause = _describeErrorCause(error);
      debugPrint('AI screen guide could not be loaded: $cause\n$stackTrace');
      _appendMessage(
        'Guide de génération indisponible : $cause',
        failedResponse: _lastFailedResponse,
      );
    } on Exception catch (error, stackTrace) {
      await _rollbackTurnSession(session);
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed (${error.runtimeType}): $cause\n'
        '$stackTrace',
      );
      _appendMessage(
        'Génération impossible (${error.runtimeType}) : $cause',
        failedResponse: _lastFailedResponse,
      );
    } catch (error, stackTrace) {
      await _rollbackTurnSession(session);
      final cause = _describeErrorCause(error);
      debugPrint(
        'AI screen generation failed with unexpected error '
        '(${error.runtimeType}): $cause\n$stackTrace',
      );
      _appendMessage(
        'Génération impossible (${error.runtimeType}) : $cause',
        failedResponse: _lastFailedResponse,
      );
    } finally {
      VibeWorkHighlightController.instance.clearStreamingTargets();
      _activeTurnSession = null;
      _pendingSnapshot = null;
      _streamingSnapshot.value = null;
      history?.commitTransaction();
      if (mounted) setState(() => _sending = false);
    }
  }

  void _logLong(String title, String content) {
    if (!VibeChatDialog.verboseLogging) {
      debugPrint('$title (${content.length} caractères).');
      return;
    }
    debugPrint('$title (${content.length} caractères) :');
    const chunkSize = 800;
    if (content.length <= chunkSize) {
      debugPrint(content);
      return;
    }
    for (var start = 0; start < content.length; start += chunkSize) {
      final end = (start + chunkSize < content.length)
          ? start + chunkSize
          : content.length;
      debugPrint(content.substring(start, end));
    }
  }

  Future<String> _invokeGenerate(
    String prompt,
    List<VibeChatAttachment> attachments,
  ) {
    final generator = widget.generate;
    if (generator
        is Future<String> Function(
          String, {
          List<VibeChatAttachment> attachments,
        })) {
      return generator(prompt, attachments: attachments);
    }
    return generator(prompt);
  }

  Future<String> _consumeStreamingGenerate(
    String turnPrompt, {
    required String systemGuide,
    required List<VibeChatAttachment> attachments,
  }) async {
    final streamFn = widget.streamGenerate ?? streamGemini;
    final parser = VibeIncrementalStreamParser();
    _pendingSnapshot = null;
    _streamingSnapshot.value = VibeStreamSnapshot.empty;

    var finalAccumulated = '';
    final stream = streamFn(
      turnPrompt,
      systemInstruction: VibeChatDialog.defaultSystemInstruction,
      staticGuide: systemGuide,
      attachments: attachments,
      speedMode: _speedMode,
    );

    await for (final event in stream) {
      if (event.deltaText.isNotEmpty) {
        final snapshot = parser.addChunk(event.deltaText);
        _publishStreamSnapshot(snapshot);
      } else if (event.isDone &&
          parser.rawBuffer.isEmpty &&
          event.accumulatedText.isNotEmpty) {
        parser.addChunk(event.accumulatedText);
      }
      if (event.accumulatedText.isNotEmpty) {
        finalAccumulated = event.accumulatedText;
      }
      if (event.isDone) {
        _pendingSnapshot = null;
        _streamingSnapshot.value = parser.current;
      }
    }

    return parser.rawBuffer.isNotEmpty ? parser.rawBuffer : finalAccumulated;
  }

  Future<
    ({
      Appearance? appearance,
      bool repositoriesUpdated,
      Map<String, dynamic> result,
      VibeAskUserRequest? askUser,
    })
  >
  _generateAndApply(
    String turnPrompt, {
    required String systemGuide,
    required _LiveTurnSession session,
    List<VibeChatAttachment> attachments = const [],
  }) async {
    var currentTurnPrompt = turnPrompt;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        _pendingSnapshot = null;
        _streamingSnapshot.value = null;
        await _rollbackTurnSession(session);
        session.livePreviewDisabled = false;
        session.liveRepoQueue = Future<void>.value();
      }
      final useStreaming = _usesStreamingGenerator;
      debugPrint(
        '[Vibe IA] Tentative ${attempt + 1}/4 — envoi du prompt '
        '(${currentTurnPrompt.length} caractères dynamiques, '
        'mode: ${useStreaming ? _speedMode.name : "custom"}, '
        'fichiers joints: ${attachments.length})...',
      );
      final String response;
      try {
        if (useStreaming) {
          response = await _consumeStreamingGenerate(
            currentTurnPrompt,
            systemGuide: systemGuide,
            attachments: attachments,
          );
        } else {
          final combinedPrompt =
              '${VibeChatDialog.defaultSystemInstruction}\n\n'
              'GUIDE DE MODÉLISATION :\n$systemGuide\n\n'
              '$currentTurnPrompt';
          response = await _invokeGenerate(combinedPrompt, attachments);
        }
      } catch (error, stackTrace) {
        debugPrint(
          '[Vibe IA] Échec de génération à la tentative ${attempt + 1} '
          '(${error.runtimeType}) : $error\n$stackTrace',
        );
        rethrow;
      }
      session.livePreviewDisabled = true;
      try {
        await session.liveRepoQueue;
      } catch (_) {
        // Ignore les erreurs transitoires de la file live avant validation finale.
      }
      _lastFailedResponse = response;
      _logLong('[Vibe IA] Réponse brute (tentative ${attempt + 1})', response);
      try {
        final json = _extractJson(response);
        final Object? result;
        try {
          result = jsonDecode(json);
        } on FormatException catch (error) {
          debugPrint(
            '[Vibe IA] Échec de jsonDecode (tentative ${attempt + 1}) : '
            '${error.message} (offset: ${error.offset})',
          );
          rethrow;
        }
        if (result is! Map<String, dynamic>) {
          debugPrint(
            '[Vibe IA] Le JSON décodé n’est pas un Map<String, dynamic> '
            '(type reçu: ${result.runtimeType}).',
          );
          throw const FormatException('La réponse doit être un objet JSON.');
        }
        final rawAskUser = VibeAskUserRequest.tryFromJson(result['askUser']);
        final repositoriesPatch = _extractRepositoriesPatch(result);
        final patch = _extractPatch(result);
        if (repositoriesPatch == null && patch == null) {
          if (rawAskUser != null &&
              (_questioningLevel == VibeQuestioningLevel.none ||
                  _isAfterAskUserReply)) {
            throw const FormatException(
              'Le questionnaire "askUser" est désactivé sur ce tour : '
              'génère directement le patch "vibe" sans "askUser".',
            );
          }
          final askUser = rawAskUser?.truncate(_questioningLevel.maxQuestions);
          final message = result['message'];
          if (askUser == null &&
              (message is! String || message.trim().isEmpty)) {
            debugPrint(
              '[Vibe IA] Réponse sans patch ni message valide. '
              'Clés reçues: ${result.keys.toList()}',
            );
            throw const FormatException(
              'La réponse ne contient ni message ni modification.',
            );
          }
          _lastFailedResponse = null;
          return (
            appearance: null,
            repositoriesUpdated: false,
            result: result,
            askUser: askUser,
          );
        }
        if (repositoriesPatch != null) {
          final repoTx = session.repoTransaction;
          if (repoTx == null) {
            throw const FormatException(
              'Aucun JsonRepositoryStore n’est actif dans ce contexte : '
              'retire la clé "repositories" et utilise des valeurs statiques.',
            );
          }
          await repoTx.applyRepositoriesPatch(repositoriesPatch);
        }
        Appearance? appearance;
        if (patch != null) {
          final rewrittenPatch = session.repoTransaction != null
              ? session.repoTransaction!.rewriteVibePatchBindings(patch)
              : patch;
          final current = session.baseAppearance;
          final activeScope = _scope;
          final effectivePatch = activeScope == null
              ? rewrittenPatch
              : VibeChatDialog.filterPatchToScope(
                  current,
                  rewrittenPatch,
                  activeScope,
                );
          if (activeScope != null && !_hasPatchChanges(effectivePatch)) {
            final parents = VibeChatDialog.parentIdsOfScope(
              current,
              activeScope,
            );
            throw FormatException(
              'Modifications hors du scope autorisé (${activeScope.displayLabel}, '
              'id: "${activeScope.canonicalComponentId}"'
              '${activeScope.zoneId != null ? ', zone: "${activeScope.zoneId}"' : ''}'
              '${parents.isNotEmpty ? ', parent: "${parents.join(', ')}"' : ''}). '
              'Modifie uniquement ce scope ou son conteneur parent.',
            );
          }
          final encodedPatch = jsonEncode(effectivePatch);
          if (VibeChatDialog.verboseLogging) {
            final formattedPatch = const JsonEncoder.withIndent('  ')
                .convert(effectivePatch);
            _logLong('[Vibe IA] Patch à appliquer', formattedPatch);
          } else {
            debugPrint(
              '[Vibe IA] Patch à appliquer (${encodedPatch.length} caractères).',
            );
          }
          try {
            appearance = AppearanceTransfer.applyVibe(
              current,
              encodedPatch,
              codec: widget.codec,
            );
          } catch (error, stackTrace) {
            debugPrint(
              '[Vibe IA] Échec lors de AppearanceTransfer.applyVibe '
              '(tentative ${attempt + 1}, ${error.runtimeType}) : $error\n'
              '$stackTrace',
            );
            rethrow;
          }
          try {
            widget.validateAppearance?.call(appearance);
          } catch (error, stackTrace) {
            debugPrint(
              '[Vibe IA] Échec lors de validateAppearance '
              '(tentative ${attempt + 1}, ${error.runtimeType}) : $error\n'
              '$stackTrace',
            );
            rethrow;
          }
          _validatePatchedComponents(
            current,
            appearance,
            effectivePatch,
            instantiatedIds: session.initialInstantiatedIds,
          );
        }
        _lastFailedResponse = null;
        return (
          appearance: appearance,
          repositoriesUpdated: repositoriesPatch != null,
          result: result,
          askUser: null,
        );
      } catch (error) {
        await _rollbackTurnSession(session);
        final isValidationError =
            error is FormatException ||
            error is ArgumentError ||
            error is StateError;
        if (attempt != 0 || !isValidationError) {
          debugPrint(
            '[Vibe IA] Tentative ${attempt + 1} échouée sans relance '
            '(${error.runtimeType}) : ${_describeErrorCause(error)}',
          );
          rethrow;
        }
        final cause = _describeErrorCause(error);
        debugPrint(
          '[Vibe IA] Tentative ${attempt + 1} rejetée ($cause). '
          'Relance avec prompt de correction...',
        );
        currentTurnPrompt =
            '''
$currentTurnPrompt

CORRECTION REQUISE :
La réponse précédente a été refusée.
Cause de l'erreur (${error.runtimeType}) :
$cause
Corrige la réponse en respectant strictement le schéma JSON du guide et en rattachant tous les nouveaux composants à un conteneur existant de l'état actuel ou à une page déclarée dans pageCatalog.
Réutilise les identifiants existants ; les identifiants du guide sont uniquement des exemples.
Si tu utilises "repositories", chaque "data" doit être un objet JSON {...} à la racine sans aucune clé débutant par "@" ni contenant ".", "[", "]", "?" ou espace, placé après "message" et avant "vibe" (uniquement si REPOSITORIES DISPONIBLES figure dans le contexte).
Si tu crées une page, son chemin doit commencer par un seul "/", être différent de "/" et ne contenir ni espace, ni "?", ni "#"; ne termine pas le chemin par "/".
Tu peux aussi éviter de créer une page si la demande ne le nécessite pas.
Réponse précédente invalide :
$response
''';
      }
    }
    throw StateError('La génération Vibe n’a pas produit de réponse valide.');
  }

  Map<String, dynamic>? _extractRepositoriesPatch(Map<String, dynamic> result) {
    if (!result.containsKey('repositories') || result['repositories'] == null) {
      return null;
    }
    final repositories = result['repositories'];
    if (repositories is! Map<String, dynamic>) {
      throw const FormatException(
        'Le champ "repositories" doit être un objet JSON ou null.',
      );
    }
    return repositories.isEmpty ? null : repositories;
  }

  Map<String, dynamic>? _extractPatch(Map<String, dynamic> result) {
    if (result.containsKey('vibe') && result['vibe'] is! bool) {
      final vibe = result['vibe'];
      if (vibe == null) return null;
      if (vibe is! Map<String, dynamic>) {
        throw const FormatException(
          'Le champ "vibe" doit être un objet JSON ou null.',
        );
      }
      return _hasPatchChanges(vibe) ? vibe : null;
    }
    final candidate = Map<String, dynamic>.of(result)
      ..remove('message')
      ..remove('askUser')
      ..remove('repositories');
    return _hasPatchChanges(candidate) ? candidate : null;
  }

  bool _hasPatchChanges(Map<String, dynamic> patch) {
    final payload = patch['data'] is Map<String, dynamic>
        ? patch['data'] as Map<String, dynamic>
        : patch;
    const metaKeys = {'version', 'vibe', 'merge', 'format', 'groups'};
    for (final entry in payload.entries) {
      if (metaKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value == null) continue;
      if (value is Map && value.isEmpty) continue;
      return true;
    }
    return false;
  }

  void _validatePatchedComponents(
    Appearance current,
    Appearance next,
    Map<String, dynamic> patch, {
    Set<String>? instantiatedIds,
  }) {
    final activeScope = _scope;
    final reachable = <String>{};
    if (activeScope != null) {
      final pending = <String>[
        ...VibeScopeHelpers.scopeRootIds(current, activeScope),
      ];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (!reachable.add(id)) continue;
        pending.addAll(
          VibeScopeHelpers.childrenOfComponent(next.components[id]),
        );
      }
    } else {
      final effectiveInstantiatedIds =
          instantiatedIds ?? widget.registry?.instantiatedComponentIds;
      final pending = [
        ...?effectiveInstantiatedIds,
        if (widget.registry == null && instantiatedIds == null)
          ...current.components.keys,
        for (final page in next.pageCatalog.pages) page.id,
      ];
      while (pending.isNotEmpty) {
        final id = pending.removeLast();
        if (!reachable.add(id)) continue;
        final component = next.components[id];
        final children = switch (component) {
          final SuperLayoutConfig layout => layout.placedSlotIds,
          final SuperListViewConfig list => list.template.placedSlotIds,
          final SuperTabConfig tab => tab.placedSlotIds,
          final SuperConditionalConfig cond => cond.placedSlotIds,
          final NativeComponentConfig native => native.placements.values.expand(
            (ids) => ids,
          ),
          final ScaffoldPageConfig scaffold =>
            scaffold.native.placements.values.expand((ids) => ids),
          _ => VibeScopeHelpers.childrenOfComponent(component),
        };
        pending.addAll(children);
      }
    }
    final payload = patch['data'] is Map ? patch['data'] as Map : patch;
    final patchedComponents = payload['components'];
    final affected = patchedComponents is Map
        ? patchedComponents.keys.whereType<String>()
        : next.components.keys.where(
            (id) => !current.components.containsKey(id),
          );
    final detached = affected
        .where(
          (id) => next.components.containsKey(id) && !reachable.contains(id),
        )
        .toList();
    if (detached.isNotEmpty) {
      debugPrint(
        '[Vibe IA] Composants détachés détectés : $detached '
        '(composants accessibles depuis l’écran : ${reachable.toList()}).',
      );
      throw FormatException(
        'Composants non rattachés à l’écran : ${detached.join(', ')}. '
        'Modifie les placements d’un conteneur existant ou déclare une page.',
      );
    }
  }

  Future<String> _loadGuide(BuildContext context) =>
      VibeChatDialog.loadStaticGuide(
        DefaultAssetBundle.of(context),
        designSystemPreset: _selectedDesignSystem,
        customDesignGuide: widget.customDesignGuide,
        replaceDefaultDesignGuide: widget.replaceDefaultDesignGuide,
      );

  String _buildConversationHistory() {
    return VibePromptBuilder.buildConversationHistory(
      _messages,
      initialGreetingText: _initialGreetingText,
      maxEntries: _maxConversationEntries,
    );
  }

  String _buildTurnPrompt({
    Appearance? appearanceOverride,
    Iterable<String>? instantiatedIdsOverride,
    String? repositoriesContext,
  }) {
    return VibePromptBuilder.buildTurnPrompt(
      questioningDirective: _questioningLevel.promptDirective(
        afterAskUserReply: _isAfterAskUserReply,
      ),
      conversation: _buildConversationHistory(),
      appearance: appearanceOverride ?? _currentAppearance,
      codec: widget.codec,
      scope: _scope,
      instantiatedComponentIds:
          instantiatedIdsOverride ?? widget.registry?.instantiatedComponentIds,
      repositoriesContext: repositoriesContext,
    );
  }

  static IconData _iconForSpeedMode(VibeAiSpeedMode mode) => switch (mode) {
    VibeAiSpeedMode.ultraFast => Icons.bolt,
    VibeAiSpeedMode.fast => Icons.flash_on,
    VibeAiSpeedMode.reasoning => Icons.psychology_outlined,
  };

  static IconData _iconForQuestioningLevel(VibeQuestioningLevel level) =>
      switch (level) {
        VibeQuestioningLevel.none => Icons.speaker_notes_off_outlined,
        VibeQuestioningLevel.light => Icons.help_outline,
        VibeQuestioningLevel.balanced => Icons.quiz_outlined,
        VibeQuestioningLevel.thorough => Icons.fact_check_outlined,
      };

  String _extractJson(String response) {
    var value = response.trim();
    if (value.startsWith('```')) {
      final newline = value.indexOf('\n');
      if (newline < 0) {
        throw const FormatException('Aucun objet JSON détecté.');
      }
      value = value.substring(newline + 1).trim();
      if (value.endsWith('```')) {
        value = value.substring(0, value.length - 3).trim();
      }
    }
    return value;
  }

  void _appendMessage(
    String text, {
    String? failedResponse,
    VibeAskUserRequest? askUser,
  }) {
    if (!mounted) return;
    setState(
      () => _messages.add(
        VibeChatMessage(
          text: text,
          isUser: false,
          failedResponse: failedResponse,
          askUser: askUser,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('vibe-chat-dialog'),
      color: scheme.surface,
      elevation: 18,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          GestureDetector(
            key: const ValueKey('vibe-chat-drag'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => widget.onDrag(details.delta),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              color: scheme.primary,
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: scheme.onPrimary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Vibe — création d’écran',
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.drag_indicator, color: scheme.onPrimary, size: 18),
                  if (widget.onExpandedChanged != null)
                    IconButton(
                      key: const ValueKey('vibe-chat-toggle-expand'),
                      tooltip: _expanded
                          ? 'Réduire en bas à droite'
                          : 'Agrandir au centre',
                      onPressed: () => _setExpanded(!_expanded),
                      icon: Icon(
                        _expanded ? Icons.close_fullscreen : Icons.open_in_full,
                        color: scheme.onPrimary,
                        size: 18,
                      ),
                    ),
                  IconButton(
                    key: const ValueKey('vibe-chat-close'),
                    tooltip: 'Fermer le chat',
                    onPressed: widget.onClose,
                    icon: Icon(Icons.close, color: scheme.onPrimary, size: 20),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, middleConstraints) => Column(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: middleConstraints.maxHeight,
                    ),
                    child: SingleChildScrollView(
                      primary: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                            child: Text(
                              'Votre demande et la configuration de l’écran sont envoyées à Gemini.',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final (index, mode)
                                        in VibeAiSpeedMode.values.indexed) ...[
                                      if (index > 0) const SizedBox(width: 6),
                                      VibeSpeedModeChip(
                                        mode: mode,
                                        icon: _iconForSpeedMode(mode),
                                        selected: _speedMode == mode,
                                        enabled: !_sending,
                                        onSelected: () => _setSpeedMode(mode),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            key: const ValueKey('vibe-chat-questioning-row'),
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
                            child: Row(
                              children: [
                                Icon(
                                  _iconForQuestioningLevel(_questioningLevel),
                                  size: 15,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Questions',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 6.5,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 12,
                                          ),
                                    ),
                                    child: Slider(
                                      key: const ValueKey(
                                        'vibe-chat-questioning-slider',
                                      ),
                                      value: _questioningLevel.index.toDouble(),
                                      min: 0,
                                      max: 3,
                                      divisions: 3,
                                      label: _questioningLevel.label,
                                      onChanged: _sending
                                          ? null
                                          : (value) => _setQuestioningLevel(
                                              VibeQuestioningLevel.fromSliderValue(
                                                value,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                Tooltip(
                                  message: _questioningLevel.tooltip,
                                  child: Container(
                                    key: const ValueKey(
                                      'vibe-chat-questioning-label',
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          _questioningLevel ==
                                              VibeQuestioningLevel.none
                                          ? scheme.surfaceContainerHighest
                                          : scheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      _questioningLevel.label,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            _questioningLevel ==
                                                VibeQuestioningLevel.none
                                            ? scheme.onSurfaceVariant
                                            : scheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                            child: VibeDesignSystemBar(
                              selectedPreset: _selectedDesignSystem,
                              sending: _sending,
                              onOpenCatalog: _openDesignSystemCatalog,
                              onClear: _clearDesignSystem,
                              onRestyle: _restyleWithSelectedDesignSystem,
                            ),
                          ),
                          if (_scope case final activeScope?)
                            Container(
                              key: const ValueKey('vibe-chat-scope-banner'),
                              width: double.infinity,
                              margin: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.filter_center_focus_outlined,
                                    size: 16,
                                    color: scheme.onSecondaryContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Scope : ${activeScope.displayLabel}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    key: const ValueKey(
                                      'vibe-chat-clear-scope',
                                    ),
                                    tooltip: 'Retirer la restriction de scope',
                                    visualDensity: VisualDensity.compact,
                                    iconSize: 16,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 24,
                                      height: 24,
                                    ),
                                    color: scheme.onSecondaryContainer,
                                    onPressed: _sending ? null : _clearScope,
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      children: [
                        if (_sending)
                          VibeStreamingAssistantBubble(
                            snapshot: _streamingSnapshot,
                          ),
                        for (var i = _messages.length - 1; i >= 0; i--)
                          VibeMessageBubble(
                            message: _messages[i],
                            sending: _sending,
                            onSubmitAskUser: (answers) =>
                                _submitAskUser(i, answers, usedDefaults: false),
                            onSkipAskUser: () {
                              final askUser = _messages[i].askUser;
                              if (askUser == null) return;
                              _submitAskUser(
                                i,
                                askUser.defaultAnswers(),
                                usedDefaults: true,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          if (_attachmentError != null)
            Container(
              key: const ValueKey('vibe-chat-attachment-error'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: scheme.errorContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _attachmentError!,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    color: scheme.onErrorContainer,
                    onPressed: () => setState(() => _attachmentError = null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          if (_pendingAttachments.isNotEmpty)
            Container(
              key: const ValueKey('vibe-chat-pending-attachments'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (index, attachment)
                        in _pendingAttachments.indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: VibePendingAttachmentChip(
                          index: index,
                          attachment: attachment,
                          onRemove: _sending
                              ? null
                              : () => _removePendingAttachment(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: const ValueKey('vibe-chat-attach'),
                  tooltip: 'Joindre un fichier (image ou texte)',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _attachFromPicker,
                  icon: const Icon(Icons.attach_file),
                ),
                IconButton(
                  key: const ValueKey('vibe-chat-paste-attachment'),
                  tooltip: 'Coller un fichier ou texte du presse-papiers',
                  visualDensity: VisualDensity.compact,
                  onPressed: _sending ? null : _attachFromClipboard,
                  icon: const Icon(Icons.content_paste),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    key: const ValueKey('vibe-chat-input'),
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Décris l’écran souhaité…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const ValueKey('vibe-chat-send'),
                  tooltip: 'Générer et appliquer',
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _LiveTurnSession {
  _LiveTurnSession({
    required this.rawInitialAppearance,
    required this.baseAppearance,
    required this.initialInstantiatedIds,
    required this.pageRouting,
    required this.initialRouteLocation,
    required this.initialPageIds,
    this.repoTransaction,
  }) : lastPreviewAppearance = baseAppearance;

  final Appearance rawInitialAppearance;
  final Appearance baseAppearance;
  final Set<String>? initialInstantiatedIds;
  final EditorPageRouter? pageRouting;
  final String? initialRouteLocation;
  final Set<String> initialPageIds;
  final VibeRepositoryTurnTransaction? repoTransaction;

  Appearance lastPreviewAppearance;
  int lastAppliedPatchRevision = 0;
  int lastAppliedRepositoriesRevision = 0;
  Future<void> liveRepoQueue = Future<void>.value();
  bool livePreviewDisabled = false;
  bool hasAppliedLivePreview = false;
  String? liveNavigatedPageId;
}

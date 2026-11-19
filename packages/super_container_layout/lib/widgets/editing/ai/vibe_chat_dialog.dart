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
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart'
    show
        AssetBundle,
        HardwareKeyboard,
        KeyDownEvent,
        LogicalKeyboardKey,
        rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:material_ui/material_ui.dart';

import '../../../ai/call_gemini.dart';
import '../../../ai/design_system_catalog.dart';
import '../../../ai/vibe_ask_user.dart';
import '../../../ai/vibe_plan.dart';
import '../../../ai/vibe_speech_to_text.dart';
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
import '../../../services/diagnostics/debug_entry.dart';
import '../../../services/inspection/vibe_app_inspector.dart';
import '../../../services/inspection/vibe_debug_capture.dart';
import '../../../services/inspection/vibe_diagnostics_inspector.dart';
import '../../../services/inspection/vibe_mounted_slot_index.dart';
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
import 'vibe_delta_recovery.dart';
import 'vibe_prompt_builder.dart';
import 'vibe_repository_applier.dart';
import 'vibe_scope_helpers.dart';
import 'vibe_task_completion_alert.dart';
import 'vibe_work_highlight.dart';
import '../../appearance/appearance_scope.dart';

export '../../../ai/call_gemini.dart' show GeminiStreamEvent, VibeAiSpeedMode;
export '../../../ai/design_md_parser.dart';
export '../../../ai/design_system_catalog.dart';
export '../../../ai/vibe_app_tools.dart'
    show
        VibeAppToolRegistry,
        VibeRegisteredTool,
        VibeToolCall,
        VibeToolDeclaration,
        VibeToolResult,
        VibeToolTrace;
export '../../../ai/vibe_ask_user.dart'
    show
        VibeAskUserFieldType,
        VibeAskUserQuestion,
        VibeAskUserRequest,
        VibeQuestioningLevel;
export '../../../ai/vibe_chat_attachment.dart';
export '../../../ai/vibe_plan.dart'
    show VibeExecutionPlan, VibeLotStatus, VibePlanLot, VibePlanStatus;
export '../../../ai/vibe_speech_to_text.dart';
export '../../../ai/vibe_stream_parser.dart' show VibeStreamSnapshot;
export 'design_system_catalog_dialog.dart';
export 'design_system_preview_card.dart';
export 'vibe_ask_user_card.dart' show VibeAskUserCard;
export 'vibe_chat_message.dart' show VibeChatMessage;
export 'vibe_plan_card.dart' show VibePlanCard;
export 'vibe_task_completion_alert.dart'
    show
        DefaultVibeTaskSoundPlayer,
        VibeTaskCompletionBanner,
        VibeTaskCompletionController,
        VibeTaskCompletionEvent,
        VibeTaskCompletionGlow,
        VibeTaskOutcome,
        VibeTaskSoundPlayer;
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
    this.initialReproduceExactMode = false,
    this.onReproduceExactModeChanged,
    this.scope,
    this.onScopeChanged,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    this.readClipboardText,
    this.speechTranscriber,
    this.validateAppearance,
    this.registry,
    this.repositoryStore,
    this.pageRouting,
    this.toolRegistry,
    this.initialDesignSystem,
    this.onDesignSystemChanged,
    this.customDesignSystems = const [],
    this.onCustomDesignSystemsChanged,
    this.customDesignGuide,
    this.replaceDefaultDesignGuide = false,
    this.expanded,
    this.onExpandedChanged,
    this.completionController,
    this.soundPlayer,
    this.initialSoundAlertEnabled,
    this.onSoundAlertEnabledChanged,
    super.key,
  });

  /// Active la journalisation multi-blocs détaillée des prompts, réponses brutes et patches JSON.
  ///
  /// Désactivé par défaut afin d'éviter le blocage de l'isolate UI sur les charges JSON volumineuses.
  static bool verboseLogging = false;

  /// Nombre maximal de tours d'appels d'outils d'introspection autorisés par génération.
  static const int maxToolRounds = 8;

  /// Instructions système invariantes transmises au modèle GenUI pour le chat Vibe IA.
  static const String defaultSystemInstruction = '''
Tu es l’assistant de création d’écrans de super_container_layout. Réponds en français.
Utilise exclusivement le guide de modélisation JSON, le guide de Design System et l’état actuel de l’application fournis.
Applique systématiquement les règles du Design System (surfaces sémantiques theme:*, hiérarchie typographique, grille d'espacement 4/8px, ergonomie Desktop productive, discipline des boutons d'action et micro-interactions) sauf consigne esthétique explicite contraire de l'utilisateur ; si des règles de design spécifiques à l'application sont fournies, elles prévalent sur le Design System générique.
Renvoie uniquement un objet JSON en plaçant impérativement la clé "message" EN PREMIER (avant "askUser" et "vibe") pour permettre l'affichage instantané en streaming, selon l'un des 3 modes suivants :
1. Création ou modification directe de l'écran : renvoie {"message":"résumé bref en français","vibe":{...}}. Le champ "vibe" doit contenir un patch JSON plat (modèle GenUI : "components", "styles", "behaviors", "usages", "pageCatalog") accepté par AppearanceTransfer.applyVibe.
2. Question pure ou demande d'information sans modification de l'écran : renvoie {"message":"réponse claire en français","vibe":null} (ou omets le champ "vibe") sans modifier l'écran.
3. Clarification interactive ("askUser") selon le NIVEAU DE QUESTIONNEMENT indiqué dans le contexte du tour : renvoie {"message":"courte introduction en français","askUser":{"questions":[{"id":"...","title":"...","type":"single|multi|boolean|text","options":["..."],"default":...}]},"vibe":null}.
4. Planification en lots (mode « Reproduire à l’identique ») : renvoie {"message":"présentation du plan en français","plan":{"title":"...","lots":[{"id":"lot-1","title":"...","description":"..."}]},"vibe":null}.
5. Interrogation et sélection dans l'application en cours d'exécution (si des mesures, diagnostics ou pointages visuels sont utiles) : tu peux appeler les outils (`get_viewport_and_route`, `get_component_geometry`, `get_runtime_tree`, `query_repository_data`, `capture_element_screenshot`, `capture_screenshot`, `get_debug_entries`, `get_datasources_and_providers`, `inspect_bindings_and_diagnostics`, `get_theme_and_contrast`, `get_registry_and_selection`, `preview_navigation_or_selection`, `select_editor_element`) soit via le Function Calling natif (à privilégier), soit en renvoyant {"message":"inspection en cours","toolCalls":[{"id":"...","name":"...","arguments":{...}}],"vibe":null}. Préfère systématiquement `capture_element_screenshot` à `capture_screenshot` pour capturer un composant, une carte, une zone ou une ligne isolée sans toute la page, et utilise `select_editor_element` pour sélectionner/montrer un élément sur le canevas en mode édition. Appelle `get_debug_entries` et `inspect_bindings_and_diagnostics` en cas d'erreur Flutter/RenderFlex ou de données vides, et `get_datasources_and_providers` avant de câbler une recherche/CRUD ; pour une modification déclarative simple dont le JSON courant suffit, réponds directement sans outil. Tu peux ajouter "verifyRender": true avec "vibe" pour inspecter l'écran juste après l'aperçu.
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
- Si un repository de REPOSITORIES DISPONIBLES expose un champ "jsonSchema", respecte strictement ce JSON Schema dans toutes les données produites ou fusionnées (toute violation bloque l'écriture). Tu peux aussi fournir une clé optionnelle "jsonSchema" (objet JSON Schema Draft 7/2020-12 ou null) dans l'enveloppe d'une entrée de "repositories" lorsqu'on te demande de définir, modifier ou dissocier le schéma d'un repository.
Règles pour "askUser" :
- Quelle que soit l'étape (création initiale, ajout, modification d'un écran existant ou d'un scope ciblé), applique systématiquement le NIVEAU DE QUESTIONNEMENT défini par le slider dans le contexte du tour courant, sans restreindre les questions à la première étape (seul le niveau 0/Aucun ou le tour d'application immédiate des réponses qui viennent d'être fournies désactive "askUser").
- Fournis toujours des valeurs "default" pertinentes sur chaque question posée.
Priorité absolue — Respect strict de la règle d'atomicité lors de chaque génération de layout, fiche ou formulaire :
- Ne concatène jamais un libellé et une donnée dans le "text" d'un même SuperValue (ex: jamais "Statut : En cours"), ni plusieurs attributs métier dans un seul composant.
- En mode visualisation ("mode": "display"), un SuperValue possède nativement "label" et une valeur ("text" ou "binding") : préfère systématiquement 1 seul SuperValue avec "label" + "text" (usage "dynamicData") ou "binding" plutôt que 2 SuperValue séparés, SAUF si le label requiert un style ou une disposition fortement personnalisés (auquel cas décompose en 1 SuperValue étiquette fixe avec usage "explanation" + "translationKey", et 1 SuperValue distinct pour la valeur avec usage "dynamicData" ou "binding").
- Évite tout placeholder de texte libre multiligne (textarea / maxLines > 1) pour représenter des listes ou récapitulatifs métier (affaires, contrats, interlocuteurs, etc., même si la demande mentionne « résumé », « récapitulatif » ou « notes ») : utilise systématiquement des cartes, des champs unitaires SuperValue atomiques, une SuperListView ou un tableau SuperTable.
Par défaut, ne mets pas de padding (ni paddingInsets) sur styles["background"] (laisse padding à 0 par défaut, sauf demande explicite) : avec les composants Flutter (Scaffold, ApplicationBar, NavigationRail, BottomAppBar, SuperLayout), ce n'est pas nécessaire ; règle l'espacement éventuel dans les zones des layouts (zoneFlows) ou les cartes.
Ne mets JAMAIS d'entrée dans "styles" pour un composant placé en "registry:Layout" (ni pour "mainLayout") : SuperLayout est purement structurel et n'a pas de surface (styles[id] est sans effet). Pour styliser un conteneur de zones (couleur, bordure, arrondi, paddingInsets), passe son placement parent en "registry:IterableContent" (en gardant components[id] en "type": "layout") ou enveloppe-le dans une "registry:Card".
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

  /// Active par défaut le mode « Reproduire à l'identique » (planification et exécution par lots automatiques).
  final bool initialReproduceExactMode;

  /// Callback optionnel notifié lorsque le mode « Reproduire à l'identique » change.
  final ValueChanged<bool>? onReproduceExactModeChanged;

  /// Périmètre restreint optionnel limitant les modifications de l'IA à un sous-arbre.
  final VibeChatScope? scope;

  /// Callback notifié lorsque l'utilisateur efface ou modifie la restriction de [scope].
  final ValueChanged<VibeChatScope?>? onScopeChanged;

  /// Sélecteur personnalisé optionnel de pièces jointes (fichiers images ou texte).
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  /// Lecteur personnalisé optionnel du presse-papiers pour les pièces jointes (bouton presse-papiers).
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;

  /// Prédicat personnalisé optionnel indiquant si le presse-papiers contient une image ou des fichiers lors d'un `Ctrl+V`.
  final bool Function()? hasClipboardMedia;

  /// Lecteur personnalisé optionnel d'images ou fichiers du presse-papiers lors d'un `Ctrl+V`.
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  /// Lecteur personnalisé optionnel du texte du presse-papiers pour l'import de chartes `DESIGN.md`.
  final Future<String?> Function()? readClipboardText;

  /// Service optionnel de dictée vocale (Speech-to-Text) pour la barre de saisie et les questions.
  final VibeSpeechTranscriber? speechTranscriber;

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

  /// Registre optionnel d'outils d'introspection exposés à l'IA (par défaut construit via [VibeAppInspector]).
  final VibeAppToolRegistry? toolRegistry;

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

  /// Contrôleur optionnel recevant les alertes visuelles et sonores de fin de tâche IA.
  ///
  /// Par défaut, utilise [VibeTaskCompletionController.instance].
  final VibeTaskCompletionController? completionController;

  /// Lecteur audio optionnel utilisé pour l'alerte sonore de fin de tâche IA.
  final VibeTaskSoundPlayer? soundPlayer;

  /// Active ou désactive initialement l'alerte sonore de fin de tâche IA.
  final bool? initialSoundAlertEnabled;

  /// Callback notifié lorsque l'utilisateur active ou coupe l'alerte sonore dans le chat.
  final ValueChanged<bool>? onSoundAlertEnabledChanged;

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
    String? toolsGuide,
    bool includeToolsGuide = true,
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
    final resolvedToolsGuide =
        toolsGuide?.trim() ??
        (includeToolsGuide ? VibeAppToolRegistry.standardToolsGuide() : '');
    if (resolvedToolsGuide.isNotEmpty) {
      buffer
        ..write('\n\n---\n\n')
        ..write(resolvedToolsGuide);
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
        tools: VibeAppToolRegistry.standardDeclarations,
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

class _VibeChatDialogState extends State<VibeChatDialog>
    with SingleTickerProviderStateMixin {
  static const String _initialGreetingText =
      'Décris l’écran à créer ou les changements souhaités.';
  static const int _maxConversationEntries = 8;
  static const Duration _completionAutoHideDuration = Duration(seconds: 6);
  static const Duration _completionGlowDuration = Duration(milliseconds: 1200);

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
  VibeSpeechSession? _speechSession;
  VibeSpeechState? _speechState;
  VoidCallback? _speechStateListener;
  late VibeChatScope? _scope = widget.scope;
  late VibeAiSpeedMode _speedMode = widget.initialSpeedMode;
  late VibeQuestioningLevel _questioningLevel = widget.initialReproduceExactMode
      ? VibeQuestioningLevel.none
      : widget.initialQuestioningLevel;
  late bool _reproduceExactMode = widget.initialReproduceExactMode;
  late VibeQuestioningLevel? _questioningLevelBeforeExactMode =
      widget.initialReproduceExactMode ? widget.initialQuestioningLevel : null;
  int? _activePlanMessageIndex;
  bool _executingPlan = false;
  bool _planStopRequested = false;
  EditorHistoryController? _openPlanHistory;
  late DesignSystemPreset? _selectedDesignSystem = widget.initialDesignSystem;
  late List<DesignSystemPreset> _customDesignSystems =
      List<DesignSystemPreset>.of(widget.customDesignSystems);
  late bool _expanded = widget.expanded ?? true;
  late final AnimationController _completionGlowController =
      AnimationController(vsync: this, duration: _completionGlowDuration);
  VibeTaskCompletionEvent? _localCompletionEvent;
  Timer? _completionHideTimer;
  late bool _soundEnabled =
      widget.initialSoundAlertEnabled ??
      _resolvedCompletionController.soundEnabled;

  VibeTaskCompletionController get _resolvedCompletionController =>
      widget.completionController ?? VibeTaskCompletionController.instance;

  @override
  void initState() {
    super.initState();
    if (widget.initialSoundAlertEnabled != null) {
      _resolvedCompletionController.setSoundEnabled(
        widget.initialSoundAlertEnabled!,
      );
    }
    _resolvedCompletionController.addListener(_onCompletionControllerChanged);
  }

  void _onCompletionControllerChanged() {
    final enabled = _resolvedCompletionController.soundEnabled;
    if (mounted && _soundEnabled != enabled) {
      setState(() => _soundEnabled = enabled);
    }
  }

  void _toggleSoundAlert() {
    final next = !_soundEnabled;
    _resolvedCompletionController.setSoundEnabled(next);
    if (mounted) {
      setState(() => _soundEnabled = next);
    }
    widget.onSoundAlertEnabledChanged?.call(next);
  }

  void _clearCompletionAlert() {
    _completionHideTimer?.cancel();
    _completionHideTimer = null;
    if (_localCompletionEvent != null && mounted) {
      setState(() => _localCompletionEvent = null);
    } else {
      _localCompletionEvent = null;
    }
  }

  void _notifyTaskCompletion({
    required VibeTaskOutcome outcome,
    required String title,
    String detail = '',
  }) {
    final event = _resolvedCompletionController.notifyCompleted(
      outcome: outcome,
      title: title,
      detail: detail,
      soundPlayer: widget.soundPlayer,
      playSound: _soundEnabled,
    );
    _completionHideTimer?.cancel();
    _completionHideTimer = Timer(_completionAutoHideDuration, () {
      if (!mounted) return;
      if (_localCompletionEvent?.id == event.id) {
        setState(() => _localCompletionEvent = null);
      }
    });
    if (mounted) {
      setState(() => _localCompletionEvent = event);
      _completionGlowController.forward(from: 0.0);
    }
  }

  bool get _isBusy => _sending || _executingPlan;

  bool get _isAfterAskUserReply {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (msg.isUser) {
        return msg.promptText != null && !msg.requestsMoreQuestions;
      }
    }
    return false;
  }

  bool get _isForceFollowUpQuestions {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (msg.isUser) {
        return msg.requestsMoreQuestions;
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
    return context
            .getInheritedWidgetOfExactType<JsonRepositoryScope>()
            ?.store ??
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
    if (oldWidget.initialQuestioningLevel != widget.initialQuestioningLevel &&
        !_reproduceExactMode) {
      _questioningLevel = widget.initialQuestioningLevel;
    }
    if (oldWidget.initialReproduceExactMode !=
        widget.initialReproduceExactMode) {
      _setReproduceExactMode(
        widget.initialReproduceExactMode,
        notifyCallback: false,
      );
    }
    if (widget.expanded != null &&
        widget.expanded != oldWidget.expanded &&
        widget.expanded != _expanded) {
      _expanded = widget.expanded!;
    }
    if (oldWidget.completionController != widget.completionController) {
      final oldCtrl =
          oldWidget.completionController ??
          VibeTaskCompletionController.instance;
      oldCtrl.removeListener(_onCompletionControllerChanged);
      _resolvedCompletionController.addListener(_onCompletionControllerChanged);
      _soundEnabled = _resolvedCompletionController.soundEnabled;
    }
    if (oldWidget.initialSoundAlertEnabled != widget.initialSoundAlertEnabled &&
        widget.initialSoundAlertEnabled != null) {
      _resolvedCompletionController.setSoundEnabled(
        widget.initialSoundAlertEnabled!,
      );
      _soundEnabled = widget.initialSoundAlertEnabled!;
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
    if (_isForceFollowUpQuestions) {
      _setExpanded(true);
      return;
    }
    if (snapshot.hasVibeObject || snapshot.hasRepositoriesObject) {
      _setExpanded(false);
    } else if (snapshot.hasAskUserObject || snapshot.hasPlanObject) {
      _setExpanded(true);
    }
  }

  void _setSpeedMode(VibeAiSpeedMode mode) {
    if (_speedMode == mode || _isBusy) return;
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
    if (_reproduceExactMode || _questioningLevel == level || _isBusy) return;
    setState(() => _questioningLevel = level);
    widget.onQuestioningLevelChanged?.call(level);
  }

  void _setReproduceExactMode(bool enabled, {bool notifyCallback = true}) {
    if (_reproduceExactMode == enabled || _isBusy) return;
    setState(() {
      _reproduceExactMode = enabled;
      if (enabled) {
        _questioningLevelBeforeExactMode = _questioningLevel;
        _questioningLevel = VibeQuestioningLevel.none;
      } else {
        _questioningLevel =
            _questioningLevelBeforeExactMode ?? widget.initialQuestioningLevel;
        _questioningLevelBeforeExactMode = null;
      }
    });
    if (notifyCallback) {
      widget.onReproduceExactModeChanged?.call(enabled);
    }
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
        snapshot.hasAskUserObject ||
        _isForceFollowUpQuestions) {
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
                await repoTx.applyRepositoriesPatchPartial(capturedRepoPatch);
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
    final base = session.checkpointAppearance;
    final activeScope = _scope;
    final effectivePatch = activeScope == null
        ? rawPatch
        : VibeChatDialog.filterPatchToScope(base, rawPatch, activeScope);
    if (!_hasPatchChanges(effectivePatch)) return;

    try {
      final partial = AppearanceTransfer.applyVibeMapPartial(
        base,
        effectivePatch,
        codec: widget.codec,
      );
      if (!partial.hasAppliedEntries &&
          partial.appearance == session.lastPreviewAppearance) {
        return;
      }
      var previewAppearance = partial.appearance;
      if (widget.validateAppearance != null) {
        try {
          widget.validateAppearance!(previewAppearance);
        } catch (_) {
          if (previewAppearance.pageCatalog != base.pageCatalog) {
            previewAppearance = previewAppearance.copyWith(
              pageCatalog: base.pageCatalog,
            );
            widget.validateAppearance!(previewAppearance);
          } else {
            rethrow;
          }
        }
      }
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
    final hadPreviewChange =
        session.hasAppliedLivePreview ||
        !identical(widget.controller.value, session.rawInitialAppearance);
    if (hadPreviewChange) {
      VibeWorkHighlightController.instance.clearAll();
      try {
        _setPreviewAppearance(session.rawInitialAppearance);
      } catch (_) {
        // Ignore en cas de contrôleur déjà disposé.
      }
      session.hasAppliedLivePreview = false;
    } else {
      VibeWorkHighlightController.instance.clearStreamingTargets();
    }
    if (session.liveNavigatedPageId != null ||
        session.previewTracker.hasNavigated) {
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

  void _restoreCheckpointPreview(_LiveTurnSession session) {
    session.lastAppliedPatchRevision = 0;
    session.lastAppliedRepositoriesRevision = 0;
    session.lastPreviewAppearance = session.checkpointAppearance;
    VibeWorkHighlightController.instance.clearStreamingTargets();
    try {
      _setPreviewAppearance(session.checkpointAppearance);
      session.hasAppliedLivePreview = true;
    } catch (_) {
      // Ignore en cas de contrôleur déjà disposé.
    }
    final navigatedPageId = session.liveNavigatedPageId;
    if (navigatedPageId != null &&
        !session.checkpointAppearance.pageCatalog.pages.any(
          (p) => p.id == navigatedPageId,
        )) {
      final routing = session.pageRouting;
      final previousLocation = session.initialRouteLocation;
      session.liveNavigatedPageId = null;
      if (routing != null) {
        try {
          routing.synchronize(session.checkpointAppearance.pageCatalog);
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
    session.previewTracker.restoreSelections(session.repoTransaction?.store);
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
    if (_isBusy) return;
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
    if (_isBusy || _selectedDesignSystem == null) return;
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
    if (preset == null || _isBusy) return;

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
              '- Mets à jour "styles" : "background" ("color": "$canvasHex") ainsi que toutes les surfaces de cartes (Card), conteneurs stylisés (IterableContent), en-têtes et lignes de collection ("color": "$surfaceHex", états "hover" et "selected" cohérents, "radius": $radiusValue, "borderWidth" et "borderColor": "$borderHex", "elevation", "shadowOpacity" et "designSystem": "$surfaceSystemName"). Ne mets jamais d’entrée "styles" sur un "registry:Layout" pur (passe son placement en "registry:IterableContent" si une surface est requise).\n'
              '- Harmonise la typographie ("fontFamily", "fontSize", "fontWeight") et les couleurs des composants existants SuperValue (texte primaire "$textHex", secondaire "$mutedHex"), SuperAction (variantes, rayons et contraste AA sur "$accentHex") et SuperIndicator.\n'
              '- Préserve à 100 % la structure métier existante : conserve tous les identifiants de composants, placements, liaisons de données (bindings), usages, comportements (behaviors) et pages (pageCatalog).'
        : 'RESTYLAGE DU PÉRIMÈTRE "${activeScope.displayLabel}" SELON LE SYSTÈME DE DESIGN "${preset.name}" :\n'
              'Ne pose pas de questionnaire "askUser" : génère directement le patch "vibe".\n'
              'Restyle uniquement le périmètre ciblé "${activeScope.displayLabel}" (id: "${activeScope.canonicalComponentId}") et son sous-arbre autorisé conformément au référentiel DESIGN.md actif ("${preset.name}") :\n'
              '- Mets à jour uniquement les styles des surfaces du périmètre (Card, IterableContent, lignes de collection — couleurs de surface "$surfaceHex", états "hover" et "selected", "radius": $radiusValue, "borderWidth", "borderColor": "$borderHex", "elevation" et "designSystem": "$surfaceSystemName"). Ne mets jamais d’entrée "styles" sur un "registry:Layout" pur (passe son placement parent en "registry:IterableContent" si une surface est requise).\n'
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
    _completionHideTimer?.cancel();
    _completionHideTimer = null;
    _resolvedCompletionController.removeListener(
      _onCompletionControllerChanged,
    );
    _completionGlowController.dispose();
    _planStopRequested = true;
    _commitOuterPlanTransaction();
    _cancelSpeechDictation();
    if (_activeTurnSession != null) {
      VibeWorkHighlightController.instance.clearStreamingTargets();
    }
    _pendingSnapshot = null;
    _streamingSnapshot.dispose();
    _input.dispose();
    super.dispose();
  }

  void _detachSpeechStateListener() {
    final session = _speechSession;
    final listener = _speechStateListener;
    if (session != null && listener != null) {
      session.state.removeListener(listener);
    }
    _speechStateListener = null;
  }

  void _cancelSpeechDictation() {
    _detachSpeechStateListener();
    final session = _speechSession;
    _speechSession = null;
    _speechState = null;
    if (session != null) {
      unawaited(session.cancel());
    }
  }

  Future<void> _toggleSpeechDictation() async {
    if (_sending) return;
    final existing = _speechSession;
    if (existing != null) {
      if (_speechState == VibeSpeechState.listening) {
        await existing.stop();
      }
      return;
    }

    setState(() => _attachmentError = null);
    try {
      final transcriber =
          widget.speechTranscriber ?? VibeSpeechTranscriber.instance;
      final session = await transcriber.startListening();
      if (!mounted) {
        await session.cancel();
        return;
      }

      void onStateChanged() {
        if (!mounted || !identical(_speechSession, session)) return;
        setState(() => _speechState = session.state.value);
      }

      _speechStateListener = onStateChanged;
      session.state.addListener(onStateChanged);
      setState(() {
        _speechSession = session;
        _speechState = session.state.value;
      });

      final transcript = await session.result;
      if (!mounted || !identical(_speechSession, session)) return;
      _detachSpeechStateListener();
      setState(() {
        _speechSession = null;
        _speechState = null;
      });
      if (transcript.trim().isNotEmpty) {
        VibeSpeechTextInsertion.insertTranscript(_input, transcript);
      }
    } on FormatException catch (error) {
      if (!mounted) return;
      _detachSpeechStateListener();
      setState(() {
        _speechSession = null;
        _speechState = null;
        _attachmentError = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      _detachSpeechStateListener();
      setState(() {
        _speechSession = null;
        _speechState = null;
        _attachmentError =
            'Dictée vocale impossible : ${_describeErrorCause(error)}';
      });
    }
  }

  void _appendPendingAttachments(Iterable<VibeChatAttachment> incoming) {
    final usedNames = <String>{for (final a in _pendingAttachments) a.name};
    for (final attachment in incoming) {
      var candidateName = attachment.name;
      if (usedNames.contains(candidateName)) {
        final dot = candidateName.lastIndexOf('.');
        final stem = dot > 0 ? candidateName.substring(0, dot) : candidateName;
        final ext = dot > 0 ? candidateName.substring(dot) : '';
        var suffix = 2;
        while (usedNames.contains('$stem-$suffix$ext')) {
          suffix++;
        }
        candidateName = '$stem-$suffix$ext';
      }
      usedNames.add(candidateName);
      _pendingAttachments.add(
        candidateName == attachment.name
            ? attachment
            : attachment.withName(candidateName),
      );
    }
  }

  Future<void> _attachFromPicker() async {
    if (_isBusy) return;
    setState(() => _attachmentError = null);
    try {
      final picker = widget.pickAttachments ?? VibeChatAttachment.pickFiles;
      final picked = await picker();
      if (!mounted || picked.isEmpty) return;
      setState(() {
        _appendPendingAttachments(picked);
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
    if (_isBusy) return;
    setState(() => _attachmentError = null);
    try {
      final paster =
          widget.pasteAttachments ?? VibeChatAttachment.fromClipboard;
      final pasted = await paster();
      if (!mounted) return;
      if (pasted.isEmpty) {
        setState(
          () => _attachmentError =
              'Aucune image, fichier ou texte trouvé dans le presse-papiers.',
        );
        return;
      }
      setState(() {
        _appendPendingAttachments(pasted);
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

  Future<void> _attachMediaFromShortcut() async {
    if (_isBusy) return;
    setState(() => _attachmentError = null);
    try {
      final paster =
          widget.pasteClipboardMedia ??
          (widget.hasClipboardMedia != null ? widget.pasteAttachments : null) ??
          VibeChatAttachment.fromClipboardImagesOrFiles;
      final pasted = await paster();
      if (!mounted || pasted.isEmpty) return;
      setState(() {
        _appendPendingAttachments(pasted);
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

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (_isBusy || event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final isCtrlOrMetaV =
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (keyboard.isControlPressed || keyboard.isMetaPressed) &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed;
    final isShiftInsert =
        event.logicalKey == LogicalKeyboardKey.insert &&
        keyboard.isShiftPressed &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed;
    if (!isCtrlOrMetaV && !isShiftInsert) return KeyEventResult.ignored;

    final hasMedia =
        (widget.hasClipboardMedia ??
        VibeChatAttachment.hasClipboardImageOrFiles)();
    if (!hasMedia) return KeyEventResult.ignored;

    unawaited(_attachMediaFromShortcut());
    return KeyEventResult.handled;
  }

  void _removePendingAttachment(int index) {
    if (_isBusy || index < 0 || index >= _pendingAttachments.length) return;
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
    _cancelSpeechDictation();
    final request = _input.text.trim();
    final attachments = List<VibeChatAttachment>.unmodifiable(
      _pendingAttachments,
    );
    if ((request.isEmpty && attachments.isEmpty) || _isBusy) return;
    _input.clear();
    if (_questioningLevel == VibeQuestioningLevel.none &&
        !_reproduceExactMode) {
      _setExpanded(false);
    }
    _stopStaleActivePlan();
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
    if (_isBusy || messageIndex < 0 || messageIndex >= _messages.length) {
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

  Future<void> _submitAskMoreFromCard(
    int messageIndex,
    Map<String, Object?> answers,
  ) async {
    if (_isBusy ||
        _reproduceExactMode ||
        messageIndex < 0 ||
        messageIndex >= _messages.length) {
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
    _setExpanded(true);
    setState(() {
      _messages[messageIndex] = target.copyWith(
        askUserAnswers: normalizedAnswers,
        askUserRequestedMore: true,
      );
    });
    final summary = request.formatDisplaySummary(normalizedAnswers);
    final displaySummary = 'Choix enregistrés (+ de questions) :\n$summary';
    final promptReply = request.formatMoreQuestionsPromptReply(
      normalizedAnswers,
    );
    await _runGenerationTurn(
      displayUserText: displaySummary,
      promptOverride: promptReply,
      requestsMoreQuestions: true,
    );
  }

  Future<void> _requestMoreQuestionsFromChat() async {
    if (_isBusy || _reproduceExactMode) return;
    _cancelSpeechDictation();
    final draft = _input.text.trim();
    final attachments = List<VibeChatAttachment>.unmodifiable(
      _pendingAttachments,
    );
    _input.clear();
    _setExpanded(true);
    _stopStaleActivePlan();
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

    final hasDraftOrFiles = draft.isNotEmpty || attachments.isNotEmpty;
    final displayUserText = draft.isNotEmpty
        ? '$draft (+ de questions)'
        : attachments.isNotEmpty
        ? '+ de questions sur les pièces jointes'
        : '+ de questions pour affiner l’écran';
    final promptOverride = hasDraftOrFiles
        ? '${draft.isEmpty ? 'Analyse les fichiers joints.' : draft}\n'
              'Ne génère PAS encore le patch "vibe" ("vibe": null obligatoire) : '
              'pose d’abord 2 à ${VibeQuestioningLevel.followUpMaxQuestions} questions ciblées '
              'et non redondantes avec "default" via "askUser" pour préciser le besoin.'
        : 'Examine l’état actuel de l’écran et l’historique de conversation, '
              'sans générer de patch "vibe" ("vibe": null obligatoire) : '
              'pose 2 à ${VibeQuestioningLevel.followUpMaxQuestions} nouvelles questions pertinentes '
              'et non redondantes avec "default" via "askUser" pour affiner, compléter ou améliorer l’écran.';

    await _runGenerationTurn(
      displayUserText: displayUserText,
      promptOverride: promptOverride,
      attachments: attachments,
      requestsMoreQuestions: true,
    );
  }

  bool _canShowMessageMoreQuestions(int index) {
    if (_reproduceExactMode || index <= 0 || index != _messages.length - 1) {
      return false;
    }
    final msg = _messages[index];
    if (msg.isUser || msg.failedResponse != null || msg.plan != null) {
      return false;
    }
    if (msg.askUser != null &&
        msg.askUserAnswers == null &&
        !msg.askUserDismissed) {
      return false;
    }
    return true;
  }

  Future<void> _runGenerationTurn({
    required String displayUserText,
    String? promptOverride,
    List<VibeChatAttachment> attachments = const [],
    bool requestsMoreQuestions = false,
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
    _clearCompletionAlert();
    setState(() {
      _sending = true;
      _messages.add(
        VibeChatMessage(
          text: displayUserText,
          promptText: promptOverride,
          isUser: true,
          attachments: attachments,
          requestsMoreQuestions: requestsMoreQuestions,
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
        if (generated.plan case final plan?) {
          _setExpanded(true);
          debugPrint(
            '[Vibe IA] Plan de reproduction reçu '
            '(${plan.lots.length} lot(s)).',
          );
        } else if (generated.askUser case final askUser?) {
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
      final summaryText = summary is String && summary.trim().isNotEmpty
          ? summary.trim()
          : null;
      final fallbackText = generated.plan != null && !hasMutations
          ? 'Plan prêt — clique sur « Exécuter les lots » pour démarrer :'
          : generated.askUser != null && !hasMutations
          ? 'Précise tes préférences :'
          : 'Modifications appliquées.';
      _appendMessage(
        summaryText ?? fallbackText,
        askUser: !hasMutations && generated.plan == null
            ? generated.askUser
            : null,
        plan: !hasMutations ? generated.plan : null,
        planSourcePrompt: !hasMutations && generated.plan != null
            ? (promptOverride ?? displayUserText)
            : null,
        planSourceAttachments: !hasMutations && generated.plan != null
            ? attachments
            : const [],
        toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
      );
      if (!hasMutations && generated.plan != null && mounted) {
        setState(() {
          _activePlanMessageIndex = _messages.length - 1;
        });
      }
      if (hasMutations) {
        final detail =
            summaryText ??
            (generated.appearance != null && generated.repositoriesUpdated
                ? 'Écran et données mis à jour.'
                : generated.appearance != null
                ? 'Modifications appliquées à l’écran.'
                : 'Données des repositories mises à jour.');
        _notifyTaskCompletion(
          outcome: VibeTaskOutcome.success,
          title: 'Tâche IA terminée',
          detail: detail,
        );
      } else if (generated.plan case final plan?) {
        _notifyTaskCompletion(
          outcome: VibeTaskOutcome.needsInput,
          title: 'Plan IA prêt',
          detail: '${plan.lots.length} lot(s) prêt(s) à exécuter.',
        );
      } else if (generated.askUser case final askUser?) {
        _notifyTaskCompletion(
          outcome: VibeTaskOutcome.needsInput,
          title: 'Clarification requise',
          detail:
              '${askUser.questions.length} question(s) en attente de réponse.',
        );
      } else {
        _notifyTaskCompletion(
          outcome: VibeTaskOutcome.info,
          title: 'Réponse IA prête',
          detail: summaryText ?? 'Réponse affichée dans le chat.',
        );
      }
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
      _notifyTaskCompletion(
        outcome: VibeTaskOutcome.error,
        title: 'Tâche IA échouée',
        detail: cause,
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
      _notifyTaskCompletion(
        outcome: VibeTaskOutcome.error,
        title: 'Tâche IA échouée',
        detail: cause,
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
      _notifyTaskCompletion(
        outcome: VibeTaskOutcome.error,
        title: 'Tâche IA échouée',
        detail: cause,
      );
    } on FlutterError catch (error, stackTrace) {
      await _rollbackTurnSession(session);
      final cause = _describeErrorCause(error);
      debugPrint('AI screen guide could not be loaded: $cause\n$stackTrace');
      _appendMessage(
        'Guide de génération indisponible : $cause',
        failedResponse: _lastFailedResponse,
      );
      _notifyTaskCompletion(
        outcome: VibeTaskOutcome.error,
        title: 'Tâche IA échouée',
        detail: cause,
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
      _notifyTaskCompletion(
        outcome: VibeTaskOutcome.error,
        title: 'Tâche IA échouée',
        detail: cause,
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
      _notifyTaskCompletion(
        outcome: VibeTaskOutcome.error,
        title: 'Tâche IA échouée',
        detail: cause,
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

  void _beginOuterPlanTransaction(EditorHistoryController? history) {
    if (history == null || _openPlanHistory != null) return;
    history.beginTransaction();
    _openPlanHistory = history;
  }

  void _commitOuterPlanTransaction() {
    final openHistory = _openPlanHistory;
    if (openHistory == null) return;
    _openPlanHistory = null;
    openHistory.commitTransaction();
  }

  void _updatePlanAt(
    int messageIndex,
    VibeExecutionPlan Function(VibeExecutionPlan plan) transform,
  ) {
    if (messageIndex < 0 || messageIndex >= _messages.length) return;
    final currentPlan = _messages[messageIndex].plan;
    if (currentPlan == null) return;
    final nextPlan = transform(currentPlan);
    if (mounted) {
      setState(() {
        _messages[messageIndex] = _messages[messageIndex].copyWith(
          plan: nextPlan,
        );
      });
    } else {
      _messages[messageIndex] = _messages[messageIndex].copyWith(
        plan: nextPlan,
      );
    }
  }

  void _stopStaleActivePlan() {
    final idx = _activePlanMessageIndex;
    if (idx == null || idx < 0 || idx >= _messages.length) {
      _activePlanMessageIndex = null;
      _commitOuterPlanTransaction();
      return;
    }
    final plan = _messages[idx].plan;
    if (plan != null &&
        (plan.status == VibePlanStatus.awaitingConfirmation ||
            plan.status == VibePlanStatus.pausedOnError)) {
      _updatePlanAt(idx, (p) => p.copyWith(status: VibePlanStatus.stopped));
    }
    _activePlanMessageIndex = null;
    _commitOuterPlanTransaction();
  }

  void _cancelPlan(int messageIndex) {
    if (_isBusy || messageIndex != _activePlanMessageIndex) return;
    final plan = _messages[messageIndex].plan;
    if (plan == null || plan.status != VibePlanStatus.awaitingConfirmation) {
      return;
    }
    _updatePlanAt(
      messageIndex,
      (p) => p.copyWith(status: VibePlanStatus.stopped),
    );
    setState(() => _activePlanMessageIndex = null);
    _commitOuterPlanTransaction();
  }

  void _stopPlan(int messageIndex) {
    if (messageIndex != _activePlanMessageIndex) return;
    final plan = _messages[messageIndex].plan;
    if (plan == null) return;
    if (_executingPlan) {
      setState(() => _planStopRequested = true);
      return;
    }
    if (plan.status == VibePlanStatus.pausedOnError ||
        plan.status == VibePlanStatus.awaitingConfirmation) {
      _updatePlanAt(
        messageIndex,
        (p) => p.copyWith(status: VibePlanStatus.stopped),
      );
      setState(() => _activePlanMessageIndex = null);
      _commitOuterPlanTransaction();
      _appendMessage(
        'Exécution du plan arrêtée (${plan.doneCount}/${plan.lots.length} lots appliqués).',
      );
    }
  }

  Future<void> _startPlanExecution(int messageIndex) async {
    if (_isBusy || messageIndex != _activePlanMessageIndex) return;
    final plan = _messages[messageIndex].plan;
    if (plan == null || plan.status != VibePlanStatus.awaitingConfirmation) {
      return;
    }
    final startIdx = plan.nextActionableIndex;
    if (startIdx < 0) return;
    _beginOuterPlanTransaction(EditorHistoryScope.controllerOf(context));
    await _runPlanLoop(messageIndex, startIdx);
  }

  Future<void> _retryPlanLot(int messageIndex) async {
    if (_isBusy || messageIndex != _activePlanMessageIndex) return;
    final plan = _messages[messageIndex].plan;
    if (plan == null || plan.status != VibePlanStatus.pausedOnError) return;
    final failedIdx = plan.lots.indexWhere(
      (lot) => lot.status == VibeLotStatus.failed,
    );
    if (failedIdx < 0) return;
    _updatePlanAt(
      messageIndex,
      (p) => p.withLotAt(
        failedIdx,
        (lot) => lot.copyWith(
          status: VibeLotStatus.pending,
          clearErrorMessage: true,
        ),
      ),
    );
    _beginOuterPlanTransaction(EditorHistoryScope.controllerOf(context));
    await _runPlanLoop(messageIndex, failedIdx);
  }

  Future<void> _skipPlanLot(int messageIndex) async {
    if (_isBusy || messageIndex != _activePlanMessageIndex) return;
    final plan = _messages[messageIndex].plan;
    if (plan == null || plan.status != VibePlanStatus.pausedOnError) return;
    final failedIdx = plan.lots.indexWhere(
      (lot) => lot.status == VibeLotStatus.failed,
    );
    if (failedIdx < 0) return;
    _updatePlanAt(
      messageIndex,
      (p) => p.withLotAt(
        failedIdx,
        (lot) => lot.copyWith(
          status: VibeLotStatus.skipped,
          clearErrorMessage: true,
        ),
      ),
    );
    final updated = _messages[messageIndex].plan!;
    final nextIdx = updated.nextActionableIndex;
    if (nextIdx < 0) {
      _updatePlanAt(
        messageIndex,
        (p) => p.copyWith(status: VibePlanStatus.completed),
      );
      if (mounted) {
        setState(() => _activePlanMessageIndex = null);
      }
      _commitOuterPlanTransaction();
      final skippedCount = updated.lots
          .where((l) => l.status == VibeLotStatus.skipped)
          .length;
      final detail = skippedCount == 0
          ? '${updated.doneCount}/${updated.lots.length} lots appliqués.'
          : '${updated.doneCount}/${updated.lots.length} lots appliqués ($skippedCount ignoré(s)).';
      _appendMessage(
        'Plan terminé (${updated.doneCount}/${updated.lots.length} lots appliqués, '
        '$skippedCount ignoré(s)).',
      );
      _notifyTaskCompletion(
        outcome: VibeTaskOutcome.success,
        title: 'Plan IA terminé',
        detail: detail,
      );
      return;
    }
    _beginOuterPlanTransaction(EditorHistoryScope.controllerOf(context));
    await _runPlanLoop(messageIndex, nextIdx);
  }

  Future<void> _runPlanLoop(int messageIndex, int startLotIndex) async {
    if (!mounted) return;
    _clearCompletionAlert();
    setState(() {
      _executingPlan = true;
      _planStopRequested = false;
    });
    _setExpanded(false);
    _updatePlanAt(
      messageIndex,
      (p) => p.copyWith(status: VibePlanStatus.running),
    );

    try {
      final totalLots = _messages[messageIndex].plan?.lots.length ?? 0;
      for (var i = startLotIndex; i < totalLots; i++) {
        if (!mounted || _planStopRequested) {
          _updatePlanAt(
            messageIndex,
            (p) => p.copyWith(status: VibePlanStatus.stopped),
          );
          final stoppedPlan = _messages[messageIndex].plan;
          if (mounted) {
            setState(() => _activePlanMessageIndex = null);
          }
          _commitOuterPlanTransaction();
          if (stoppedPlan != null) {
            final summary =
                '${stoppedPlan.doneCount}/${stoppedPlan.lots.length} lots appliqués';
            _appendMessage('Exécution du plan arrêtée ($summary).');
            _notifyTaskCompletion(
              outcome: VibeTaskOutcome.info,
              title: 'Plan IA arrêté',
              detail: '$summary.',
            );
          }
          return;
        }

        final currentPlan = _messages[messageIndex].plan;
        if (currentPlan == null) return;
        final lot = currentPlan.lots[i];
        if (lot.status == VibeLotStatus.done ||
            lot.status == VibeLotStatus.skipped) {
          continue;
        }

        _updatePlanAt(
          messageIndex,
          (p) => p
              .copyWith(status: VibePlanStatus.running)
              .withLotAt(
                i,
                (l) => l.copyWith(
                  status: VibeLotStatus.running,
                  clearErrorMessage: true,
                ),
              ),
        );

        final errorCause = await _executeSingleLot(messageIndex, i);
        if (!mounted) return;

        if (errorCause == null) {
          _updatePlanAt(
            messageIndex,
            (p) => p.withLotAt(
              i,
              (l) => l.copyWith(
                status: VibeLotStatus.done,
                clearErrorMessage: true,
              ),
            ),
          );
          continue;
        }

        if (_planStopRequested) {
          _updatePlanAt(
            messageIndex,
            (p) => p
                .copyWith(status: VibePlanStatus.stopped)
                .withLotAt(
                  i,
                  (l) => l.copyWith(
                    status: VibeLotStatus.failed,
                    errorMessage: errorCause,
                  ),
                ),
          );
          final stoppedPlan = _messages[messageIndex].plan;
          setState(() => _activePlanMessageIndex = null);
          _commitOuterPlanTransaction();
          if (stoppedPlan != null) {
            final summary =
                '${stoppedPlan.doneCount}/${stoppedPlan.lots.length} lots appliqués';
            _appendMessage('Exécution du plan arrêtée ($summary).');
            _notifyTaskCompletion(
              outcome: VibeTaskOutcome.info,
              title: 'Plan IA arrêté',
              detail: '$summary.',
            );
          }
          return;
        }

        _updatePlanAt(
          messageIndex,
          (p) => p
              .copyWith(status: VibePlanStatus.pausedOnError)
              .withLotAt(
                i,
                (l) => l.copyWith(
                  status: VibeLotStatus.failed,
                  errorMessage: errorCause,
                ),
              ),
        );
        _setExpanded(true);
        _notifyTaskCompletion(
          outcome: VibeTaskOutcome.error,
          title: 'Plan IA en pause (erreur)',
          detail: 'Lot ${i + 1}/$totalLots : $errorCause',
        );
        return;
      }

      if (!mounted) return;
      final completedPlan = _messages[messageIndex].plan;
      _updatePlanAt(
        messageIndex,
        (p) => p.copyWith(status: VibePlanStatus.completed),
      );
      setState(() => _activePlanMessageIndex = null);
      _commitOuterPlanTransaction();
      if (completedPlan != null) {
        final skipped = completedPlan.lots
            .where((l) => l.status == VibeLotStatus.skipped)
            .length;
        final detail = skipped == 0
            ? '${completedPlan.doneCount}/${completedPlan.lots.length} lots appliqués.'
            : '${completedPlan.doneCount}/${completedPlan.lots.length} lots appliqués ($skipped ignoré(s)).';
        _appendMessage(
          skipped == 0
              ? 'Reproduction terminée : ${completedPlan.doneCount}/${completedPlan.lots.length} lots appliqués.'
              : 'Reproduction terminée : ${completedPlan.doneCount}/${completedPlan.lots.length} lots appliqués ($skipped ignoré(s)).',
        );
        _notifyTaskCompletion(
          outcome: VibeTaskOutcome.success,
          title: 'Plan IA terminé',
          detail: detail,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _executingPlan = false;
          _planStopRequested = false;
        });
      } else {
        _executingPlan = false;
        _planStopRequested = false;
      }
    }
  }

  Future<String?> _executeSingleLot(int messageIndex, int lotIndex) async {
    final planMessage = _messages[messageIndex];
    final plan = planMessage.plan;
    if (plan == null) return 'Plan introuvable.';

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
    setState(() => _sending = true);

    final sourcePrompt = planMessage.planSourcePrompt ?? '';
    final sourceAttachments = planMessage.planSourceAttachments;
    debugPrint(
      '[Vibe IA][Plan] Exécution lot ${lotIndex + 1}/${plan.lots.length} : '
      '"${plan.lots[lotIndex].title}"',
    );
    history?.beginTransaction();
    try {
      final guide = await _loadGuide(context);
      final repositoriesContext = resolvedRepositoryStore == null
          ? null
          : await VibeRepositoryPromptFormatter.formatStoreContext(
              resolvedRepositoryStore,
            );
      String buildLotPrompt({
        Appearance? appearanceOverride,
        Iterable<String>? instantiatedIdsOverride,
        String? repositoriesContext,
      }) => VibePromptBuilder.buildLotTurnPrompt(
        plan: plan,
        lotIndex: lotIndex,
        sourcePrompt: sourcePrompt,
        sourceAttachments: sourceAttachments,
        appearance: appearanceOverride ?? session.baseAppearance,
        codec: widget.codec,
        scope: _scope,
        instantiatedComponentIds:
            instantiatedIdsOverride ?? session.initialInstantiatedIds,
        mountedSlotSummaries: VibeMountedSlotIndex.instance
            .mountedSlotSummaries(),
        repositoriesContext: repositoriesContext,
      );

      final turnPrompt = buildLotPrompt(
        appearanceOverride: session.baseAppearance,
        instantiatedIdsOverride: session.initialInstantiatedIds,
        repositoriesContext: repositoriesContext,
      );
      final generated = await _generateAndApply(
        turnPrompt,
        systemGuide: guide,
        session: session,
        attachments: sourceAttachments,
        allowPlan: false,
        promptBuilder: buildLotPrompt,
      );
      final hasMutations =
          generated.appearance != null || generated.repositoriesUpdated;
      if (!hasMutations) {
        await _rollbackTurnSession(session);
        return 'Le lot n’a produit aucune modification d’écran ("vibe" vide).';
      }
      if (generated.appearance case final appearance?) {
        widget.controller.value = appearance;
        _pulseAppearanceDiff(session, appearance);
        if (_scope == null) {
          _maybeNavigateToNewLivePage(session, appearance);
        }
      } else {
        _rollbackLivePreview(session);
      }
      if (session.repoTransaction?.buildHistoryCallbacks()
          case final repoCallbacks?) {
        history?.addTransactionSideEffect(
          undo: repoCallbacks.undo,
          redo: repoCallbacks.redo,
        );
      }
      return null;
    } on FormatException catch (error) {
      await _rollbackTurnSession(session);
      return _describeErrorCause(error);
    } on ArgumentError catch (error) {
      await _rollbackTurnSession(session);
      return _describeErrorCause(error);
    } on StateError catch (error) {
      await _rollbackTurnSession(session);
      return _describeErrorCause(error);
    } on FlutterError catch (error) {
      await _rollbackTurnSession(session);
      return _describeErrorCause(error);
    } on Exception catch (error) {
      await _rollbackTurnSession(session);
      return _describeErrorCause(error);
    } catch (error) {
      await _rollbackTurnSession(session);
      return _describeErrorCause(error);
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

  VibeAppToolRegistry _resolveToolRegistry(_LiveTurnSession session) {
    final explicit = widget.toolRegistry;
    if (explicit != null) return explicit;
    return VibeAppInspector(
      readAppearance: () => session.checkpointAppearance,
      registry: widget.registry,
      repositoryStore: session.repoTransaction?.store,
      pageRouting: session.pageRouting,
      readScope: () => _scope,
      onSelectScope: (nextScope) {
        if (mounted) {
          setState(() => _scope = nextScope);
        } else {
          _scope = nextScope;
        }
        widget.onScopeChanged?.call(nextScope);
      },
      fallbackContext: () => mounted ? context : null,
      turnStartMarker: session.turnStartMarker,
      previewTracker: session.previewTracker,
    ).buildToolRegistry();
  }

  static String _formatToolStatusLabel(List<VibeToolCall> calls) {
    if (calls.isEmpty) return 'Inspection de l’application…';
    if (calls.length == 1) {
      return switch (calls.first.name) {
        'get_viewport_and_route' => 'Lecture du viewport et de la route…',
        'get_component_geometry' => 'Mesure des composants à l’écran…',
        'get_runtime_tree' => 'Inspection de l’arbre monté…',
        'query_repository_data' => 'Interrogation des repositories…',
        'capture_element_screenshot' => 'Capture visuelle de l’élément…',
        'capture_screenshot' => 'Capture visuelle de l’écran…',
        'get_debug_entries' => 'Lecture des journaux et erreurs…',
        'get_datasources_and_providers' =>
          'Inspection des datasources et providers…',
        'inspect_bindings_and_diagnostics' => 'Audit des liaisons JSON…',
        'get_theme_and_contrast' => 'Vérification du thème et des contrastes…',
        'get_registry_and_selection' =>
          'Lecture du registre et de la sélection…',
        'preview_navigation_or_selection' =>
          'Mise à jour de la route / sélection d’aperçu…',
        'select_editor_element' =>
          'Sélection de l’élément dans l’éditeur…',
        final other => 'Exécution de $other…',
      };
    }
    return 'Inspection de l’application (${calls.map((c) => c.name).join(', ')})…';
  }

  static void _recordToolTraces(
    _LiveTurnSession session,
    List<VibeToolCall> calls,
    List<VibeToolResult> results, {
    bool isPostVerify = false,
  }) {
    final count = calls.length < results.length ? calls.length : results.length;
    for (var i = 0; i < count; i++) {
      session.toolTraces.add(
        VibeToolTrace.fromExecution(
          calls[i],
          results[i],
          isPostVerify: isPostVerify,
        ),
      );
    }
  }

  Future<({Appearance? correctedAppearance, String? summaryMessage})>
  _runPostRenderVerifyPass({
    required Appearance candidateAppearance,
    required String systemGuide,
    required _LiveTurnSession session,
    required VibeAppToolRegistry toolRegistry,
    required bool isDirectGemini,
    required bool useStreaming,
    List<DebugEntry> detectedErrors = const <DebugEntry>[],
  }) async {
    const maxVerifyToolRounds = 2;
    try {
      session.checkpointAppearance = candidateAppearance;
      session.hasCheckpoint = true;
      _setPreviewAppearance(candidateAppearance);
      _pulseAppearanceDiff(session, candidateAppearance);
      if (_scope == null) {
        _maybeNavigateToNewLivePage(session, candidateAppearance);
      }

      _streamingSnapshot.value =
          (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
            activeToolStatus: detectedErrors.isNotEmpty
                ? 'Correction des erreurs d’exécution détectées…'
                : 'Vérification du rendu appliqué…',
            toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
          );

      SchedulerBinding.instance.ensureVisualUpdate();
      if (!_isWidgetTestBinding &&
          SchedulerBinding.instance.hasScheduledFrame) {
        try {
          await SchedulerBinding.instance.endOfFrame.timeout(
            const Duration(milliseconds: 120),
          );
        } on TimeoutException {
          // Ignore si aucune pompe de frame n'est active (ex. tests sans ticker).
        }
      }

      final mountedSummaries = VibeMountedSlotIndex.instance
          .mountedSlotSummaries();
      final errorsSection = detectedErrors.isEmpty
          ? null
          : 'ERREURS D’EXÉCUTION DÉTECTÉES DANS debugEntries APRÈS L’APERÇU :\n'
                '${detectedErrors.take(5).map((e) => '- ${e.message}').join('\n')}\n'
                'Corrige impérativement la cause de ces erreurs dans ton patch delta "vibe".';
      final verifyPrompt = [
        'VÉRIFICATION POST-RENDU (APERÇU APPLIQUÉ) :',
        'Le patch "vibe" vient d’être appliqué en aperçu à l’écran.',
        ?errorsSection,
        if (mountedSummaries.isNotEmpty)
          'Slots montés actuellement à l’écran : ${jsonEncode(mountedSummaries)}.',
        'Appelle si besoin `get_component_geometry`, `get_debug_entries` ou `capture_element_screenshot` pour vérifier les dimensions réelles et détecter tout débordement, zone de taille nulle ou chevauchement.',
        '- Si le rendu est correct et sans erreur, renvoie {"message":"Rendu vérifié.","vibe":null}.',
        '- Si un ajustement est nécessaire, renvoie uniquement un petit patch delta correctif dans "vibe" (avec "verifyRender": false).',
      ].join('\n');

      var roundPrompt = verifyPrompt;
      var roundAttachments = const <VibeChatAttachment>[];
      final conversationContents = isDirectGemini
          ? <Map<String, Object?>>[
              <String, Object?>{
                'role': 'user',
                'parts': GeminiRestClient.buildUserParts(
                  verifyPrompt,
                  const <VibeChatAttachment>[],
                ),
              },
            ]
          : null;

      late String verifyResponse;
      Map<String, dynamic>? decoded;

      for (var round = 0; round <= maxVerifyToolRounds; round++) {
        final allowTools = round < maxVerifyToolRounds;
        var nativeCalls = const <VibeToolCall>[];
        var rawModelParts = const <Map<String, Object?>>[];

        if (useStreaming) {
          final streamed = await _consumeStreamingGenerate(
            roundPrompt,
            systemGuide: systemGuide,
            attachments: roundAttachments,
            tools: allowTools ? toolRegistry.declarations : const [],
            conversationContents: conversationContents,
            enforceJsonResponse: !allowTools,
            completedToolTraces: List<VibeToolTrace>.unmodifiable(
              session.toolTraces,
            ),
          );
          verifyResponse = streamed.rawResponse;
          nativeCalls = streamed.functionCalls;
          rawModelParts = streamed.rawModelParts;
        } else {
          final combined =
              '${VibeChatDialog.defaultSystemInstruction}\n\n'
              'GUIDE DE MODÉLISATION :\n$systemGuide\n\n'
              '$roundPrompt';
          verifyResponse = await _invokeGenerate(combined, roundAttachments);
        }

        if (nativeCalls.isNotEmpty) {
          if (!allowTools) break;
          _streamingSnapshot.value =
              (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
                activeToolStatus: _formatToolStatusLabel(nativeCalls),
                toolTraces: List<VibeToolTrace>.unmodifiable(
                  session.toolTraces,
                ),
              );
          final results = await toolRegistry.executeAll(nativeCalls);
          _recordToolTraces(session, nativeCalls, results, isPostVerify: true);
          _streamingSnapshot.value =
              (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
                activeToolStatus: _formatToolStatusLabel(nativeCalls),
                toolTraces: List<VibeToolTrace>.unmodifiable(
                  session.toolTraces,
                ),
              );
          final generatedAttachments = <VibeChatAttachment>[
            for (final r in results) ...r.attachments,
          ];
          if (generatedAttachments.isNotEmpty) {
            roundAttachments = [...roundAttachments, ...generatedAttachments];
          }
          if (conversationContents != null) {
            conversationContents.add(<String, Object?>{
              'role': 'model',
              'parts': rawModelParts.isNotEmpty
                  ? rawModelParts
                  : <Map<String, Object?>>[
                      for (final c in nativeCalls)
                        <String, Object?>{
                          'functionCall': c.toGeminiFunctionCall(),
                        },
                    ],
            });
            conversationContents.add(<String, Object?>{
              'role': 'user',
              'parts': <Map<String, Object?>>[
                for (final r in results)
                  <String, Object?>{
                    'functionResponse': <String, Object?>{
                      'name': r.name,
                      'response': r.toGeminiFunctionResponsePayload(),
                    },
                  },
                for (final att in generatedAttachments)
                  if (att.isImage) ...<Map<String, Object?>>[
                    <String, Object?>{
                      'text':
                          'Capture d’écran produite par outil (${att.name}) :',
                    },
                    <String, Object?>{
                      'inlineData': <String, Object?>{
                        'mimeType': att.mimeType,
                        'data': base64Encode(att.bytes),
                      },
                    },
                  ],
              ],
            });
          } else {
            roundPrompt =
                '$roundPrompt\n\nRÉSULTATS DES OUTILS DEMANDÉS (vérification ${round + 1}) :\n'
                '${jsonEncode([for (final r in results) r.toJson()])}\n'
                'Conclue maintenant avec {"message":"...","vibe":null} ou un patch delta correctif.';
          }
          continue;
        }

        decoded = null;
        List<VibeToolCall> jsonCalls = const <VibeToolCall>[];
        if (verifyResponse.trim().isNotEmpty) {
          final parsed = _decodeResponseJson(_extractJson(verifyResponse));
          if (parsed is Map<String, dynamic>) {
            decoded = parsed;
            if (parsed['vibe'] == null && parsed['toolCalls'] != null) {
              jsonCalls = VibeToolCall.tryListFromJson(parsed['toolCalls']);
            }
          }
        }
        if (jsonCalls.isNotEmpty && allowTools) {
          _streamingSnapshot.value =
              (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
                activeToolStatus: _formatToolStatusLabel(jsonCalls),
                toolTraces: List<VibeToolTrace>.unmodifiable(
                  session.toolTraces,
                ),
              );
          final results = await toolRegistry.executeAll(jsonCalls);
          _recordToolTraces(session, jsonCalls, results, isPostVerify: true);
          _streamingSnapshot.value =
              (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
                activeToolStatus: _formatToolStatusLabel(jsonCalls),
                toolTraces: List<VibeToolTrace>.unmodifiable(
                  session.toolTraces,
                ),
              );
          final generatedAttachments = <VibeChatAttachment>[
            for (final r in results) ...r.attachments,
          ];
          if (generatedAttachments.isNotEmpty) {
            roundAttachments = [...roundAttachments, ...generatedAttachments];
          }
          final encodedResults = jsonEncode([
            for (final r in results) r.toJson(),
          ]);
          if (conversationContents != null) {
            conversationContents.add(<String, Object?>{
              'role': 'model',
              'parts': <Map<String, Object?>>[
                <String, Object?>{'text': verifyResponse},
              ],
            });
            conversationContents.add(<String, Object?>{
              'role': 'user',
              'parts': <Map<String, Object?>>[
                <String, Object?>{
                  'text':
                      'RÉSULTATS DES OUTILS DEMANDÉS (vérification ${round + 1}) :\n'
                      '$encodedResults\n'
                      'Conclue maintenant avec {"message":"...","vibe":null} ou un patch delta correctif.',
                },
                for (final att in generatedAttachments)
                  if (att.isImage) ...<Map<String, Object?>>[
                    <String, Object?>{
                      'text':
                          'Capture d’écran produite par outil (${att.name}) :',
                    },
                    <String, Object?>{
                      'inlineData': <String, Object?>{
                        'mimeType': att.mimeType,
                        'data': base64Encode(att.bytes),
                      },
                    },
                  ],
              ],
            });
          } else {
            roundPrompt =
                '$roundPrompt\n\nRÉSULTATS DES OUTILS DEMANDÉS (vérification ${round + 1}) :\n'
                '$encodedResults\n'
                'Conclue maintenant avec {"message":"...","vibe":null} ou un patch delta correctif.';
          }
          continue;
        }
        break;
      }

      if (decoded == null) {
        return (correctedAppearance: null, summaryMessage: null);
      }
      final summary = decoded['message'] is String
          ? (decoded['message'] as String).trim()
          : null;
      final patch = _extractPatch(decoded);
      if (patch == null) {
        return (correctedAppearance: null, summaryMessage: summary);
      }

      final activeScope = _scope;
      final rewritten = session.repoTransaction != null
          ? session.repoTransaction!.rewriteVibePatchBindings(patch)
          : patch;
      final effectivePatch = activeScope == null
          ? rewritten
          : VibeChatDialog.filterPatchToScope(
              candidateAppearance,
              rewritten,
              activeScope,
            );
      if (!_hasPatchChanges(effectivePatch)) {
        return (correctedAppearance: null, summaryMessage: summary);
      }

      final corrected = AppearanceTransfer.applyVibe(
        candidateAppearance,
        jsonEncode(effectivePatch),
        codec: widget.codec,
      );
      widget.validateAppearance?.call(corrected);
      _validatePatchedComponents(
        candidateAppearance,
        corrected,
        effectivePatch,
        instantiatedIds: session.initialInstantiatedIds,
      );
      return (correctedAppearance: corrected, summaryMessage: summary);
    } catch (error) {
      debugPrint(
        '[Vibe IA] Passe de vérification post-rendu ignorée après erreur : $error',
      );
      return (correctedAppearance: null, summaryMessage: null);
    }
  }

  Future<
    ({
      String rawResponse,
      VibeStreamSnapshot finalSnapshot,
      List<VibeToolCall> functionCalls,
      List<Map<String, Object?>> rawModelParts,
    })
  >
  _consumeStreamingGenerate(
    String turnPrompt, {
    required String systemGuide,
    required List<VibeChatAttachment> attachments,
    List<VibeToolDeclaration> tools = const <VibeToolDeclaration>[],
    List<Map<String, Object?>>? conversationContents,
    bool enforceJsonResponse = true,
    List<VibeToolTrace> completedToolTraces = const <VibeToolTrace>[],
  }) async {
    final customStream = widget.streamGenerate;
    final parser = VibeIncrementalStreamParser();
    _pendingSnapshot = null;
    _streamingSnapshot.value = VibeStreamSnapshot(
      toolTraces: completedToolTraces,
    );

    var finalAccumulated = '';
    var functionCalls = const <VibeToolCall>[];
    var rawModelParts = const <Map<String, Object?>>[];
    final stream = customStream != null
        ? customStream(
            turnPrompt,
            systemInstruction: VibeChatDialog.defaultSystemInstruction,
            staticGuide: systemGuide,
            attachments: attachments,
            speedMode: _speedMode,
          )
        : streamGemini(
            turnPrompt,
            systemInstruction: VibeChatDialog.defaultSystemInstruction,
            staticGuide: systemGuide,
            attachments: attachments,
            speedMode: _speedMode,
            tools: tools,
            conversationContents: conversationContents,
            enforceJsonResponse: enforceJsonResponse,
          );

    await for (final event in stream) {
      if (event.deltaText.isNotEmpty) {
        final snapshot = parser
            .addChunk(event.deltaText)
            .copyWith(toolTraces: completedToolTraces);
        _publishStreamSnapshot(snapshot);
      } else if (event.isDone &&
          parser.rawBuffer.isEmpty &&
          event.accumulatedText.isNotEmpty) {
        parser.addChunk(event.accumulatedText);
      }
      if (event.functionCalls.isNotEmpty) {
        functionCalls = event.functionCalls;
      }
      if (event.rawModelParts.isNotEmpty) {
        rawModelParts = event.rawModelParts;
      }
      if (event.accumulatedText.isNotEmpty) {
        finalAccumulated = event.accumulatedText;
      }
      if (event.isDone) {
        _pendingSnapshot = null;
        _streamingSnapshot.value = parser.current.copyWith(
          toolTraces: completedToolTraces,
        );
      }
    }

    final rawResponse = parser.rawBuffer.isNotEmpty
        ? parser.rawBuffer
        : finalAccumulated;
    return (
      rawResponse: rawResponse,
      finalSnapshot: parser.current,
      functionCalls: functionCalls,
      rawModelParts: rawModelParts,
    );
  }

  Future<
    ({
      Appearance? appearance,
      bool repositoriesUpdated,
      Map<String, dynamic> result,
      VibeAskUserRequest? askUser,
      VibeExecutionPlan? plan,
    })
  >
  _generateAndApply(
    String turnPrompt, {
    required String systemGuide,
    required _LiveTurnSession session,
    List<VibeChatAttachment> attachments = const [],
    bool allowPlan = true,
    String Function({
      Appearance? appearanceOverride,
      Iterable<String>? instantiatedIdsOverride,
      String? repositoriesContext,
    })?
    promptBuilder,
  }) async {
    const maxAttempts = 4;
    var currentTurnPrompt = turnPrompt;
    var attemptAttachments = List<VibeChatAttachment>.of(attachments);
    var disableToolsForAttempt = false;
    final priorCauses = <String>[];
    final toolRegistry = _resolveToolRegistry(session);
    VibeSalvageOutcome? lastCheckpointSalvage;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final attemptDebugMarker = VibeDebugCapture.markNow();
      if (attempt > 0) {
        _pendingSnapshot = null;
        _streamingSnapshot.value = null;
        session.livePreviewDisabled = false;
        session.liveRepoQueue = Future<void>.value();
        session.toolTraces.clear();
      }
      final useStreaming = _usesStreamingGenerator;
      final isDirectGemini =
          useStreaming &&
          widget.streamGenerate == null &&
          identical(widget.generate, callGemini);
      debugPrint(
        '[Vibe IA] Tentative ${attempt + 1}/$maxAttempts — envoi du prompt '
        '(${currentTurnPrompt.length} caractères dynamiques, '
        'mode: ${useStreaming ? _speedMode.name : "custom"}, '
        'fichiers joints: ${attemptAttachments.length}'
        '${session.hasCheckpoint ? ", mode: delta sur checkpoint" : ""})...',
      );

      var roundPrompt = currentTurnPrompt;
      var roundAttachments = List<VibeChatAttachment>.of(attemptAttachments);
      final collectedToolResults = <Map<String, Object?>>[];
      final collectedToolAttachments = <VibeChatAttachment>[];
      final conversationContents = isDirectGemini
          ? <Map<String, Object?>>[
              <String, Object?>{
                'role': 'user',
                'parts': GeminiRestClient.buildUserParts(
                  currentTurnPrompt,
                  attemptAttachments,
                ),
              },
            ]
          : null;

      late String response;
      late VibeStreamSnapshot finalSnapshot;
      Map<String, dynamic>? preDecodedMap;
      var exceededNativeToolRounds = false;

      for (
        var toolRound = 0;
        toolRound <= VibeChatDialog.maxToolRounds;
        toolRound++
      ) {
        final allowTools =
            !disableToolsForAttempt &&
            toolRegistry.isNotEmpty &&
            toolRound < VibeChatDialog.maxToolRounds;
        var nativeCalls = const <VibeToolCall>[];
        var rawModelParts = const <Map<String, Object?>>[];
        try {
          if (useStreaming) {
            final streamed = await _consumeStreamingGenerate(
              roundPrompt,
              systemGuide: systemGuide,
              attachments: roundAttachments,
              tools: allowTools ? toolRegistry.declarations : const [],
              conversationContents: conversationContents,
              enforceJsonResponse: !allowTools,
              completedToolTraces: List<VibeToolTrace>.unmodifiable(
                session.toolTraces,
              ),
            );
            response = streamed.rawResponse;
            finalSnapshot = streamed.finalSnapshot;
            nativeCalls = streamed.functionCalls;
            rawModelParts = streamed.rawModelParts;
          } else {
            final toolsSection = allowTools && toolRound == 0
                ? '\n\n${toolRegistry.formatToolsGuideSection()}'
                : '';
            final combinedPrompt =
                '${VibeChatDialog.defaultSystemInstruction}\n\n'
                'GUIDE DE MODÉLISATION :\n$systemGuide$toolsSection\n\n'
                '$roundPrompt';
            response = await _invokeGenerate(combinedPrompt, roundAttachments);
            final parser = VibeIncrementalStreamParser()..addChunk(response);
            finalSnapshot = parser.current;
          }
        } catch (error, stackTrace) {
          debugPrint(
            '[Vibe IA] Échec de génération à la tentative ${attempt + 1} '
            '(tour outil $toolRound, ${error.runtimeType}) : $error\n$stackTrace',
          );
          rethrow;
        }

        if (nativeCalls.isNotEmpty) {
          if (!allowTools) {
            exceededNativeToolRounds = true;
            break;
          }
          debugPrint(
            '[Vibe IA] Exécution de ${nativeCalls.length} outil(s) natif(s) : '
            '${nativeCalls.map((c) => c.name).join(', ')}',
          );
          _streamingSnapshot.value = (_streamingSnapshot.value ?? finalSnapshot)
              .copyWith(
                activeToolStatus: _formatToolStatusLabel(nativeCalls),
                toolTraces: List<VibeToolTrace>.unmodifiable(
                  session.toolTraces,
                ),
              );
          final results = await toolRegistry.executeAll(nativeCalls);
          _recordToolTraces(session, nativeCalls, results);
          _streamingSnapshot.value = (_streamingSnapshot.value ?? finalSnapshot)
              .copyWith(
                activeToolStatus: _formatToolStatusLabel(nativeCalls),
                toolTraces: List<VibeToolTrace>.unmodifiable(
                  session.toolTraces,
                ),
              );
          collectedToolResults.addAll(results.map((r) => r.toJson()));
          final generatedAttachments = <VibeChatAttachment>[
            for (final r in results) ...r.attachments,
          ];
          if (generatedAttachments.isNotEmpty) {
            roundAttachments = [...roundAttachments, ...generatedAttachments];
            collectedToolAttachments.addAll(generatedAttachments);
          }
          final isLastToolRound = toolRound + 1 >= VibeChatDialog.maxToolRounds;
          if (conversationContents != null) {
            conversationContents.add(<String, Object?>{
              'role': 'model',
              'parts': rawModelParts.isNotEmpty
                  ? rawModelParts
                  : <Map<String, Object?>>[
                      for (final c in nativeCalls)
                        <String, Object?>{
                          'functionCall': c.toGeminiFunctionCall(),
                        },
                    ],
            });
            conversationContents.add(<String, Object?>{
              'role': 'user',
              'parts': <Map<String, Object?>>[
                for (final r in results)
                  <String, Object?>{
                    'functionResponse': <String, Object?>{
                      'name': r.name,
                      'response': r.toGeminiFunctionResponsePayload(),
                    },
                  },
                if (isLastToolRound)
                  const <String, Object?>{
                    'text':
                        'ATTENTION : limite maximale d’appels d’outils atteinte. '
                        'Tu disposes maintenant de toutes les mesures nécessaires : '
                        'n’appelle PLUS aucun outil (ni functionCall ni toolCalls) et '
                        'renvoie immédiatement ta réponse JSON finale '
                        '{"message":"...","vibe":...} (ou "vibe":null).',
                  },
                for (final att in generatedAttachments)
                  if (att.isImage) ...<Map<String, Object?>>[
                    <String, Object?>{
                      'text':
                          'Capture d’écran produite par outil (${att.name}) :',
                    },
                    <String, Object?>{
                      'inlineData': <String, Object?>{
                        'mimeType': att.mimeType,
                        'data': base64Encode(att.bytes),
                      },
                    },
                  ],
              ],
            });
          } else {
            roundPrompt =
                '$roundPrompt\n\nRÉSULTATS DES OUTILS DEMANDÉS (tour ${toolRound + 1}) :\n'
                '${jsonEncode([for (final r in results) r.toJson()])}\n'
                '${isLastToolRound ? 'ATTENTION : limite maximale d’appels d’outils atteinte. N’appelle PLUS aucun outil et génère immédiatement ta réponse JSON finale {"message":"...","vibe":...} (ou "vibe":null).' : 'Utilise ces mesures réelles pour poursuivre ou produire ta réponse JSON finale.'}';
          }
          continue;
        }

        // Vérifie le protocole JSON unifié ("toolCalls": [...]) lorsqu'aucun patch final n'est émis.
        preDecodedMap = null;
        List<VibeToolCall> jsonToolCalls = const <VibeToolCall>[];
        if (response.trim().isNotEmpty) {
          try {
            final extracted = _extractJson(response);
            final parsed = _decodeResponseJson(extracted);
            if (parsed is Map<String, dynamic>) {
              preDecodedMap = parsed;
              final hasFinalPayload =
                  parsed['vibe'] != null ||
                  parsed['repositories'] != null ||
                  parsed['askUser'] != null ||
                  parsed['plan'] != null;
              if (!hasFinalPayload && parsed['toolCalls'] != null) {
                jsonToolCalls = VibeToolCall.tryListFromJson(
                  parsed['toolCalls'],
                );
              }
            }
          } on FormatException {
            // Laisse la phase de validation normale diagnostiquer l'erreur JSON.
          }
        }

        if (jsonToolCalls.isNotEmpty) {
          if (!allowTools) {
            preDecodedMap = null;
            break;
          }
          debugPrint(
            '[Vibe IA] Exécution de ${jsonToolCalls.length} outil(s) JSON : '
            '${jsonToolCalls.map((c) => c.name).join(', ')}',
          );
          _streamingSnapshot.value = (_streamingSnapshot.value ?? finalSnapshot)
              .copyWith(
                activeToolStatus: _formatToolStatusLabel(jsonToolCalls),
                toolTraces: List<VibeToolTrace>.unmodifiable(
                  session.toolTraces,
                ),
              );
          final results = await toolRegistry.executeAll(jsonToolCalls);
          _recordToolTraces(session, jsonToolCalls, results);
          _streamingSnapshot.value = (_streamingSnapshot.value ?? finalSnapshot)
              .copyWith(
                activeToolStatus: _formatToolStatusLabel(jsonToolCalls),
                toolTraces: List<VibeToolTrace>.unmodifiable(
                  session.toolTraces,
                ),
              );
          collectedToolResults.addAll(results.map((r) => r.toJson()));
          final generatedAttachments = <VibeChatAttachment>[
            for (final r in results) ...r.attachments,
          ];
          if (generatedAttachments.isNotEmpty) {
            roundAttachments = [...roundAttachments, ...generatedAttachments];
            collectedToolAttachments.addAll(generatedAttachments);
          }
          final encodedResults = jsonEncode([
            for (final r in results) r.toJson(),
          ]);
          final isLastToolRound = toolRound + 1 >= VibeChatDialog.maxToolRounds;
          final nextToolDirective = isLastToolRound
              ? 'ATTENTION : limite maximale d’appels d’outils atteinte. '
                    'N’appelle PLUS aucun outil et renvoie immédiatement ta réponse JSON finale '
                    '(sans "toolCalls").'
              : 'Utilise ces mesures réelles pour appeler un autre outil ou renvoyer ta réponse JSON finale (sans "toolCalls").';
          if (conversationContents != null) {
            conversationContents.add(<String, Object?>{
              'role': 'model',
              'parts': <Map<String, Object?>>[
                <String, Object?>{'text': response},
              ],
            });
            conversationContents.add(<String, Object?>{
              'role': 'user',
              'parts': <Map<String, Object?>>[
                <String, Object?>{
                  'text':
                      'RÉSULTATS DES OUTILS DEMANDÉS (tour ${toolRound + 1}) :\n'
                      '$encodedResults\n'
                      '$nextToolDirective',
                },
                for (final att in generatedAttachments)
                  if (att.isImage) ...<Map<String, Object?>>[
                    <String, Object?>{
                      'text':
                          'Capture d’écran produite par outil (${att.name}) :',
                    },
                    <String, Object?>{
                      'inlineData': <String, Object?>{
                        'mimeType': att.mimeType,
                        'data': base64Encode(att.bytes),
                      },
                    },
                  ],
              ],
            });
          } else {
            roundPrompt =
                '$roundPrompt\n\nRÉSULTATS DES OUTILS DEMANDÉS (tour ${toolRound + 1}) :\n'
                '$encodedResults\n'
                '$nextToolDirective';
          }
          continue;
        }

        break;
      }

      session.livePreviewDisabled = true;
      try {
        await session.liveRepoQueue;
      } catch (_) {
        // Ignore les erreurs transitoires de la file live avant validation finale.
      }
      _lastFailedResponse = response;
      _logLong('[Vibe IA] Réponse brute (tentative ${attempt + 1})', response);
      Map<String, dynamic>? decodedMap;
      try {
        if (exceededNativeToolRounds) {
          disableToolsForAttempt = true;
          throw const FormatException(
            'Nombre maximal d’appels d’outils atteint : génère maintenant la réponse finale sans appeler d’outil.',
          );
        }
        final Object? result;
        if (preDecodedMap != null) {
          result = preDecodedMap;
        } else {
          final json = _extractJson(response);
          try {
            result = _decodeResponseJson(json);
          } on FormatException catch (error) {
            debugPrint(
              '[Vibe IA] Échec de jsonDecode (tentative ${attempt + 1}) : '
              '${error.message} (offset: ${error.offset})',
            );
            rethrow;
          }
        }
        if (result is! Map<String, dynamic>) {
          debugPrint(
            '[Vibe IA] Le JSON décodé n’est pas un Map<String, dynamic> '
            '(type reçu: ${result.runtimeType}).',
          );
          throw const FormatException('La réponse doit être un objet JSON.');
        }
        decodedMap = result;
        if (result['toolCalls'] != null &&
            VibeToolCall.tryListFromJson(result['toolCalls']).isNotEmpty &&
            result['vibe'] == null &&
            result['repositories'] == null &&
            result['askUser'] == null &&
            result['plan'] == null) {
          disableToolsForAttempt = true;
          throw const FormatException(
            'Nombre maximal d’appels d’outils atteint : génère maintenant la réponse finale sans "toolCalls".',
          );
        }
        final rawAskUser = VibeAskUserRequest.tryFromJson(result['askUser']);
        final rawPlan = allowPlan
            ? VibeExecutionPlan.tryFromJson(result['plan'])
            : null;
        if (_isForceFollowUpQuestions) {
          final followUpAskUser = rawAskUser?.truncate(
            VibeQuestioningLevel.followUpMaxQuestions,
          );
          if (followUpAskUser == null) {
            throw const FormatException(
              'L’utilisateur a demandé "+ de questions" : renvoie un objet "askUser" '
              'contenant 2 à 4 questions complémentaires et "vibe": null.',
            );
          }
          _lastFailedResponse = null;
          return (
            appearance: null,
            repositoriesUpdated: false,
            result: result,
            askUser: followUpAskUser,
            plan: null,
          );
        }
        final repositoriesPatch = _extractRepositoriesPatch(result);
        final patch = _extractPatch(result);
        if (repositoriesPatch == null &&
            patch == null &&
            !session.hasCheckpoint) {
          if (rawPlan != null) {
            _lastFailedResponse = null;
            return (
              appearance: null,
              repositoriesUpdated: false,
              result: result,
              askUser: null,
              plan: rawPlan,
            );
          }
          if (rawAskUser != null &&
              (_questioningLevel == VibeQuestioningLevel.none ||
                  _reproduceExactMode ||
                  _isAfterAskUserReply)) {
            throw const FormatException(
              'Le questionnaire "askUser" est désactivé sur ce tour : '
              'génère directement le patch "vibe" ou un "plan" sans "askUser".',
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
            plan: null,
          );
        }
        if (session.hasCheckpoint &&
            patch == null &&
            repositoriesPatch == null) {
          if (rawAskUser != null) {
            throw const FormatException(
              'Ne renvoie pas "askUser" lors d’une correction delta : '
              'génère directement le patch "vibe" correctif.',
            );
          }
          final message = result['message'];
          if (message is! String || message.trim().isEmpty) {
            throw const FormatException(
              'La réponse corrective ne contient ni patch "vibe" ni message valide.',
            );
          }
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
        Map<String, dynamic>? effectivePatch;
        final current = session.checkpointAppearance;
        final activeScope = _scope;
        if (patch != null) {
          final rewrittenPatch = session.repoTransaction != null
              ? session.repoTransaction!.rewriteVibePatchBindings(patch)
              : patch;
          effectivePatch = activeScope == null
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
        } else if (session.hasCheckpoint) {
          appearance = AppearanceTransfer.applyVibeMap(
            current,
            const <String, dynamic>{},
            codec: widget.codec,
            normalizeRoundTrip: true,
          );
          widget.validateAppearance?.call(appearance);
        }

        if (session.hasCheckpoint && appearance != null) {
          final finalReachableIds = VibeDeltaRecovery.computeReachableIds(
            baseForScope: session.baseAppearance,
            next: appearance,
            scope: activeScope,
            instantiatedIds: session.initialInstantiatedIds,
            initialPageIds: session.initialPageIds,
            hasRegistry: widget.registry != null,
            requireNewPageComponent: true,
          );
          final patchedComponentsRaw = effectivePatch == null
              ? null
              : (effectivePatch['data'] is Map
                    ? (effectivePatch['data'] as Map)['components']
                    : effectivePatch['components']);
          final patchedCompKeys = patchedComponentsRaw is Map
              ? patchedComponentsRaw.keys.whereType<String>().toSet()
              : const <String>{};

          final unresolvedFixes = <String>[
            for (final id in session.pendingComponentFixes)
              if (!patchedCompKeys.contains(id) &&
                  (finalReachableIds.contains(id) ||
                      session.baseAppearance.components.containsKey(id)))
                id,
          ];
          if (unresolvedFixes.isNotEmpty) {
            throw FormatException(
              'Composant(s) en erreur ou manquants non corrigés dans le patch delta : '
              '${unresolvedFixes.join(', ')}. Fournis leur configuration valide dans "components".',
            );
          }

          if (session.requiresScreenAttachment) {
            final hasAttachedChange =
                appearance.pageCatalog != session.baseAppearance.pageCatalog ||
                finalReachableIds.any(
                  (id) =>
                      session.baseAppearance.components[id] !=
                      appearance!.components[id],
                );
            if (!hasAttachedChange) {
              throw const FormatException(
                'Les composants générés ne sont rattachés à aucun conteneur de l’écran : '
                'mets à jour les "placements" d’un conteneur existant.',
              );
            }
          }

          appearance = VibeDeltaRecovery.pruneUnreachableTurnDrafts(
            baseAppearance: session.baseAppearance,
            nextAppearance: appearance,
            reachableIds: finalReachableIds,
          );
        }

        _lastFailedResponse = null;
        var finalResult = result;
        var detectedPostErrors = const <DebugEntry>[];
        if (appearance != null && toolRegistry.isNotEmpty) {
          if (!_isWidgetTestBinding) {
            _setPreviewAppearance(appearance);
            session.hasAppliedLivePreview = true;
            if (SchedulerBinding.instance.hasScheduledFrame) {
              try {
                await SchedulerBinding.instance.endOfFrame.timeout(
                  const Duration(milliseconds: 80),
                );
              } on TimeoutException {
                // Poursuit sans attente supplémentaire.
              }
            }
          }
          detectedPostErrors = VibeDebugCapture.entriesSince(
            attemptDebugMarker,
            type: DebugEntryType.error,
          );
        }
        final wantsPostVerify =
            appearance != null &&
            toolRegistry.isNotEmpty &&
            (result['verifyRender'] == true ||
                detectedPostErrors.isNotEmpty ||
                (_reproduceExactMode &&
                    isDirectGemini &&
                    VibeMountedSlotIndex.instance.allEntries.isNotEmpty));
        if (wantsPostVerify) {
          final verified = await _runPostRenderVerifyPass(
            candidateAppearance: appearance,
            systemGuide: systemGuide,
            session: session,
            toolRegistry: toolRegistry,
            isDirectGemini: isDirectGemini,
            useStreaming: useStreaming,
            detectedErrors: detectedPostErrors,
          );
          if (verified.correctedAppearance != null) {
            appearance = verified.correctedAppearance;
          }
          if (verified.summaryMessage != null &&
              verified.summaryMessage!.isNotEmpty) {
            finalResult = <String, dynamic>{
              ...result,
              'message': verified.summaryMessage,
            };
          }
        }
        return (
          appearance: appearance,
          repositoriesUpdated:
              (session.repoTransaction?.hasChanges ?? false) ||
              repositoriesPatch != null,
          result: finalResult,
          askUser: null,
          plan: null,
        );
      } catch (error) {
        session.livePreviewDisabled = true;
        try {
          await session.liveRepoQueue;
        } catch (_) {}

        final preRollbackAliases = session.repoTransaction == null
            ? const <String, String>{}
            : Map<String, String>.of(session.repoTransaction!.aliasToActualId);

        if (session.repoCheckpoint != null) {
          try {
            await session.repoTransaction?.restoreSavepoint(
              session.repoCheckpoint!,
            );
          } catch (_) {}
        } else {
          try {
            await session.repoTransaction?.rollback();
          } catch (_) {}
        }

        final isValidationError =
            error is FormatException ||
            error is ArgumentError ||
            error is StateError;
        if (attempt >= maxAttempts - 1 || !isValidationError) {
          await _rollbackTurnSession(session);
          debugPrint(
            '[Vibe IA] Tentative ${attempt + 1} échouée sans relance '
            '(${error.runtimeType}) : ${_describeErrorCause(error)}',
          );
          rethrow;
        }

        final cause = _describeErrorCause(error);
        priorCauses.add(
          'Tentative ${attempt + 1} (${error.runtimeType}) : $cause',
        );

        // Tentative de récupération incrémentale (checkpoint des entrées déjà valides) :
        final wasTruncated = decodedMap == null;
        Map<String, dynamic>? rawReposCandidate;
        Map<String, dynamic>? rawVibeCandidate;
        if (decodedMap != null) {
          if (decodedMap['repositories'] is Map<String, dynamic>) {
            final repos = decodedMap['repositories'] as Map<String, dynamic>;
            if (repos.isNotEmpty) rawReposCandidate = repos;
          }
          try {
            rawVibeCandidate = _extractPatch(decodedMap);
          } on FormatException {
            rawVibeCandidate = null;
          }
        } else {
          rawReposCandidate = finalSnapshot.partialRepositoriesPatch;
          rawVibeCandidate = finalSnapshot.partialVibePatch;
        }

        var appliedRepoKeys = const <String>{};
        var rejectedRepoEntries = const <PatchRejectedEntry>[];
        if (wasTruncated &&
            rawReposCandidate != null &&
            session.repoTransaction != null) {
          final repoPartial = await session.repoTransaction!
              .applyRepositoriesPatchPartial(rawReposCandidate);
          appliedRepoKeys = repoPartial.appliedEntries.keys.toSet();
          rejectedRepoEntries = repoPartial.rejectedEntries;
        }

        Map<String, dynamic>? buildEffectiveCandidate(
          Map<String, String> aliasMap,
        ) {
          if (rawVibeCandidate == null) return null;
          final rewritten = aliasMap.isNotEmpty
              ? rewriteVibePatchRepositoryAliases(rawVibeCandidate, aliasMap)
              : (session.repoTransaction != null
                    ? session.repoTransaction!.rewriteVibePatchBindings(
                        rawVibeCandidate,
                      )
                    : rawVibeCandidate);
          return _scope == null
              ? rewritten
              : VibeChatDialog.filterPatchToScope(
                  session.checkpointAppearance,
                  rewritten,
                  _scope!,
                );
        }

        var effectiveCandidatePatch = buildEffectiveCandidate(
          wasTruncated
              ? (session.repoTransaction?.aliasToActualId ??
                    const <String, String>{})
              : preRollbackAliases,
        );

        var salvage = VibeDeltaRecovery.salvageFailedAttempt(
          initialAppearance: session.baseAppearance,
          workingAppearance: session.checkpointAppearance,
          initialPageIds: session.initialPageIds,
          instantiatedIds: session.initialInstantiatedIds,
          hasRegistry: widget.registry != null,
          scope: _scope,
          codec: widget.codec,
          validateAppearance: widget.validateAppearance,
          effectiveVibePatch: effectiveCandidatePatch,
          rejectedRepoEntries: rejectedRepoEntries,
          appliedRepoKeys: appliedRepoKeys,
          wasTruncated: wasTruncated,
          interruptedSection: wasTruncated ? finalSnapshot.activeSection : null,
          interruptedKey: wasTruncated ? finalSnapshot.activeEntryKey : null,
        );

        if (!wasTruncated &&
            salvage.hasCheckpoint &&
            rawReposCandidate != null &&
            session.repoTransaction != null) {
          final repoPartial = await session.repoTransaction!
              .applyRepositoriesPatchPartial(rawReposCandidate);
          appliedRepoKeys = repoPartial.appliedEntries.keys.toSet();
          rejectedRepoEntries = repoPartial.rejectedEntries;
          effectiveCandidatePatch = buildEffectiveCandidate(
            session.repoTransaction!.aliasToActualId,
          );
          salvage = VibeDeltaRecovery.salvageFailedAttempt(
            initialAppearance: session.baseAppearance,
            workingAppearance: session.checkpointAppearance,
            initialPageIds: session.initialPageIds,
            instantiatedIds: session.initialInstantiatedIds,
            hasRegistry: widget.registry != null,
            scope: _scope,
            codec: widget.codec,
            validateAppearance: widget.validateAppearance,
            effectiveVibePatch: effectiveCandidatePatch,
            rejectedRepoEntries: rejectedRepoEntries,
            appliedRepoKeys: appliedRepoKeys,
            wasTruncated: false,
          );
        }

        if (salvage.hasCheckpoint) {
          final candidateComps = effectiveCandidatePatch == null
              ? null
              : (effectiveCandidatePatch['data'] is Map
                    ? (effectiveCandidatePatch['data'] as Map)['components']
                    : effectiveCandidatePatch['components']);
          final rejectedCompKeys = {
            for (final entry in salvage.rejectedEntries)
              if (entry.section == 'components') entry.key,
          };
          if (candidateComps is Map) {
            for (final key in candidateComps.keys.whereType<String>()) {
              if (!rejectedCompKeys.contains(key)) {
                session.pendingComponentFixes.remove(key);
              }
            }
          }
          session.pendingComponentFixes.addAll(
            salvage.pendingRequiredComponentIds,
          );
          session.checkpointAppearance = salvage.checkpointAppearance;
          session.hasCheckpoint = true;
          session.requiresScreenAttachment = salvage.requiresScreenAttachment;
          session.repoCheckpoint = session.repoTransaction?.createSavepoint();
          lastCheckpointSalvage = salvage;
          _restoreCheckpointPreview(session);

          final resolvedStore = session.repoTransaction?.store;
          final refreshedReposContext = resolvedStore == null
              ? null
              : await VibeRepositoryPromptFormatter.formatStoreContext(
                  resolvedStore,
                );
          final buildPrompt = promptBuilder ?? _buildTurnPrompt;
          final refreshedTurnPrompt = buildPrompt(
            appearanceOverride: session.checkpointAppearance,
            instantiatedIdsOverride: session.initialInstantiatedIds,
            repositoriesContext: refreshedReposContext,
          );
          currentTurnPrompt = VibeDeltaRecovery.buildDeltaRetryPrompt(
            refreshedTurnPrompt: refreshedTurnPrompt,
            priorCauses: priorCauses,
            salvage: salvage,
            pendingRequiredComponentIds: session.pendingComponentFixes,
          );
          if (collectedToolResults.isNotEmpty) {
            currentTurnPrompt =
                '$currentTurnPrompt\n\nMESURES D’OUTILS DÉJÀ COLLECTÉES (n’appelle plus d’outils) :\n'
                '${jsonEncode(collectedToolResults)}';
          }
          if (collectedToolAttachments.isNotEmpty) {
            attemptAttachments = [
              ...attemptAttachments,
              ...collectedToolAttachments,
            ];
          }
          debugPrint(
            '[Vibe IA] Tentative ${attempt + 1} rejetée ($cause). '
            'Checkpoint partiel conservé (composants: '
            '${session.checkpointAppearance.components.length}, '
            'styles: ${session.checkpointAppearance.styles.length}, '
            'rejets isolés: ${salvage.rejectedEntries.length}). '
            'Relance en mode delta incrémental...',
          );
          continue;
        }

        // Aucun nouveau progrès récupérable sur cette tentative :
        if (session.repoCheckpoint != null) {
          try {
            await session.repoTransaction?.restoreSavepoint(
              session.repoCheckpoint!,
            );
          } catch (_) {}
        } else {
          try {
            await session.repoTransaction?.rollback();
          } catch (_) {}
        }

        if (session.hasCheckpoint && lastCheckpointSalvage != null) {
          _restoreCheckpointPreview(session);
          final resolvedStore = session.repoTransaction?.store;
          final refreshedReposContext = resolvedStore == null
              ? null
              : await VibeRepositoryPromptFormatter.formatStoreContext(
                  resolvedStore,
                );
          final buildPrompt = promptBuilder ?? _buildTurnPrompt;
          final refreshedTurnPrompt = buildPrompt(
            appearanceOverride: session.checkpointAppearance,
            instantiatedIdsOverride: session.initialInstantiatedIds,
            repositoriesContext: refreshedReposContext,
          );
          currentTurnPrompt = VibeDeltaRecovery.buildDeltaRetryPrompt(
            refreshedTurnPrompt: refreshedTurnPrompt,
            priorCauses: priorCauses,
            salvage: lastCheckpointSalvage,
            pendingRequiredComponentIds: session.pendingComponentFixes,
          );
          if (collectedToolResults.isNotEmpty) {
            currentTurnPrompt =
                '$currentTurnPrompt\n\nMESURES D’OUTILS DÉJÀ COLLECTÉES (n’appelle plus d’outils) :\n'
                '${jsonEncode(collectedToolResults)}';
          }
          if (collectedToolAttachments.isNotEmpty) {
            attemptAttachments = [
              ...attemptAttachments,
              ...collectedToolAttachments,
            ];
          }
          debugPrint(
            '[Vibe IA] Tentative ${attempt + 1} rejetée ($cause). '
            'Maintien du checkpoint précédent et relance en mode delta...',
          );
          continue;
        }

        await _rollbackTurnSession(session);
        debugPrint(
          '[Vibe IA] Tentative ${attempt + 1} rejetée ($cause). '
          'Relance avec prompt de correction...',
        );
        if (collectedToolAttachments.isNotEmpty) {
          attemptAttachments = [
            ...attemptAttachments,
            ...collectedToolAttachments,
          ];
        }
        final toolResultsSection = collectedToolResults.isEmpty
            ? ''
            : '\nMESURES D’OUTILS DÉJÀ COLLECTÉES (n’appelle plus d’outils) :\n'
                  '${jsonEncode(collectedToolResults)}\n';
        final causesSummary = priorCauses.length == 1
            ? cause
            : priorCauses.join('\n- ');
        currentTurnPrompt =
            '''
$turnPrompt

CORRECTION REQUISE :
La réponse précédente a été refusée.
Cause de l'erreur (${error.runtimeType}) :
${priorCauses.length == 1 ? causesSummary : '- $causesSummary'}
$toolResultsSection
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
      ..remove('plan')
      ..remove('toolCalls')
      ..remove('verifyRender')
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

    final rawStyles = payload['styles'];
    final patchedStyleIds = rawStyles is Map
        ? rawStyles.keys.whereType<String>().toSet()
        : null;
    final layoutStyleViolations =
        AppearanceTransfer.findIneffectiveLayoutStyleViolations(
          next,
          previous: current,
          patchedStyleIds: patchedStyleIds,
        );
    if (layoutStyleViolations.isNotEmpty) {
      debugPrint(
        '[Vibe IA] Styles inopérants détectés sur des Layout : '
        '${layoutStyleViolations.keys.toList()}.',
      );
      throw FormatException(layoutStyleViolations.values.join(' '));
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
        forceFollowUpQuestions: _isForceFollowUpQuestions,
      ),
      conversation: _buildConversationHistory(),
      appearance: appearanceOverride ?? _currentAppearance,
      codec: widget.codec,
      scope: _scope,
      instantiatedComponentIds:
          instantiatedIdsOverride ?? widget.registry?.instantiatedComponentIds,
      mountedSlotSummaries: VibeMountedSlotIndex.instance
          .mountedSlotSummaries(),
      repositoriesContext: repositoriesContext,
      reproduceExactMode: _reproduceExactMode,
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
        VibeQuestioningLevel.exhaustive => Icons.checklist_rtl,
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

  Object? _decodeResponseJson(String json) {
    try {
      return jsonDecode(json);
    } on FormatException catch (originalError) {
      final repaired = _tryCloseTrailingJsonDelimiters(json);
      if (repaired == null) rethrow;
      try {
        final decoded = jsonDecode(repaired.json);
        if (decoded is Map<String, dynamic> &&
            (decoded.containsKey('vibe') ||
                decoded.containsKey('message') ||
                decoded.containsKey('askUser') ||
                decoded.containsKey('plan') ||
                decoded.containsKey('toolCalls') ||
                decoded.containsKey('repositories'))) {
          debugPrint(
            '[Vibe IA] JSON réparé automatiquement '
            '(${repaired.closing.length} délimiteur(s) fermant(s) manquant(s) '
            'en fin de réponse : "${repaired.closing}").',
          );
          return decoded;
        }
      } on FormatException {
        // La réparation n'a pas produit un JSON valide : relance l'erreur initiale.
      }
      Error.throwWithStackTrace(originalError, StackTrace.current);
    }
  }

  static ({String json, String closing})? _tryCloseTrailingJsonDelimiters(
    String json,
  ) {
    final stack = <int>[];
    var inString = false;
    var escaped = false;
    int? lastNonWhitespace;

    for (var i = 0; i < json.length; i++) {
      final unit = json.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5C) {
          escaped = true;
        } else if (unit == 0x22) {
          inString = false;
          lastNonWhitespace = unit;
        }
        continue;
      }
      if (unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D) {
        continue;
      }
      lastNonWhitespace = unit;
      if (unit == 0x22) {
        inString = true;
      } else if (unit == 0x7B || unit == 0x5B) {
        stack.add(unit);
      } else if (unit == 0x7D) {
        if (stack.isEmpty || stack.last != 0x7B) return null;
        stack.removeLast();
      } else if (unit == 0x5D) {
        if (stack.isEmpty || stack.last != 0x5B) return null;
        stack.removeLast();
      }
    }

    if (inString ||
        escaped ||
        stack.isEmpty ||
        stack.length > 4 ||
        stack.first != 0x7B ||
        lastNonWhitespace == null) {
      return null;
    }

    // N'autorise la fermeture automatique que si le dernier jeton hors espaces
    // termine une valeur JSON complète ('}', ']', '"', chiffre, 'e' de true/false, 'l' de null).
    final validValueEnd =
        lastNonWhitespace == 0x7D ||
        lastNonWhitespace == 0x5D ||
        lastNonWhitespace == 0x22 ||
        (lastNonWhitespace >= 0x30 && lastNonWhitespace <= 0x39) ||
        lastNonWhitespace == 0x65 ||
        lastNonWhitespace == 0x6C;
    if (!validValueEnd) return null;

    final closingBuffer = StringBuffer();
    for (var i = stack.length - 1; i >= 0; i--) {
      closingBuffer.writeCharCode(stack[i] == 0x7B ? 0x7D : 0x5D);
    }
    final closing = closingBuffer.toString();
    return (json: '$json$closing', closing: closing);
  }

  void _appendMessage(
    String text, {
    String? failedResponse,
    VibeAskUserRequest? askUser,
    VibeExecutionPlan? plan,
    String? planSourcePrompt,
    List<VibeChatAttachment> planSourceAttachments = const [],
    List<VibeToolTrace> toolTraces = const [],
  }) {
    if (!mounted) return;
    setState(
      () => _messages.add(
        VibeChatMessage(
          text: text,
          isUser: false,
          failedResponse: failedResponse,
          askUser: askUser,
          plan: plan,
          planSourcePrompt: planSourcePrompt,
          planSourceAttachments: planSourceAttachments,
          toolTraces: toolTraces,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final completionEvent = _localCompletionEvent;
    final headerBadgePalette = completionEvent == null
        ? null
        : VibeTaskOutcomePalette.resolve(context, completionEvent.outcome);
    return AnimatedBuilder(
      animation: _completionGlowController,
      builder: (context, child) => VibeTaskCompletionGlow(
        progress: _completionGlowController.isAnimating
            ? _completionGlowController.value
            : 1.0,
        outcome: completionEvent?.outcome,
        child: child!,
      ),
      child: Material(
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
                    if (completionEvent != null && headerBadgePalette != null) ...[
                      Container(
                        key: const ValueKey('vibe-chat-header-completion-badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: headerBadgePalette.background,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: headerBadgePalette.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              headerBadgePalette.icon,
                              size: 13,
                              color: headerBadgePalette.accent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              headerBadgePalette.shortLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: headerBadgePalette.foreground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    IconButton(
                      key: const ValueKey('vibe-chat-sound-toggle'),
                      tooltip: _soundEnabled
                          ? 'Désactiver l’alerte sonore'
                          : 'Activer l’alerte sonore',
                      visualDensity: VisualDensity.compact,
                      onPressed: _toggleSoundAlert,
                      icon: Icon(
                        _soundEnabled
                            ? Icons.volume_up_outlined
                            : Icons.volume_off_outlined,
                        color: scheme.onPrimary,
                        size: 18,
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
            if (completionEvent != null)
              VibeTaskCompletionBanner(
                event: completionEvent,
                onDismiss: _clearCompletionAlert,
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
                                        enabled: !_isBusy,
                                        onSelected: () => _setSpeedMode(mode),
                                      ),
                                    ],
                                    const SizedBox(width: 6),
                                    VibeReproduceExactChip(
                                      selected: _reproduceExactMode,
                                      enabled: !_isBusy,
                                      onToggle: () => _setReproduceExactMode(
                                        !_reproduceExactMode,
                                      ),
                                    ),
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
                                      max:
                                          (VibeQuestioningLevel.values.length -
                                                  1)
                                              .toDouble(),
                                      divisions:
                                          VibeQuestioningLevel.values.length -
                                          1,
                                      label: _questioningLevel.label,
                                      onChanged: _isBusy || _reproduceExactMode
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
                                  message: _reproduceExactMode
                                      ? 'Désactivé en mode « Reproduire à l’identique »'
                                      : _questioningLevel.tooltip,
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
                            child: _reproduceExactMode
                                ? Container(
                                    key: const ValueKey(
                                      'vibe-chat-exact-design-notice',
                                    ),
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.tertiaryContainer
                                          .withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.straighten_outlined,
                                          size: 15,
                                          color: scheme.onTertiaryContainer,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Style fidèle à la source (Design System ignoré) • Plan & lots auto',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: scheme.onTertiaryContainer,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : VibeDesignSystemBar(
                                    selectedPreset: _selectedDesignSystem,
                                    sending: _isBusy,
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
                                    onPressed: _isBusy ? null : _clearScope,
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
                            sending: _isBusy,
                            isActivePlan: _activePlanMessageIndex == i,
                            speechTranscriber: widget.speechTranscriber,
                            onSpeechError: (message) {
                              if (mounted) {
                                setState(() => _attachmentError = message);
                              }
                            },
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
                            onAskMoreAskUser: _reproduceExactMode
                                ? null
                                : (answers) => _submitAskMoreFromCard(i, answers),
                            onRequestMoreQuestions:
                                _canShowMessageMoreQuestions(i)
                                ? _requestMoreQuestionsFromChat
                                : null,
                            onStartPlan: () => _startPlanExecution(i),
                            onCancelPlan: () => _cancelPlan(i),
                            onStopPlan: () => _stopPlan(i),
                            onRetryPlanLot: () => _retryPlanLot(i),
                            onSkipPlanLot: () => _skipPlanLot(i),
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
                          onRemove: _isBusy
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
                  onPressed: _isBusy ? null : _attachFromPicker,
                  icon: const Icon(Icons.attach_file),
                ),
                IconButton(
                  key: const ValueKey('vibe-chat-paste-attachment'),
                  tooltip: 'Coller une image, un fichier ou du texte du presse-papiers',
                  visualDensity: VisualDensity.compact,
                  onPressed: _isBusy ? null : _attachFromClipboard,
                  icon: const Icon(Icons.content_paste),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleInputKeyEvent,
                    skipTraversal: true,
                    child: TextField(
                      key: const ValueKey('vibe-chat-input'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _speechState == VibeSpeechState.listening
                            ? 'Écoute en cours… (parlez puis faites une pause)'
                            : _speechState == VibeSpeechState.transcribing
                            ? 'Transcription en cours…'
                            : _reproduceExactMode
                            ? 'Décris ou joins un .md / capture à reproduire à l’identique…'
                            : 'Décris l’écran souhaité…',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('vibe-chat-mic'),
                  isSelected: _speechSession != null,
                  tooltip: _speechState == VibeSpeechState.listening
                      ? 'Arrêter la dictée (arrêt auto après silence)'
                      : _speechState == VibeSpeechState.transcribing
                      ? 'Transcription vocale en cours…'
                      : 'Dicter au microphone',
                  visualDensity: VisualDensity.compact,
                  style: _speechState == VibeSpeechState.listening
                      ? IconButton.styleFrom(
                          backgroundColor: scheme.errorContainer,
                          foregroundColor: scheme.onErrorContainer,
                        )
                      : null,
                  onPressed:
                      _isBusy || _speechState == VibeSpeechState.transcribing
                      ? null
                      : _toggleSpeechDictation,
                  icon: _speechState == VibeSpeechState.transcribing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _speechState == VibeSpeechState.listening
                              ? Icons.stop_circle_outlined
                              : Icons.mic_none_outlined,
                        ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const ValueKey('vibe-chat-ask-more'),
                  tooltip: _reproduceExactMode
                      ? 'Questions désactivées en mode « Reproduire à l’identique »'
                      : '+ de questions (poser 2 à 4 questions ciblées avant de générer)',
                  visualDensity: VisualDensity.compact,
                  onPressed: _isBusy || _reproduceExactMode
                      ? null
                      : _requestMoreQuestionsFromChat,
                  icon: const Icon(Icons.add_comment_outlined),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  key: const ValueKey('vibe-chat-send'),
                  tooltip: _reproduceExactMode
                      ? 'Analyser et préparer le plan par lots'
                      : 'Générer et appliquer',
                  onPressed: _isBusy ? null : _send,
                  icon: _isBusy
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
  }) : checkpointAppearance = baseAppearance,
       lastPreviewAppearance = baseAppearance;

  final Appearance rawInitialAppearance;
  final Appearance baseAppearance;
  final Set<String>? initialInstantiatedIds;
  final EditorPageRouter? pageRouting;
  final String? initialRouteLocation;
  final Set<String> initialPageIds;
  final VibeRepositoryTurnTransaction? repoTransaction;

  Appearance checkpointAppearance;
  bool hasCheckpoint = false;
  bool requiresScreenAttachment = false;
  final Set<String> pendingComponentFixes = <String>{};
  VibeRepositorySavepoint? repoCheckpoint;

  Appearance lastPreviewAppearance;
  int lastAppliedPatchRevision = 0;
  int lastAppliedRepositoriesRevision = 0;
  Future<void> liveRepoQueue = Future<void>.value();
  bool livePreviewDisabled = false;
  bool hasAppliedLivePreview = false;
  String? liveNavigatedPageId;
  final List<VibeToolTrace> toolTraces = <VibeToolTrace>[];
  final VibeDebugMarker turnStartMarker = VibeDebugCapture.markNow();
  final VibePreviewStateTracker previewTracker = VibePreviewStateTracker();
}

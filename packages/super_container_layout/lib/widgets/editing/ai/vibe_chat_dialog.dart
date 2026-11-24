/// Interface de chat IA (« Vibe ») pour la génération et la modification incrémentale d'écrans ([VibeChatDialog]).
///
/// Met en cache les guides `SCREEN_JSON_AI_GUIDE.md`, `REPOSITORY_JSON_AI_GUIDE.md`,
/// `BEHAVIOR_JSON_AI_GUIDE.md`, `SCREEN_DESIGN_AI_GUIDE.md` et le référentiel `DESIGN.md`
/// actif ([DesignSystemPreset], [VibeChatDialog.warmUp]), assemble un instantané JSON compact (global ou ciblé sur un
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
import '../../../models/a4_page_config.dart';
import '../../../models/component_usage.dart';
import '../../../models/native_component_config.dart';
import '../../../models/registry.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../models/super_action_config.dart';
import '../../../models/super_conditional_config.dart';
import '../../../models/super_indicator_config.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_list_view_config.dart';
import '../../../models/super_separator_config.dart';
import '../../../models/super_tab_config.dart';
import '../../../models/super_table_config.dart';
import '../../../models/super_tree_view_config.dart';
import '../../../models/super_value_config.dart';
import '../../../services/appearance/appearance_codec.dart';
import '../../../services/appearance/appearance_store.dart';
import '../../../services/appearance/appearance_transfer.dart';
import '../../../services/appearance/custom_design_system_store.dart';
import '../../../services/diagnostics/debug_entry.dart';
import '../../../services/inspection/vibe_app_inspector.dart';
import '../../../services/inspection/vibe_debug_capture.dart';
import '../../../services/inspection/vibe_diagnostics_inspector.dart';
import '../../../services/inspection/vibe_mounted_slot_index.dart';
import '../../../services/inspection/vibe_page_audit.dart';
import '../../../services/pages/editor_page_graph.dart';
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
import 'vibe_incremental_preview.dart';
import 'vibe_live_page_router.dart';
import 'vibe_prompt_builder.dart';
import 'vibe_repository_applier.dart';
import 'vibe_scope_helpers.dart';
import 'vibe_task_completion_alert.dart';
import 'vibe_work_highlight.dart';
import '../../appearance/appearance_scope.dart';
import '../../appearance/dynamic_font_scope.dart';

export '../../../ai/call_gemini.dart'
    show
        GeminiStreamEvent,
        VibeAiSpeedMode,
        VibeCancellationToken,
        VibeCancelledException;
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
    show
        VibeExecutionPlan,
        VibeLotStatus,
        VibePlanLot,
        VibePlanStatus,
        VibeTimedTrace,
        formatVibeDuration;
export '../../../ai/vibe_speech_to_text.dart';
export '../../../ai/vibe_stream_parser.dart'
    show VibePatchEntryDelta, VibeStreamSnapshot;
export '../../../services/appearance/custom_design_system_store.dart'
    show CustomDesignSystemStore;
export 'design_system_catalog_dialog.dart';
export 'design_system_preview_card.dart';
export 'vibe_ask_user_card.dart' show VibeAskUserCard;
export 'vibe_chat_message.dart' show VibeChatMessage, VibeRetryTurnPayload;
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
    this.onSpeedModeChanged,
    this.initialQuestioningLevel = VibeQuestioningLevel.balanced,
    this.onQuestioningLevelChanged,
    this.initialPlanMode = false,
    this.onPlanModeChanged,
    this.initialReproduceExactMode = false,
    this.onReproduceExactModeChanged,
    this.initialVisibleOnlyMode = false,
    this.onVisibleOnlyModeChanged,
    this.initialVerifyRenderEnabled = true,
    this.onVerifyRenderEnabledChanged,
    this.initialReactiveValuesEnabled,
    this.onReactiveValuesEnabledChanged,
    this.smartVerifyLocalGate,
    this.throttleStreamingPreviewLogs,
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
    this.customDesignSystemStore,
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

  /// Nombre maximal de lots indépendants (`dependsOn`) exécutés simultanément dans une vague.
  static const int maxParallelPlanLots = 3;

  /// Intervalle minimal entre deux reconstructions d'aperçu en direct pendant un flux SSE.
  static const Duration livePreviewMinInterval = Duration(milliseconds: 250);

  /// Instructions système invariantes transmises au modèle GenUI pour le chat Vibe IA.
  static const String defaultSystemInstruction = '''
Tu es l’assistant de création d’écrans de super_container_layout. Réponds en français.
Utilise exclusivement le guide de modélisation JSON, le guide de Design System et l’état actuel de l’application fournis.
Applique systématiquement les règles du Design System (surfaces sémantiques theme:*, hiérarchie typographique, grille d'espacement 4/8px, ergonomie Desktop productive, discipline des boutons d'action et micro-interactions) sauf consigne esthétique explicite contraire de l'utilisateur ; si des règles de design spécifiques à l'application sont fournies, elles prévalent sur le Design System générique.
Renvoie uniquement un objet JSON en plaçant impérativement la clé "message" EN PREMIER (avant "askUser" et "vibe") pour permettre l'affichage instantané en streaming, selon l'un des 3 modes suivants :
1. Création ou modification directe de l'écran : renvoie {"message":"résumé bref en français","vibe":{...}}. Le champ "vibe" doit contenir un patch JSON plat (modèle GenUI : "components", "styles", "behaviors", "usages", "pageCatalog") accepté par AppearanceTransfer.applyVibe.
2. Question pure ou demande d'information sans modification de l'écran : renvoie {"message":"réponse claire en français","vibe":null} (ou omets le champ "vibe") sans modifier l'écran.
3. Clarification interactive ("askUser") selon le NIVEAU DE QUESTIONNEMENT indiqué dans le contexte du tour : renvoie {"message":"courte introduction en français","askUser":{"questions":[{"id":"...","title":"...","type":"single|multi|boolean|text","options":["..."],"default":...}]},"vibe":null}.
4. Planification en lots (mode « Plan ») : renvoie {"message":"présentation du plan en français","plan":{"title":"...","lots":[{"id":"lot-1","title":"...","description":"..."}]},"vibe":null}.
5. Interrogation et sélection dans l'application en cours d'exécution (si des mesures, diagnostics ou pointages visuels sont utiles) : tu peux appeler les outils (`get_viewport_and_route`, `get_component_geometry`, `get_runtime_tree`, `query_repository_data`, `manage_repository_json_schema`, `capture_element_screenshot`, `capture_screenshot`, `get_debug_entries`, `get_datasources_and_providers`, `inspect_bindings_and_diagnostics`, `get_theme_and_contrast`, `get_registry_and_selection`, `preview_navigation_or_selection`, `select_editor_element`, `register_design_system`, `validate_or_list_icons`) soit via le Function Calling natif (à privilégier), soit en renvoyant {"message":"inspection en cours","toolCalls":[{"id":"...","name":"...","arguments":{...}}],"vibe":null}. Pour les icônes ("icon" sur SuperAction, SuperIndicator, SuperChoice, onglets SuperTab, etc.), choisis directement un identifiant dans le catalogue `MaterialIconCatalog` fourni dans le guide sans appeler d'outil ; n'appelle `validate_or_list_icons` qu'en cas de recherche par mot-clé ou de doute sur un identifiant hors liste. Utilise `manage_repository_json_schema` pour lire, inférer, valider, créer, modifier ou dissocier le JSON Schema d'un repository existant. Utilise `register_design_system` dès que l'utilisateur demande de générer, extraire ou ajouter un `DESIGN.md` / Design System dans la liste des choix possibles (notamment à partir des pièces jointes du chat), en essayant systématiquement de récupérer ou reconstruire le logo de la marque (URL exacte ou Data URI issue des pièces jointes, `<svg>` joint ou extrait, ou `<svg>` vectoriel simple fidèle au logo visible sans inventer d'URL) dans le champ `logo` et dans le document `DESIGN.md`. Préfère systématiquement `capture_element_screenshot` à `capture_screenshot` pour capturer un composant, une carte, une zone ou une ligne isolée sans toute la page, et utilise `select_editor_element` pour sélectionner/montrer un élément sur le canevas en mode édition. Appelle `get_debug_entries` et `inspect_bindings_and_diagnostics` en cas d'erreur Flutter/RenderFlex, de message d'erreur de repository/validation, de conflit schéma/masque/données ou de données vides, et `get_datasources_and_providers` avant de câbler une recherche/CRUD (regroupe toujours plusieurs outils d'un même diagnostic en un seul appel parallèle) ; si `get_debug_entries` ou `inspect_bindings_and_diagnostics` révèle des données existantes incompatibles avec le JSON Schema ou un conflit de masque/date, propose le correctif exact et demande confirmation via `"askUser"` avant d'écraser les données ou le schéma. Pour une modification déclarative simple dont le JSON courant et le catalogue d'icônes du guide suffisent, réponds directement sans outil. Tu peux ajouter "verifyRender": true avec "vibe" sur le dernier lot ou lorsqu'une inspection après aperçu est indispensable.
Formatage compact & ordre d'émission obligatoire dans "vibe" pour le streaming live :
- Formate systématiquement ta réponse JSON de manière compacte sur une seule ligne (sans indentation multi-espaces ni retours à la ligne hors chaînes) afin de maximiser la vitesse de génération.
- Le moteur déduit automatiquement `usages[<id>]` pour les conteneurs (`layout`), boutons (`action`), saisies (`userInput`), indicateurs/séparateurs (`decoration`) et étiquettes simples (`explanation`) : n'émets dans `"usages"` que les rôles métier spécifiques non déductibles (`"dynamicData"`, `"staticData"`, `"feedback"`, ou une `"translationKey"` sur mesure).
- Ordonne les clés de "vibe" dans cet ordre : d'abord "pageCatalog" et les réglages globaux de thème s'ils changent, puis "styles", puis "components", puis "behaviors" et éventuellement "usages".
- Dans "components", émets toujours les conteneurs de haut en bas (Top-Down) : d'abord la page ou le conteneur racine avec ses "placements", "slotTypes" et "slotLabels", puis chaque sous-conteneur/zone dans l'ordre visuel de lecture, et enfin les composants feuilles placés dans chaque zone, afin que l'utilisateur voie la structure et les zones se construire en direct.
Règles pour "repositories" (création et mise à jour des repositories JSON) :
- Lorsqu'une section REPOSITORIES DISPONIBLES (JSON) est fournie dans le contexte du tour, tu peux créer de nouveaux repositories ou mettre à jour/peupler des repositories existants via la clé optionnelle "repositories" placée après "message" et avant "vibe" : {"message":"...","repositories":{"<idOuAlias>":{"name":"...","mode":"merge","data":{...},"jsonSchema":{...}}},"vibe":{...}} (ou "vibe": null si la demande ne modifie que les données des repositories sans changer l'écran). Si aucune section REPOSITORIES DISPONIBLES (JSON) n'est présente dans le contexte, n'émets pas la clé "repositories".
- Respecte impérativement l'ordre d'émission live : "message" -> "repositories" -> "vibe", afin que les repositories soient créés et peuplés avant l'instanciation des composants liés.
- Règle d'or anti-collision de clé racine : "vibe" est STRICTEMENT une clé racine de premier niveau (frère de "message" et "repositories"), JAMAIS imbriquée dans "repositories". Il est formellement interdit d'émettre une clé nommée "vibe", "components", "styles", "behaviors", "usages", "pageCatalog" ou "responsiveLayout" à l'intérieur de "repositories".
- Réutilisation prioritaire des IDs de repository existants : lorsqu'un repository métier est déjà listé dans REPOSITORIES DISPONIBLES, réutilise SYSTÉMATIQUEMENT son "id" technique exact (ex. ID 32 hex ou ID applicatif) dans "repositories" ET dans tous les bindings "<id>:chemin" de "vibe", plutôt que d'inventer un nouvel alias. Ne crée un alias snake_case (^[a-z0-9_]{1,32}\$, sans inventer d'ID de 32 caractères hexadécimaux) que pour un repository réellement nouveau déclaré dans "repositories" du même tour.
- Chemins de liaison dans une liste/table/onglet dynamique (mode « hérité de la liste englobante ») : écris TOUJOURS le chemin complet depuis la racine du repository avec joker(s) [?] (ex: "deals[?].title", "clients[?].nom", "clients[?].commandes[?].ref"), même si repositoryId est omis ; n'écris JAMAIS un nom de champ nu comme "title" ou "nom" (sauf dans un SuperTreeView), sinon il est lu à la racine du document et affiche vide.
- Héritage strictement descendant (Pattern Maître / Détail) : l'héritage de repositoryId ne se propage JAMAIS horizontalement vers une branche sœur (ex: du panneau west vers la fiche détaillée en center). Tout composant hors de la liste source (SuperValue, KPI, sous-liste, Chart) DOIT déclarer explicitement son préfixe "<repoId>:..." ou "<alias>:..." (ou {"repositoryId":"...","path":"..."}) afin que le runtime synchronise sa sélection [?].
- Dans chaque entrée de "repositories", "data" doit être un objet JSON {...} à la racine, et aucune clé JSON stockée ne doit jamais débuter par "@" (préfixe strictement réservé aux attributs calculés en lecture seule) ni contenir ".", "[", "]", "?" ou espace.
- JSON Schema associé ("jsonSchema") — création systématique et évolution cohérente :
  - À CHAQUE création d'un nouveau repository dans "repositories.<alias>", génère SYSTÉMATIQUEMENT une clé "jsonSchema" (objet JSON Schema Draft 7 / Draft 2020-12) cohérente avec "data", afin que les champs liés (`SuperValue` avec `useRepositorySchema: true`) héritent automatiquement des types, formats, masques et validations.
  - Lorsqu'un repository existant de REPOSITORIES DISPONIBLES expose déjà un "jsonSchema", respecte strictement ce schéma dans toutes les données produites ou fusionnées (toute violation bloque l'écriture) ; si tu ajoutes de nouveaux champs ou tableaux à ce repository (hors schéma figé en code), mets à jour "jsonSchema" dans la même entrée de "repositories" pour les déclarer. Tu peux aussi passer "jsonSchema": null uniquement sur demande explicite de dissociation.
  - Profil de schéma riche et compatible saisie (exploite TOUTES les capacités `SuperValue` héritées via `useRepositorySchema: true` sans les dupliquer dans `components.<id>.field`) : déclare l'arborescence complète (`type`, `properties`, `items`, `required`), les longueurs et motifs (`minLength`, `maxLength`, `pattern`), les `enum`/`const` alignés sur les `SuperValue.choice` et `states.named`, les `format` standard (`date`, `date-time`, `time`, `email`, `uri`, `uuid`, `phone`, `ipv4`, `ipv6`, `hostname`), les bornes et pas numériques (`minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`, `multipleOf`), ainsi que les extensions UI `SuperValue` dès qu'elles s'appliquent : formatage numérique FR (`x-decimalDigits`, `x-decimalSeparator`: `","`, `x-thousandsSeparator`: `" "` pour montants/taux/grands nombres), masques (`x-mask` avec jetons `#`/`A`/`U`/`L`/`*` + `x-maskIncludeLiterals` cohérent avec `"data"` et `pattern`, ex. téléphone `"## ## ## ## ##"`, code postal `"#####"`, SIRET `"### ### ### #####"`, référence `"UUU-####"`), et `x-validationMessage` en français. N'inclus JAMAIS les attributs calculés `@...` dans "jsonSchema", n'ajoute PAS `"additionalProperties": false` par défaut (sauf demande explicite de verrouillage strict), et veille à la compatibilité avec l'ajout de nouvelles lignes (`allowAdd: true`) en fournissant `"default"` sur les champs requis contraints ou en utilisant un type nullable `["string", "null"]` pour les champs optionnels formatés (ex. email, téléphone, URI).
- Convention stricte pour les dates dans "jsonSchema" et "data" : stocke TOUJOURS les dates au format ISO 8601 (`"YYYY-MM-DD"` pour `"format": "date"`, `"YYYY-MM-DDTHH:MM:SSZ"` pour `"format": "date-time"`) dans `"repositories.*.data"` ; n'ajoute NI `"x-mask"` manuel redondant NI `"pattern"` au format `"dd/MM/yyyy"` sur un champ `"format": "date"` (le moteur déduit automatiquement le masque d'affichage/saisie `##/##/####` + `dd/MM/yyyy` et reconvertit vers ISO à l'écriture).
Règles pour "askUser" :
- Quelle que soit l'étape (création initiale, ajout, modification d'un écran existant ou d'un scope ciblé), applique systématiquement le NIVEAU DE QUESTIONNEMENT défini par le slider dans le contexte du tour courant, sans restreindre les questions à la première étape (seul le niveau 0/Aucun ou le tour d'application immédiate des réponses qui viennent d'être fournies désactive "askUser").
- Fournis toujours des valeurs "default" pertinentes sur chaque question posée.
Priorité absolue — Respect strict de la règle d'atomicité lors de chaque génération de layout, fiche ou formulaire :
- Ne concatène jamais un libellé et une donnée dans le "text" d'un même SuperValue (ex: jamais "Statut : En cours"), ni plusieurs attributs métier dans un seul composant.
- En mode visualisation ("mode": "display"), un SuperValue possède nativement "label" et une valeur ("text" ou "binding") : préfère systématiquement 1 seul SuperValue avec "label" + "text" (usage "dynamicData") ou "binding" plutôt que 2 SuperValue séparés, SAUF si le label requiert un style ou une disposition fortement personnalisés (auquel cas décompose en 1 SuperValue étiquette fixe avec usage "explanation" + "translationKey", et 1 SuperValue distinct pour la valeur avec usage "dynamicData" ou "binding").
- Évite tout placeholder de texte libre multiligne (textarea / maxLines > 1) pour représenter des listes ou récapitulatifs métier (affaires, contrats, interlocuteurs, etc., même si la demande mentionne « résumé », « récapitulatif » ou « notes ») : utilise systématiquement des cartes, des champs unitaires SuperValue atomiques, une SuperListView ou un tableau SuperTable.
Par défaut, ne mets pas de padding (ni paddingInsets) sur styles["background"] (laisse padding à 0 par défaut, sauf demande explicite) : avec les composants Flutter (Scaffold, ApplicationBar, NavigationRail, BottomAppBar, SuperLayout), ce n'est pas nécessaire ; règle l'espacement éventuel dans les zones des layouts (zoneFlows) ou les cartes.
Lorsque "allowRemove": true sur une SuperListView, le bouton supprimer natif flotte en haut à droite (top: 0, right: 0) de chaque ligne : configure systématiquement styles["<listId>:item"].paddingInsets avec right >= 38 (ex. [12, 38, 12, 12]) pour éviter tout chevauchement avec le contenu.
Pour les SuperAction placées dans placements.tabs d'un SuperTab (onglets), ne définis JAMAIS de style de fond ni de bordure spécifique (pas de backgroundColor, borderColor, borderWidth, elevation, style, styles["<tabSlotId>"], ni de variant plein/encadré — omets variant) ; l'habillage de la barre et de l'onglet actif se règle uniquement sur le SuperTab (tabBarStyle, indicator*, labelColor, unselectedLabelColor).
Ne mets JAMAIS d'entrée dans "styles" pour un composant placé en "registry:Layout" (ni pour "mainLayout") : SuperLayout est purement structurel et n'a pas de surface (styles[id] est sans effet). Pour styliser un conteneur de zones (couleur, bordure, arrondi, paddingInsets), passe son placement parent en "registry:IterableContent" (en gardant components[id] en "type": "layout") ou enveloppe-le dans une "registry:Card".
Réutilise les identifiants des conteneurs de l'état actuel, y compris ceux dont la configuration est encore celle par défaut. Les identifiants du guide (comme "contA") sont des exemples, pas des racines d'écran implicites.
Contrôle d'exhaustivité des placements descendants : tout composant déclaré dans "components" (conteneurs, rangées de KPIs, graphiques, onglets, champs feuilles) doit OBLIGATOIREMENT être référencé dans les "placements" d'un conteneur parent monté (chaîne continue jusqu'à "root"/"mainLayout" ou une page de "pageCatalog"), sinon il reste un composant fantôme invisible. Créer un layout ou composant isolé ne l'affiche pas.
La route "/" existe déjà côté hôte (page racine "root" / "mainLayout") : ne déclare JAMAIS une page avec "path": "/" dans "pageCatalog" (configure directement "root" / "mainLayout" pour "/", ou utilise un chemin distinct comme "/accueil" avec éventuellement "homePageId"). Tout chemin de "pageCatalog" doit commencer par un seul "/", être différent de "/", ne pas se terminer par "/", et ne contenir ni espace, ni "?", ni "#".
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

  static const List<String> _behaviorGuideAssets = [
    'BEHAVIOR_JSON_AI_GUIDE.md',
    'packages/super_container_layout/BEHAVIOR_JSON_AI_GUIDE.md',
  ];

  static const List<String> _designGuideAssets = [
    'SCREEN_DESIGN_AI_GUIDE.md',
    'packages/super_container_layout/SCREEN_DESIGN_AI_GUIDE.md',
  ];

  static String? _cachedRootBundleGuide;
  static Future<String>? _inFlightRootBundleGuide;
  static String? _cachedRootBundleRepositoryGuide;
  static Future<String?>? _inFlightRootBundleRepositoryGuide;
  static String? _cachedRootBundleBehaviorGuide;
  static Future<String?>? _inFlightRootBundleBehaviorGuide;
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

  /// Callback optionnel notifié lorsque l'utilisateur change le mode de vitesse.
  final ValueChanged<VibeAiSpeedMode>? onSpeedModeChanged;

  /// Niveau initial de questionnement préalable ([VibeQuestioningLevel.balanced] par défaut).
  final VibeQuestioningLevel initialQuestioningLevel;

  /// Callback optionnel notifié lorsque l'utilisateur ajuste le niveau de questionnement via le slider.
  final ValueChanged<VibeQuestioningLevel>? onQuestioningLevelChanged;

  /// Active par défaut le mode « Plan » (planification et exécution par lots validés).
  final bool initialPlanMode;

  /// Callback optionnel notifié lorsque le mode « Plan » change.
  final ValueChanged<bool>? onPlanModeChanged;

  /// Active par défaut le mode « Reproduire à l'identique » (pixel-perfect).
  final bool initialReproduceExactMode;

  /// Callback optionnel notifié lorsque le mode « Reproduire à l'identique » change.
  final ValueChanged<bool>? onReproduceExactModeChanged;

  /// Active par défaut le mode « Uniquement visible » (verrouillant l'onglet actif et le scroll courant).
  final bool initialVisibleOnlyMode;

  /// Callback optionnel notifié lorsque le mode « Uniquement visible » change.
  final ValueChanged<bool>? onVisibleOnlyModeChanged;

  /// Autorise par défaut la passe de vérification post-rendu (`verifyRender: true`) demandée par l'IA.
  final bool initialVerifyRenderEnabled;

  /// Callback optionnel notifié lorsque l'activation de `verifyRender` change.
  final ValueChanged<bool>? onVerifyRenderEnabledChanged;

  /// Active par défaut la phase finale « Valeurs réactives » en fin de génération
  /// (exécutée avant la vérification post-rendu).
  ///
  /// Vaut `true` par défaut hors `TestWidgetsFlutterBinding` afin de préserver les
  /// suites de tests existantes qui attendent un nombre fixe d'appels LLM.
  final bool? initialReactiveValuesEnabled;

  /// Callback optionnel notifié lorsque l'activation de la phase « Valeurs réactives » change.
  final ValueChanged<bool>? onReactiveValuesEnabledChanged;

  /// Court-circuite l'appel LLM `verifyRender` lorsque le pré-audit déterministe local
  /// (`VibePageAuditService` + diagnostics + erreurs runtime) ne détecte aucune anomalie.
  ///
  /// Vaut `true` par défaut hors `TestWidgetsFlutterBinding` (où la pompe de frame n'est pas automatique).
  final bool? smartVerifyLocalGate;

  /// Regroupe les logs console `[Vibe IA][Preview]` intermédiaires pendant le streaming
  /// (1er palier + paliers avec rejets + bilan final).
  ///
  /// Vaut `true` par défaut hors `TestWidgetsFlutterBinding` lorsque [verboseLogging] est `false`.
  final bool? throttleStreamingPreviewLogs;

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

  /// Magasin disque optionnel persistant les `DESIGN.md` personnalisés (`<store>/design_systems/*.md`).
  final CustomDesignSystemStore? customDesignSystemStore;

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
    String? behaviorGuide,
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
    final trimmedBehavior = behaviorGuide?.trim() ?? '';
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

    if (trimmedBehavior.isNotEmpty) {
      buffer
        ..write(
          '\n\n---\n\nGUIDE DES COMPORTEMENTS (BEHAVIORS, EVENTS, VALIDATORS & ACTIONS) :\n',
        )
        ..write(trimmedBehavior);
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
          '- Hiérarchie typographique ("fontSize", "fontWeight", "fontFamily") et style des actions ("SuperAction" avec contraste AA garanti). Les familles Google Fonts déclarées dans le DESIGN.md actif sont téléchargées et mises en cache dynamiquement par le moteur : utilise fidèlement leurs noms exacts.\n'
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

  static Future<String?> _loadBehaviorGuideFromBundle(
    AssetBundle bundle,
  ) async {
    final isRoot = identical(bundle, rootBundle);
    if (isRoot) {
      final cached = _cachedRootBundleBehaviorGuide;
      if (cached != null) return cached;
      final inFlight = _inFlightRootBundleBehaviorGuide;
      if (inFlight != null) return inFlight;
    }

    Future<String?> load() async {
      for (final asset in _behaviorGuideAssets) {
        try {
          final guide = await bundle.loadString(asset);
          if (guide.trim().isNotEmpty) {
            if (isRoot) {
              _cachedRootBundleBehaviorGuide = guide;
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
    _inFlightRootBundleBehaviorGuide = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightRootBundleBehaviorGuide, future)) {
        _inFlightRootBundleBehaviorGuide = null;
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
  /// `REPOSITORY_JSON_AI_GUIDE.md` éventuel + `BEHAVIOR_JSON_AI_GUIDE.md` éventuel +
  /// `SCREEN_DESIGN_AI_GUIDE.md` + [designSystemPreset] éventuel + [customDesignGuide]
  /// éventuel) depuis [bundle].
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
    final behaviorGuide = await _loadBehaviorGuideFromBundle(bundle);
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
      behaviorGuide: behaviorGuide,
      defaultDesignGuide: defaultDesignGuide,
      selectedDesignSystemMarkdown: selectedDesignSystemMarkdown,
      selectedDesignSystemName: designSystemPreset?.name,
      customDesignGuide: customDesignGuide,
      replaceDefaultDesignGuide: replaceDefaultDesignGuide,
    );
  }

  /// Précharge en mémoire les guides `SCREEN_JSON_AI_GUIDE.md`,
  /// `REPOSITORY_JSON_AI_GUIDE.md`, `BEHAVIOR_JSON_AI_GUIDE.md`, `SCREEN_DESIGN_AI_GUIDE.md`
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

  /// Callback enregistré par le panneau flottant actif pour ouvrir ou cibler le chat avec des options de session.
  static bool Function(
    VibeChatScope scope, {
    VibeAiSpeedMode? speedMode,
    VibeQuestioningLevel? questioningLevel,
  })?
  onOpenScopedRequested;

  /// Opens the Vibe AI chat targeted at [scope]: reuses the active
  /// `StyleEditBanner` panel when mounted, or falls back to an editor dialog.
  static Future<void> showScoped(
    BuildContext context,
    VibeChatScope scope, {
    VibeAiSpeedMode? speedMode,
    VibeQuestioningLevel? questioningLevel,
    String? customDesignGuide,
    bool? replaceDefaultDesignGuide,
  }) async {
    debugPrint(
      '[Vibe IA][Scope] Ouverture assistant composant : '
      '"${scope.displayLabel}" (ids=${scope.canonicalComponentIds.toList()}'
      '${scope.zoneId != null ? ', zone=${scope.zoneId}' : ''}).',
    );
    if (onOpenScopedRequested case final handler?
        when handler(
          scope,
          speedMode: speedMode,
          questioningLevel: questioningLevel,
        )) {
      return;
    }
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
                pageRouting: app?.pageRouting,
                validateAppearance: app?.pageRouting == null
                    ? null
                    : (value) => app!.pageRouting!.validate(value.pageCatalog),
                scope: scope,
                initialSpeedMode: speedMode ?? VibeAiSpeedMode.fast,
                initialQuestioningLevel:
                    questioningLevel ?? VibeQuestioningLevel.balanced,
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
  final List<_LiveTurnSession> _activeParallelSessions = <_LiveTurnSession>[];
  JsonRepositoryStore? _ambientRepositoryStore;
  bool _frameSnapshotScheduled = false;
  bool _disposed = false;
  bool _didWarmUpDependencies = false;
  bool _didLoadCustomDesignSystems = false;
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
  late bool _planMode = widget.initialPlanMode;
  late bool _reproduceExactMode = widget.initialReproduceExactMode;
  late bool _visibleOnlyMode = widget.initialVisibleOnlyMode;
  late bool _verifyRenderEnabled = widget.initialVerifyRenderEnabled;
  late bool _reactiveValuesEnabled =
      widget.initialReactiveValuesEnabled ?? !_isWidgetTestBinding;
  late VibeQuestioningLevel? _questioningLevelBeforeExactMode =
      widget.initialReproduceExactMode ? widget.initialQuestioningLevel : null;
  int? _activePlanMessageIndex;
  bool _executingPlan = false;
  bool _planStopRequested = false;
  EditorHistoryController? _openPlanHistory;
  final Map<(int, int), _LotPartialCheckpoint> _planLotCheckpoints =
      <(int, int), _LotPartialCheckpoint>{};
  final Map<int, Appearance> _planPreRunAppearances = <int, Appearance>{};
  final Map<int, List<VibeRepositoryHistoryCallbacks>> _planRepoCallbacks =
      <int, List<VibeRepositoryHistoryCallbacks>>{};
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

  CustomDesignSystemStore? _resolveCustomDesignSystemStore() {
    if (widget.customDesignSystemStore != null) {
      return widget.customDesignSystemStore;
    }
    final repoStore = _resolveRepositoryStore();
    if (repoStore != null) {
      return CustomDesignSystemStore.forRepositoryStore(repoStore);
    }
    if (_isWidgetTestBinding) return null;
    return CustomDesignSystemStore.tryDefaultStore();
  }

  Future<void> _loadPersistedCustomDesignSystemsIfNeeded() async {
    if (_didLoadCustomDesignSystems) return;
    _didLoadCustomDesignSystems = true;
    final store = _resolveCustomDesignSystemStore();
    if (store == null) return;
    try {
      final loaded = await store.loadAll();
      if (!mounted || loaded.isEmpty) return;

      final existingIds = <String>{
        for (final preset in _customDesignSystems) preset.id,
      };
      final additions = <DesignSystemPreset>[
        for (final preset in loaded)
          if (!existingIds.contains(preset.id)) preset,
      ];
      if (additions.isEmpty) return;

      setState(() {
        _customDesignSystems = List<DesignSystemPreset>.of([
          ..._customDesignSystems,
          ...additions,
        ]);
      });
      widget.onCustomDesignSystemsChanged?.call(
        List<DesignSystemPreset>.unmodifiable(_customDesignSystems),
      );
    } catch (error) {
      debugPrint(
        '[Vibe IA] Chargement des DESIGN.md personnalisés ignoré : $error',
      );
    }
  }

  Future<void> _persistCustomDesignPresets(
    Iterable<DesignSystemPreset> presets,
  ) async {
    final store = _resolveCustomDesignSystemStore();
    if (store == null) return;
    for (final preset in presets) {
      try {
        await store.save(preset);
      } catch (error) {
        debugPrint(
          '[Vibe IA] Sauvegarde du DESIGN.md "${preset.id}" ignorée : $error',
        );
      }
    }
  }

  Future<({String? persistedPath, int totalCustomPresets})>
  _registerDesignSystemFromTool(
    DesignSystemPreset preset, {
    required bool select,
    _LiveTurnSession? session,
  }) async {
    String? persistedPath;
    final store = _resolveCustomDesignSystemStore();
    if (store != null) {
      final savedFile = await store.save(preset);
      persistedPath = savedFile.path;
    }

    final updated = List<DesignSystemPreset>.of(_customDesignSystems);
    final existingIdx = updated.indexWhere((item) => item.id == preset.id);
    if (existingIdx >= 0) {
      updated.removeAt(existingIdx);
    }
    updated.insert(0, preset);

    if (mounted) {
      setState(() {
        _customDesignSystems = updated;
        if (select) {
          _selectedDesignSystem = preset;
        }
      });
    } else {
      _customDesignSystems = updated;
      if (select) {
        _selectedDesignSystem = preset;
      }
    }

    if (session != null) {
      session.registeredDesignSystem = preset;
      session.registeredDesignSystemSelected = select;
    }

    widget.onCustomDesignSystemsChanged?.call(
      List<DesignSystemPreset>.unmodifiable(_customDesignSystems),
    );
    if (select) {
      widget.onDesignSystemChanged?.call(preset);
      if (mounted) {
        final fontManager = DynamicFontScope.readOf(context);
        if (fontManager != null && fontManager.autoDownloadEnabled) {
          unawaited(fontManager.ensureDesignSystemFonts(preset));
        }
      }
      if (mounted && _usesStreamingGenerator) {
        unawaited(
          VibeChatDialog.warmUp(
            DefaultAssetBundle.of(context),
            speedMode: _speedMode,
            designSystemPreset: preset,
            customDesignGuide: widget.customDesignGuide,
            replaceDefaultDesignGuide: widget.replaceDefaultDesignGuide,
          ),
        );
      }
    }

    return (
      persistedPath: persistedPath,
      totalCustomPresets: _customDesignSystems.length,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ambientRepositoryStore =
        JsonRepositoryScope.maybeOf(context) ??
        SuperApp.maybeOf(context)?.repositoryStore;
    unawaited(_loadPersistedCustomDesignSystemsIfNeeded());
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
    if (oldWidget.initialPlanMode != widget.initialPlanMode) {
      _setPlanMode(widget.initialPlanMode, notifyCallback: false);
    }
    if (oldWidget.initialReproduceExactMode !=
        widget.initialReproduceExactMode) {
      _setReproduceExactMode(
        widget.initialReproduceExactMode,
        notifyCallback: false,
      );
    }
    if (oldWidget.initialVisibleOnlyMode != widget.initialVisibleOnlyMode) {
      _setVisibleOnlyMode(widget.initialVisibleOnlyMode, notifyCallback: false);
    }
    if (oldWidget.initialVerifyRenderEnabled !=
        widget.initialVerifyRenderEnabled) {
      _setVerifyRenderEnabled(
        widget.initialVerifyRenderEnabled,
        notifyCallback: false,
      );
    }
    if (oldWidget.initialReactiveValuesEnabled !=
        widget.initialReactiveValuesEnabled) {
      _setReactiveValuesEnabled(
        widget.initialReactiveValuesEnabled ?? !_isWidgetTestBinding,
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
    widget.onSpeedModeChanged?.call(mode);
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

  void _setPlanMode(bool enabled, {bool notifyCallback = true}) {
    if (_planMode == enabled || _isBusy) return;
    setState(() => _planMode = enabled);
    if (notifyCallback) {
      widget.onPlanModeChanged?.call(enabled);
    }
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

  void _setVisibleOnlyMode(bool enabled, {bool notifyCallback = true}) {
    if (_visibleOnlyMode == enabled || _isBusy) return;
    setState(() => _visibleOnlyMode = enabled);
    if (notifyCallback) {
      widget.onVisibleOnlyModeChanged?.call(enabled);
    }
  }

  void _setVerifyRenderEnabled(bool enabled, {bool notifyCallback = true}) {
    if (_verifyRenderEnabled == enabled || _isBusy) return;
    setState(() => _verifyRenderEnabled = enabled);
    if (notifyCallback) {
      widget.onVerifyRenderEnabledChanged?.call(enabled);
    }
  }

  void _setReactiveValuesEnabled(bool enabled, {bool notifyCallback = true}) {
    if (_reactiveValuesEnabled == enabled || _isBusy) return;
    setState(() => _reactiveValuesEnabled = enabled);
    if (notifyCallback) {
      widget.onReactiveValuesEnabledChanged?.call(enabled);
    }
  }

  bool get _effectiveSmartVerifyLocalGate =>
      widget.smartVerifyLocalGate ?? !_isWidgetTestBinding;

  bool get _effectiveThrottlePreviewLogs =>
      widget.throttleStreamingPreviewLogs ??
      (!_isWidgetTestBinding && !VibeChatDialog.verboseLogging);

  VibeVisibleViewportSnapshot _captureVisibleViewportSnapshot(
    Appearance appearance,
  ) => VibeAppInspector(
    readAppearance: () => appearance,
    registry: widget.registry,
    repositoryStore: _resolveRepositoryStore(),
    pageRouting: widget.pageRouting ?? SuperApp.maybeOf(context)?.pageRouting,
    readScope: () => _scope,
    readVisibleOnly: () => _visibleOnlyMode,
    fallbackContext: () => mounted ? context : null,
  ).captureVisibleViewportSnapshot(appearance);

  void _updateStreamingSnapshot(VibeStreamSnapshot? snapshot) {
    if (_disposed) return;
    _streamingSnapshot.value = snapshot;
  }

  void _updateSessionStreamingSnapshot(
    _LiveTurnSession? session,
    VibeStreamSnapshot? snapshot,
  ) {
    if (session != null && session.suppressUiUpdates) {
      if (snapshot != null) {
        session.onStreamProgress?.call(snapshot);
      }
      return;
    }
    _updateStreamingSnapshot(snapshot);
  }

  void _cancelActiveAiCall() {
    if (!_isBusy) return;
    if (_executingPlan && !_planStopRequested) {
      if (mounted) {
        setState(() => _planStopRequested = true);
      } else {
        _planStopRequested = true;
      }
    }
    _activeTurnSession?.cancellationToken.cancel();
    for (final s in _activeParallelSessions) {
      s.cancellationToken.cancel();
    }
  }

  void _publishStreamSnapshot(VibeStreamSnapshot snapshot) {
    if (_disposed) return;
    if (!_frameSnapshotScheduled) {
      _updateStreamingSnapshot(snapshot);
      _syncExpansionFromSnapshot(snapshot);
      _applyLivePreviewFromSnapshot(snapshot);
      _frameSnapshotScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _frameSnapshotScheduled = false;
        if (_disposed || !mounted || (!_sending && !_executingPlan)) {
          return;
        }
        final pending = _pendingSnapshot;
        if (pending != null) {
          _pendingSnapshot = null;
          _updateStreamingSnapshot(pending);
          _syncExpansionFromSnapshot(pending);
          _applyLivePreviewFromSnapshot(pending);
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
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

  Set<String> _resolveScopedExistingSubtreeIds(
    _LiveTurnSession session,
    Appearance appearance,
    VibeChatScope activeScope,
  ) {
    if (identical(session.cachedSubtreeAppearance, appearance) &&
        session.cachedSubtreeScope == activeScope &&
        session.cachedSubtreeIds != null) {
      return session.cachedSubtreeIds!;
    }
    final built = VibeScopeHelpers.existingSubtreeIds(appearance, activeScope);
    session.cachedSubtreeAppearance = appearance;
    session.cachedSubtreeScope = activeScope;
    session.cachedSubtreeIds = built;
    return built;
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
      if (session.lastHighlightEntryKey != null) {
        session.lastHighlightSection = null;
        session.lastHighlightEntryKey = null;
        session.lastHighlightAppearance = null;
        VibeWorkHighlightController.instance.clearStreamingTargets();
      }
      return;
    }
    if (session.lastHighlightSection == section &&
        session.lastHighlightEntryKey == entryKey &&
        identical(
          session.lastHighlightAppearance,
          session.lastPreviewAppearance,
        )) {
      return;
    }
    session.lastHighlightSection = section;
    session.lastHighlightEntryKey = entryKey;
    session.lastHighlightAppearance = session.lastPreviewAppearance;

    final activeScope = _scope;
    if (activeScope != null) {
      final allowed = _resolveScopedExistingSubtreeIds(
        session,
        session.lastPreviewAppearance,
        activeScope,
      );
      if (!activeScope.canonicalComponentIds.contains(entryKey) &&
          !allowed.contains(entryKey)) {
        VibeWorkHighlightController.instance.clearStreamingTargets();
        return;
      }
    }
    if (!_visibleOnlyMode && session.pageRouting != null) {
      final decision = VibeLivePageRouter.resolveForStreamingEntry(
        routing: session.pageRouting!,
        appearance: session.lastPreviewAppearance,
        activeSection: section,
        activeEntryKey: entryKey,
        initialPageIds: session.initialPageIds,
        hasNavigatedForVisualChange: session.hasNavigatedForVisualChange,
      );
      if (decision != null) {
        _applyLiveNavigationDecision(
          session,
          decision,
          session.lastPreviewAppearance,
        );
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

  void _flushSuppressedPreviewLogSummary(_LiveTurnSession session) {
    final suppressed = session.suppressedPreviewLogCount;
    if (suppressed <= 0) return;
    session.suppressedPreviewLogCount = 0;
    debugPrint(
      '[Vibe IA][Preview] Bilan streaming : ${session.appliedPreviewStepCount} '
      'palier(s) appliqué(s) ($suppressed intermédiaire(s) regroupé(s)).',
    );
  }

  void _applyLivePreviewFromSnapshot(VibeStreamSnapshot snapshot) {
    final session = _activeTurnSession;
    if (session == null ||
        session.livePreviewDisabled ||
        session.suppressUiUpdates ||
        snapshot.hasAskUserObject ||
        _isForceFollowUpQuestions) {
      return;
    }
    _syncStreamingWorkHighlight(session, snapshot);

    // Throttle les reconstructions d'aperçu après le tout premier palier (hors tests widgets).
    if (!_isWidgetTestBinding && session.lastPreviewApplyElapsedMs != null) {
      final elapsed = session.turnStopwatch.elapsedMilliseconds;
      final minIntervalMs =
          VibeChatDialog.livePreviewMinInterval.inMilliseconds;
      final deltaMs = elapsed - session.lastPreviewApplyElapsedMs!;
      if (deltaMs < minIntervalMs) {
        session.deferredPreviewSnapshot = snapshot;
        session.deferredPreviewTimer ??= Timer(
          Duration(milliseconds: minIntervalMs - deltaMs),
          () {
            session.deferredPreviewTimer = null;
            final deferred = session.deferredPreviewSnapshot;
            session.deferredPreviewSnapshot = null;
            if (_disposed ||
                !mounted ||
                deferred == null ||
                session.livePreviewDisabled ||
                !identical(_activeTurnSession, session)) {
              return;
            }
            _applyLivePreviewFromSnapshot(deferred);
          },
        );
        return;
      }
    }
    session.deferredPreviewTimer?.cancel();
    session.deferredPreviewTimer = null;
    session.deferredPreviewSnapshot = null;

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
      session.pendingRepoQueueSnapshot = snapshot;
      if (session.repoQueueDraining) {
        return;
      }
      session.repoQueueDraining = true;
      session.liveRepoQueue = session.liveRepoQueue
          .then((_) async {
            try {
              while (true) {
                final nextSnap = session.pendingRepoQueueSnapshot;
                session.pendingRepoQueueSnapshot = null;
                if (nextSnap == null ||
                    !mounted ||
                    session.livePreviewDisabled ||
                    !identical(_activeTurnSession, session)) {
                  break;
                }
                final repoTx = session.repoTransaction!;
                final repoPatch = nextSnap.partialRepositoriesPatch;
                final repoRev = nextSnap.repositoriesRevision;
                if (repoPatch != null &&
                    repoRev > session.lastAppliedRepositoriesRevision) {
                  session.lastAppliedRepositoriesRevision = repoRev;
                  try {
                    await repoTx.applyRepositoriesPatchPartial(repoPatch);
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
                  break;
                }
                final latestSnap = session.pendingRepoQueueSnapshot ?? nextSnap;
                if (identical(latestSnap, session.pendingRepoQueueSnapshot) &&
                    latestSnap.partialRepositoriesPatch != null &&
                    latestSnap.repositoriesRevision >
                        session.lastAppliedRepositoriesRevision) {
                  continue;
                }
                session.pendingRepoQueueSnapshot = null;
                final aliasMap = repoTx.aliasToActualId;
                final aliasChanged =
                    aliasMap.length != session.lastAppliedAliasCount;
                final patchRev = latestSnap.patchRevision;
                final nonUsagesRev = latestSnap.nonUsagesPatchRevision;
                if (latestSnap.partialVibePatch != null &&
                    (patchRev > session.lastAppliedPatchRevision ||
                        aliasChanged)) {
                  session.lastAppliedPatchRevision = patchRev;
                  if (!aliasChanged &&
                      nonUsagesRev > 0 &&
                      nonUsagesRev == session.lastAppliedNonUsagesRevision) {
                    continue;
                  }
                  session.lastAppliedNonUsagesRevision = nonUsagesRev;
                  session.lastAppliedAliasCount = aliasMap.length;
                  session.lastPreviewApplyElapsedMs =
                      session.turnStopwatch.elapsedMilliseconds;
                  _applyVibePatchPreviewSnapshot(
                    session,
                    latestSnap,
                    aliasToActualId: aliasMap,
                  );
                }
              }
            } finally {
              session.repoQueueDraining = false;
            }
          })
          .catchError((Object _) {
            session.repoQueueDraining = false;
          });
      return;
    }

    if (snapshot.patchRevision <= session.lastAppliedPatchRevision) {
      return;
    }
    session.lastAppliedPatchRevision = snapshot.patchRevision;
    if (snapshot.partialVibePatch == null) return;
    if (snapshot.nonUsagesPatchRevision > 0 &&
        snapshot.nonUsagesPatchRevision ==
            session.lastAppliedNonUsagesRevision) {
      return;
    }
    if (snapshot.nonUsagesPatchRevision == 0 &&
        snapshot.patchEntries.isNotEmpty &&
        snapshot.patchEntries.every((e) => e.isUsageEntry)) {
      return;
    }
    session.lastAppliedNonUsagesRevision = snapshot.nonUsagesPatchRevision;
    session.lastPreviewApplyElapsedMs =
        session.turnStopwatch.elapsedMilliseconds;
    _applyVibePatchPreviewSnapshot(session, snapshot);
  }

  void _applyVibePatchPreviewSnapshot(
    _LiveTurnSession session,
    VibeStreamSnapshot snapshot, {
    Map<String, String> aliasToActualId = const <String, String>{},
  }) {
    final base = session.checkpointAppearance;
    final applier = session.previewApplier ??= VibeIncrementalPreviewApplier(
      baseAppearance: base,
      codec: widget.codec,
    );
    if (!identical(applier.baseAppearance, base)) {
      applier.reset(base);
    }
    final activeScope = _scope;
    final viewportSnap = _visibleOnlyMode
        ? session.visibleViewportSnapshot
        : null;

    try {
      final stepResult = applier.applyStep(
        snapshot: snapshot,
        aliasToActualId: aliasToActualId,
        scope: activeScope,
        visibleViewportSnapshot: viewportSnap,
        validateAppearance: widget.validateAppearance,
      );
      if (stepResult == null) {
        if (activeScope != null && !_effectiveThrottlePreviewLogs) {
          debugPrint(
            '[Vibe IA][Preview] Patch partiel #${session.lastAppliedPatchRevision} '
            'ignoré (hors scope "${activeScope.displayLabel}").',
          );
        }
        return;
      }
      if (!stepResult.didChangeAppearance &&
          stepResult.appearance == session.lastPreviewAppearance) {
        return;
      }
      final previewAppearance = stepResult.appearance;
      final prevPreview = session.lastPreviewAppearance;
      _setPreviewAppearance(previewAppearance);
      final appliedAppearance = widget.controller.value;
      _pulseAppearanceDiff(session, appliedAppearance);
      session.hasAppliedLivePreview = true;
      session.appliedPreviewStepCount++;

      final shouldLogThisStep =
          !_effectiveThrottlePreviewLogs ||
          session.appliedPreviewStepCount == 1 ||
          stepResult.rejectedEntries.isNotEmpty;
      if (shouldLogThisStep) {
        final diffDesc = _describeAppearanceDiff(
          prevPreview,
          appliedAppearance,
        );
        final rejDesc = stepResult.rejectedEntries.isEmpty
            ? ''
            : ', rejets=${stepResult.rejectedEntries.map((e) => '${e.section}[${e.key}]').toList()}';
        debugPrint(
          '[Vibe IA][Preview] Palier #${session.lastAppliedPatchRevision} '
          '(${_describePatchTargets(stepResult.effectiveStepPatch)}) -> '
          '${diffDesc.isEmpty ? "aucun delta" : diffDesc}$rejDesc',
        );
      } else {
        session.suppressedPreviewLogCount++;
      }

      if (!_visibleOnlyMode && session.pageRouting != null) {
        final decision = VibeLivePageRouter.resolveForPreviewStep(
          routing: session.pageRouting!,
          previousAppearance: prevPreview,
          nextAppearance: appliedAppearance,
          effectivePatch: stepResult.effectiveStepPatch,
          initialPageIds: session.initialPageIds,
          hasNavigatedForVisualChange: session.hasNavigatedForVisualChange,
        );
        if (decision != null) {
          _applyLiveNavigationDecision(session, decision, appliedAppearance);
        } else if (appliedAppearance.pageCatalog != prevPreview.pageCatalog) {
          try {
            session.pageRouting!.synchronize(appliedAppearance.pageCatalog);
          } on FormatException {
            // Ignoré si le catalogue partiel est encore transitoire.
          }
        }
      }
    } on FormatException catch (error) {
      debugPrint(
        '[Vibe IA][Preview] Palier #${session.lastAppliedPatchRevision} '
        'différé (FormatException : ${_describeErrorCause(error)}).',
      );
    } on ArgumentError catch (error) {
      debugPrint(
        '[Vibe IA][Preview] Palier #${session.lastAppliedPatchRevision} '
        'différé (ArgumentError : ${_describeErrorCause(error)}).',
      );
    } on StateError catch (error) {
      debugPrint(
        '[Vibe IA][Preview] Palier #${session.lastAppliedPatchRevision} '
        'différé (StateError : ${_describeErrorCause(error)}).',
      );
    }
  }

  void _applyLiveNavigationDecision(
    _LiveTurnSession session,
    VibeStepNavigationDecision decision,
    Appearance appearance,
  ) {
    final routing = session.pageRouting;
    if (routing == null) return;
    if (decision.isVisualChange) {
      session.hasNavigatedForVisualChange = true;
    }
    final navigated = VibeLivePageRouter.navigateToTarget(
      routing: routing,
      appearance: appearance,
      target: decision.target,
    );
    if (navigated) {
      session.liveNavigatedTargetKey = decision.target.key;
      session.liveNavigatedPageId = decision.target.pageId;
    }
  }

  void _syncLivePageOutcome(_LiveTurnSession session, Appearance appearance) {
    final routing = session.pageRouting;
    if (routing == null || _visibleOnlyMode) return;
    try {
      routing.synchronize(appearance.pageCatalog);
    } on FormatException {
      return;
    }
    final target = VibeLivePageRouter.resolveForTurnOutcome(
      routing: routing,
      baseAppearance: session.baseAppearance,
      finalAppearance: appearance,
      initialPageIds: session.initialPageIds,
    );
    if (target == null) return;
    final navigated = VibeLivePageRouter.navigateToTarget(
      routing: routing,
      appearance: appearance,
      target: target,
    );
    if (navigated) {
      session.liveNavigatedTargetKey = target.key;
      session.liveNavigatedPageId = target.pageId;
    }
  }

  void _rollbackLivePreview(_LiveTurnSession session) {
    session.pendingRepoQueueSnapshot = null;
    session.lastAppliedPatchRevision = 0;
    session.lastAppliedNonUsagesRevision = 0;
    session.lastAppliedAliasCount = 0;
    session.previewApplier?.reset(session.baseAppearance);
    session.lastHighlightSection = null;
    session.lastHighlightEntryKey = null;
    session.lastHighlightAppearance = null;
    session.lastPreviewAppearance = session.baseAppearance;
    session.hasNavigatedForVisualChange = false;
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
    if (session.liveNavigatedTargetKey != null ||
        session.liveNavigatedPageId != null ||
        session.previewTracker.hasNavigated) {
      final routing = session.pageRouting;
      final previousLocation = session.initialRouteLocation;
      session.liveNavigatedTargetKey = null;
      session.liveNavigatedPageId = null;
      if (routing != null) {
        try {
          if (previousLocation != null &&
              previousLocation.isNotEmpty &&
              routing.currentUri.toString() != previousLocation) {
            routing.restoreLocation(previousLocation);
          }
          routing.synchronize(session.rawInitialAppearance.pageCatalog);
          final currentLocation = routing.currentUri.toString();
          if (previousLocation != null &&
              previousLocation.isNotEmpty &&
              currentLocation != previousLocation) {
            routing.openLocation(previousLocation);
          }
        } catch (_) {
          // Ignore lors de la restauration de route.
        }
      }
    }
  }

  void _restoreCheckpointPreview(_LiveTurnSession session) {
    session.pendingRepoQueueSnapshot = null;
    session.lastAppliedPatchRevision = 0;
    session.lastAppliedNonUsagesRevision = 0;
    session.lastAppliedAliasCount = 0;
    session.lastAppliedRepositoriesRevision = 0;
    session.previewApplier?.reset(session.checkpointAppearance);
    session.lastHighlightSection = null;
    session.lastHighlightEntryKey = null;
    session.lastHighlightAppearance = null;
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
      session.liveNavigatedTargetKey = null;
      session.liveNavigatedPageId = null;
      session.hasNavigatedForVisualChange = false;
      if (routing != null) {
        try {
          if (previousLocation != null &&
              previousLocation.isNotEmpty &&
              routing.currentUri.toString() != previousLocation) {
            routing.restoreLocation(previousLocation);
          }
          routing.synchronize(session.checkpointAppearance.pageCatalog);
          final checkpointTarget = VibeLivePageRouter.resolveForTurnOutcome(
            routing: routing,
            baseAppearance: session.baseAppearance,
            finalAppearance: session.checkpointAppearance,
            initialPageIds: session.initialPageIds,
          );
          if (checkpointTarget != null &&
              VibeLivePageRouter.navigateToTarget(
                routing: routing,
                appearance: session.checkpointAppearance,
                target: checkpointTarget,
              )) {
            session.liveNavigatedTargetKey = checkpointTarget.key;
            session.liveNavigatedPageId = checkpointTarget.pageId;
          } else {
            final currentLocation = routing.currentUri.toString();
            if (previousLocation != null &&
                previousLocation.isNotEmpty &&
                currentLocation != previousLocation) {
              routing.openLocation(previousLocation);
            }
          }
        } catch (_) {
          // Ignore lors de la restauration de route.
        }
      }
    } else if (!_visibleOnlyMode && session.pageRouting != null) {
      _syncLivePageOutcome(session, widget.controller.value);
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
    session.previewTracker.restoreTabs();
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

  Future<void> _deleteCustomDesignSystem(DesignSystemPreset preset) async {
    final removedSelected = _selectedDesignSystem?.id == preset.id;
    final updated = [
      for (final item in _customDesignSystems)
        if (item.id != preset.id) item,
    ];
    if (mounted) {
      setState(() {
        _customDesignSystems = updated;
        if (removedSelected) {
          _selectedDesignSystem = null;
        }
      });
    } else {
      _customDesignSystems = updated;
      if (removedSelected) {
        _selectedDesignSystem = null;
      }
    }
    widget.onCustomDesignSystemsChanged?.call(
      List<DesignSystemPreset>.unmodifiable(_customDesignSystems),
    );
    if (removedSelected) {
      widget.onDesignSystemChanged?.call(null);
      if (mounted && _usesStreamingGenerator) {
        unawaited(
          VibeChatDialog.warmUp(
            DefaultAssetBundle.of(context),
            speedMode: _speedMode,
            designSystemPreset: null,
            customDesignGuide: widget.customDesignGuide,
            replaceDefaultDesignGuide: widget.replaceDefaultDesignGuide,
          ),
        );
      }
    }
    final store = _resolveCustomDesignSystemStore();
    if (store != null) {
      try {
        await store.delete(preset.id);
      } catch (error) {
        debugPrint(
          '[Vibe IA] Suppression du DESIGN.md "${preset.id}" ignorée : $error',
        );
      }
    }
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
      onDeleteCustomPreset: (preset) =>
          unawaited(_deleteCustomDesignSystem(preset)),
      assetBundle: bundle,
    );
    if (!mounted || result == null) return;

    final previousCustomIds = {
      for (final item in _customDesignSystems) item.id,
    };
    final nextCustomIds = {
      for (final item in result.updatedCustomPresets) item.id,
    };
    final removedCustomIds = previousCustomIds.difference(nextCustomIds);
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
        unawaited(_persistCustomDesignPresets(_customDesignSystems));
        final store = _resolveCustomDesignSystemStore();
        if (store != null) {
          for (final removedId in removedCustomIds) {
            unawaited(store.delete(removedId));
          }
        }
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
    if (selectedPreset != null && mounted) {
      final fontManager = DynamicFontScope.readOf(context);
      if (fontManager != null && fontManager.autoDownloadEnabled) {
        unawaited(fontManager.ensureDesignSystemFonts(selectedPreset));
      }
    }
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
              'Restyle uniquement le périmètre ciblé "${activeScope.displayLabel}" (${activeScope.isMultiTarget ? 'ids: ${activeScope.canonicalComponentIds.map((id) => '"$id"').join(', ')}' : 'id: "${activeScope.canonicalComponentId}"'}) et son sous-arbre autorisé conformément au référentiel DESIGN.md actif ("${preset.name}") :\n'
              '- Mets à jour uniquement les styles des surfaces du périmètre (Card, IterableContent, lignes de collection — couleurs de surface "$surfaceHex", états "hover" et "selected", "radius": $radiusValue, "borderWidth", "borderColor": "$borderHex", "elevation" et "designSystem": "$surfaceSystemName"). Ne mets jamais d’entrée "styles" sur un "registry:Layout" pur (passe son placement parent en "registry:IterableContent" si une surface est requise).\n'
              '- Harmonise la typographie et les couleurs des composants SuperValue (texte primaire "$textHex", secondaire "$mutedHex"), SuperAction et SuperIndicator appartenant à ce périmètre.\n'
              '- Ne modifie aucune propriété globale de thème ("mode", "accent", styles["background"]) ni "pageCatalog".\n'
              '- Préserve à 100 % les identifiants de composants, placements, liaisons de données (bindings), usages et comportements (behaviors) existants.';

    await _runGenerationTurn(
      displayUserText: displayUserText,
      promptOverride: promptOverride,
    );
  }

  Future<void> _runPageAudit() async {
    if (_isBusy) return;
    _cancelSpeechDictation();
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
    final displayUserText = activeScope != null
        ? 'Audit & correction de ${activeScope.displayLabel}.'
        : _visibleOnlyMode
        ? 'Audit & correction de la zone visible (onglet et scroll courants).'
        : 'Audit & correction de la page active.';

    await _runGenerationTurn(
      displayUserText: displayUserText,
      runPageAudit: true,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _completionHideTimer?.cancel();
    _completionHideTimer = null;
    _resolvedCompletionController.removeListener(
      _onCompletionControllerChanged,
    );
    _completionGlowController.dispose();
    _planStopRequested = true;
    _activeTurnSession?.disposePreviewTimer();
    _activeTurnSession?.cancellationToken.cancel();
    for (final s in _activeParallelSessions) {
      s.disposePreviewTimer();
      s.cancellationToken.cancel();
    }
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
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (_isBusy) {
      if (event.logicalKey == LogicalKeyboardKey.escape &&
          !keyboard.isControlPressed &&
          !keyboard.isAltPressed &&
          !keyboard.isShiftPressed &&
          !keyboard.isMetaPressed) {
        _cancelActiveAiCall();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
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
        !_reproduceExactMode &&
        !_planMode) {
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

  Future<void> _generateDesignSystemFromAttachments() async {
    if (_isBusy || _pendingAttachments.isEmpty) return;
    _cancelSpeechDictation();
    final userNote = _input.text.trim();
    final attachments = List<VibeChatAttachment>.unmodifiable(
      _pendingAttachments,
    );
    _input.clear();
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

    final fileNames = attachments.map((a) => '"${a.name}"').join(', ');
    final displayUserText = userNote.isEmpty
        ? 'Générer et ajouter un DESIGN.md à partir des pièces jointes ($fileNames).'
        : 'Générer un DESIGN.md ($fileNames) : $userNote';

    final promptOverride =
        'GÉNÉRATION DE DESIGN SYSTEM (DESIGN.md) À PARTIR DES PIÈCES JOINTES ($fileNames) :\n'
        '${userNote.isNotEmpty ? 'Précisions utilisateur : $userNote\n\n' : ''}'
        '1. Analyse attentivement toutes les pièces jointes fournies (couleurs exactes #RRGGBB de fond/canvas, cartes/surface, accent primaire, textes primaire/secondaire, bordures, mode light/dark, typographie, rayons d’arrondi, ombres/élévation, style de boutons, badges et densité).\n'
        '2. Essaie impérativement de RÉCUPÉRER UN LOGO depuis les pièces jointes :\n'
        '   - Si un fichier `.svg` est joint ou si un `<svg>...</svg>` / `<img src="...">` / URL ou Data URI de logo est présent dans le code source (HTML/CSS/Markdown), extrais-le exactement.\n'
        '   - Si un logo ou logotype simple est visible sur une image/capture jointe sans source vectorielle, essaie d’en produire une version `<svg viewBox="...">...</svg>` compacte et fidèle avec les couleurs extraites (n’invente jamais une URL `https://...` fictive).\n'
        '   - Transmets ce logo dans le paramètre `logo` de `register_design_system` et documente-le dans le `DESIGN.md` (ex. bloc Brand Logo + exemple `styles["brand-logo"].fill.imageUrl` avec `imageFit: "contain"` dans la section 9).\n'
        '3. Appelle OBLIGATOIREMENT l’outil `register_design_system` (avec `select: true`) en lui passant :\n'
        '   - `name`, `slug`, `category`, `tagline`, `description`, `mode`, `accent`, `canvasColor`, `surfaceColor`, `textColor`, `mutedTextColor`, `borderColor`, `cardRadius`, `surfaceSystem`, `fontFamily`, `logo` (si récupéré), `tags` ;\n'
        '   - `markdown` : un guide `DESIGN.md` complet et actionnable pour `super_container_layout` structuré avec les 9 sections standard (`1. Visual Theme & Atmosphere`, `2. Color Palette & Roles`, `3. Typography Rules`, `4. Component Stylings`, `5. Layout Principles`, `6. Depth & Elevation`, `7. Do\'s and Don\'ts`, `8. Responsive & Desktop Ergonomics`, `9. Agent Prompt Guide`).\n'
        '4. Ne pose pas de questionnaire ("askUser": null) et ne modifie pas l’écran courant ("vibe": null) : renvoie uniquement {"message":"résumé en français du DESIGN.md généré (en précisant si le logo a été récupéré)","vibe":null} après l’exécution de `register_design_system`.';

    await _runGenerationTurn(
      displayUserText: displayUserText,
      promptOverride: promptOverride,
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
      planMode: _planMode,
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

  ({String prompt, List<VibeChatAttachment> attachments})
  _collectPlanSourceContext({
    required String currentPrompt,
    required List<VibeChatAttachment> currentAttachments,
  }) {
    final userTurnEntries = <VibeChatMessage>[];
    for (var i = _messages.length - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (msg.isUser) {
        userTurnEntries.add(msg);
        continue;
      }
      final isPendingClarificationOrRetry =
          msg.askUser != null || msg.failedResponse != null;
      if (!isPendingClarificationOrRetry) {
        break;
      }
    }
    if (userTurnEntries.length <= 1) {
      return (prompt: currentPrompt, attachments: currentAttachments);
    }
    final orderedUsers = userTurnEntries.reversed.toList();
    final promptParts = <String>[];
    final mergedAttachments = <VibeChatAttachment>[];
    for (var i = 0; i < orderedUsers.length; i++) {
      final msg = orderedUsers[i];
      final isLast = i == orderedUsers.length - 1;
      final body = isLast
          ? currentPrompt
          : (msg.promptText ??
                (msg.text.isEmpty && msg.attachments.isNotEmpty
                    ? 'Analyse les fichiers joints et applique les modifications correspondantes.'
                    : msg.text));
      if (body.trim().isNotEmpty) {
        promptParts.add(body.trim());
      }
      mergedAttachments.addAll(msg.attachments);
    }
    return (
      prompt: promptParts.isEmpty ? currentPrompt : promptParts.join('\n\n'),
      attachments: mergedAttachments.isEmpty
          ? currentAttachments
          : List<VibeChatAttachment>.unmodifiable(mergedAttachments),
    );
  }

  Future<void> _runGenerationTurn({
    required String displayUserText,
    String? promptOverride,
    List<VibeChatAttachment> attachments = const [],
    bool requestsMoreQuestions = false,
    bool runPageAudit = false,
  }) async {
    final history = EditorHistoryScope.controllerOf(context);
    final resolvedPageRouting =
        widget.pageRouting ?? SuperApp.maybeOf(context)?.pageRouting;
    final resolvedRepositoryStore = _resolveRepositoryStore();
    if (widget.controller case final PersistentAppearanceController persistent
        when persistent.hasUnloadedCatalogPages) {
      await persistent.ensureAllPagesLoaded();
      if (!mounted) return;
    }
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
      initialRouteLocation: resolvedPageRouting?.currentUri.toString(),
      initialPageIds: {
        for (final page in baseAppearance.pageCatalog.pages) page.id,
      },
      repoTransaction: resolvedRepositoryStore == null
          ? null
          : VibeRepositoryTurnTransaction(resolvedRepositoryStore),
      visibleViewportSnapshot: _visibleOnlyMode
          ? _captureVisibleViewportSnapshot(baseAppearance)
          : null,
    );

    VibeWorkHighlightController.instance.suppressAutoTabSwitch =
        _visibleOnlyMode;
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

    final activeScope = _scope;
    debugPrint(
      '[Vibe IA] Nouvelle demande utilisateur : "$displayUserText" '
      '(scope: ${activeScope != null ? '"${activeScope.displayLabel}" ${activeScope.canonicalComponentIds.toList()}' : 'global'}, '
      'mode: ${_speedMode.name}'
      '${_planMode ? ', plan' : ''}'
      '${_visibleOnlyMode ? ', visibleOnly' : ''}'
      '${_reproduceExactMode ? ', exact' : ''}'
      '${_reactiveValuesEnabled ? ', reactiveValues' : ''}'
      '${_selectedDesignSystem != null ? ', design=${_selectedDesignSystem!.id}' : ''}, '
      'pièces jointes: ${attachments.map((a) => a.name).toList()})',
    );
    history?.beginTransaction();
    try {
      final turnStopwatch = session.turnStopwatch;
      final guideStopwatch = Stopwatch()..start();
      final guide = await _loadGuide(context);
      session.cancellationToken.throwIfCancelled();
      guideStopwatch.stop();
      _recordTimedTrace(
        session,
        phase: 'context',
        label: 'Chargement du guide',
        durationMs: guideStopwatch.elapsedMilliseconds,
        scopeLabel: _planMode ? 'Plan][Phase 1' : 'Tour',
      );
      final repoStopwatch = Stopwatch()..start();
      final repositoriesContext = resolvedRepositoryStore == null
          ? null
          : await VibeRepositoryPromptFormatter.formatStoreContext(
              resolvedRepositoryStore,
            );
      session.cancellationToken.throwIfCancelled();
      repoStopwatch.stop();
      if (resolvedRepositoryStore != null) {
        _recordTimedTrace(
          session,
          phase: 'context',
          label: 'Contexte repositories',
          durationMs: repoStopwatch.elapsedMilliseconds,
          scopeLabel: _planMode ? 'Plan][Phase 1' : 'Tour',
        );
      }
      String effectivePlanPrompt = promptOverride ?? displayUserText;
      final String turnPrompt;
      if (runPageAudit) {
        final auditStopwatch = Stopwatch()..start();
        final auditInspector = VibeAppInspector(
          readAppearance: () => session.baseAppearance,
          registry: widget.registry,
          repositoryStore: resolvedRepositoryStore,
          pageRouting: resolvedPageRouting,
          readScope: () => _scope,
          readVisibleOnly: () => _visibleOnlyMode,
          fallbackContext: () => mounted ? context : null,
          turnStartMarker: session.turnStartMarker,
          allowEndOfFrameInWidgetTests: true,
        );
        final auditReport = await VibePageAuditService.collect(auditInspector);
        session.cancellationToken.throwIfCancelled();
        auditStopwatch.stop();
        _recordTimedTrace(
          session,
          phase: 'context',
          label: 'Pré-audit déterministe',
          durationMs: auditStopwatch.elapsedMilliseconds,
          detail: '${auditReport.findings.length} constat(s)',
          scopeLabel: 'Plan][Audit',
        );
        final auditSummaryPrompt =
            'AUDIT & CORRECTION :\n${auditReport.toPromptSummary()}';
        effectivePlanPrompt = auditSummaryPrompt;
        if (mounted && _messages.isNotEmpty) {
          final lastIdx = _messages.length - 1;
          if (_messages[lastIdx].isUser) {
            _messages[lastIdx] = _messages[lastIdx].copyWith(
              promptText: auditSummaryPrompt,
            );
          }
        }
        turnPrompt = VibePromptBuilder.buildAuditTurnPrompt(
          report: auditReport,
          conversation: _buildConversationHistory(),
          appearance: session.baseAppearance,
          codec: widget.codec,
          scope: _scope,
          instantiatedComponentIds: session.initialInstantiatedIds,
          mountedSlotSummaries: VibeMountedSlotIndex.instance
              .mountedSlotSummaries(),
          repositoriesContext: repositoriesContext,
          planMode: _planMode,
          visibleOnlyMode: _visibleOnlyMode,
          visibleViewportContext: session.visibleViewportSnapshot
              ?.toPromptContext(),
        );
      } else {
        final promptStopwatch = Stopwatch()..start();
        turnPrompt = _buildTurnPrompt(
          appearanceOverride: session.baseAppearance,
          instantiatedIdsOverride: session.initialInstantiatedIds,
          repositoriesContext: repositoriesContext,
        );
        promptStopwatch.stop();
        _recordTimedTrace(
          session,
          phase: 'context',
          label: 'Construction du prompt',
          durationMs: promptStopwatch.elapsedMilliseconds,
          detail: '${turnPrompt.length} car.',
          scopeLabel: _planMode ? 'Plan][Phase 1' : 'Tour',
        );
      }
      final generated = await _generateAndApply(
        turnPrompt,
        systemGuide: guide,
        session: session,
        attachments: attachments,
        traceScopeLabel: _planMode ? 'Plan][Phase 1' : 'Tour',
        phaseUiLabel: _planMode ? 'Planification (Phase 1)' : null,
      );
      turnStopwatch.stop();
      final totalTurnMs = turnStopwatch.elapsedMilliseconds;
      final hasMutations =
          generated.appearance != null || generated.repositoriesUpdated;
      if (hasMutations) {
        _setExpanded(false);
        if (generated.appearance case final appearance?) {
          widget.controller.value = appearance;
          if (mounted) {
            final fontManager = DynamicFontScope.readOf(context);
            if (fontManager != null && fontManager.autoDownloadEnabled) {
              unawaited(fontManager.ensureAppearanceFonts(appearance));
            }
          }
          final committedAppearance = widget.controller.value;
          _pulseAppearanceDiff(session, committedAppearance);
          _syncLivePageOutcome(session, committedAppearance);
          final tourDiff = _describeAppearanceDiff(
            session.baseAppearance,
            appearance,
          );
          debugPrint(
            '[Vibe IA] Apparence mise à jour avec succès '
            '(composants: ${appearance.components.length}, '
            'styles: ${appearance.styles.length}, '
            'pages: ${appearance.pageCatalog.pages.length}'
            '${tourDiff.isEmpty ? '' : ', $tourDiff'}'
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
      final registeredDesign = session.registeredDesignSystem;
      final fallbackText = generated.plan != null && !hasMutations
          ? 'Plan prêt — clique sur « Exécuter les lots » pour démarrer :'
          : generated.askUser != null && !hasMutations
          ? 'Précise tes préférences :'
          : registeredDesign != null && !hasMutations
          ? 'Design System « ${registeredDesign.name} » ajouté à la liste.'
          : 'Modifications appliquées.';
      final planSource = !hasMutations && generated.plan != null
          ? _collectPlanSourceContext(
              currentPrompt: effectivePlanPrompt,
              currentAttachments: attachments,
            )
          : null;
      final enrichedPlan = !hasMutations && generated.plan != null
          ? generated.plan!.copyWith(
              planningDurationMs: totalTurnMs,
              planningTraces: session.timedTraces,
            )
          : null;
      if (enrichedPlan != null) {
        debugPrint(
          '[Vibe IA][Plan][Phase 1] Plan prêt en $totalTurnMs ms '
          '(${enrichedPlan.lots.length} lot(s), '
          '${session.attemptsExecuted} tentative(s)).',
        );
      }
      _appendMessage(
        summaryText ?? fallbackText,
        askUser: !hasMutations && enrichedPlan == null
            ? generated.askUser
            : null,
        plan: enrichedPlan,
        planSourcePrompt: planSource?.prompt,
        planSourceAttachments: planSource?.attachments ?? const [],
        toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
        timedTraces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        generationDurationMs: totalTurnMs,
      );
      if (enrichedPlan != null && mounted) {
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
      } else if (registeredDesign != null) {
        _notifyTaskCompletion(
          outcome: VibeTaskOutcome.success,
          title: 'Design System DESIGN.md ajouté',
          detail:
              summaryText ??
              '« ${registeredDesign.name} » ajouté à la liste${session.registeredDesignSystemSelected ? ' et activé' : ''}.',
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
    } on VibeCancelledException {
      await _rollbackTurnSession(session);
      debugPrint(
        '[Vibe IA] Appel IA annulé par l’utilisateur '
        '(${session.turnStopwatch.elapsedMilliseconds} ms).',
      );
      _appendMessage(
        'Appel IA annulé.',
        toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
        timedTraces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        generationDurationMs: session.turnStopwatch.elapsedMilliseconds,
        retryTurn: VibeRetryTurnPayload(
          displayUserText: displayUserText,
          promptOverride: promptOverride,
          attachments: attachments,
          requestsMoreQuestions: requestsMoreQuestions,
          runPageAudit: runPageAudit,
        ),
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
        toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
        timedTraces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        generationDurationMs: session.turnStopwatch.elapsedMilliseconds,
        retryTurn: VibeRetryTurnPayload(
          displayUserText: displayUserText,
          promptOverride: promptOverride,
          attachments: attachments,
          requestsMoreQuestions: requestsMoreQuestions,
          runPageAudit: runPageAudit,
        ),
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
        toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
        timedTraces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        generationDurationMs: session.turnStopwatch.elapsedMilliseconds,
        retryTurn: VibeRetryTurnPayload(
          displayUserText: displayUserText,
          promptOverride: promptOverride,
          attachments: attachments,
          requestsMoreQuestions: requestsMoreQuestions,
          runPageAudit: runPageAudit,
        ),
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
        toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
        timedTraces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        generationDurationMs: session.turnStopwatch.elapsedMilliseconds,
        retryTurn: VibeRetryTurnPayload(
          displayUserText: displayUserText,
          promptOverride: promptOverride,
          attachments: attachments,
          requestsMoreQuestions: requestsMoreQuestions,
          runPageAudit: runPageAudit,
        ),
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
        toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
        timedTraces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        generationDurationMs: session.turnStopwatch.elapsedMilliseconds,
        retryTurn: VibeRetryTurnPayload(
          displayUserText: displayUserText,
          promptOverride: promptOverride,
          attachments: attachments,
          requestsMoreQuestions: requestsMoreQuestions,
          runPageAudit: runPageAudit,
        ),
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
        toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
        timedTraces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        generationDurationMs: session.turnStopwatch.elapsedMilliseconds,
        retryTurn: VibeRetryTurnPayload(
          displayUserText: displayUserText,
          promptOverride: promptOverride,
          attachments: attachments,
          requestsMoreQuestions: requestsMoreQuestions,
          runPageAudit: runPageAudit,
        ),
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
        toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
        timedTraces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        generationDurationMs: session.turnStopwatch.elapsedMilliseconds,
        retryTurn: VibeRetryTurnPayload(
          displayUserText: displayUserText,
          promptOverride: promptOverride,
          attachments: attachments,
          requestsMoreQuestions: requestsMoreQuestions,
          runPageAudit: runPageAudit,
        ),
      );
      _notifyTaskCompletion(
        outcome: VibeTaskOutcome.error,
        title: 'Tâche IA échouée',
        detail: cause,
      );
    } finally {
      session.disposePreviewTimer();
      VibeWorkHighlightController.instance.suppressAutoTabSwitch = false;
      VibeWorkHighlightController.instance.clearStreamingTargets();
      _activeTurnSession = null;
      _pendingSnapshot = null;
      _updateStreamingSnapshot(null);
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

  void _clearPlanCheckpointsForMessage(int messageIndex) {
    _planLotCheckpoints.removeWhere((key, _) => key.$1 == messageIndex);
  }

  void _cancelPlan(int messageIndex) {
    if (_isBusy || messageIndex != _activePlanMessageIndex) return;
    final plan = _messages[messageIndex].plan;
    if (plan == null || plan.status != VibePlanStatus.awaitingConfirmation) {
      return;
    }
    _clearPlanCheckpointsForMessage(messageIndex);
    _updatePlanAt(
      messageIndex,
      (p) => p.copyWith(status: VibePlanStatus.stopped),
    );
    setState(() => _activePlanMessageIndex = null);
    _commitOuterPlanTransaction();
  }

  void _togglePlanLot(int messageIndex, int lotIndex) {
    if (_isBusy || messageIndex != _activePlanMessageIndex) return;
    final plan = _messages[messageIndex].plan;
    if (plan == null ||
        plan.status != VibePlanStatus.awaitingConfirmation ||
        lotIndex < 0 ||
        lotIndex >= plan.lots.length) {
      return;
    }
    _updatePlanAt(
      messageIndex,
      (p) => p.withLotAt(
        lotIndex,
        (lot) => lot.copyWith(
          status: lot.status == VibeLotStatus.disabled
              ? VibeLotStatus.pending
              : VibeLotStatus.disabled,
        ),
      ),
    );
  }

  void _stopPlan(int messageIndex) {
    if (messageIndex != _activePlanMessageIndex) return;
    final plan = _messages[messageIndex].plan;
    if (plan == null) return;
    if (_executingPlan) {
      setState(() => _planStopRequested = true);
      _activeTurnSession?.cancellationToken.cancel();
      for (final s in _activeParallelSessions) {
        s.cancellationToken.cancel();
      }
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

  Future<void> _startPlanExecution(
    int messageIndex, {
    bool parallel = false,
  }) async {
    if (_isBusy || messageIndex != _activePlanMessageIndex) return;
    final plan = _messages[messageIndex].plan;
    if (plan == null || plan.status != VibePlanStatus.awaitingConfirmation) {
      return;
    }
    final startIdx = plan.nextActionableIndex;
    if (startIdx < 0) return;
    _updatePlanAt(messageIndex, (p) => p.copyWith(parallelExecution: parallel));
    _planPreRunAppearances.putIfAbsent(
      messageIndex,
      () => widget.controller.value,
    );
    _planRepoCallbacks.putIfAbsent(
      messageIndex,
      () => <VibeRepositoryHistoryCallbacks>[],
    );
    _beginOuterPlanTransaction(EditorHistoryScope.controllerOf(context));
    await _runPlanLoop(messageIndex, startIdx);
  }

  Future<void> _retryPlanLot(int messageIndex, {bool partial = false}) async {
    if (_isBusy || messageIndex != _activePlanMessageIndex) return;
    final plan = _messages[messageIndex].plan;
    if (plan == null || plan.status != VibePlanStatus.pausedOnError) return;
    final failedIdx = plan.lots.indexWhere(
      (lot) => lot.status == VibeLotStatus.failed,
    );
    if (failedIdx < 0) return;
    final checkpoint = partial
        ? _planLotCheckpoints.remove((messageIndex, failedIdx))
        : null;
    if (!partial) {
      _planLotCheckpoints.remove((messageIndex, failedIdx));
    }
    debugPrint(
      '[Vibe IA][Plan] Relance ${checkpoint != null ? "partielle (checkpoint)" : "complète"} '
      'du lot ${failedIdx + 1}/${plan.lots.length} ("${plan.lots[failedIdx].title}").',
    );
    _updatePlanAt(
      messageIndex,
      (p) => p.withLotAt(
        failedIdx,
        (lot) => lot.copyWith(
          status: VibeLotStatus.pending,
          clearErrorMessage: true,
          clearPartialCheckpoint: checkpoint == null,
        ),
      ),
    );
    _beginOuterPlanTransaction(EditorHistoryScope.controllerOf(context));
    await _runPlanLoop(
      messageIndex,
      failedIdx,
      initialLotCheckpoint: checkpoint,
      initialCheckpointLotIndex: checkpoint != null ? failedIdx : null,
    );
  }

  Future<void> _resumePlan(int messageIndex) async {
    if (_isBusy || messageIndex < 0 || messageIndex >= _messages.length) return;
    final plan = _messages[messageIndex].plan;
    if (plan == null) return;
    if (plan.status == VibePlanStatus.stopped) {
      final nextIdx = plan.nextActionableIndex;
      if (nextIdx < 0) return;
      final checkpoint = _planLotCheckpoints.remove((messageIndex, nextIdx));
      _updatePlanAt(
        messageIndex,
        (p) => p
            .copyWith(status: VibePlanStatus.running)
            .withLotAt(
              nextIdx,
              (lot) => lot.copyWith(
                status: VibeLotStatus.pending,
                clearErrorMessage: true,
                clearPartialCheckpoint: checkpoint == null,
              ),
            ),
      );
      if (mounted) {
        setState(() => _activePlanMessageIndex = messageIndex);
      } else {
        _activePlanMessageIndex = messageIndex;
      }
      _beginOuterPlanTransaction(EditorHistoryScope.controllerOf(context));
      await _runPlanLoop(
        messageIndex,
        nextIdx,
        initialLotCheckpoint: checkpoint,
        initialCheckpointLotIndex: checkpoint != null ? nextIdx : null,
      );
      return;
    }
    if (plan.status == VibePlanStatus.completed) {
      final hasSkipped = plan.lots.any(
        (lot) => lot.status == VibeLotStatus.skipped,
      );
      if (!hasSkipped) return;
      _updatePlanAt(
        messageIndex,
        (p) => p.copyWith(
          status: VibePlanStatus.running,
          lots: [
            for (final lot in p.lots)
              if (lot.status == VibeLotStatus.skipped)
                lot.copyWith(
                  status: VibeLotStatus.pending,
                  clearErrorMessage: true,
                  clearPartialCheckpoint: true,
                )
              else
                lot,
          ],
        ),
      );
      final updated = _messages[messageIndex].plan!;
      final nextIdx = updated.nextActionableIndex;
      if (nextIdx < 0) return;
      if (mounted) {
        setState(() => _activePlanMessageIndex = messageIndex);
      } else {
        _activePlanMessageIndex = messageIndex;
      }
      _beginOuterPlanTransaction(EditorHistoryScope.controllerOf(context));
      await _runPlanLoop(messageIndex, nextIdx);
    }
  }

  Future<void> _retryPlanAll(int messageIndex) async {
    if (_isBusy || messageIndex < 0 || messageIndex >= _messages.length) return;
    final plan = _messages[messageIndex].plan;
    if (plan == null) return;
    _clearPlanCheckpointsForMessage(messageIndex);

    final history = EditorHistoryScope.controllerOf(context);
    final preRunAppearance = _planPreRunAppearances[messageIndex];
    final repoCallbacks = _planRepoCallbacks[messageIndex];
    if (_openPlanHistory != null) {
      if (preRunAppearance != null) {
        widget.controller.value = preRunAppearance;
      }
      if (repoCallbacks != null) {
        for (final cb in repoCallbacks.reversed) {
          try {
            await cb.undo();
          } catch (_) {}
        }
        repoCallbacks.clear();
      }
      _openPlanHistory!.cancelTransaction();
      _openPlanHistory = null;
    } else {
      if (preRunAppearance != null) {
        widget.controller.value = preRunAppearance;
      }
      if (repoCallbacks != null) {
        for (final cb in repoCallbacks.reversed) {
          try {
            await cb.undo();
          } catch (_) {}
        }
        repoCallbacks.clear();
      }
    }

    _planPreRunAppearances[messageIndex] = widget.controller.value;
    _planRepoCallbacks[messageIndex] = <VibeRepositoryHistoryCallbacks>[];
    _updatePlanAt(
      messageIndex,
      (p) => p.copyWith(
        status: VibePlanStatus.running,
        clearExecutionDuration: true,
        lots: [
          for (final lot in p.lots)
            lot.status == VibeLotStatus.disabled
                ? lot
                : lot.copyWith(
                    status: VibeLotStatus.pending,
                    clearErrorMessage: true,
                    clearDuration: true,
                    attempts: 0,
                    clearPartialCheckpoint: true,
                    traces: const <VibeTimedTrace>[],
                  ),
        ],
      ),
    );
    final updated = _messages[messageIndex].plan!;
    final startIdx = updated.nextActionableIndex;
    if (startIdx < 0) return;
    if (mounted) {
      setState(() => _activePlanMessageIndex = messageIndex);
    } else {
      _activePlanMessageIndex = messageIndex;
    }
    debugPrint(
      '[Vibe IA][Plan] Relance complète du plan "${updated.title}" '
      '(${updated.actionableCount} lot(s) actif(s)).',
    );
    _beginOuterPlanTransaction(history);
    await _runPlanLoop(messageIndex, startIdx);
  }

  Future<void> _retryFailedTurn(int messageIndex) async {
    if (_isBusy || messageIndex < 0 || messageIndex >= _messages.length) return;
    final payload = _messages[messageIndex].retryTurn;
    if (payload == null) return;
    setState(() {
      _messages[messageIndex] = _messages[messageIndex].copyWith(
        clearRetryTurn: true,
      );
    });
    await _runGenerationTurn(
      displayUserText: payload.displayUserText,
      promptOverride: payload.promptOverride,
      attachments: payload.attachments,
      requestsMoreQuestions: payload.requestsMoreQuestions,
      runPageAudit: payload.runPageAudit,
    );
  }

  Future<void> _skipPlanLot(int messageIndex) async {
    if (_isBusy || messageIndex != _activePlanMessageIndex) return;
    final plan = _messages[messageIndex].plan;
    if (plan == null || plan.status != VibePlanStatus.pausedOnError) return;
    final failedIdx = plan.lots.indexWhere(
      (lot) => lot.status == VibeLotStatus.failed,
    );
    if (failedIdx < 0) return;
    _planLotCheckpoints.remove((messageIndex, failedIdx));
    _updatePlanAt(
      messageIndex,
      (p) => p.withLotAt(
        failedIdx,
        (lot) => lot.copyWith(
          status: VibeLotStatus.skipped,
          clearErrorMessage: true,
          clearPartialCheckpoint: true,
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
      final disabledCount = updated.lots
          .where((l) => l.status == VibeLotStatus.disabled)
          .length;
      final omissions = [
        if (skippedCount > 0) '$skippedCount ignoré(s)',
        if (disabledCount > 0) '$disabledCount désactivé(s)',
      ].join(', ');
      final detail =
          '${updated.doneCount}/${updated.lots.length} lots appliqués'
          '${omissions.isEmpty ? '' : ' ($omissions)'}.';
      _appendMessage(
        disabledCount == 0
            ? 'Plan terminé (${updated.doneCount}/${updated.lots.length} '
                  'lots appliqués, $skippedCount ignoré(s)).'
            : 'Plan terminé : $detail',
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

  Future<void> _runPlanLoop(
    int messageIndex,
    int startLotIndex, {
    _LotPartialCheckpoint? initialLotCheckpoint,
    int? initialCheckpointLotIndex,
  }) async {
    if (!mounted) return;
    _clearCompletionAlert();
    final runStopwatch = Stopwatch()..start();
    final previousExecDurationMs =
        _messages[messageIndex].plan?.executionDurationMs ?? 0;
    int accumulatedDurationMs() =>
        previousExecDurationMs + runStopwatch.elapsedMilliseconds;

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
      var usedInitialCheckpoint = false;
      var ranFinalReactivePassInLastLot = false;
      while (true) {
        if (!mounted || _planStopRequested) {
          runStopwatch.stop();
          _updatePlanAt(
            messageIndex,
            (p) => p.copyWith(
              status: VibePlanStatus.stopped,
              executionDurationMs: accumulatedDurationMs(),
            ),
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
        final totalLots = currentPlan.lots.length;

        final List<int> waveIndices;
        if (!usedInitialCheckpoint &&
            initialCheckpointLotIndex != null &&
            initialLotCheckpoint != null &&
            initialCheckpointLotIndex >= startLotIndex &&
            initialCheckpointLotIndex < totalLots &&
            (currentPlan.lots[initialCheckpointLotIndex].status ==
                    VibeLotStatus.pending ||
                currentPlan.lots[initialCheckpointLotIndex].status ==
                    VibeLotStatus.failed)) {
          waveIndices = <int>[initialCheckpointLotIndex];
        } else {
          final maxWaveCount = currentPlan.parallelExecution
              ? VibeChatDialog.maxParallelPlanLots
              : 1;
          waveIndices = currentPlan.nextReadyActionableIndices(
            minIndex: startLotIndex,
            maxCount: maxWaveCount,
          );
        }
        if (waveIndices.isEmpty) break;

        if (waveIndices.length >= 2) {
          usedInitialCheckpoint = true;
          _updatePlanAt(messageIndex, (p) {
            var next = p.copyWith(status: VibePlanStatus.running);
            for (final idx in waveIndices) {
              next = next.withLotAt(
                idx,
                (l) => l.copyWith(
                  status: VibeLotStatus.running,
                  clearErrorMessage: true,
                ),
              );
            }
            return next;
          });

          final waveOutcomes = await _executeParallelLotWave(
            messageIndex,
            waveIndices,
          );
          if (!mounted) return;

          int? firstFailedIdx;
          String? firstErrorCause;
          var anyWasCancelled = false;

          _updatePlanAt(messageIndex, (p) {
            var next = p.copyWith(executionDurationMs: accumulatedDurationMs());
            for (final idx in waveIndices) {
              final outcome = waveOutcomes[idx]!;
              if (outcome.errorCause == null) {
                _planLotCheckpoints.remove((messageIndex, idx));
                next = next.withLotAt(
                  idx,
                  (l) => l.copyWith(
                    status: VibeLotStatus.done,
                    clearErrorMessage: true,
                    durationMs: outcome.durationMs,
                    attempts: outcome.attempts,
                    clearPartialCheckpoint: true,
                    traces: outcome.traces,
                  ),
                );
              } else {
                if (outcome.partialCheckpoint != null) {
                  _planLotCheckpoints[(messageIndex, idx)] =
                      outcome.partialCheckpoint!;
                } else {
                  _planLotCheckpoints.remove((messageIndex, idx));
                }
                if (outcome.wasCancelled) {
                  anyWasCancelled = true;
                  next = next.withLotAt(
                    idx,
                    (l) => l.copyWith(
                      status: VibeLotStatus.pending,
                      clearErrorMessage: true,
                      durationMs: outcome.durationMs,
                      attempts: outcome.attempts,
                      clearPartialCheckpoint: true,
                      traces: outcome.traces,
                    ),
                  );
                } else {
                  firstFailedIdx ??= idx;
                  firstErrorCause ??= outcome.errorCause;
                  next = next.withLotAt(
                    idx,
                    (l) => l.copyWith(
                      status: VibeLotStatus.failed,
                      errorMessage: outcome.errorCause,
                      durationMs: outcome.durationMs,
                      attempts: outcome.attempts,
                      hasPartialCheckpoint: outcome.partialCheckpoint != null,
                      partialCheckpointSummary:
                          outcome.partialCheckpoint?.summary,
                      traces: outcome.traces,
                    ),
                  );
                }
              }
            }
            return next;
          });

          if (_planStopRequested || anyWasCancelled) {
            runStopwatch.stop();
            _updatePlanAt(
              messageIndex,
              (p) => p.copyWith(
                status: VibePlanStatus.stopped,
                executionDurationMs: accumulatedDurationMs(),
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

          if (firstFailedIdx != null) {
            runStopwatch.stop();
            _updatePlanAt(
              messageIndex,
              (p) => p.copyWith(
                status: VibePlanStatus.pausedOnError,
                executionDurationMs: accumulatedDurationMs(),
              ),
            );
            _setExpanded(true);
            _notifyTaskCompletion(
              outcome: VibeTaskOutcome.error,
              title: 'Plan IA en pause (erreur)',
              detail:
                  'Lot ${firstFailedIdx! + 1}/$totalLots : ${firstErrorCause ?? "Erreur"}',
            );
            return;
          }
          continue;
        }

        final i = waveIndices.single;
        usedInitialCheckpoint = true;

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

        final remainingActionableCount = currentPlan.lots
            .where(
              (l) =>
                  l.status == VibeLotStatus.pending ||
                  l.status == VibeLotStatus.failed,
            )
            .length;
        final isLastActionableLot = remainingActionableCount <= 1;
        final lotCheckpoint = initialCheckpointLotIndex == i
            ? initialLotCheckpoint
            : null;
        final outcome = await _executeSingleLot(
          messageIndex,
          i,
          isIntermediateLot: !isLastActionableLot,
          initialCheckpoint: lotCheckpoint,
        );
        if (!mounted) return;

        if (outcome.errorCause == null) {
          if (isLastActionableLot) {
            ranFinalReactivePassInLastLot = true;
          }
          _planLotCheckpoints.remove((messageIndex, i));
          _updatePlanAt(
            messageIndex,
            (p) => p
                .copyWith(executionDurationMs: accumulatedDurationMs())
                .withLotAt(
                  i,
                  (l) => l.copyWith(
                    status: VibeLotStatus.done,
                    clearErrorMessage: true,
                    durationMs: outcome.durationMs,
                    attempts: outcome.attempts,
                    clearPartialCheckpoint: true,
                    traces: outcome.traces,
                  ),
                ),
          );
          continue;
        }

        final errorCause = outcome.errorCause!;
        final failureCheckpoint = outcome.partialCheckpoint;
        if (failureCheckpoint != null) {
          _planLotCheckpoints[(messageIndex, i)] = failureCheckpoint;
        } else {
          _planLotCheckpoints.remove((messageIndex, i));
        }

        if (_planStopRequested || outcome.wasCancelled) {
          runStopwatch.stop();
          _updatePlanAt(
            messageIndex,
            (p) => p
                .copyWith(
                  status: VibePlanStatus.stopped,
                  executionDurationMs: accumulatedDurationMs(),
                )
                .withLotAt(
                  i,
                  (l) => outcome.wasCancelled
                      ? l.copyWith(
                          status: VibeLotStatus.pending,
                          clearErrorMessage: true,
                          durationMs: outcome.durationMs,
                          attempts: outcome.attempts,
                          clearPartialCheckpoint: true,
                          traces: outcome.traces,
                        )
                      : l.copyWith(
                          status: VibeLotStatus.failed,
                          errorMessage: errorCause,
                          durationMs: outcome.durationMs,
                          attempts: outcome.attempts,
                          hasPartialCheckpoint: failureCheckpoint != null,
                          partialCheckpointSummary: failureCheckpoint?.summary,
                          traces: outcome.traces,
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

        runStopwatch.stop();
        _updatePlanAt(
          messageIndex,
          (p) => p
              .copyWith(
                status: VibePlanStatus.pausedOnError,
                executionDurationMs: accumulatedDurationMs(),
              )
              .withLotAt(
                i,
                (l) => l.copyWith(
                  status: VibeLotStatus.failed,
                  errorMessage: errorCause,
                  durationMs: outcome.durationMs,
                  attempts: outcome.attempts,
                  hasPartialCheckpoint: failureCheckpoint != null,
                  partialCheckpointSummary: failureCheckpoint?.summary,
                  traces: outcome.traces,
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
      VibeTimedTrace? planFinalReactiveTrace;
      final planBeforeFinalize = _messages[messageIndex].plan;
      if (_reactiveValuesEnabled &&
          !ranFinalReactivePassInLastLot &&
          !_planStopRequested &&
          planBeforeFinalize != null &&
          planBeforeFinalize.doneCount > 0) {
        planFinalReactiveTrace = await _runPlanFinalReactiveValuesPass(
          messageIndex,
        );
        if (!mounted) return;
      }
      runStopwatch.stop();
      final totalExecMs = accumulatedDurationMs();
      _updatePlanAt(
        messageIndex,
        (p) => p.copyWith(
          status: VibePlanStatus.completed,
          executionDurationMs: totalExecMs,
        ),
      );
      final completedPlan = _messages[messageIndex].plan;
      setState(() => _activePlanMessageIndex = null);
      _commitOuterPlanTransaction();
      if (completedPlan != null) {
        final skipped = completedPlan.lots
            .where((l) => l.status == VibeLotStatus.skipped)
            .length;
        final disabled = completedPlan.lots
            .where((l) => l.status == VibeLotStatus.disabled)
            .length;
        final omissions = [
          if (skipped > 0) '$skipped ignoré(s)',
          if (disabled > 0) '$disabled désactivé(s)',
        ].join(', ');
        final detail =
            '${completedPlan.doneCount}/${completedPlan.lots.length} lots appliqués'
            '${omissions.isEmpty ? '' : ' ($omissions)'}.';
        final completionPrefix = completedPlan.reproduceExact
            ? 'Reproduction terminée'
            : 'Plan terminé';
        debugPrint(
          '[Vibe IA][Plan] $completionPrefix en $totalExecMs ms — $detail',
        );
        _appendMessage(
          '$completionPrefix : $detail',
          timedTraces: [
            for (final (idx, lot) in completedPlan.lots.indexed)
              if (lot.durationMs != null)
                VibeTimedTrace(
                  phase: 'step',
                  label:
                      'Lot ${idx + 1}/${completedPlan.lots.length} (${lot.title})',
                  durationMs: lot.durationMs!,
                  detail: lot.attempts > 1
                      ? '${lot.attempts} essais · ${lot.status.label}'
                      : lot.status.label,
                  isError: lot.status == VibeLotStatus.failed,
                ),
            ?planFinalReactiveTrace,
          ],
          generationDurationMs: totalExecMs,
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

  /// Exécute une passe finale « Valeurs réactives » sur l'état fusionné d'un
  /// plan terminé par une vague parallèle (qui n'a pas eu de lot final séquentiel).
  Future<VibeTimedTrace?> _runPlanFinalReactiveValuesPass(
    int messageIndex,
  ) async {
    if (!mounted) return null;
    final history = EditorHistoryScope.controllerOf(context);
    final fontManager = DynamicFontScope.readOf(context);
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
      initialRouteLocation: resolvedPageRouting?.currentUri.toString(),
      initialPageIds: {
        for (final page in baseAppearance.pageCatalog.pages) page.id,
      },
      repoTransaction: resolvedRepositoryStore == null
          ? null
          : VibeRepositoryTurnTransaction(resolvedRepositoryStore),
      visibleViewportSnapshot: _visibleOnlyMode
          ? _captureVisibleViewportSnapshot(baseAppearance)
          : null,
    );
    _activeTurnSession = session;
    final watch = Stopwatch()..start();
    try {
      final guide = await _loadGuide(context);
      session.cancellationToken.throwIfCancelled();
      final toolRegistry = _resolveToolRegistry(session);
      final useStreaming = _usesStreamingGenerator;
      final isDirectGemini =
          useStreaming &&
          widget.streamGenerate == null &&
          identical(widget.generate, callGemini);
      final reactive = await _runPostReactiveValuesPass(
        candidateAppearance: baseAppearance,
        systemGuide: guide,
        session: session,
        toolRegistry: toolRegistry,
        isDirectGemini: isDirectGemini,
        useStreaming: useStreaming,
        traceScopeLabel: 'Plan][Valeurs réactives',
      );
      if (reactive.updatedAppearance case final updated?) {
        widget.controller.value = updated;
        if (mounted && fontManager != null && fontManager.autoDownloadEnabled) {
          unawaited(fontManager.ensureAppearanceFonts(updated));
        }
        final committed = widget.controller.value;
        _pulseAppearanceDiff(session, committed);
        _syncLivePageOutcome(session, committed);
      } else {
        _rollbackLivePreview(session);
      }
      if (session.repoTransaction?.buildHistoryCallbacks()
          case final repoCallbacks?) {
        history?.addTransactionSideEffect(
          undo: repoCallbacks.undo,
          redo: repoCallbacks.redo,
        );
        (_planRepoCallbacks[messageIndex] ??=
                <VibeRepositoryHistoryCallbacks>[])
            .add(repoCallbacks);
      }
      watch.stop();
      final detail = _describeReactivePassDetail(
        appearanceUpdated: reactive.updatedAppearance != null,
        repositoriesUpdated: reactive.repositoriesUpdated,
      );
      return VibeTimedTrace(
        phase: 'reactive',
        label: 'Valeurs réactives',
        durationMs: watch.elapsedMilliseconds,
        detail: detail,
      );
    } on VibeCancelledException {
      await _rollbackTurnSession(session);
      return null;
    } catch (error) {
      await _rollbackTurnSession(session);
      watch.stop();
      debugPrint(
        '[Vibe IA][Plan][PostReactive] Passe finale ignorée après erreur '
        '(${watch.elapsedMilliseconds}ms) : $error',
      );
      return null;
    } finally {
      session.disposePreviewTimer();
      if (identical(_activeTurnSession, session)) {
        _activeTurnSession = null;
      }
      _updateStreamingSnapshot(null);
    }
  }

  Future<
    ({
      String? errorCause,
      int durationMs,
      int attempts,
      List<VibeTimedTrace> traces,
      _LotPartialCheckpoint? partialCheckpoint,
      bool wasCancelled,
    })
  >
  _executeSingleLot(
    int messageIndex,
    int lotIndex, {
    bool isIntermediateLot = false,
    _LotPartialCheckpoint? initialCheckpoint,
  }) async {
    final planMessage = _messages[messageIndex];
    final plan = planMessage.plan;
    if (plan == null) {
      return (
        errorCause: 'Plan introuvable.',
        durationMs: 0,
        attempts: 0,
        traces: const <VibeTimedTrace>[],
        partialCheckpoint: null,
        wasCancelled: false,
      );
    }

    final history = EditorHistoryScope.controllerOf(context);
    final resolvedPageRouting =
        widget.pageRouting ?? SuperApp.maybeOf(context)?.pageRouting;
    final resolvedRepositoryStore = _resolveRepositoryStore();
    if (widget.controller case final PersistentAppearanceController persistent
        when persistent.hasUnloadedCatalogPages) {
      await persistent.ensureAllPagesLoaded();
      if (!mounted) {
        return (
          errorCause: 'Composant démonté.',
          durationMs: 0,
          attempts: 0,
          traces: const <VibeTimedTrace>[],
          partialCheckpoint: null,
          wasCancelled: true,
        );
      }
    }
    final rawInitialAppearance = widget.controller.value;
    final baseAppearance =
        initialCheckpoint?.baseAppearance ?? _currentAppearance;
    final initialInstantiatedIds = widget.registry == null
        ? null
        : Set<String>.unmodifiable(widget.registry!.instantiatedComponentIds);
    final session = _LiveTurnSession(
      rawInitialAppearance: rawInitialAppearance,
      baseAppearance: baseAppearance,
      initialInstantiatedIds: initialInstantiatedIds,
      pageRouting: resolvedPageRouting,
      initialRouteLocation: resolvedPageRouting?.currentUri.toString(),
      initialPageIds: {
        for (final page in baseAppearance.pageCatalog.pages) page.id,
      },
      repoTransaction:
          initialCheckpoint?.repoTransaction ??
          (resolvedRepositoryStore == null
              ? null
              : VibeRepositoryTurnTransaction(resolvedRepositoryStore)),
      visibleViewportSnapshot: _visibleOnlyMode
          ? _captureVisibleViewportSnapshot(baseAppearance)
          : null,
    );

    VibeWorkHighlightController.instance.suppressAutoTabSwitch =
        _visibleOnlyMode;
    _lastFailedResponse = null;
    _activeTurnSession = session;
    setState(() => _sending = true);

    final guideBundle = DefaultAssetBundle.of(context);
    final fontManager = DynamicFontScope.readOf(context);
    final sourcePrompt = planMessage.planSourcePrompt ?? '';
    final sourceAttachments = planMessage.planSourceAttachments;
    final lotScopeLabel = 'Plan][Lot ${lotIndex + 1}/${plan.lots.length}';
    final lotUiLabel =
        'Lot ${lotIndex + 1}/${plan.lots.length} : ${plan.lots[lotIndex].title}';
    debugPrint(
      '[Vibe IA][$lotScopeLabel] Démarrage "${plan.lots[lotIndex].title}"'
      '${initialCheckpoint != null ? " (reprise partielle sur checkpoint)" : ""}',
    );
    history?.beginTransaction();
    try {
      if (_planStopRequested) {
        session.cancellationToken.cancel();
      }
      session.cancellationToken.throwIfCancelled();
      if (initialCheckpoint != null) {
        final restoreWatch = Stopwatch()..start();
        if (initialCheckpoint.repoSavepoint != null &&
            session.repoTransaction != null) {
          await session.repoTransaction!.restoreSavepoint(
            initialCheckpoint.repoSavepoint!,
          );
          session.repoCheckpoint = session.repoTransaction!.createSavepoint();
        }
        session.checkpointAppearance = initialCheckpoint.checkpointAppearance;
        session.hasCheckpoint = true;
        session.requiresScreenAttachment =
            initialCheckpoint.requiresScreenAttachment;
        session.pendingComponentFixes.addAll(
          initialCheckpoint.pendingComponentFixes,
        );
        _restoreCheckpointPreview(session);
        restoreWatch.stop();
        _recordTimedTrace(
          session,
          phase: 'retry',
          label: 'Reprise checkpoint partiel',
          durationMs: restoreWatch.elapsedMilliseconds,
          detail: initialCheckpoint.summary,
          scopeLabel: lotScopeLabel,
        );
      }

      final guideWatch = Stopwatch()..start();
      final guide = await VibeChatDialog.loadStaticGuide(
        guideBundle,
        designSystemPreset: _selectedDesignSystem,
        customDesignGuide: widget.customDesignGuide,
        replaceDefaultDesignGuide: widget.replaceDefaultDesignGuide,
      );
      session.cancellationToken.throwIfCancelled();
      guideWatch.stop();
      _recordTimedTrace(
        session,
        phase: 'context',
        label: 'Chargement du guide',
        durationMs: guideWatch.elapsedMilliseconds,
        scopeLabel: lotScopeLabel,
      );

      final repoWatch = Stopwatch()..start();
      final repositoriesContext = resolvedRepositoryStore == null
          ? null
          : await VibeRepositoryPromptFormatter.formatStoreContext(
              resolvedRepositoryStore,
            );
      session.cancellationToken.throwIfCancelled();
      repoWatch.stop();
      if (resolvedRepositoryStore != null) {
        _recordTimedTrace(
          session,
          phase: 'context',
          label: 'Contexte repositories',
          durationMs: repoWatch.elapsedMilliseconds,
          scopeLabel: lotScopeLabel,
        );
      }

      final codedRoutePaths = resolvedPageRouting == null
          ? const <String>[]
          : <String>[
              for (final route in resolvedPageRouting.codedRoutes) route.path,
            ];

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
        codedRoutePaths: codedRoutePaths,
        repositoriesContext: repositoriesContext,
        visibleOnlyMode: _visibleOnlyMode,
        visibleViewportContext: session.visibleViewportSnapshot
            ?.toPromptContext(),
      );

      final promptWatch = Stopwatch()..start();
      final turnPrompt = initialCheckpoint != null
          ? VibeDeltaRecovery.buildDeltaRetryPrompt(
              refreshedTurnPrompt: buildLotPrompt(
                appearanceOverride: session.checkpointAppearance,
                instantiatedIdsOverride: session.initialInstantiatedIds,
                repositoriesContext: repositoriesContext,
              ),
              priorCauses: initialCheckpoint.priorCauses,
              salvage: initialCheckpoint.salvage,
              pendingRequiredComponentIds: session.pendingComponentFixes,
            )
          : buildLotPrompt(
              appearanceOverride: session.baseAppearance,
              instantiatedIdsOverride: session.initialInstantiatedIds,
              repositoriesContext: repositoriesContext,
            );
      promptWatch.stop();
      _recordTimedTrace(
        session,
        phase: 'context',
        label: initialCheckpoint != null
            ? 'Prompt delta partiel'
            : 'Construction prompt lot',
        durationMs: promptWatch.elapsedMilliseconds,
        detail: '${turnPrompt.length} car.',
        scopeLabel: lotScopeLabel,
      );

      final generated = await _generateAndApply(
        turnPrompt,
        systemGuide: guide,
        session: session,
        attachments: sourceAttachments,
        allowPlan: false,
        promptBuilder: buildLotPrompt,
        traceScopeLabel: lotScopeLabel,
        phaseUiLabel: lotUiLabel,
        isIntermediatePlanLot: isIntermediateLot,
        preserveCheckpointOnFailure: true,
        initialCheckpoint: initialCheckpoint,
      );
      final hasMutations =
          generated.appearance != null || generated.repositoriesUpdated;
      if (!hasMutations) {
        await _rollbackTurnSession(session);
        session.turnStopwatch.stop();
        return (
          errorCause:
              'Le lot n’a produit aucune modification d’écran ("vibe" vide).',
          durationMs: session.turnStopwatch.elapsedMilliseconds,
          attempts: session.attemptsExecuted,
          traces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
          partialCheckpoint: null,
          wasCancelled: false,
        );
      }
      final commitWatch = Stopwatch()..start();
      var lotDiff = '';
      if (generated.appearance case final appearance?) {
        lotDiff = _describeAppearanceDiff(session.baseAppearance, appearance);
        widget.controller.value = appearance;
        if (mounted && fontManager != null && fontManager.autoDownloadEnabled) {
          unawaited(fontManager.ensureAppearanceFonts(appearance));
        }
        final committedAppearance = widget.controller.value;
        _pulseAppearanceDiff(session, committedAppearance);
        _syncLivePageOutcome(session, committedAppearance);
      } else {
        _rollbackLivePreview(session);
      }
      if (session.repoTransaction?.buildHistoryCallbacks()
          case final repoCallbacks?) {
        history?.addTransactionSideEffect(
          undo: repoCallbacks.undo,
          redo: repoCallbacks.redo,
        );
        (_planRepoCallbacks[messageIndex] ??=
                <VibeRepositoryHistoryCallbacks>[])
            .add(repoCallbacks);
      }
      commitWatch.stop();
      session.turnStopwatch.stop();
      debugPrint(
        '[Vibe IA][$lotScopeLabel] Terminé en '
        '${session.turnStopwatch.elapsedMilliseconds} ms '
        '(${session.attemptsExecuted} tentative(s), commit ${commitWatch.elapsedMilliseconds} ms'
        '${lotDiff.isEmpty ? '' : ', $lotDiff'}).',
      );
      return (
        errorCause: null,
        durationMs: session.turnStopwatch.elapsedMilliseconds,
        attempts: session.attemptsExecuted,
        traces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        partialCheckpoint: null,
        wasCancelled: false,
      );
    } on VibeCancelledException {
      await _rollbackTurnSession(session);
      session.turnStopwatch.stop();
      return (
        errorCause: 'Appel IA annulé par l’utilisateur.',
        durationMs: session.turnStopwatch.elapsedMilliseconds,
        attempts: session.attemptsExecuted,
        traces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        partialCheckpoint: null,
        wasCancelled: true,
      );
    } on FormatException catch (error) {
      await _rollbackTurnSession(session);
      session.turnStopwatch.stop();
      return (
        errorCause: _describeErrorCause(error),
        durationMs: session.turnStopwatch.elapsedMilliseconds,
        attempts: session.attemptsExecuted,
        traces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        partialCheckpoint: session.preservedFailureCheckpoint,
        wasCancelled: false,
      );
    } on ArgumentError catch (error) {
      await _rollbackTurnSession(session);
      session.turnStopwatch.stop();
      return (
        errorCause: _describeErrorCause(error),
        durationMs: session.turnStopwatch.elapsedMilliseconds,
        attempts: session.attemptsExecuted,
        traces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        partialCheckpoint: session.preservedFailureCheckpoint,
        wasCancelled: false,
      );
    } on StateError catch (error) {
      await _rollbackTurnSession(session);
      session.turnStopwatch.stop();
      return (
        errorCause: _describeErrorCause(error),
        durationMs: session.turnStopwatch.elapsedMilliseconds,
        attempts: session.attemptsExecuted,
        traces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        partialCheckpoint: session.preservedFailureCheckpoint,
        wasCancelled: false,
      );
    } on FlutterError catch (error) {
      await _rollbackTurnSession(session);
      session.turnStopwatch.stop();
      return (
        errorCause: _describeErrorCause(error),
        durationMs: session.turnStopwatch.elapsedMilliseconds,
        attempts: session.attemptsExecuted,
        traces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        partialCheckpoint: session.preservedFailureCheckpoint,
        wasCancelled: false,
      );
    } on Exception catch (error) {
      await _rollbackTurnSession(session);
      session.turnStopwatch.stop();
      return (
        errorCause: _describeErrorCause(error),
        durationMs: session.turnStopwatch.elapsedMilliseconds,
        attempts: session.attemptsExecuted,
        traces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        partialCheckpoint: session.preservedFailureCheckpoint,
        wasCancelled: false,
      );
    } catch (error) {
      await _rollbackTurnSession(session);
      session.turnStopwatch.stop();
      return (
        errorCause: _describeErrorCause(error),
        durationMs: session.turnStopwatch.elapsedMilliseconds,
        attempts: session.attemptsExecuted,
        traces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        partialCheckpoint: session.preservedFailureCheckpoint,
        wasCancelled: false,
      );
    } finally {
      session.disposePreviewTimer();
      VibeWorkHighlightController.instance.suppressAutoTabSwitch = false;
      VibeWorkHighlightController.instance.clearStreamingTargets();
      _activeTurnSession = null;
      _pendingSnapshot = null;
      _updateStreamingSnapshot(null);
      history?.commitTransaction();
      if (mounted) setState(() => _sending = false);
    }
  }

  static Map<String, dynamic> _reconcileParallelPatchAgainstAccumulated({
    required Appearance waveBase,
    required Appearance accumulated,
    required Map<String, dynamic> lotPatch,
    required AppearanceCodec codec,
  }) {
    if (accumulated == waveBase) return lotPatch;
    final baseJson = codec.toCompactJson(waveBase);
    final accJson = codec.toCompactJson(accumulated);
    final wrapsData = lotPatch['data'] is Map<String, dynamic>;
    final payload = wrapsData
        ? Map<String, dynamic>.of(lotPatch['data'] as Map<String, dynamic>)
        : Map<String, dynamic>.of(lotPatch);

    String? slotEntryId(Object? item) {
      if (item is String) return item;
      if (item is Map && item['id'] is String) return item['id'] as String;
      return null;
    }

    if (payload['pageCatalog'] case final Map<Object?, Object?> rawCatalog
        when rawCatalog['pages'] is List) {
      final basePages = (baseJson['pageCatalog'] is Map)
          ? ((baseJson['pageCatalog'] as Map)['pages'] as List? ?? const [])
          : const [];
      final accPages = (accJson['pageCatalog'] is Map)
          ? ((accJson['pageCatalog'] as Map)['pages'] as List? ?? const [])
          : const [];
      final baseIds = <String>{
        for (final p in basePages)
          if (p is Map && p['id'] is String) p['id'] as String,
      };
      final lotPages = List<Object?>.of(rawCatalog['pages'] as List);
      final lotIds = <String>{
        for (final p in lotPages)
          if (p is Map && p['id'] is String) p['id'] as String,
      };
      final lotPaths = <String>{
        for (final p in lotPages)
          if (p is Map && p['path'] is String) p['path'] as String,
      };
      final preserved = <Object?>[];
      for (final p in accPages) {
        if (p is! Map) continue;
        final pid = p['id'];
        final ppath = p['path'];
        if (pid is String &&
            !baseIds.contains(pid) &&
            !lotIds.contains(pid) &&
            (ppath is! String || !lotPaths.contains(ppath))) {
          preserved.add(p);
        }
      }
      if (preserved.isNotEmpty) {
        payload['pageCatalog'] = <String, Object?>{
          for (final e in rawCatalog.entries) '${e.key}': e.value,
          'pages': <Object?>[...preserved, ...lotPages],
        };
      }
    }

    if (payload['components'] case final Map<Object?, Object?> rawComps) {
      final baseComps = baseJson['components'] is Map
          ? baseJson['components'] as Map
          : const <Object?, Object?>{};
      final accComps = accJson['components'] is Map
          ? accJson['components'] as Map
          : const <Object?, Object?>{};
      Map<String, Object?>? updatedComps;

      for (final entry in rawComps.entries) {
        final compId = entry.key;
        final lotComp = entry.value;
        if (compId is! String ||
            lotComp is! Map ||
            !baseComps.containsKey(compId) ||
            accComps[compId] is! Map) {
          continue;
        }
        final baseComp = baseComps[compId] as Map;
        final accComp = accComps[compId] as Map;
        if (lotComp['placements'] is! Map || accComp['placements'] is! Map) {
          continue;
        }
        final basePlacements = baseComp['placements'] is Map
            ? baseComp['placements'] as Map
            : const <Object?, Object?>{};
        final accPlacements = accComp['placements'] as Map;
        final lotPlacements = Map<String, Object?>.fromEntries(
          (lotComp['placements'] as Map).entries.map(
            (e) => MapEntry('${e.key}', e.value),
          ),
        );
        final accLabels = accComp['slotLabels'] is Map
            ? accComp['slotLabels'] as Map
            : const <Object?, Object?>{};
        Map<String, Object?>? mergedLabels;
        var changed = false;

        for (final zEntry in accPlacements.entries) {
          final zone = '${zEntry.key}';
          final accList = zEntry.value;
          if (accList is! List) continue;
          final baseZoneIds = <String>{
            if (basePlacements[zone] case final List<Object?> bList)
              for (final item in bList)
                if (slotEntryId(item) case final String id) id,
          };
          final currentLotZone = lotPlacements[zone] is List
              ? List<Object?>.of(lotPlacements[zone] as List)
              : <Object?>[];
          final lotZoneIds = <String>{
            for (final item in currentLotZone)
              if (slotEntryId(item) case final String id) id,
          };
          final toPreserve = <Object?>[];
          for (final item in accList) {
            final id = slotEntryId(item);
            if (id != null &&
                !baseZoneIds.contains(id) &&
                !lotZoneIds.contains(id)) {
              toPreserve.add(item);
              if (accLabels[id] case final String lbl when lbl.isNotEmpty) {
                mergedLabels ??= <String, Object?>{
                  if (lotComp['slotLabels'] case final Map<Object?, Object?> m)
                    for (final le in m.entries) '${le.key}': le.value,
                };
                mergedLabels.putIfAbsent(id, () => lbl);
              }
            }
          }
          if (toPreserve.isNotEmpty) {
            lotPlacements[zone] = <Object?>[...currentLotZone, ...toPreserve];
            changed = true;
          }
        }

        if (changed) {
          updatedComps ??= <String, Object?>{
            for (final ce in rawComps.entries) '${ce.key}': ce.value,
          };
          updatedComps[compId] = <String, Object?>{
            for (final ce in lotComp.entries) '${ce.key}': ce.value,
            'placements': lotPlacements,
            'slotLabels': ?mergedLabels,
          };
        }
      }

      if (updatedComps != null) {
        payload['components'] = updatedComps;
      }
    }

    return wrapsData
        ? <String, dynamic>{...lotPatch, 'data': payload}
        : payload;
  }

  Future<
    Map<
      int,
      ({
        String? errorCause,
        int durationMs,
        int attempts,
        List<VibeTimedTrace> traces,
        _LotPartialCheckpoint? partialCheckpoint,
        bool wasCancelled,
      })
    >
  >
  _executeParallelLotWave(int messageIndex, List<int> waveIndices) async {
    final planMessage = _messages[messageIndex];
    final plan = planMessage.plan!;
    final history = EditorHistoryScope.controllerOf(context);
    final resolvedPageRouting =
        widget.pageRouting ?? SuperApp.maybeOf(context)?.pageRouting;
    final resolvedRepositoryStore = _resolveRepositoryStore();
    if (widget.controller case final PersistentAppearanceController persistent
        when persistent.hasUnloadedCatalogPages) {
      await persistent.ensureAllPagesLoaded();
      if (!mounted) {
        return {
          for (final idx in waveIndices)
            idx: (
              errorCause: 'Composant démonté.',
              durationMs: 0,
              attempts: 0,
              traces: const <VibeTimedTrace>[],
              partialCheckpoint: null,
              wasCancelled: true,
            ),
        };
      }
    }

    final rawInitialAppearance = widget.controller.value;
    final waveBaseAppearance = _currentAppearance;
    final initialInstantiatedIds = widget.registry == null
        ? null
        : Set<String>.unmodifiable(widget.registry!.instantiatedComponentIds);
    final initialPageIds = <String>{
      for (final page in waveBaseAppearance.pageCatalog.pages) page.id,
    };
    final visibleSnapshot = _visibleOnlyMode
        ? _captureVisibleViewportSnapshot(waveBaseAppearance)
        : null;

    final guideBundle = DefaultAssetBundle.of(context);
    final fontManager = DynamicFontScope.readOf(context);
    final sourcePrompt = planMessage.planSourcePrompt ?? '';
    final sourceAttachments = planMessage.planSourceAttachments;

    final guide = await VibeChatDialog.loadStaticGuide(
      guideBundle,
      designSystemPreset: _selectedDesignSystem,
      customDesignGuide: widget.customDesignGuide,
      replaceDefaultDesignGuide: widget.replaceDefaultDesignGuide,
    );
    final repositoriesContext = resolvedRepositoryStore == null
        ? null
        : await VibeRepositoryPromptFormatter.formatStoreContext(
            resolvedRepositoryStore,
          );
    final codedRoutePaths = resolvedPageRouting == null
        ? const <String>[]
        : <String>[
            for (final route in resolvedPageRouting.codedRoutes) route.path,
          ];
    final mountedSummaries = VibeMountedSlotIndex.instance
        .mountedSlotSummaries();

    final waveStopwatch = Stopwatch()..start();
    final sessionsByIndex = <int, _LiveTurnSession>{};
    final activeWaveLots = <int>{...waveIndices};
    final completedWavePatches = <int, Map<String, dynamic>>{};
    final failedWaveLots = <int>{};
    final lastAppliedRepoRevisions = <int, int>{};

    int? focusedLotIndex = waveIndices.first;
    int? lastTrackedFocusedLot = focusedLotIndex;
    var focusedLotHasNavigatedVisual = false;
    final waveInitialRouteLocation = resolvedPageRouting?.currentUri.toString();
    var lastExpectedRouteLocation = waveInitialRouteLocation;
    var userOverrodeWaveNavigation = false;
    var waveDidAutoNavigate = false;

    var waveClosed = false;
    var waveUiFrameScheduled = false;
    var wavePreviewStepCount = 0;
    var waveSuppressedPreviewLogCount = 0;
    int? lastWavePreviewApplyElapsedMs;
    String? lastWaveNonUsagesSignature;
    final cachedWavePrefixSteps =
        <({int lotIdx, String lotToken, Appearance composed})>[];
    int? lastWaveHighlightFocusLot;
    String? lastWaveHighlightSection;
    String? lastWaveHighlightKey;
    Appearance? lastWaveHighlightAppearance;
    Timer? waveDeferredPreviewTimer;
    Future<void> waveRepoQueue = Future<void>.value();
    var lastWavePreviewAppearance = waveBaseAppearance;
    var waveHasAppliedPreview = false;

    void checkManualRouteOverride() {
      if (_visibleOnlyMode ||
          resolvedPageRouting == null ||
          userOverrodeWaveNavigation) {
        return;
      }
      final currentLoc = resolvedPageRouting.currentUri.toString();
      if (lastExpectedRouteLocation != null &&
          currentLoc != lastExpectedRouteLocation) {
        userOverrodeWaveNavigation = true;
        debugPrint(
          '[Vibe IA][Plan][Parallèle] Navigation manuelle détectée ($currentLoc) — maintien du choix utilisateur sur cette vague.',
        );
      }
    }

    void navigateWaveToTarget(
      VibeStepNavigationDecision decision,
      Appearance appearance,
    ) {
      if (_visibleOnlyMode ||
          resolvedPageRouting == null ||
          userOverrodeWaveNavigation) {
        return;
      }
      checkManualRouteOverride();
      if (userOverrodeWaveNavigation) return;
      if (decision.isVisualChange) {
        focusedLotHasNavigatedVisual = true;
      }
      final navigated = VibeLivePageRouter.navigateToTarget(
        routing: resolvedPageRouting,
        appearance: appearance,
        target: decision.target,
      );
      if (navigated) {
        waveDidAutoNavigate = true;
        lastExpectedRouteLocation = resolvedPageRouting.currentUri.toString();
      }
    }

    String buildWavePhaseLabel() {
      final runningNumbers = [
        for (final idx in waveIndices)
          if (activeWaveLots.contains(idx)) idx + 1,
      ];
      final base = runningNumbers.isEmpty
          ? 'Finalisation vague parallèle'
          : 'Lots en parallèle (${runningNumbers.join(', ')}/${plan.lots.length})';
      if (focusedLotIndex != null && activeWaveLots.length >= 2) {
        return '$base · focus Lot ${focusedLotIndex! + 1}';
      }
      return base;
    }

    void publishAggregatedWaveSnapshotNow() {
      if (_disposed || !mounted || waveClosed) return;
      var totalComponents = 0;
      var totalChars = 0;
      var anyHasVibe = false;
      var anyHasRepo = false;
      String? activeToolStatus;
      final allToolTraces = <VibeToolTrace>[];

      for (final idx in waveIndices) {
        final s = sessionsByIndex[idx]!;
        final snap = s.lastStreamSnapshot;
        if (snap != null) {
          totalComponents += snap.estimatedComponentCount;
          totalChars += snap.receivedChars;
          if (snap.hasVibeObject) anyHasVibe = true;
          if (snap.hasRepositoriesObject) anyHasRepo = true;
          if (activeToolStatus == null &&
              activeWaveLots.contains(idx) &&
              snap.activeToolStatus != null &&
              snap.activeToolStatus!.isNotEmpty) {
            activeToolStatus = 'Lot ${idx + 1} : ${snap.activeToolStatus!}';
          }
        }
        allToolTraces.addAll(s.toolTraces);
      }

      final focusSnap = focusedLotIndex != null
          ? sessionsByIndex[focusedLotIndex!]?.lastStreamSnapshot
          : null;
      final aggregated = VibeStreamSnapshot(
        message: focusSnap?.message,
        isMessageComplete: focusSnap?.isMessageComplete ?? false,
        hasVibeObject: anyHasVibe,
        hasRepositoriesObject: anyHasRepo,
        estimatedComponentCount: totalComponents,
        receivedChars: totalChars,
        activeSection: focusSnap?.activeSection,
        activeEntryKey: focusSnap?.activeEntryKey,
        activeToolStatus: activeToolStatus,
        toolTraces: List<VibeToolTrace>.unmodifiable(allToolTraces),
        elapsedMs: waveStopwatch.elapsedMilliseconds,
        activePhaseLabel: buildWavePhaseLabel(),
      );
      _updateStreamingSnapshot(aggregated);
      if (anyHasVibe || anyHasRepo) {
        _setExpanded(false);
      }
    }

    void scheduleAggregatedWaveUiUpdate() {
      if (_disposed || waveClosed) return;
      if (!waveUiFrameScheduled) {
        publishAggregatedWaveSnapshotNow();
        if (_isWidgetTestBinding) return;
        waveUiFrameScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          waveUiFrameScheduled = false;
          if (!_disposed && mounted && !waveClosed) {
            publishAggregatedWaveSnapshotNow();
          }
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    }

    void syncWaveStreamingHighlights() {
      const highlightSections = <String>{
        'components',
        'styles',
        'behaviors',
        'usages',
      };
      final activeKeys = <String>[];
      for (final idx in waveIndices) {
        if (!activeWaveLots.contains(idx)) continue;
        final snap = sessionsByIndex[idx]?.lastStreamSnapshot;
        final key = snap?.activeEntryKey;
        final section = snap?.activeSection;
        if (key != null &&
            key.isNotEmpty &&
            section != null &&
            highlightSections.contains(section) &&
            !activeKeys.contains(key)) {
          activeKeys.add(key);
        }
      }
      if (activeKeys.isEmpty) {
        VibeWorkHighlightController.instance.clearStreamingTargets();
      } else {
        VibeWorkHighlightController.instance.setStreamingTargets(activeKeys);
      }

      // Navigation anticipée sur l'entrée en cours du lot focalisé uniquement.
      if (!_visibleOnlyMode &&
          resolvedPageRouting != null &&
          !userOverrodeWaveNavigation &&
          focusedLotIndex != null) {
        final focusSnap = sessionsByIndex[focusedLotIndex!]?.lastStreamSnapshot;
        final focusKey = focusSnap?.activeEntryKey;
        final focusSec = focusSnap?.activeSection;
        if (focusKey != null &&
            focusKey.isNotEmpty &&
            focusSec != null &&
            highlightSections.contains(focusSec) &&
            (lastWaveHighlightFocusLot != focusedLotIndex ||
                lastWaveHighlightSection != focusSec ||
                lastWaveHighlightKey != focusKey ||
                !identical(
                  lastWaveHighlightAppearance,
                  lastWavePreviewAppearance,
                ))) {
          lastWaveHighlightFocusLot = focusedLotIndex;
          lastWaveHighlightSection = focusSec;
          lastWaveHighlightKey = focusKey;
          lastWaveHighlightAppearance = lastWavePreviewAppearance;
          final decision = VibeLivePageRouter.resolveForStreamingEntry(
            routing: resolvedPageRouting,
            appearance: lastWavePreviewAppearance,
            activeSection: focusSec,
            activeEntryKey: focusKey,
            initialPageIds: initialPageIds,
            hasNavigatedForVisualChange: focusedLotHasNavigatedVisual,
          );
          if (decision != null) {
            navigateWaveToTarget(decision, lastWavePreviewAppearance);
          }
        }
      }
    }

    void composeAndApplyWavePreviewSync({bool forceRouteCheck = false}) {
      if (_disposed || !mounted || waveClosed || _planStopRequested) return;
      syncWaveStreamingHighlights();

      final activeScope = _scope;
      final collectedPatches =
          <({int lotIdx, String lotToken, Map<String, dynamic> patch})>[];
      for (final idx in waveIndices) {
        if (failedWaveLots.contains(idx)) continue;
        Map<String, dynamic>? candidatePatch;
        String lotToken;
        if (completedWavePatches.containsKey(idx)) {
          candidatePatch = completedWavePatches[idx];
          lotToken = 'done:$idx';
        } else {
          final session = sessionsByIndex[idx]!;
          final snap = session.lastStreamSnapshot;
          final snapPatch = snap?.partialVibePatch;
          if (snap == null || snapPatch == null) continue;
          final nonUsagesRev = snap.nonUsagesPatchRevision;
          if (nonUsagesRev == 0 &&
              snap.patchEntries.isNotEmpty &&
              snap.patchEntries.every((e) => e.isUsageEntry)) {
            continue;
          }
          final aliasMap =
              session.repoTransaction?.aliasToActualId ??
              const <String, String>{};
          lotToken = 'stream:$nonUsagesRev:${aliasMap.length}';
          if (aliasMap.isNotEmpty) {
            final applier = session.previewApplier ??=
                VibeIncrementalPreviewApplier(
                  baseAppearance: waveBaseAppearance,
                  codec: widget.codec,
                );
            candidatePatch = applier.buildEffectiveCumulativePatch(
              snapshot: snap,
              aliasToActualId: aliasMap,
            );
          } else {
            candidatePatch = snapPatch;
          }
        }
        if (candidatePatch == null) continue;
        var filtered = activeScope == null
            ? candidatePatch
            : VibeChatDialog.filterPatchToScope(
                waveBaseAppearance,
                candidatePatch,
                activeScope,
              );
        if (_visibleOnlyMode && visibleSnapshot != null) {
          filtered = VibeScopeHelpers.filterPatchToVisibleViewport(
            waveBaseAppearance,
            filtered,
            visibleSnapshot,
          );
        }
        if (_hasPatchChanges(filtered)) {
          collectedPatches.add((
            lotIdx: idx,
            lotToken: lotToken,
            patch: filtered,
          ));
        }
      }
      if (collectedPatches.isEmpty) return;

      final focusChanged = lastTrackedFocusedLot != focusedLotIndex;
      lastTrackedFocusedLot = focusedLotIndex;
      final combinedSig = [
        for (final item in collectedPatches) '${item.lotIdx}:${item.lotToken}',
      ].join('|');
      if (!forceRouteCheck &&
          !focusChanged &&
          combinedSig == lastWaveNonUsagesSignature) {
        return;
      }
      lastWaveNonUsagesSignature = combinedSig;
      lastWavePreviewApplyElapsedMs = waveStopwatch.elapsedMilliseconds;

      var composed = waveBaseAppearance;
      Appearance? beforeFocusedAppearance;
      Appearance? afterFocusedAppearance;
      Map<String, dynamic>? focusedReconciledPatch;
      var appliedAny = false;
      var rejectedCount = 0;

      var reuseCount = 0;
      while (reuseCount < cachedWavePrefixSteps.length &&
          reuseCount < collectedPatches.length) {
        final cached = cachedWavePrefixSteps[reuseCount];
        final target = collectedPatches[reuseCount];
        if (cached.lotIdx != target.lotIdx ||
            cached.lotToken != target.lotToken ||
            target.lotIdx == focusedLotIndex) {
          break;
        }
        composed = cached.composed;
        reuseCount++;
      }
      if (cachedWavePrefixSteps.length > reuseCount) {
        cachedWavePrefixSteps.removeRange(
          reuseCount,
          cachedWavePrefixSteps.length,
        );
      }

      for (var i = reuseCount; i < collectedPatches.length; i++) {
        final item = collectedPatches[i];
        final reconciled = _reconcileParallelPatchAgainstAccumulated(
          waveBase: waveBaseAppearance,
          accumulated: composed,
          lotPatch: item.patch,
          codec: widget.codec,
        );
        if (item.lotIdx == focusedLotIndex) {
          beforeFocusedAppearance = composed;
          focusedReconciledPatch = reconciled;
        }
        try {
          final partial = AppearanceTransfer.applyVibeMapPartial(
            composed,
            reconciled,
            codec: widget.codec,
          );
          rejectedCount += partial.rejectedEntries.length;
          var candidate = partial.appearance;
          if (widget.validateAppearance != null) {
            try {
              widget.validateAppearance!(candidate);
            } catch (_) {
              if (candidate.pageCatalog != composed.pageCatalog) {
                candidate = candidate.copyWith(
                  pageCatalog: composed.pageCatalog,
                );
                widget.validateAppearance!(candidate);
              } else {
                rethrow;
              }
            }
          }
          composed = candidate;
          if (partial.hasAppliedEntries) {
            appliedAny = true;
          }
        } on FormatException {
          // Conserve l'aperçu des lots valides pendant le streaming partiel.
        } on ArgumentError {
          // Conserve l'aperçu des lots valides pendant le streaming partiel.
        } on StateError {
          // Conserve l'aperçu des lots valides pendant le streaming partiel.
        }
        if (item.lotIdx == focusedLotIndex) {
          afterFocusedAppearance = composed;
        }
        cachedWavePrefixSteps.add((
          lotIdx: item.lotIdx,
          lotToken: item.lotToken,
          composed: composed,
        ));
      }

      if (!appliedAny &&
          composed == lastWavePreviewAppearance &&
          !forceRouteCheck &&
          !focusChanged) {
        return;
      }

      final prevWavePreview = lastWavePreviewAppearance;
      if (composed != prevWavePreview) {
        _setPreviewAppearance(composed);
        final appliedAppearance = widget.controller.value;
        final diff = VibeAppearanceDiff.compute(
          prevWavePreview,
          appliedAppearance,
        );
        lastWavePreviewAppearance = appliedAppearance;
        waveHasAppliedPreview = true;
        if (!diff.isEmpty) {
          VibeWorkHighlightController.instance.pulseTargets(
            addedIds: diff.addedIds,
            modifiedIds: diff.modifiedIds,
          );
        }
        wavePreviewStepCount++;
        if (!_effectiveThrottlePreviewLogs ||
            wavePreviewStepCount == 1 ||
            rejectedCount > 0) {
          final diffDesc = _describeAppearanceDiff(
            prevWavePreview,
            appliedAppearance,
          );
          debugPrint(
            '[Vibe IA][Preview][Parallèle] Palier #$wavePreviewStepCount '
            '(lots: ${collectedPatches.map((e) => e.lotIdx + 1).toList()}'
            '${focusedLotIndex != null ? ", focus=${focusedLotIndex! + 1}" : ""}) -> '
            '${diffDesc.isEmpty ? "aucun delta" : diffDesc}',
          );
        } else {
          waveSuppressedPreviewLogCount++;
        }
      }

      if (!_visibleOnlyMode &&
          resolvedPageRouting != null &&
          !userOverrodeWaveNavigation &&
          focusedLotIndex != null &&
          focusedReconciledPatch != null) {
        final decision = VibeLivePageRouter.resolveForPreviewStep(
          routing: resolvedPageRouting,
          previousAppearance: beforeFocusedAppearance ?? waveBaseAppearance,
          nextAppearance: afterFocusedAppearance ?? lastWavePreviewAppearance,
          effectivePatch: focusedReconciledPatch,
          initialPageIds: initialPageIds,
          hasNavigatedForVisualChange: focusedLotHasNavigatedVisual,
        );
        if (decision != null) {
          navigateWaveToTarget(decision, lastWavePreviewAppearance);
        }
      }
    }

    void scheduleWavePreview({
      bool immediate = false,
      bool forceRouteCheck = false,
    }) {
      if (_disposed || !mounted || waveClosed || _planStopRequested) return;
      if (!immediate &&
          !_isWidgetTestBinding &&
          lastWavePreviewApplyElapsedMs != null) {
        final elapsed = waveStopwatch.elapsedMilliseconds;
        final minIntervalMs =
            VibeChatDialog.livePreviewMinInterval.inMilliseconds;
        final deltaMs = elapsed - lastWavePreviewApplyElapsedMs!;
        if (deltaMs < minIntervalMs) {
          syncWaveStreamingHighlights();
          waveDeferredPreviewTimer ??= Timer(
            Duration(milliseconds: minIntervalMs - deltaMs),
            () {
              waveDeferredPreviewTimer = null;
              scheduleWavePreview(
                immediate: true,
                forceRouteCheck: forceRouteCheck,
              );
            },
          );
          return;
        }
      }
      waveDeferredPreviewTimer?.cancel();
      waveDeferredPreviewTimer = null;

      // Applique d'abord dans l'ordre les éventuels patches partiels de repositories.
      var hasPendingRepoStep = false;
      for (final idx in waveIndices) {
        if (failedWaveLots.contains(idx)) continue;
        final session = sessionsByIndex[idx]!;
        final snap = session.lastStreamSnapshot;
        final repoTx = session.repoTransaction;
        if (repoTx != null &&
            snap?.partialRepositoriesPatch != null &&
            snap!.repositoriesRevision > (lastAppliedRepoRevisions[idx] ?? 0)) {
          hasPendingRepoStep = true;
          break;
        }
      }

      if (hasPendingRepoStep) {
        waveRepoQueue = waveRepoQueue
            .then((_) async {
              if (_disposed || !mounted || waveClosed || _planStopRequested) {
                return;
              }
              for (final idx in waveIndices) {
                if (failedWaveLots.contains(idx)) continue;
                final session = sessionsByIndex[idx]!;
                final snap = session.lastStreamSnapshot;
                final repoTx = session.repoTransaction;
                final prevRev = lastAppliedRepoRevisions[idx] ?? 0;
                if (repoTx != null &&
                    snap?.partialRepositoriesPatch != null &&
                    snap!.repositoriesRevision > prevRev) {
                  lastAppliedRepoRevisions[idx] = snap.repositoriesRevision;
                  try {
                    await repoTx.applyRepositoriesPatchPartial(
                      snap.partialRepositoriesPatch!,
                    );
                  } catch (_) {
                    // Ignoré jusqu'à la validation finale du lot.
                  }
                }
              }
              composeAndApplyWavePreviewSync(forceRouteCheck: forceRouteCheck);
            })
            .catchError((Object _) {});
      } else {
        composeAndApplyWavePreviewSync(forceRouteCheck: forceRouteCheck);
      }
    }

    void advanceFocusAfterLotFinished(
      int finishedLotIdx, {
      required bool succeeded,
    }) {
      activeWaveLots.remove(finishedLotIdx);
      if (!succeeded) {
        failedWaveLots.add(finishedLotIdx);
      }
      if (focusedLotIndex == finishedLotIdx) {
        int? nextFocus;
        for (final idx in waveIndices) {
          if (activeWaveLots.contains(idx)) {
            nextFocus = idx;
            break;
          }
        }
        focusedLotIndex = nextFocus;
        focusedLotHasNavigatedVisual = false;
        if (nextFocus != null) {
          debugPrint(
            '[Vibe IA][Plan][Parallèle] Lot ${finishedLotIdx + 1} terminé — bascule du suivi live sur Lot ${nextFocus + 1}.',
          );
        }
      }
      scheduleAggregatedWaveUiUpdate();
      scheduleWavePreview(immediate: true, forceRouteCheck: true);
    }

    for (final idx in waveIndices) {
      final session =
          _LiveTurnSession(
              rawInitialAppearance: rawInitialAppearance,
              baseAppearance: waveBaseAppearance,
              initialInstantiatedIds: initialInstantiatedIds,
              pageRouting: resolvedPageRouting,
              initialRouteLocation: waveInitialRouteLocation,
              initialPageIds: initialPageIds,
              repoTransaction: resolvedRepositoryStore == null
                  ? null
                  : VibeRepositoryTurnTransaction(resolvedRepositoryStore),
              visibleViewportSnapshot: visibleSnapshot,
            )
            ..suppressUiUpdates = true
            ..livePreviewDisabled = true;
      session.onStreamProgress = (_) {
        scheduleAggregatedWaveUiUpdate();
        scheduleWavePreview();
      };
      sessionsByIndex[idx] = session;
      _activeParallelSessions.add(session);
    }

    debugPrint(
      '[Vibe IA][Plan][Parallèle] Démarrage vague de ${waveIndices.length} lots : '
      '${waveIndices.map((idx) => '[${idx + 1}/${plan.lots.length}] "${plan.lots[idx].title}"').join(', ')}',
    );
    setState(() => _sending = true);
    _updateStreamingSnapshot(
      VibeStreamSnapshot(activePhaseLabel: buildWavePhaseLabel()),
    );

    Future<
      ({
        int lotIndex,
        Map<String, dynamic>? effectivePatch,
        Appearance? appearance,
        bool repositoriesUpdated,
        String? errorCause,
        int durationMs,
        int attempts,
        List<VibeTimedTrace> traces,
        _LotPartialCheckpoint? partialCheckpoint,
        bool wasCancelled,
      })
    >
    runOne(int lotIndex) async {
      final session = sessionsByIndex[lotIndex]!;
      final lotScopeLabel = 'Plan][Lot ${lotIndex + 1}/${plan.lots.length}';
      final lotUiLabel =
          'Lot ${lotIndex + 1}/${plan.lots.length} : ${plan.lots[lotIndex].title}';
      try {
        if (_planStopRequested) {
          session.cancellationToken.cancel();
        }
        session.cancellationToken.throwIfCancelled();
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
          mountedSlotSummaries: mountedSummaries,
          codedRoutePaths: codedRoutePaths,
          repositoriesContext: repositoriesContext,
          visibleOnlyMode: _visibleOnlyMode,
          visibleViewportContext: visibleSnapshot?.toPromptContext(),
        );
        final promptWatch = Stopwatch()..start();
        final turnPrompt = buildLotPrompt(
          appearanceOverride: session.baseAppearance,
          instantiatedIdsOverride: session.initialInstantiatedIds,
          repositoriesContext: repositoriesContext,
        );
        promptWatch.stop();
        _recordTimedTrace(
          session,
          phase: 'context',
          label: 'Construction prompt lot',
          durationMs: promptWatch.elapsedMilliseconds,
          detail: '${turnPrompt.length} car.',
          scopeLabel: lotScopeLabel,
        );

        final generated = await _generateAndApply(
          turnPrompt,
          systemGuide: guide,
          session: session,
          attachments: sourceAttachments,
          allowPlan: false,
          promptBuilder: buildLotPrompt,
          traceScopeLabel: lotScopeLabel,
          phaseUiLabel: lotUiLabel,
          isIntermediatePlanLot: true,
          preserveCheckpointOnFailure: true,
        );
        final hasMutations =
            generated.appearance != null || generated.repositoriesUpdated;
        if (!hasMutations) {
          await session.repoTransaction?.rollback();
          session.turnStopwatch.stop();
          advanceFocusAfterLotFinished(lotIndex, succeeded: false);
          return (
            lotIndex: lotIndex,
            effectivePatch: null,
            appearance: null,
            repositoriesUpdated: false,
            errorCause:
                'Le lot n’a produit aucune modification d’écran ("vibe" vide).',
            durationMs: session.turnStopwatch.elapsedMilliseconds,
            attempts: session.attemptsExecuted,
            traces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
            partialCheckpoint: null,
            wasCancelled: false,
          );
        }
        if (session.lastAppliedEffectivePatch != null) {
          completedWavePatches[lotIndex] = session.lastAppliedEffectivePatch!;
        }
        session.turnStopwatch.stop();
        advanceFocusAfterLotFinished(lotIndex, succeeded: true);
        return (
          lotIndex: lotIndex,
          effectivePatch: session.lastAppliedEffectivePatch,
          appearance: generated.appearance,
          repositoriesUpdated: generated.repositoriesUpdated,
          errorCause: null,
          durationMs: session.turnStopwatch.elapsedMilliseconds,
          attempts: session.attemptsExecuted,
          traces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
          partialCheckpoint: null,
          wasCancelled: false,
        );
      } on VibeCancelledException {
        await session.repoTransaction?.rollback();
        session.turnStopwatch.stop();
        advanceFocusAfterLotFinished(lotIndex, succeeded: false);
        return (
          lotIndex: lotIndex,
          effectivePatch: null,
          appearance: null,
          repositoriesUpdated: false,
          errorCause: 'Appel IA annulé par l’utilisateur.',
          durationMs: session.turnStopwatch.elapsedMilliseconds,
          attempts: session.attemptsExecuted,
          traces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
          partialCheckpoint: null,
          wasCancelled: true,
        );
      } catch (error) {
        await session.repoTransaction?.rollback();
        session.turnStopwatch.stop();
        advanceFocusAfterLotFinished(lotIndex, succeeded: false);
        return (
          lotIndex: lotIndex,
          effectivePatch: null,
          appearance: null,
          repositoriesUpdated: false,
          errorCause: _describeErrorCause(error),
          durationMs: session.turnStopwatch.elapsedMilliseconds,
          attempts: session.attemptsExecuted,
          traces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
          partialCheckpoint: session.preservedFailureCheckpoint,
          wasCancelled: session.cancellationToken.isCancelled,
        );
      }
    }

    history?.beginTransaction();
    try {
      final rawResults = await Future.wait([
        for (final idx in waveIndices) runOne(idx),
      ]);
      waveClosed = true;
      waveDeferredPreviewTimer?.cancel();
      waveDeferredPreviewTimer = null;
      if (waveSuppressedPreviewLogCount > 0) {
        debugPrint(
          '[Vibe IA][Preview][Parallèle] Bilan streaming : $wavePreviewStepCount '
          'palier(s) appliqué(s) ($waveSuppressedPreviewLogCount intermédiaire(s) regroupé(s)).',
        );
      }
      try {
        await waveRepoQueue;
      } catch (_) {}

      final finalOutcomes =
          <
            int,
            ({
              String? errorCause,
              int durationMs,
              int attempts,
              List<VibeTimedTrace> traces,
              _LotPartialCheckpoint? partialCheckpoint,
              bool wasCancelled,
            })
          >{};

      var accumulatedAppearance = waveBaseAppearance;
      var anyAppearanceApplied = false;
      int? lastSucceededLotIndex;

      for (final res in rawResults) {
        final idx = res.lotIndex;
        final session = sessionsByIndex[idx]!;
        if (res.errorCause != null) {
          finalOutcomes[idx] = (
            errorCause: res.errorCause,
            durationMs: res.durationMs,
            attempts: res.attempts,
            traces: res.traces,
            partialCheckpoint: res.partialCheckpoint,
            wasCancelled: res.wasCancelled,
          );
          continue;
        }

        try {
          if (res.effectivePatch != null) {
            final reconciled = _reconcileParallelPatchAgainstAccumulated(
              waveBase: waveBaseAppearance,
              accumulated: accumulatedAppearance,
              lotPatch: res.effectivePatch!,
              codec: widget.codec,
            );
            var nextAppearance = AppearanceTransfer.applyVibe(
              accumulatedAppearance,
              jsonEncode(reconciled),
              codec: widget.codec,
            );
            nextAppearance = _inferMissingDefaultUsages(
              accumulatedAppearance,
              nextAppearance,
              reconciled,
            );
            widget.validateAppearance?.call(nextAppearance);
            accumulatedAppearance = nextAppearance;
            anyAppearanceApplied = true;
            lastSucceededLotIndex = idx;
          } else if (res.appearance != null && !anyAppearanceApplied) {
            accumulatedAppearance = res.appearance!;
            anyAppearanceApplied = true;
            lastSucceededLotIndex = idx;
          }

          if (session.repoTransaction?.buildHistoryCallbacks()
              case final repoCallbacks?) {
            history?.addTransactionSideEffect(
              undo: repoCallbacks.undo,
              redo: repoCallbacks.redo,
            );
            (_planRepoCallbacks[messageIndex] ??=
                    <VibeRepositoryHistoryCallbacks>[])
                .add(repoCallbacks);
          }

          debugPrint(
            '[Vibe IA][Plan][Lot ${idx + 1}/${plan.lots.length}] Terminé en '
            '${res.durationMs} ms (${res.attempts} tentative(s), vague parallèle).',
          );
          finalOutcomes[idx] = (
            errorCause: null,
            durationMs: res.durationMs,
            attempts: res.attempts,
            traces: res.traces,
            partialCheckpoint: null,
            wasCancelled: false,
          );
        } catch (mergeError) {
          await session.repoTransaction?.rollback();
          finalOutcomes[idx] = (
            errorCause: _describeErrorCause(mergeError),
            durationMs: res.durationMs,
            attempts: res.attempts,
            traces: res.traces,
            partialCheckpoint: null,
            wasCancelled: false,
          );
        }
      }

      if (anyAppearanceApplied && mounted) {
        checkManualRouteOverride();
        final prevAppearance = lastWavePreviewAppearance;
        widget.controller.value = accumulatedAppearance;
        if (fontManager != null && fontManager.autoDownloadEnabled) {
          unawaited(fontManager.ensureAppearanceFonts(accumulatedAppearance));
        }
        final committed = widget.controller.value;
        final finalDiff = VibeAppearanceDiff.compute(prevAppearance, committed);
        if (!finalDiff.isEmpty) {
          VibeWorkHighlightController.instance.pulseTargets(
            addedIds: finalDiff.addedIds,
            modifiedIds: finalDiff.modifiedIds,
          );
        }
        if (resolvedPageRouting != null) {
          try {
            resolvedPageRouting.synchronize(committed.pageCatalog);
          } on FormatException {
            // Ignoré si le catalogue n'a pas changé ou contient un paramètre externe.
          }
          if (!_visibleOnlyMode &&
              !userOverrodeWaveNavigation &&
              !waveDidAutoNavigate &&
              lastSucceededLotIndex != null) {
            _syncLivePageOutcome(
              sessionsByIndex[lastSucceededLotIndex]!,
              committed,
            );
          }
        }
      } else if (mounted &&
          (waveHasAppliedPreview ||
              !identical(widget.controller.value, rawInitialAppearance))) {
        VibeWorkHighlightController.instance.clearAll();
        try {
          _setPreviewAppearance(rawInitialAppearance);
        } catch (_) {}
        if (waveDidAutoNavigate && resolvedPageRouting != null) {
          try {
            if (waveInitialRouteLocation != null &&
                waveInitialRouteLocation.isNotEmpty &&
                resolvedPageRouting.currentUri.toString() !=
                    waveInitialRouteLocation) {
              resolvedPageRouting.restoreLocation(waveInitialRouteLocation);
            }
            resolvedPageRouting.synchronize(rawInitialAppearance.pageCatalog);
            if (waveInitialRouteLocation != null &&
                waveInitialRouteLocation.isNotEmpty &&
                resolvedPageRouting.currentUri.toString() !=
                    waveInitialRouteLocation) {
              resolvedPageRouting.openLocation(waveInitialRouteLocation);
            }
          } catch (_) {}
        }
      }

      return finalOutcomes;
    } finally {
      waveClosed = true;
      waveDeferredPreviewTimer?.cancel();
      waveDeferredPreviewTimer = null;
      waveStopwatch.stop();
      VibeWorkHighlightController.instance.clearStreamingTargets();
      for (final s in sessionsByIndex.values) {
        s.onStreamProgress = null;
        s.disposePreviewTimer();
        _activeParallelSessions.remove(s);
      }
      _pendingSnapshot = null;
      _updateStreamingSnapshot(null);
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

  Future<T> _awaitCancellable<T>(
    Future<T> future,
    VibeCancellationToken? cancellationToken,
  ) {
    if (cancellationToken == null) return future;
    cancellationToken.throwIfCancelled();
    final completer = Completer<T>();
    final removeListener = cancellationToken.addListener(() {
      if (!completer.isCompleted) {
        completer.completeError(const VibeCancelledException());
      }
    });
    future.then(
      (value) {
        removeListener();
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        removeListener();
        if (!completer.isCompleted) {
          completer.completeError(
            cancellationToken.isCancelled
                ? const VibeCancelledException()
                : error,
            stackTrace,
          );
        }
      },
    );
    return completer.future;
  }

  Future<String> _invokeGenerate(
    String prompt,
    List<VibeChatAttachment> attachments, {
    VibeCancellationToken? cancellationToken,
  }) {
    final generator = widget.generate;
    final Future<String> future;
    if (generator
        is Future<String> Function(
          String, {
          List<VibeChatAttachment> attachments,
        })) {
      future = generator(prompt, attachments: attachments);
    } else {
      future = generator(prompt);
    }
    return _awaitCancellable(future, cancellationToken);
  }

  Future<void> _ensureSessionPageLoaded(
    _LiveTurnSession session,
    String pageId,
  ) async {
    final controller = widget.controller;
    if (controller is! PersistentAppearanceController) return;
    final before = controller.value;
    await controller.ensurePageLoaded(pageId);
    final after = controller.value;
    if (identical(before, after)) return;
    final slice = EditorPageAppearanceSlice(
      styles: {
        for (final entry in after.styles.entries)
          if (!before.styles.containsKey(entry.key)) entry.key: entry.value,
      },
      components: {
        for (final entry in after.components.entries)
          if (!before.components.containsKey(entry.key)) entry.key: entry.value,
      },
      behaviors: {
        for (final entry in after.behaviors.entries)
          if (!before.behaviors.containsKey(entry.key)) entry.key: entry.value,
      },
      usages: {
        for (final entry in after.usages.entries)
          if (!before.usages.containsKey(entry.key)) entry.key: entry.value,
      },
    );
    session.rawInitialAppearance = slice.mergeInto(
      session.rawInitialAppearance,
    );
    session.baseAppearance = slice.mergeInto(session.baseAppearance);
    session.checkpointAppearance = slice.mergeInto(
      session.checkpointAppearance,
    );
    session.lastPreviewAppearance = slice.mergeInto(
      session.lastPreviewAppearance,
    );
  }

  VibeAppToolRegistry _resolveToolRegistry(_LiveTurnSession session) {
    final explicit = widget.toolRegistry;
    if (explicit != null) return explicit;
    return VibeAppInspector(
      readAppearance: () => session.checkpointAppearance,
      registry: widget.registry,
      repositoryStore: session.repoTransaction?.store,
      pageRouting: session.pageRouting,
      ensurePageLoaded: (pageId) => _ensureSessionPageLoaded(session, pageId),
      readScope: () => _scope,
      readVisibleOnly: () => _visibleOnlyMode,
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
      repoTransaction: session.repoTransaction,
      customDesignSystemStore: _resolveCustomDesignSystemStore(),
      fontManager: mounted ? DynamicFontScope.readOf(context) : null,
      allowEndOfFrameInWidgetTests: true,
      onRegisterDesignSystem: (preset, {required select}) =>
          _registerDesignSystemFromTool(
            preset,
            select: select,
            session: session,
          ),
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
        'manage_repository_json_schema' =>
          'Gestion du JSON Schema du repository…',
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
        'select_editor_element' => 'Sélection de l’élément dans l’éditeur…',
        'register_design_system' =>
          'Génération et ajout du Design System DESIGN.md…',
        'audit_active_page' => 'Audit complet de la page active…',
        'validate_or_list_icons' => 'Validation / liste des icônes…',
        final other => 'Exécution de $other…',
      };
    }
    return 'Inspection de l’application (${calls.map((c) => c.name).join(', ')})…';
  }

  static void _recordTimedTrace(
    _LiveTurnSession session, {
    required String phase,
    required String label,
    required int durationMs,
    String? detail,
    bool isError = false,
    String scopeLabel = 'Tour',
  }) {
    final offsetMs = session.turnStopwatch.elapsedMilliseconds;
    final trace = VibeTimedTrace(
      phase: phase,
      label: label,
      durationMs: durationMs,
      elapsedFromStartMs: offsetMs,
      detail: detail,
      isError: isError,
    );
    session.timedTraces.add(trace);
    debugPrint(
      '[Vibe IA][$scopeLabel][+${offsetMs}ms][$phase] '
      '$label (${durationMs}ms)'
      '${detail == null || detail.isEmpty ? "" : " — $detail"}',
    );
  }

  static bool _isRetryableTransportError(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException ||
        error is HandshakeException) {
      return true;
    }
    if (error is GeminiApiException) {
      return error.statusCode == 408 ||
          error.statusCode == 429 ||
          error.statusCode >= 500;
    }
    return false;
  }

  static String _formatSalvageSummary(
    _LiveTurnSession session,
    VibeSalvageOutcome salvage,
  ) {
    final addedComps =
        salvage.checkpointAppearance.components.length -
        session.baseAppearance.components.length;
    final addedStyles =
        salvage.checkpointAppearance.styles.length -
        session.baseAppearance.styles.length;
    return 'composants: ${addedComps >= 0 ? "+$addedComps" : "$addedComps"}, '
        'styles: ${addedStyles >= 0 ? "+$addedStyles" : "$addedStyles"}, '
        'rejets: ${salvage.rejectedEntries.length}';
  }

  static String _formatBoundedIdList(
    Iterable<String> ids, {
    int maxItems = 12,
  }) {
    final list = ids.toList();
    if (list.length <= maxItems) return list.join(', ');
    return '${list.take(maxItems).join(', ')} (+${list.length - maxItems})';
  }

  static String _describePatchTargets(Map<String, dynamic> patch) {
    final payload = patch['data'] is Map<String, dynamic>
        ? patch['data'] as Map<String, dynamic>
        : patch;
    final parts = <String>[];
    for (final section in const <String>[
      'components',
      'styles',
      'behaviors',
      'usages',
    ]) {
      final raw = payload[section];
      if (raw is Map && raw.isNotEmpty) {
        final keys = raw.keys.whereType<String>().toList();
        parts.add('$section(${keys.length}): [${_formatBoundedIdList(keys)}]');
      }
    }
    final rawPages = payload['pageCatalog'];
    if (rawPages is Map && rawPages.isNotEmpty) {
      parts.add('pageCatalog');
    }
    for (final globalKey in const <String>[
      'mode',
      'accent',
      'backgroundOpacity',
    ]) {
      if (payload.containsKey(globalKey)) {
        parts.add('$globalKey=${payload[globalKey]}');
      }
    }
    return parts.isEmpty ? 'aucune section' : parts.join(', ');
  }

  static String _describeAppearanceDiff(Appearance before, Appearance after) {
    final addedComps = <String>[
      for (final id in after.components.keys)
        if (!before.components.containsKey(id)) id,
    ];
    final modifiedComps = <String>[
      for (final entry in after.components.entries)
        if (before.components.containsKey(entry.key) &&
            before.components[entry.key] != entry.value)
          entry.key,
    ];
    final removedComps = <String>[
      for (final id in before.components.keys)
        if (!after.components.containsKey(id)) id,
    ];
    final touchedStyles = <String>[
      for (final entry in after.styles.entries)
        if (before.styles[entry.key] != entry.value) entry.key,
      for (final id in before.styles.keys)
        if (!after.styles.containsKey(id)) '-$id',
    ];
    final touchedBehaviors = <String>[
      for (final id in {...before.behaviors.keys, ...after.behaviors.keys})
        if (before.behaviors[id] != after.behaviors[id]) id,
    ];
    final parts = <String>[
      if (addedComps.isNotEmpty)
        '+comp(${addedComps.length}): [${_formatBoundedIdList(addedComps)}]',
      if (modifiedComps.isNotEmpty)
        '~comp(${modifiedComps.length}): [${_formatBoundedIdList(modifiedComps)}]',
      if (removedComps.isNotEmpty)
        '-comp(${removedComps.length}): [${_formatBoundedIdList(removedComps)}]',
      if (touchedStyles.isNotEmpty)
        'styles(${touchedStyles.length}): [${_formatBoundedIdList(touchedStyles)}]',
      if (touchedBehaviors.isNotEmpty)
        'behaviors(${touchedBehaviors.length}): [${_formatBoundedIdList(touchedBehaviors)}]',
    ];
    return parts.join(', ');
  }

  static void _recordToolTraces(
    _LiveTurnSession session,
    List<VibeToolCall> calls,
    List<VibeToolResult> results, {
    bool isPostVerify = false,
    String scopeLabel = 'Tour',
  }) {
    final count = calls.length < results.length ? calls.length : results.length;
    for (var i = 0; i < count; i++) {
      final trace = VibeToolTrace.fromExecution(
        calls[i],
        results[i],
        isPostVerify: isPostVerify,
      );
      session.toolTraces.add(trace);
      final argsText = trace.arguments.isEmpty
          ? ''
          : jsonEncode(trace.arguments);
      final clippedArgs = argsText.length > 160
          ? '${argsText.substring(0, 160)}…'
          : argsText;
      debugPrint(
        '[Vibe IA][$scopeLabel][Outil${isPostVerify ? ' post-rendu' : ''}] '
        '${trace.name}($clippedArgs) -> '
        '${trace.isError ? 'ERREUR' : 'OK'} '
        '(${trace.durationMs ?? 0}ms)'
        '${trace.summary.isEmpty ? '' : ' : ${trace.summary}'}',
      );
    }
  }

  Future<({bool satisfiedLocally, String? precomputedAuditSummary})>
  _evaluateLocalVerifyRenderGate({
    required Appearance candidateAppearance,
    required _LiveTurnSession session,
    required String traceScopeLabel,
  }) async {
    try {
      final inspector = VibeAppInspector(
        readAppearance: () => candidateAppearance,
        registry: widget.registry,
        repositoryStore: _resolveRepositoryStore(),
        pageRouting: session.pageRouting,
        readScope: () => _scope,
        readVisibleOnly: () => _visibleOnlyMode,
        fallbackContext: () => mounted ? context : null,
        turnStartMarker: session.turnStartMarker,
      );
      if (inspector.slotIndex.mountedComponentIds.isEmpty) {
        debugPrint(
          '[Vibe IA][$traceScopeLabel][PostVerify] Contrôle local non concluant (aucun slot monté).',
        );
        return (satisfiedLocally: false, precomputedAuditSummary: null);
      }
      final auditReport = await VibePageAuditService.collect(inspector);
      if (auditReport.measuredGeometrySummaries.isEmpty) {
        debugPrint(
          '[Vibe IA][$traceScopeLabel][PostVerify] Contrôle local non concluant (0 mesure géométrique).',
        );
        return (satisfiedLocally: false, precomputedAuditSummary: null);
      }
      final renderFindings = auditReport.findings
          .where((f) => f.category != VibeAuditCategory.missingCalculation)
          .toList(growable: false);
      if (renderFindings.isEmpty) {
        return (satisfiedLocally: true, precomputedAuditSummary: null);
      }
      debugPrint(
        '[Vibe IA][$traceScopeLabel][PostVerify] Escalade LLM après contrôle local '
        '(${renderFindings.length} anomalie(s) : '
        '${renderFindings.take(4).map((f) => '${f.kind}@${f.componentId ?? ""}/${f.zoneId ?? ""}').join(', ')}).',
      );
      return (
        satisfiedLocally: false,
        precomputedAuditSummary: auditReport.toPromptSummary(),
      );
    } catch (error) {
      debugPrint(
        '[Vibe IA][$traceScopeLabel][PostVerify] Contrôle local en échec ($error), repli LLM.',
      );
      return (satisfiedLocally: false, precomputedAuditSummary: null);
    }
  }

  static String _describeReactivePassDetail({
    required bool appearanceUpdated,
    required bool repositoriesUpdated,
  }) {
    if (appearanceUpdated && repositoriesUpdated) {
      return 'repositories + écran mis à jour';
    }
    if (repositoriesUpdated) return 'repositories mis à jour';
    if (appearanceUpdated) return 'ajustement appliqué';
    return 'conforme';
  }

  Future<
    ({
      Appearance? updatedAppearance,
      bool repositoriesUpdated,
      String? summaryMessage,
    })
  >
  _runPostReactiveValuesPass({
    required Appearance candidateAppearance,
    required String systemGuide,
    required _LiveTurnSession session,
    required VibeAppToolRegistry toolRegistry,
    required bool isDirectGemini,
    required bool useStreaming,
    List<VibeChatAttachment> cachedAttachments = const <VibeChatAttachment>[],
    String traceScopeLabel = 'Tour',
  }) async {
    const maxReactiveToolRounds = 3;
    final reactiveWatch = Stopwatch()..start();
    final preReactiveSavepoint = session.repoTransaction?.createSavepoint();
    debugPrint(
      '[Vibe IA][$traceScopeLabel][PostReactive] Démarrage phase finale valeurs réactives '
      '(streaming: $useStreaming).',
    );
    try {
      session.checkpointAppearance = candidateAppearance;
      session.hasCheckpoint = true;
      if (!session.suppressUiUpdates) {
        _setPreviewAppearance(candidateAppearance);
        final appliedCandidate = widget.controller.value;
        _pulseAppearanceDiff(session, appliedCandidate);
        _syncLivePageOutcome(session, appliedCandidate);

        _updateSessionStreamingSnapshot(
          session,
          (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
            activeToolStatus: 'Configuration des valeurs réactives…',
            toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
          ),
        );
      }

      final resolvedRepoStore =
          session.repoTransaction?.store ?? _resolveRepositoryStore();
      final repositoriesContext = resolvedRepoStore == null
          ? null
          : await VibeRepositoryPromptFormatter.formatStoreContext(
              resolvedRepoStore,
            );
      session.cancellationToken.throwIfCancelled();

      final mountedSummaries = VibeMountedSlotIndex.instance
          .mountedSlotSummaries();
      final reactivePrompt = VibePromptBuilder.buildPostReactiveValuesPrompt(
        appearance: candidateAppearance,
        codec: widget.codec,
        scope: _scope,
        mountedSlotSummaries: mountedSummaries,
        repositoriesContext: repositoriesContext,
        visibleOnlyMode: _visibleOnlyMode,
        visibleViewportContext: session.visibleViewportSnapshot
            ?.toPromptContext(),
      );

      var roundPrompt = reactivePrompt;
      var roundAttachments = const <VibeChatAttachment>[];
      final conversationContents = isDirectGemini
          ? <Map<String, Object?>>[
              <String, Object?>{
                'role': 'user',
                'parts': GeminiRestClient.buildUserParts(
                  reactivePrompt,
                  const <VibeChatAttachment>[],
                ),
              },
            ]
          : null;

      late String reactiveResponse;
      Map<String, dynamic>? decoded;

      for (var round = 0; round <= maxReactiveToolRounds; round++) {
        session.cancellationToken.throwIfCancelled();
        final allowTools =
            toolRegistry.isNotEmpty && round < maxReactiveToolRounds;
        var nativeCalls = const <VibeToolCall>[];
        var rawModelParts = const <Map<String, Object?>>[];
        final roundWatch = Stopwatch()..start();

        if (useStreaming) {
          final streamed = await _consumeStreamingGenerate(
            roundPrompt,
            systemGuide: systemGuide,
            attachments: roundAttachments,
            cachedAttachments: cachedAttachments,
            session: session,
            tools: allowTools ? toolRegistry.declarations : const [],
            conversationContents: conversationContents,
            enforceJsonResponse: !allowTools,
            completedToolTraces: List<VibeToolTrace>.unmodifiable(
              session.toolTraces,
            ),
          );
          reactiveResponse = streamed.rawResponse;
          nativeCalls = streamed.functionCalls;
          rawModelParts = streamed.rawModelParts;
        } else {
          final combined =
              '${VibeChatDialog.defaultSystemInstruction}\n\n'
              'GUIDE DE MODÉLISATION :\n$systemGuide\n\n'
              '$roundPrompt';
          reactiveResponse = await _invokeGenerate(
            combined,
            roundAttachments,
            cancellationToken: session.cancellationToken,
          );
        }
        session.cancellationToken.throwIfCancelled();
        roundWatch.stop();
        debugPrint(
          '[Vibe IA][$traceScopeLabel][PostReactive] Tour ${round + 1} LLM '
          '(${roundWatch.elapsedMilliseconds}ms, ${reactiveResponse.length} car., '
          'nativeCalls=${nativeCalls.length}).',
        );

        if (nativeCalls.isNotEmpty) {
          if (!allowTools) break;
          _updateStreamingSnapshot(
            (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
              activeToolStatus: _formatToolStatusLabel(nativeCalls),
              toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
            ),
          );
          final results = await _awaitCancellable(
            toolRegistry.executeAll(nativeCalls),
            session.cancellationToken,
          );
          _recordToolTraces(
            session,
            nativeCalls,
            results,
            isPostVerify: true,
            scopeLabel: traceScopeLabel,
          );
          _updateStreamingSnapshot(
            (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
              activeToolStatus: _formatToolStatusLabel(nativeCalls),
              toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
            ),
          );
          final generatedAttachments = <VibeChatAttachment>[
            for (final r in results) ...r.attachments,
          ];
          if (generatedAttachments.isNotEmpty) {
            roundAttachments = [...roundAttachments, ...generatedAttachments];
          }
          final isLastRound = round + 1 >= maxReactiveToolRounds;
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
                if (isLastRound)
                  const <String, Object?>{
                    'text':
                        'ATTENTION : limite maximale d’appels d’outils atteinte. '
                        'N’appelle PLUS aucun outil (ni functionCall ni toolCalls) et '
                        'renvoie immédiatement ta réponse JSON finale '
                        '{"message":"Valeurs réactives vérifiées.","vibe":null} '
                        'ou un patch delta dans "repositories" / "vibe".',
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
                '$roundPrompt\n\nRÉSULTATS DES OUTILS DEMANDÉS (valeurs réactives ${round + 1}) :\n'
                '${jsonEncode([for (final r in results) r.toJson()])}\n'
                'Conclue maintenant avec {"message":"...","vibe":null} ou un patch delta "repositories" / "vibe".';
          }
          continue;
        }

        decoded = null;
        List<VibeToolCall> jsonCalls = const <VibeToolCall>[];
        if (reactiveResponse.trim().isNotEmpty) {
          final parsed = _decodeResponseJson(_extractJson(reactiveResponse));
          if (parsed is Map<String, dynamic>) {
            decoded = parsed;
            if (parsed['vibe'] == null &&
                parsed['repositories'] == null &&
                parsed['toolCalls'] != null) {
              jsonCalls = VibeToolCall.tryListFromJson(parsed['toolCalls']);
            }
          }
        }
        if (jsonCalls.isNotEmpty && allowTools) {
          _updateStreamingSnapshot(
            (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
              activeToolStatus: _formatToolStatusLabel(jsonCalls),
              toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
            ),
          );
          final results = await _awaitCancellable(
            toolRegistry.executeAll(jsonCalls),
            session.cancellationToken,
          );
          _recordToolTraces(
            session,
            jsonCalls,
            results,
            isPostVerify: true,
            scopeLabel: traceScopeLabel,
          );
          _updateStreamingSnapshot(
            (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
              activeToolStatus: _formatToolStatusLabel(jsonCalls),
              toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
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
                <String, Object?>{'text': reactiveResponse},
              ],
            });
            conversationContents.add(<String, Object?>{
              'role': 'user',
              'parts': <Map<String, Object?>>[
                <String, Object?>{
                  'text':
                      'RÉSULTATS DES OUTILS DEMANDÉS (valeurs réactives ${round + 1}) :\n'
                      '$encodedResults\n'
                      'Conclue maintenant avec {"message":"...","vibe":null} ou un patch delta "repositories" / "vibe".',
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
                '$roundPrompt\n\nRÉSULTATS DES OUTILS DEMANDÉS (valeurs réactives ${round + 1}) :\n'
                '$encodedResults\n'
                'Conclue maintenant avec {"message":"...","vibe":null} ou un patch delta "repositories" / "vibe".';
          }
          continue;
        }
        break;
      }

      if (decoded == null) {
        return (
          updatedAppearance: null,
          repositoriesUpdated: false,
          summaryMessage: null,
        );
      }
      final sanitized = VibeRepositoryApplier.sanitizeResponseEnvelope(decoded);
      final effectiveDecoded = sanitized.response;
      for (final warning in sanitized.warnings) {
        debugPrint(
          '[Vibe IA][$traceScopeLabel][PostReactive] ${warning.replaceFirst('[Vibe IA] ', '')}',
        );
        VibeDebugCapture.recordTypedError(
          message: warning,
          category: DebugErrorCategory.binding,
          severity: DebugSeverity.warning,
          source: 'VibeRepositoryApplier.sanitizeEnvelope',
          visibleInUi: false,
        );
      }
      final summary = effectiveDecoded['message'] is String
          ? (effectiveDecoded['message'] as String).trim()
          : null;

      final repositoriesPatch = _extractRepositoriesPatch(effectiveDecoded);
      var repositoriesUpdated = false;
      if (repositoriesPatch != null) {
        final repoTx = session.repoTransaction;
        if (repoTx == null) {
          throw const FormatException(
            'Aucun JsonRepositoryStore actif pour appliquer les valeurs réactives.',
          );
        }
        await repoTx.applyRepositoriesPatch(repositoriesPatch);
        await repoTx.assertAllSchemasValid();
        repositoriesUpdated = true;
      }

      final patch = _extractPatch(effectiveDecoded);
      Appearance? updatedAppearance;
      if (patch != null) {
        final activeScope = _scope;
        final rewritten = session.repoTransaction != null
            ? session.repoTransaction!.rewriteVibePatchBindings(patch)
            : patch;
        var effectivePatch = activeScope == null
            ? rewritten
            : VibeChatDialog.filterPatchToScope(
                candidateAppearance,
                rewritten,
                activeScope,
              );
        if (_visibleOnlyMode && session.visibleViewportSnapshot != null) {
          effectivePatch = VibeScopeHelpers.filterPatchToVisibleViewport(
            candidateAppearance,
            effectivePatch,
            session.visibleViewportSnapshot!,
          );
        }
        if (_hasPatchChanges(effectivePatch)) {
          debugPrint(
            '[Vibe IA][$traceScopeLabel][PostReactive] Patch valeurs réactives à appliquer : '
            '${_describePatchTargets(effectivePatch)}.',
          );
          var next = AppearanceTransfer.applyVibe(
            candidateAppearance,
            jsonEncode(effectivePatch),
            codec: widget.codec,
          );
          next = _inferMissingDefaultUsages(
            candidateAppearance,
            next,
            effectivePatch,
          );
          widget.validateAppearance?.call(next);
          _validatePatchedComponents(
            candidateAppearance,
            next,
            effectivePatch,
            instantiatedIds: session.initialInstantiatedIds,
          );
          updatedAppearance = next;
          session.lastAppliedEffectivePatch = effectivePatch;
        }
      }

      if (updatedAppearance == null && !repositoriesUpdated) {
        debugPrint(
          '[Vibe IA][$traceScopeLabel][PostReactive] Valeurs réactives conformes — '
          'aucun patch supplémentaire (${reactiveWatch.elapsedMilliseconds}ms).',
        );
      } else {
        final diff = updatedAppearance == null
            ? ''
            : _describeAppearanceDiff(candidateAppearance, updatedAppearance);
        debugPrint(
          '[Vibe IA][$traceScopeLabel][PostReactive] Phase valeurs réactives appliquée en '
          '${reactiveWatch.elapsedMilliseconds}ms'
          '${repositoriesUpdated ? ' (repositories mis à jour)' : ''}'
          '${diff.isEmpty ? '' : ' ($diff)'}.',
        );
      }
      return (
        updatedAppearance: updatedAppearance,
        repositoriesUpdated: repositoriesUpdated,
        summaryMessage: summary,
      );
    } on VibeCancelledException {
      rethrow;
    } catch (error) {
      if (session.cancellationToken.isCancelled) {
        throw const VibeCancelledException();
      }
      if (preReactiveSavepoint != null) {
        try {
          await session.repoTransaction?.restoreSavepoint(preReactiveSavepoint);
        } catch (_) {}
      }
      debugPrint(
        '[Vibe IA][$traceScopeLabel][PostReactive] Phase valeurs réactives ignorée après erreur '
        '(${reactiveWatch.elapsedMilliseconds}ms) : $error',
      );
      return (
        updatedAppearance: null,
        repositoriesUpdated: false,
        summaryMessage: null,
      );
    } finally {
      session.previewTracker.restoreTabs();
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
    List<VibeChatAttachment> cachedAttachments = const <VibeChatAttachment>[],
    List<DebugEntry> detectedErrors = const <DebugEntry>[],
    String? precomputedAuditSummary,
    String traceScopeLabel = 'Tour',
  }) async {
    const maxVerifyToolRounds = 3;
    final verifyWatch = Stopwatch()..start();
    debugPrint(
      '[Vibe IA][$traceScopeLabel][PostVerify] Démarrage passe de vérification post-rendu '
      '(erreurs détectées: ${detectedErrors.length}, streaming: $useStreaming).',
    );
    try {
      session.checkpointAppearance = candidateAppearance;
      session.hasCheckpoint = true;
      if (!session.suppressUiUpdates) {
        _setPreviewAppearance(candidateAppearance);
        final appliedCandidate = widget.controller.value;
        _pulseAppearanceDiff(session, appliedCandidate);
        _syncLivePageOutcome(session, appliedCandidate);

        _updateSessionStreamingSnapshot(
          session,
          (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
            activeToolStatus: detectedErrors.isNotEmpty
                ? 'Correction des erreurs d’exécution détectées…'
                : 'Vérification du rendu appliqué…',
            toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
          ),
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
      }

      final mountedSummaries = VibeMountedSlotIndex.instance
          .mountedSlotSummaries();
      final preVerifyDiagnosticsSection =
          precomputedAuditSummary ??
          await _collectFastVerifyContext(
            candidateAppearance: candidateAppearance,
            session: session,
          );
      final errorsSection = detectedErrors.isEmpty
          ? null
          : 'ERREURS D’EXÉCUTION DÉTECTÉES DANS debugEntries APRÈS L’APERÇU :\n'
                '${detectedErrors.take(8).map((e) => '- ${VibeDebugCapture.formatEntryForAi(e)}').join('\n')}\n'
                'Corrige impérativement la cause de ces erreurs (priorité : critical > error > warning) dans ton patch delta "vibe".';
      final verifyPrompt = [
        'VÉRIFICATION POST-RENDU (APERÇU APPLIQUÉ) :',
        'Le patch "vibe" vient d’être appliqué en aperçu à l’écran.',
        ?errorsSection,
        ?preVerifyDiagnosticsSection,
        if (mountedSummaries.isNotEmpty)
          'Slots montés actuellement à l’écran : ${jsonEncode(mountedSummaries)}.',
        'Réutilise directement les diagnostics et dimensions ci-dessus sans rappeler d’outil inutile ; appelle en un seul lot parallèle `get_component_geometry`, `get_debug_entries` ou `capture_element_screenshot` uniquement si une mesure supplémentaire manque réellement.',
        "- **Contrôle systématique du budget de largeur en ligne (`zoneAxes: 'row'`)** / **Contrôle budgétaire de largeur en ligne (`zoneAxes: 'row'`)** : Dès qu'une zone est disposée en ligne (`zoneAxes: 'row'`), additionne systématiquement via `get_component_geometry` les largeurs mesurées des composants enfants et lève/corrige une alerte dès que `somme(width) > parentWidth - paddings` (`[somme(width) + espacements]` doit rester strictement inférieur à `parentWidth - paddingLeft - paddingRight`).",
        "- **Maîtrise du budget de largeur & prévention de la troncature silencieuse (tout `SuperLayout` et `template`)** : Interdis `autoSides: [\"east\"]` / `[\"west\"]` dès que le côté héberge données dynamiques, badges ou actions (remplace par `eastSize`/`westSize` fixe entre 180 et 320 dp) ; vérifie sur tout `SuperLayout` que `[somme(tailles fixes des côtés actifs) + paddings + marges] < largeur totale disponible` avec une zone `center` viable ; et sur toute ligne riche (titre + métadonnées), impose soit `eastSize` en dur, soit `slotSizeConstraints` (`maxWidth` sur le texte long et `fitContent: true` sur les contrôles).",
        "- **Règle d'or sur les volets latéraux étroits (largeur ≤ 480 dp)** : Interdis sur une même ligne la cohabitation d'un titre long (> 30 caractères) et d'un bouton d'action complet texte + icône ; exige soit un bouton d'action à icône seule (`kind: 'icon'`), soit un titre compacté.",
        "- **Audit visuel obligatoire par capture isolée (`capture_element_screenshot`)** & **Inspection visuelle par élément** : Ordonne et exécute une capture visuelle de contrôle avec `capture_element_screenshot` sur chaque en-tête de carte maître avant de clore un lot d'audit (ainsi qu'en cas de modification d'en-tête ou de barre d'outils), et sur la première occurrence (`occurrenceIndex: 0`) de toute `SuperListView` ou `SuperTable` créée ou auditée pour valider l'alignement et l'absence de coupure, de texte tronqué ou de superposition en fin de ligne.",
        if (_visibleOnlyMode)
          "- **Mode Uniquement visible** : Reste strictement sur l'onglet actif et la position de scroll courante ; vérifie uniquement les éléments actuellement visibles à l'écran sans changer d'onglet ni faire défiler la vue."
        else if (_scope == null)
          "- **Balayage des onglets (hors scope)** : Si la page contient un `SuperTab` et que plusieurs onglets sont concernés, balaie chaque onglet via `preview_navigation_or_selection` (`tabComponentId` + `tabIndex` ou `tabId`) avant d'appeler `get_component_geometry` ou `capture_element_screenshot` dessus.",
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
        session.cancellationToken.throwIfCancelled();
        final allowTools = round < maxVerifyToolRounds;
        var nativeCalls = const <VibeToolCall>[];
        var rawModelParts = const <Map<String, Object?>>[];
        final roundWatch = Stopwatch()..start();

        if (useStreaming) {
          final streamed = await _consumeStreamingGenerate(
            roundPrompt,
            systemGuide: systemGuide,
            attachments: roundAttachments,
            cachedAttachments: cachedAttachments,
            session: session,
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
          verifyResponse = await _invokeGenerate(
            combined,
            roundAttachments,
            cancellationToken: session.cancellationToken,
          );
        }
        session.cancellationToken.throwIfCancelled();
        roundWatch.stop();
        debugPrint(
          '[Vibe IA][$traceScopeLabel][PostVerify] Tour ${round + 1} LLM '
          '(${roundWatch.elapsedMilliseconds}ms, ${verifyResponse.length} car., '
          'nativeCalls=${nativeCalls.length}).',
        );

        if (nativeCalls.isNotEmpty) {
          if (!allowTools) break;
          _updateStreamingSnapshot(
            (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
              activeToolStatus: _formatToolStatusLabel(nativeCalls),
              toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
            ),
          );
          final results = await _awaitCancellable(
            toolRegistry.executeAll(nativeCalls),
            session.cancellationToken,
          );
          _recordToolTraces(
            session,
            nativeCalls,
            results,
            isPostVerify: true,
            scopeLabel: traceScopeLabel,
          );
          _updateStreamingSnapshot(
            (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
              activeToolStatus: _formatToolStatusLabel(nativeCalls),
              toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
            ),
          );
          final generatedAttachments = <VibeChatAttachment>[
            for (final r in results) ...r.attachments,
          ];
          if (generatedAttachments.isNotEmpty) {
            roundAttachments = [...roundAttachments, ...generatedAttachments];
          }
          final isLastVerifyRound = round + 1 >= maxVerifyToolRounds;
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
                if (isLastVerifyRound)
                  const <String, Object?>{
                    'text':
                        'ATTENTION : limite maximale d’appels d’outils atteinte. '
                        'N’appelle PLUS aucun outil (ni functionCall ni toolCalls) et '
                        'renvoie immédiatement ta réponse JSON finale '
                        '{"message":"Rendu vérifié.","vibe":null} ou un patch delta correctif dans "vibe".',
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
          _updateStreamingSnapshot(
            (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
              activeToolStatus: _formatToolStatusLabel(jsonCalls),
              toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
            ),
          );
          final results = await _awaitCancellable(
            toolRegistry.executeAll(jsonCalls),
            session.cancellationToken,
          );
          _recordToolTraces(
            session,
            jsonCalls,
            results,
            isPostVerify: true,
            scopeLabel: traceScopeLabel,
          );
          _updateStreamingSnapshot(
            (_streamingSnapshot.value ?? VibeStreamSnapshot.empty).copyWith(
              activeToolStatus: _formatToolStatusLabel(jsonCalls),
              toolTraces: List<VibeToolTrace>.unmodifiable(session.toolTraces),
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
      final sanitizedVerify = VibeRepositoryApplier.sanitizeResponseEnvelope(
        decoded,
      );
      final effectiveDecoded = sanitizedVerify.response;
      for (final warning in sanitizedVerify.warnings) {
        debugPrint(
          '[Vibe IA][$traceScopeLabel][PostVerify] ${warning.replaceFirst('[Vibe IA] ', '')}',
        );
        VibeDebugCapture.recordTypedError(
          message: warning,
          category: DebugErrorCategory.binding,
          severity: DebugSeverity.warning,
          source: 'VibeRepositoryApplier.sanitizeEnvelope',
          visibleInUi: false,
        );
      }
      final summary = effectiveDecoded['message'] is String
          ? (effectiveDecoded['message'] as String).trim()
          : null;
      final patch = _extractPatch(effectiveDecoded);
      if (patch == null) {
        debugPrint(
          '[Vibe IA][$traceScopeLabel][PostVerify] Rendu conforme — aucun patch correctif '
          '(${verifyWatch.elapsedMilliseconds}ms).',
        );
        return (correctedAppearance: null, summaryMessage: summary);
      }

      final activeScope = _scope;
      final rewritten = session.repoTransaction != null
          ? session.repoTransaction!.rewriteVibePatchBindings(patch)
          : patch;
      var effectivePatch = activeScope == null
          ? rewritten
          : VibeChatDialog.filterPatchToScope(
              candidateAppearance,
              rewritten,
              activeScope,
            );
      if (_visibleOnlyMode && session.visibleViewportSnapshot != null) {
        effectivePatch = VibeScopeHelpers.filterPatchToVisibleViewport(
          candidateAppearance,
          effectivePatch,
          session.visibleViewportSnapshot!,
        );
      }
      if (!_hasPatchChanges(effectivePatch)) {
        debugPrint(
          '[Vibe IA][$traceScopeLabel][PostVerify] Rendu conforme — aucun patch correctif nécessaire '
          '(${verifyWatch.elapsedMilliseconds}ms).',
        );
        return (correctedAppearance: null, summaryMessage: summary);
      }

      debugPrint(
        '[Vibe IA][$traceScopeLabel][PostVerify] Patch correctif à appliquer : '
        '${_describePatchTargets(effectivePatch)}.',
      );
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
      final verifyDiff = _describeAppearanceDiff(
        candidateAppearance,
        corrected,
      );
      debugPrint(
        '[Vibe IA][$traceScopeLabel][PostVerify] Patch correctif appliqué en '
        '${verifyWatch.elapsedMilliseconds}ms'
        '${verifyDiff.isEmpty ? '' : ' ($verifyDiff)'}.',
      );
      return (correctedAppearance: corrected, summaryMessage: summary);
    } on VibeCancelledException {
      rethrow;
    } catch (error) {
      if (session.cancellationToken.isCancelled) {
        throw const VibeCancelledException();
      }
      debugPrint(
        '[Vibe IA][$traceScopeLabel][PostVerify] Passe de vérification post-rendu ignorée après erreur '
        '(${verifyWatch.elapsedMilliseconds}ms) : $error',
      );
      return (correctedAppearance: null, summaryMessage: null);
    } finally {
      session.previewTracker.restoreTabs();
    }
  }

  Future<String?> _collectFastVerifyContext({
    required Appearance candidateAppearance,
    required _LiveTurnSession session,
  }) async {
    if (_isWidgetTestBinding) return null;
    try {
      final patch = session.lastAppliedEffectivePatch;
      final payload = patch != null && patch['data'] is Map
          ? patch['data'] as Map
          : patch;
      final rawComps = payload?['components'];
      final targetIds = rawComps is Map
          ? rawComps.keys.whereType<String>().take(80).toList(growable: false)
          : const <String>[];
      if (targetIds.isEmpty) return null;

      final inspector = VibeAppInspector(
        readAppearance: () => candidateAppearance,
        registry: widget.registry,
        repositoryStore: _resolveRepositoryStore(),
        pageRouting: session.pageRouting,
        readScope: () => _scope,
        readVisibleOnly: () => _visibleOnlyMode,
        fallbackContext: () => mounted ? context : null,
        turnStartMarker: session.turnStartMarker,
      );
      final sections = <String>[];
      final diag = await inspector.inspectBindingsAndDiagnostics(
        <String, Object?>{'componentIds': targetIds},
      );
      if (diag['issues'] case final List<Object?> issues
          when issues.isNotEmpty) {
        final lines = issues
            .take(10)
            .map((e) {
              if (e is! Map) return '- $e';
              return '- [${e['componentId'] ?? 'global'}] ${e['kind']}: ${e['message']}';
            })
            .join('\n');
        sections.add(
          'ALERTES DE LIAISONS DÉTECTÉES SUR LES COMPOSANTS DU LOT (${issues.length}) :\n$lines',
        );
      }
      final mountedSet = inspector.slotIndex.mountedComponentIds.toSet();
      final mountedTargets = <String>[
        for (final id in targetIds)
          if (mountedSet.contains(id)) id,
      ].take(25).toList(growable: false);
      if (mountedTargets.isNotEmpty) {
        final geo = await inspector.getComponentGeometry(<String, Object?>{
          'ids': mountedTargets,
          'includeZones': false,
        });
        if (geo['components'] case final Map<Object?, Object?> comps) {
          final summaries = <String>[];
          for (final entry in comps.entries) {
            final occs = entry.value is Map
                ? (entry.value as Map)['occurrences']
                : null;
            if (occs is List && occs.isNotEmpty && occs.first is Map) {
              final sz = (occs.first as Map)['size'];
              if (sz is Map && sz['width'] is num && sz['height'] is num) {
                summaries.add(
                  '${entry.key}: ${(sz['width'] as num).round()}×${(sz['height'] as num).round()} dp',
                );
              }
            }
          }
          if (summaries.isNotEmpty) {
            sections.add(
              'DIMENSIONS RENDUES DES COMPOSANTS DU LOT : ${summaries.join(', ')}',
            );
          }
        }
      }
      return sections.isEmpty ? null : sections.join('\n');
    } catch (_) {
      return null;
    }
  }

  static Appearance _inferMissingDefaultUsages(
    Appearance previous,
    Appearance next,
    Map<String, dynamic> effectivePatch,
  ) {
    final payload = effectivePatch['data'] is Map
        ? effectivePatch['data'] as Map
        : effectivePatch;
    final rawComponents = payload['components'];
    if (rawComponents is! Map || rawComponents.isEmpty) return next;
    final explicitUsages = payload['usages'] is Map
        ? payload['usages'] as Map
        : const <Object?, Object?>{};

    Map<String, ComponentUsage>? updatedUsages;
    for (final key in rawComponents.keys) {
      if (key is! String) continue;
      if (previous.components.containsKey(key)) continue;
      if (explicitUsages.containsKey(key)) continue;
      if (next.usages.containsKey(key)) continue;
      final config = next.components[key];
      if (config == null || config.referencedBindings.isNotEmpty) continue;

      final ComponentUsage inferred = switch (config) {
        SuperLayoutConfig() ||
        NativeComponentConfig() ||
        ScaffoldPageConfig() ||
        SuperListViewConfig() ||
        SuperTableConfig() ||
        SuperTreeViewConfig() ||
        SuperTabConfig() ||
        SuperConditionalConfig() ||
        A4PageConfig() => const ComponentUsage(kind: ComponentUsageKind.layout),
        SuperActionConfig() => const ComponentUsage(
          kind: ComponentUsageKind.action,
        ),
        SuperIndicatorConfig() || SuperSeparatorConfig() =>
          const ComponentUsage(kind: ComponentUsageKind.decoration),
        final SuperValueConfig val
            when val.mode == SuperValueMode.input ||
                val.kind == SuperValueKind.choice =>
          const ComponentUsage(kind: ComponentUsageKind.userInput),
        final SuperValueConfig val => () {
          final rawSeed = val.label.trim().isNotEmpty
              ? val.label.trim()
              : (val.initialText.trim().isNotEmpty
                    ? val.initialText.trim()
                    : key);
          final suggested = ComponentUsage.suggestTranslationKey(rawSeed);
          if (ComponentUsage.translationKeyError(suggested) == null) {
            return ComponentUsage.explanation(suggested);
          }
          return const ComponentUsage(kind: ComponentUsageKind.staticData);
        }(),
        _ => const ComponentUsage(kind: ComponentUsageKind.decoration),
      };
      (updatedUsages ??= Map<String, ComponentUsage>.of(next.usages))[key] =
          inferred;
    }
    return updatedUsages == null ? next : next.copyWith(usages: updatedUsages);
  }

  Future<
    ({
      String rawResponse,
      VibeStreamSnapshot finalSnapshot,
      List<VibeToolCall> functionCalls,
      List<Map<String, Object?>> rawModelParts,
      int? ttftMs,
      int totalMs,
    })
  >
  _consumeStreamingGenerate(
    String turnPrompt, {
    required String systemGuide,
    required List<VibeChatAttachment> attachments,
    List<VibeChatAttachment> cachedAttachments = const <VibeChatAttachment>[],
    _LiveTurnSession? session,
    String? activePhaseLabel,
    List<VibeToolDeclaration> tools = const <VibeToolDeclaration>[],
    List<Map<String, Object?>>? conversationContents,
    bool enforceJsonResponse = true,
    List<VibeToolTrace> completedToolTraces = const <VibeToolTrace>[],
  }) async {
    final cancellationToken = session?.cancellationToken;
    cancellationToken?.throwIfCancelled();
    final customStream = widget.streamGenerate;
    final parser = VibeIncrementalStreamParser();
    final streamStopwatch = Stopwatch()..start();
    int? ttftMs;
    if (session == null || !session.suppressUiUpdates) {
      _pendingSnapshot = null;
      _frameSnapshotScheduled = false;
      final timedSnapshot = session == null
          ? const <VibeTimedTrace>[]
          : List<VibeTimedTrace>.unmodifiable(session.timedTraces);
      _updateStreamingSnapshot(
        VibeStreamSnapshot(
          toolTraces: completedToolTraces,
          elapsedMs: session?.turnStopwatch.elapsedMilliseconds,
          activePhaseLabel: activePhaseLabel,
          timedTraces: timedSnapshot,
        ),
      );
    }

    var finalAccumulated = '';
    var functionCalls = const <VibeToolCall>[];
    var rawModelParts = const <Map<String, Object?>>[];
    final stream = customStream != null
        ? customStream(
            turnPrompt,
            systemInstruction: VibeChatDialog.defaultSystemInstruction,
            staticGuide: systemGuide,
            attachments: cachedAttachments.isEmpty
                ? attachments
                : <VibeChatAttachment>[...cachedAttachments, ...attachments],
            speedMode: _speedMode,
          )
        : streamGemini(
            turnPrompt,
            systemInstruction: VibeChatDialog.defaultSystemInstruction,
            staticGuide: systemGuide,
            attachments: attachments,
            cachedAttachments: cachedAttachments,
            speedMode: _speedMode,
            tools: tools,
            conversationContents: conversationContents,
            enforceJsonResponse: enforceJsonResponse,
            cancellationToken: cancellationToken,
          );

    final streamDone = Completer<void>();
    StreamSubscription<GeminiStreamEvent>? subscription;
    void Function()? removeCancelListener;

    void handleCancellation() {
      final sub = subscription;
      subscription = null;
      if (sub != null) {
        unawaited(sub.cancel());
      }
      if (!streamDone.isCompleted) {
        streamDone.completeError(const VibeCancelledException());
      }
    }

    try {
      if (cancellationToken != null) {
        removeCancelListener = cancellationToken.addListener(
          handleCancellation,
        );
      }
      if (cancellationToken?.isCancelled == true) {
        throw const VibeCancelledException();
      }
      subscription = stream.listen(
        (event) {
          if (cancellationToken?.isCancelled == true) return;
          if (event.deltaText.isNotEmpty) {
            ttftMs ??= streamStopwatch.elapsedMilliseconds;
            final snapshot = parser
                .addChunk(event.deltaText)
                .copyWith(
                  toolTraces: completedToolTraces,
                  elapsedMs: session?.turnStopwatch.elapsedMilliseconds,
                  activePhaseLabel: activePhaseLabel,
                  timedTraces: session == null
                      ? const <VibeTimedTrace>[]
                      : List<VibeTimedTrace>.unmodifiable(session.timedTraces),
                );
            if (session != null) {
              session.lastStreamSnapshot = snapshot;
            }
            if (session != null && session.suppressUiUpdates) {
              session.onStreamProgress?.call(snapshot);
            } else {
              _publishStreamSnapshot(snapshot);
            }
          } else if (event.isDone &&
              parser.rawBuffer.isEmpty &&
              event.accumulatedText.isNotEmpty) {
            ttftMs ??= streamStopwatch.elapsedMilliseconds;
            parser.addChunk(event.accumulatedText);
          }
          if (event.functionCalls.isNotEmpty) {
            ttftMs ??= streamStopwatch.elapsedMilliseconds;
            functionCalls = event.functionCalls;
          }
          if (event.rawModelParts.isNotEmpty) {
            rawModelParts = event.rawModelParts;
          }
          if (event.accumulatedText.isNotEmpty) {
            finalAccumulated = event.accumulatedText;
          }
          if (event.isDone) {
            final hadPending = _pendingSnapshot != null;
            _pendingSnapshot = null;
            final doneSnap = parser.current.copyWith(
              toolTraces: completedToolTraces,
              elapsedMs: session?.turnStopwatch.elapsedMilliseconds,
              activePhaseLabel: activePhaseLabel,
              timedTraces: session == null
                  ? const <VibeTimedTrace>[]
                  : List<VibeTimedTrace>.unmodifiable(session.timedTraces),
            );
            if (session != null) {
              session.lastStreamSnapshot = doneSnap;
              if (session.suppressUiUpdates) {
                session.onStreamProgress?.call(doneSnap);
              } else {
                if (hadPending ||
                    doneSnap.patchRevision > session.lastAppliedPatchRevision ||
                    doneSnap.repositoriesRevision >
                        session.lastAppliedRepositoriesRevision) {
                  _applyLivePreviewFromSnapshot(doneSnap);
                }
                _flushSuppressedPreviewLogSummary(session);
              }
            }
            if (session == null || !session.suppressUiUpdates) {
              _updateStreamingSnapshot(doneSnap);
            }
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          subscription = null;
          if (!streamDone.isCompleted) {
            streamDone.completeError(
              cancellationToken?.isCancelled == true
                  ? const VibeCancelledException()
                  : error,
              stackTrace,
            );
          }
        },
        onDone: () {
          subscription = null;
          if (!streamDone.isCompleted) {
            streamDone.complete();
          }
        },
        cancelOnError: true,
      );
      await streamDone.future;
      cancellationToken?.throwIfCancelled();
    } catch (_) {
      if (session != null) {
        session.lastStreamSnapshot = parser.current.copyWith(
          toolTraces: completedToolTraces,
          elapsedMs: session.turnStopwatch.elapsedMilliseconds,
          activePhaseLabel: activePhaseLabel,
          timedTraces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
        );
      }
      rethrow;
    } finally {
      removeCancelListener?.call();
      final sub = subscription;
      subscription = null;
      if (sub != null) {
        await sub.cancel();
      }
      streamStopwatch.stop();
    }

    final rawResponse = parser.rawBuffer.isNotEmpty
        ? parser.rawBuffer
        : finalAccumulated;
    return (
      rawResponse: rawResponse,
      finalSnapshot: parser.current,
      functionCalls: functionCalls,
      rawModelParts: rawModelParts,
      ttftMs: ttftMs,
      totalMs: streamStopwatch.elapsedMilliseconds,
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
    String traceScopeLabel = 'Tour',
    String? phaseUiLabel,
    bool isIntermediatePlanLot = false,
    bool preserveCheckpointOnFailure = false,
    _LotPartialCheckpoint? initialCheckpoint,
    String Function({
      Appearance? appearanceOverride,
      Iterable<String>? instantiatedIdsOverride,
      String? repositoriesContext,
    })?
    promptBuilder,
  }) async {
    const maxAttempts = 4;
    var currentTurnPrompt = turnPrompt;
    var attemptAttachments = List<VibeChatAttachment>.of([
      ...attachments,
      ...?initialCheckpoint?.collectedToolAttachments,
    ]);
    var disableToolsForAttempt = false;
    final priorCauses = <String>[...?initialCheckpoint?.priorCauses];
    final toolRegistry = _resolveToolRegistry(session);
    VibeSalvageOutcome? lastCheckpointSalvage = initialCheckpoint?.salvage;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      session.cancellationToken.throwIfCancelled();
      session.attemptsExecuted = attempt + 1;
      final attemptStopwatch = Stopwatch()..start();
      final attemptDebugMarker = VibeDebugCapture.markNow();
      final attemptPhaseLabel = phaseUiLabel == null
          ? (attempt == 0
                ? null
                : 'Tentative ${attempt + 1}/$maxAttempts'
                      '${session.hasCheckpoint ? " (delta)" : ""}')
          : '$phaseUiLabel · Tentative ${attempt + 1}/$maxAttempts'
                '${session.hasCheckpoint ? " (delta)" : ""}';
      session.lastStreamSnapshot = null;
      if (attempt > 0) {
        if (!session.suppressUiUpdates) {
          _pendingSnapshot = null;
          _updateSessionStreamingSnapshot(
            session,
            VibeStreamSnapshot(
              elapsedMs: session.turnStopwatch.elapsedMilliseconds,
              activePhaseLabel: attemptPhaseLabel,
              timedTraces: List<VibeTimedTrace>.unmodifiable(
                session.timedTraces,
              ),
            ),
          );
          session.livePreviewDisabled = false;
        }
        session.liveRepoQueue = Future<void>.value();
        session.toolTraces.clear();
      } else if (!session.suppressUiUpdates) {
        _updateSessionStreamingSnapshot(
          session,
          VibeStreamSnapshot(
            elapsedMs: session.turnStopwatch.elapsedMilliseconds,
            activePhaseLabel: attemptPhaseLabel,
            timedTraces: List<VibeTimedTrace>.unmodifiable(session.timedTraces),
          ),
        );
      }
      final useStreaming = _usesStreamingGenerator;
      final isDirectGemini =
          useStreaming &&
          widget.streamGenerate == null &&
          identical(widget.generate, callGemini);
      final useExplicitAttachmentCache =
          isDirectGemini &&
          GeminiRestClient.totalAttachmentBytes(attachments) >=
              GeminiRestClient.defaultMinAttachmentBytesForExplicitCache;
      final effectiveCachedAttachments = useExplicitAttachmentCache
          ? List<VibeChatAttachment>.unmodifiable(attachments)
          : const <VibeChatAttachment>[];
      debugPrint(
        '[Vibe IA][$traceScopeLabel] Tentative ${attempt + 1}/$maxAttempts — envoi du prompt '
        '(${currentTurnPrompt.length} car., '
        'mode: ${useStreaming ? _speedMode.name : "custom"}, '
        'fichiers: ${attemptAttachments.length}'
        '${useExplicitAttachmentCache ? " [cached]" : ""}'
        '${session.hasCheckpoint ? ", delta checkpoint" : ""})...',
      );

      var roundPrompt = currentTurnPrompt;
      var roundAttachments = useExplicitAttachmentCache
          ? List<VibeChatAttachment>.of([
              ...?initialCheckpoint?.collectedToolAttachments,
            ])
          : List<VibeChatAttachment>.of(attemptAttachments);
      final collectedToolResults = <Map<String, Object?>>[
        ...?initialCheckpoint?.collectedToolResults,
      ];
      final collectedToolAttachments = <VibeChatAttachment>[];
      final conversationContents = isDirectGemini
          ? <Map<String, Object?>>[
              <String, Object?>{
                'role': 'user',
                'parts': GeminiRestClient.buildUserParts(
                  currentTurnPrompt,
                  roundAttachments,
                ),
              },
            ]
          : null;

      var response = '';
      var finalSnapshot = VibeStreamSnapshot.empty;
      Map<String, dynamic>? preDecodedMap;
      var exceededNativeToolRounds = false;
      Map<String, dynamic>? decodedMap;

      try {
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
          final llmStopwatch = Stopwatch()..start();
          int? ttftMs;
          try {
            if (useStreaming) {
              final streamed = await _consumeStreamingGenerate(
                roundPrompt,
                systemGuide: systemGuide,
                attachments: roundAttachments,
                cachedAttachments: effectiveCachedAttachments,
                session: session,
                activePhaseLabel: attemptPhaseLabel,
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
              ttftMs = streamed.ttftMs;
            } else {
              final toolsSection = allowTools && toolRound == 0
                  ? '\n\n${toolRegistry.formatToolsGuideSection()}'
                  : '';
              final combinedPrompt =
                  '${VibeChatDialog.defaultSystemInstruction}\n\n'
                  'GUIDE DE MODÉLISATION :\n$systemGuide$toolsSection\n\n'
                  '$roundPrompt';
              response = await _invokeGenerate(
                combinedPrompt,
                roundAttachments,
                cancellationToken: session.cancellationToken,
              );
              final parser = VibeIncrementalStreamParser()..addChunk(response);
              finalSnapshot = parser.current;
            }
          } catch (error, stackTrace) {
            llmStopwatch.stop();
            finalSnapshot =
                session.lastStreamSnapshot ?? VibeStreamSnapshot.empty;
            if (error is VibeCancelledException ||
                session.cancellationToken.isCancelled) {
              rethrow;
            }
            _recordTimedTrace(
              session,
              phase: 'llm',
              label:
                  'Tentative ${attempt + 1}/$maxAttempts (${error.runtimeType})',
              durationMs: llmStopwatch.elapsedMilliseconds,
              detail: finalSnapshot.estimatedComponentCount > 0
                  ? '${finalSnapshot.estimatedComponentCount} comp. reçus avant coupure'
                  : _describeErrorCause(error),
              isError: true,
              scopeLabel: traceScopeLabel,
            );
            debugPrint(
              '[Vibe IA][$traceScopeLabel] Échec de génération à la tentative ${attempt + 1} '
              '(tour outil $toolRound, ${llmStopwatch.elapsedMilliseconds}ms, ${error.runtimeType}) : '
              '$error\n$stackTrace',
            );
            rethrow;
          }
          llmStopwatch.stop();
          _recordTimedTrace(
            session,
            phase: 'llm',
            label: nativeCalls.isNotEmpty
                ? 'LLM → ${nativeCalls.length} outil(s) (T${attempt + 1})'
                : 'LLM réponse (T${attempt + 1})',
            durationMs: llmStopwatch.elapsedMilliseconds,
            detail: [
              if (ttftMs != null) 'TTFT $ttftMs ms',
              '${response.length} car.',
              if (finalSnapshot.estimatedComponentCount > 0)
                '${finalSnapshot.estimatedComponentCount} comp.',
            ].join(', '),
            scopeLabel: traceScopeLabel,
          );

          if (nativeCalls.isNotEmpty) {
            if (!allowTools) {
              exceededNativeToolRounds = true;
              break;
            }
            debugPrint(
              '[Vibe IA][$traceScopeLabel] Exécution de ${nativeCalls.length} outil(s) natif(s) : '
              '${nativeCalls.map((c) => c.name).join(', ')}',
            );
            _updateStreamingSnapshot(
              (_streamingSnapshot.value ?? finalSnapshot).copyWith(
                activeToolStatus: _formatToolStatusLabel(nativeCalls),
                toolTraces: List<VibeToolTrace>.unmodifiable(
                  session.toolTraces,
                ),
                elapsedMs: session.turnStopwatch.elapsedMilliseconds,
                activePhaseLabel: attemptPhaseLabel,
                timedTraces: List<VibeTimedTrace>.unmodifiable(
                  session.timedTraces,
                ),
              ),
            );
            final toolsWatch = Stopwatch()..start();
            final results = await _awaitCancellable(
              toolRegistry.executeAll(nativeCalls),
              session.cancellationToken,
            );
            toolsWatch.stop();
            _recordToolTraces(
              session,
              nativeCalls,
              results,
              scopeLabel: traceScopeLabel,
            );
            _recordTimedTrace(
              session,
              phase: 'tool',
              label: 'Outils (${nativeCalls.map((c) => c.name).join(', ')})',
              durationMs: toolsWatch.elapsedMilliseconds,
              isError: results.any((r) => r.isError),
              scopeLabel: traceScopeLabel,
            );
            _updateStreamingSnapshot(
              (_streamingSnapshot.value ?? finalSnapshot).copyWith(
                activeToolStatus: _formatToolStatusLabel(nativeCalls),
                toolTraces: List<VibeToolTrace>.unmodifiable(
                  session.toolTraces,
                ),
                elapsedMs: session.turnStopwatch.elapsedMilliseconds,
                activePhaseLabel: attemptPhaseLabel,
                timedTraces: List<VibeTimedTrace>.unmodifiable(
                  session.timedTraces,
                ),
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
            final isLastToolRound =
                toolRound + 1 >= VibeChatDialog.maxToolRounds;
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
              '[Vibe IA][$traceScopeLabel] Exécution de ${jsonToolCalls.length} outil(s) JSON : '
              '${jsonToolCalls.map((c) => c.name).join(', ')}',
            );
            _updateStreamingSnapshot(
              (_streamingSnapshot.value ?? finalSnapshot).copyWith(
                activeToolStatus: _formatToolStatusLabel(jsonToolCalls),
                toolTraces: List<VibeToolTrace>.unmodifiable(
                  session.toolTraces,
                ),
                elapsedMs: session.turnStopwatch.elapsedMilliseconds,
                activePhaseLabel: attemptPhaseLabel,
                timedTraces: List<VibeTimedTrace>.unmodifiable(
                  session.timedTraces,
                ),
              ),
            );
            final toolsWatch = Stopwatch()..start();
            final results = await _awaitCancellable(
              toolRegistry.executeAll(jsonToolCalls),
              session.cancellationToken,
            );
            toolsWatch.stop();
            _recordToolTraces(
              session,
              jsonToolCalls,
              results,
              scopeLabel: traceScopeLabel,
            );
            _recordTimedTrace(
              session,
              phase: 'tool',
              label:
                  'Outils JSON (${jsonToolCalls.map((c) => c.name).join(', ')})',
              durationMs: toolsWatch.elapsedMilliseconds,
              isError: results.any((r) => r.isError),
              scopeLabel: traceScopeLabel,
            );
            _updateStreamingSnapshot(
              (_streamingSnapshot.value ?? finalSnapshot).copyWith(
                activeToolStatus: _formatToolStatusLabel(jsonToolCalls),
                toolTraces: List<VibeToolTrace>.unmodifiable(
                  session.toolTraces,
                ),
                elapsedMs: session.turnStopwatch.elapsedMilliseconds,
                activePhaseLabel: attemptPhaseLabel,
                timedTraces: List<VibeTimedTrace>.unmodifiable(
                  session.timedTraces,
                ),
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
            final isLastToolRound =
                toolRound + 1 >= VibeChatDialog.maxToolRounds;
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
        _logLong(
          '[Vibe IA] Réponse brute (tentative ${attempt + 1})',
          response,
        );

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
              '[Vibe IA][$traceScopeLabel] Échec de jsonDecode (tentative ${attempt + 1}) : '
              '${error.message} (offset: ${error.offset})',
            );
            rethrow;
          }
        }
        if (result is! Map<String, dynamic>) {
          debugPrint(
            '[Vibe IA][$traceScopeLabel] Le JSON décodé n’est pas un Map<String, dynamic> '
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
            ? VibeExecutionPlan.tryFromJson(
                result['plan'],
                reproduceExact: _reproduceExactMode,
              )
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
        final sanitizedEnvelope =
            VibeRepositoryApplier.sanitizeResponseEnvelope(result);
        final effectiveResult = sanitizedEnvelope.response;
        decodedMap = effectiveResult;
        for (final warning in sanitizedEnvelope.warnings) {
          debugPrint(
            '[Vibe IA][$traceScopeLabel] ${warning.replaceFirst('[Vibe IA] ', '')}',
          );
          VibeDebugCapture.recordTypedError(
            message: warning,
            category: DebugErrorCategory.binding,
            severity: DebugSeverity.warning,
            source: 'VibeRepositoryApplier.sanitizeEnvelope',
            visibleInUi: false,
          );
        }
        final repositoriesPatch = _extractRepositoriesPatch(effectiveResult);
        final patch = _extractPatch(effectiveResult);
        final hasToolRepoChanges = session.repoTransaction?.hasChanges ?? false;
        if (repositoriesPatch == null &&
            patch == null &&
            !session.hasCheckpoint &&
            (!hasToolRepoChanges || rawAskUser != null || rawPlan != null)) {
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
              '[Vibe IA][$traceScopeLabel] Réponse sans patch ni message valide. '
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
        final applyStopwatch = Stopwatch()..start();
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
        await session.repoTransaction?.assertAllSchemasValid();
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
          if (_visibleOnlyMode && session.visibleViewportSnapshot != null) {
            effectivePatch = VibeScopeHelpers.filterPatchToVisibleViewport(
              current,
              effectivePatch,
              session.visibleViewportSnapshot!,
            );
          }
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
          final patchTargets = _describePatchTargets(effectivePatch);
          if (VibeChatDialog.verboseLogging) {
            final formattedPatch = const JsonEncoder.withIndent('  ')
                .convert(effectivePatch);
            _logLong(
              '[Vibe IA][$traceScopeLabel] Patch à appliquer',
              formattedPatch,
            );
          } else {
            debugPrint(
              '[Vibe IA][$traceScopeLabel] Patch à appliquer (${encodedPatch.length} car.) — '
              '${activeScope != null ? 'scope="${activeScope.displayLabel}", ' : ''}'
              '$patchTargets.',
            );
          }
          try {
            appearance = AppearanceTransfer.applyVibe(
              current,
              encodedPatch,
              codec: widget.codec,
            );
            appearance = _inferMissingDefaultUsages(
              current,
              appearance,
              effectivePatch,
            );
            session.lastAppliedEffectivePatch = effectivePatch;
          } catch (error, stackTrace) {
            debugPrint(
              '[Vibe IA][$traceScopeLabel] Échec lors de AppearanceTransfer.applyVibe '
              '(tentative ${attempt + 1}, ${error.runtimeType}) : $error\n'
              '$stackTrace',
            );
            rethrow;
          }
          try {
            widget.validateAppearance?.call(appearance);
          } catch (error, stackTrace) {
            debugPrint(
              '[Vibe IA][$traceScopeLabel] Échec lors de validateAppearance '
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
          final appliedDiff = _describeAppearanceDiff(current, appearance);
          if (appliedDiff.isNotEmpty) {
            debugPrint(
              '[Vibe IA][$traceScopeLabel] Diff composants appliqué : $appliedDiff.',
            );
          }
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
        applyStopwatch.stop();
        _recordTimedTrace(
          session,
          phase: 'apply',
          label: 'Application & validation patch',
          durationMs: applyStopwatch.elapsedMilliseconds,
          detail: appearance == null
              ? 'repositories seuls'
              : '${appearance.components.length} comp.',
          scopeLabel: traceScopeLabel,
        );

        _lastFailedResponse = null;
        var finalResult = effectiveResult;
        var hasRepoUpdates =
            (session.repoTransaction?.hasChanges ?? false) ||
            repositoriesPatch != null;

        // Phase finale « Valeurs réactives » (exécutée avant « Vérif. rendu »
        // afin que la vérification post-rendu contrôle aussi les calculs,
        // liaisons et graphiques ajoutés ou ajustés).
        final wantsPostReactiveValues =
            _reactiveValuesEnabled &&
            !isIntermediatePlanLot &&
            !session.suppressUiUpdates &&
            (appearance != null || hasRepoUpdates);
        if (wantsPostReactiveValues) {
          final reactiveStopwatch = Stopwatch()..start();
          final reactive = await _runPostReactiveValuesPass(
            candidateAppearance: appearance ?? session.checkpointAppearance,
            systemGuide: systemGuide,
            session: session,
            toolRegistry: toolRegistry,
            isDirectGemini: isDirectGemini,
            useStreaming: useStreaming,
            cachedAttachments: effectiveCachedAttachments,
            traceScopeLabel: traceScopeLabel,
          );
          reactiveStopwatch.stop();
          _recordTimedTrace(
            session,
            phase: 'reactive',
            label: 'Valeurs réactives',
            durationMs: reactiveStopwatch.elapsedMilliseconds,
            detail: _describeReactivePassDetail(
              appearanceUpdated: reactive.updatedAppearance != null,
              repositoriesUpdated: reactive.repositoriesUpdated,
            ),
            scopeLabel: traceScopeLabel,
          );
          if (reactive.updatedAppearance != null) {
            appearance = reactive.updatedAppearance;
          }
          if (reactive.repositoriesUpdated) {
            hasRepoUpdates = true;
          }
          if ((reactive.updatedAppearance != null ||
                  reactive.repositoriesUpdated) &&
              reactive.summaryMessage != null &&
              reactive.summaryMessage!.isNotEmpty) {
            finalResult = <String, dynamic>{
              ...finalResult,
              'message': reactive.summaryMessage,
            };
          }
        }

        var detectedPostErrors = const <DebugEntry>[];
        if (appearance != null &&
            toolRegistry.isNotEmpty &&
            !session.suppressUiUpdates) {
          var errorCheckMarker = attemptDebugMarker;
          if (!_isWidgetTestBinding || _effectiveSmartVerifyLocalGate) {
            errorCheckMarker = VibeDebugCapture.markNow();
            _setPreviewAppearance(appearance);
            session.hasAppliedLivePreview = true;
            _syncLivePageOutcome(session, widget.controller.value);
            SchedulerBinding.instance.ensureVisualUpdate();
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
            errorCheckMarker,
            type: DebugEntryType.error,
            forAutoVerify: true,
          );
        }
        final explicitVerifyRender =
            effectiveResult['verifyRender'] == true ||
            (effectiveResult['vibe'] is Map &&
                (effectiveResult['vibe'] as Map)['verifyRender'] == true);
        final hasRuntimeErrorTrigger =
            !isIntermediatePlanLot && detectedPostErrors.isNotEmpty;
        final hasExactModeTrigger =
            _reproduceExactMode &&
            !isIntermediatePlanLot &&
            isDirectGemini &&
            VibeMountedSlotIndex.instance.allEntries.isNotEmpty;
        final wantsPostVerify =
            appearance != null &&
            toolRegistry.isNotEmpty &&
            !session.suppressUiUpdates &&
            ((_verifyRenderEnabled && explicitVerifyRender) ||
                hasRuntimeErrorTrigger ||
                hasExactModeTrigger);
        if (wantsPostVerify) {
          final verifyStopwatch = Stopwatch()..start();
          String? precomputedAuditSummary;
          var skipLlmVerify = false;
          final hasImageAttachment = attachments.any((a) => a.isImage);
          if (_effectiveSmartVerifyLocalGate &&
              !hasRuntimeErrorTrigger &&
              !hasExactModeTrigger &&
              !hasImageAttachment) {
            final localGate = await _evaluateLocalVerifyRenderGate(
              candidateAppearance: appearance,
              session: session,
              traceScopeLabel: traceScopeLabel,
            );
            precomputedAuditSummary = localGate.precomputedAuditSummary;
            if (localGate.satisfiedLocally) {
              skipLlmVerify = true;
              verifyStopwatch.stop();
              debugPrint(
                '[Vibe IA][$traceScopeLabel][PostVerify] Court-circuit local : '
                '0 anomalie détectée (${verifyStopwatch.elapsedMilliseconds}ms), '
                'appel LLM post-rendu évité.',
              );
              _recordTimedTrace(
                session,
                phase: 'verify',
                label: 'Vérification post-rendu (locale)',
                durationMs: verifyStopwatch.elapsedMilliseconds,
                detail: 'conforme sans appel IA',
                scopeLabel: traceScopeLabel,
              );
            }
          }
          if (!skipLlmVerify) {
            final verified = await _runPostRenderVerifyPass(
              candidateAppearance: appearance,
              systemGuide: systemGuide,
              session: session,
              toolRegistry: toolRegistry,
              isDirectGemini: isDirectGemini,
              useStreaming: useStreaming,
              cachedAttachments: effectiveCachedAttachments,
              detectedErrors: detectedPostErrors,
              precomputedAuditSummary: precomputedAuditSummary,
              traceScopeLabel: traceScopeLabel,
            );
            verifyStopwatch.stop();
            _recordTimedTrace(
              session,
              phase: 'verify',
              label: 'Vérification post-rendu',
              durationMs: verifyStopwatch.elapsedMilliseconds,
              detail: verified.correctedAppearance != null
                  ? 'ajustement appliqué'
                  : 'conforme',
              scopeLabel: traceScopeLabel,
            );
            if (verified.correctedAppearance != null) {
              appearance = verified.correctedAppearance;
            }
            if (verified.summaryMessage != null &&
                verified.summaryMessage!.isNotEmpty) {
              finalResult = <String, dynamic>{
                ...finalResult,
                'message': verified.summaryMessage,
              };
            }
          }
        }
        attemptStopwatch.stop();
        return (
          appearance: appearance,
          repositoriesUpdated:
              hasRepoUpdates || (session.repoTransaction?.hasChanges ?? false),
          result: finalResult,
          askUser: null,
          plan: null,
        );
      } catch (error) {
        attemptStopwatch.stop();
        session.livePreviewDisabled = true;
        try {
          await session.liveRepoQueue;
        } catch (_) {}

        if (error is VibeCancelledException ||
            session.cancellationToken.isCancelled) {
          await _rollbackTurnSession(session);
          throw const VibeCancelledException();
        }

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
        final isTransportRetryable = _isRetryableTransportError(error);
        final canAttemptSalvage =
            allowPlan == false || isValidationError || isTransportRetryable;
        final canRetry =
            attempt < maxAttempts - 1 &&
            (isValidationError || isTransportRetryable);

        final cause = _describeErrorCause(error);
        priorCauses.add(
          'Tentative ${attempt + 1} (${error.runtimeType}) : $cause',
        );

        // Tentative de récupération incrémentale (checkpoint des entrées déjà valides) :
        final effectiveSnapshot = finalSnapshot != VibeStreamSnapshot.empty
            ? finalSnapshot
            : (session.lastStreamSnapshot ?? VibeStreamSnapshot.empty);
        final salvageStopwatch = Stopwatch()..start();
        var salvage = VibeSalvageOutcome.none(session.checkpointAppearance);
        Map<String, dynamic>? effectiveCandidatePatch;

        if (canAttemptSalvage &&
            (decodedMap != null ||
                effectiveSnapshot.partialVibePatch != null ||
                effectiveSnapshot.partialRepositoriesPatch != null)) {
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
            rawReposCandidate = effectiveSnapshot.partialRepositoriesPatch;
            rawVibeCandidate = effectiveSnapshot.partialVibePatch;
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

          effectiveCandidatePatch = buildEffectiveCandidate(
            wasTruncated
                ? (session.repoTransaction?.aliasToActualId ??
                      const <String, String>{})
                : preRollbackAliases,
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
            wasTruncated: wasTruncated,
            interruptedSection: wasTruncated
                ? effectiveSnapshot.activeSection
                : null,
            interruptedKey: wasTruncated
                ? effectiveSnapshot.activeEntryKey
                : null,
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
        }
        salvageStopwatch.stop();

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
          _recordTimedTrace(
            session,
            phase: 'salvage',
            label: 'Tentative ${attempt + 1}/$maxAttempts → checkpoint partiel',
            durationMs: attemptStopwatch.elapsedMilliseconds,
            detail: _formatSalvageSummary(session, salvage),
            isError: true,
            scopeLabel: traceScopeLabel,
          );
        }

        if (!canRetry) {
          if (preserveCheckpointOnFailure &&
              session.hasCheckpoint &&
              lastCheckpointSalvage != null) {
            session.preservedFailureCheckpoint = _LotPartialCheckpoint(
              baseAppearance: session.baseAppearance,
              checkpointAppearance: session.checkpointAppearance,
              salvage: lastCheckpointSalvage,
              pendingComponentFixes: Set<String>.unmodifiable(
                session.pendingComponentFixes,
              ),
              requiresScreenAttachment: session.requiresScreenAttachment,
              priorCauses: List<String>.unmodifiable(priorCauses),
              collectedToolResults: List<Map<String, Object?>>.unmodifiable(
                collectedToolResults,
              ),
              collectedToolAttachments: List<VibeChatAttachment>.unmodifiable([
                ...attemptAttachments,
                ...collectedToolAttachments,
              ]),
              repoTransaction: session.repoTransaction,
              repoSavepoint: session.repoCheckpoint,
              summary: _formatSalvageSummary(session, lastCheckpointSalvage),
            );
            debugPrint(
              '[Vibe IA][$traceScopeLabel] Échec final après ${attempt + 1} tentative(s) — '
              'checkpoint partiel préservé pour retry partiel (${session.preservedFailureCheckpoint!.summary}).',
            );
          } else if (!salvage.hasCheckpoint) {
            _recordTimedTrace(
              session,
              phase: 'retry',
              label:
                  'Tentative ${attempt + 1}/$maxAttempts — échec final ($cause)',
              durationMs: attemptStopwatch.elapsedMilliseconds,
              isError: true,
              scopeLabel: traceScopeLabel,
            );
          }
          await _rollbackTurnSession(session);
          debugPrint(
            '[Vibe IA][$traceScopeLabel] Tentative ${attempt + 1} échouée sans relance '
            '(${error.runtimeType}, ${attemptStopwatch.elapsedMilliseconds}ms) : $cause',
          );
          rethrow;
        }

        if (salvage.hasCheckpoint) {
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
            '[Vibe IA][$traceScopeLabel] Tentative ${attempt + 1} rejetée ($cause, '
            '${attemptStopwatch.elapsedMilliseconds}ms). '
            'Checkpoint partiel conservé (salvage ${salvageStopwatch.elapsedMilliseconds}ms : '
            '${_formatSalvageSummary(session, salvage)}). '
            'Relance automatique en mode delta partiel...',
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
          _recordTimedTrace(
            session,
            phase: 'retry',
            label:
                'Tentative ${attempt + 1}/$maxAttempts → maintien checkpoint',
            durationMs: attemptStopwatch.elapsedMilliseconds,
            detail: cause,
            isError: true,
            scopeLabel: traceScopeLabel,
          );
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
            '[Vibe IA][$traceScopeLabel] Tentative ${attempt + 1} rejetée ($cause, '
            '${attemptStopwatch.elapsedMilliseconds}ms). '
            'Maintien du checkpoint précédent et relance en mode delta...',
          );
          continue;
        }

        _recordTimedTrace(
          session,
          phase: 'retry',
          label: 'Tentative ${attempt + 1}/$maxAttempts → retry complet',
          durationMs: attemptStopwatch.elapsedMilliseconds,
          detail: cause,
          isError: true,
          scopeLabel: traceScopeLabel,
        );
        await _rollbackTurnSession(session);
        debugPrint(
          '[Vibe IA][$traceScopeLabel] Tentative ${attempt + 1} rejetée ($cause, '
          '${attemptStopwatch.elapsedMilliseconds}ms). '
          'Relance complète avec prompt de correction...',
        );
        if (collectedToolAttachments.isNotEmpty) {
          attemptAttachments = [
            ...attemptAttachments,
            ...collectedToolAttachments,
          ];
        }
        if (isTransportRetryable && response.trim().isEmpty) {
          if (!_isWidgetTestBinding) {
            await Future<void>.delayed(
              Duration(milliseconds: 250 * (attempt + 1)),
            );
          }
          currentTurnPrompt = turnPrompt;
        } else {
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
Si tu utilises "repositories", chaque "data" doit être un objet JSON {...} à la racine sans aucune clé débutant par "@" ni contenant ".", "[", "]", "?" ou espace, placé après "message" et avant "vibe" (uniquement si REPOSITORIES DISPONIBLES figure dans le contexte). N'émets JAMAIS de clé "vibe", "components", "styles", "behaviors", "usages", "pageCatalog" ou "responsiveLayout" à l'intérieur de "repositories" ("vibe" est strictement une clé racine). Réutilise prioritairement les IDs techniques exacts présents dans REPOSITORIES DISPONIBLES plutôt que d'inventer un alias. Pour tout nouveau repository, fournis son "jsonSchema" conforme à "data" (sans clés "@..." et sans "x-mask"/"pattern" redondant sur "format": "date").
Si tu crées une page dans "pageCatalog", son chemin doit commencer par un seul "/", être différent de "/" (car "/" est déjà réservé par la page racine "root" / "mainLayout"), ne contenir ni espace, ni "?", ni "#", et ne pas se terminer par "/".
Pour modifier la page d’accueil "/" existante, configure directement "root" et "mainLayout" sans ajouter de page "/" dans "pageCatalog" (ou utilise un chemin distinct comme "/accueil" avec "homePageId").
Réponse précédente invalide :
$response
''';
        }
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

  static const Set<String> _envelopeOnlyKeys = <String>{
    'message',
    'askUser',
    'plan',
    'toolCalls',
    'verifyRender',
    'repositories',
  };

  static Map<String, dynamic> _stripEnvelopeKeys(Map<String, dynamic> raw) {
    var cleaned = raw;
    if (raw.keys.any(_envelopeOnlyKeys.contains)) {
      cleaned = <String, dynamic>{
        for (final entry in raw.entries)
          if (!_envelopeOnlyKeys.contains(entry.key)) entry.key: entry.value,
      };
    }
    if (cleaned['data'] case final Map<String, dynamic> innerData
        when innerData.keys.any(_envelopeOnlyKeys.contains)) {
      cleaned = <String, dynamic>{
        ...cleaned,
        'data': <String, dynamic>{
          for (final entry in innerData.entries)
            if (!_envelopeOnlyKeys.contains(entry.key)) entry.key: entry.value,
        },
      };
    }
    return cleaned;
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
      final cleaned = _stripEnvelopeKeys(vibe);
      return _hasPatchChanges(cleaned) ? cleaned : null;
    }
    final candidate = _stripEnvelopeKeys(result);
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
        for (final shell in next.pageCatalog.shells) shell.id,
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
    final resolvedPageRouting =
        _activeTurnSession?.pageRouting ??
        widget.pageRouting ??
        (mounted ? SuperApp.maybeOf(context)?.pageRouting : null);
    final codedRoutePaths = resolvedPageRouting == null
        ? const <String>[]
        : <String>[
            for (final route in resolvedPageRouting.codedRoutes) route.path,
          ];
    return VibePromptBuilder.buildTurnPrompt(
      questioningDirective: _questioningLevel.promptDirective(
        afterAskUserReply: _isAfterAskUserReply,
        forceFollowUpQuestions: _isForceFollowUpQuestions,
        planMode: _planMode,
      ),
      conversation: _buildConversationHistory(),
      appearance: appearanceOverride ?? _currentAppearance,
      codec: widget.codec,
      scope: _scope,
      instantiatedComponentIds:
          instantiatedIdsOverride ?? widget.registry?.instantiatedComponentIds,
      mountedSlotSummaries: VibeMountedSlotIndex.instance
          .mountedSlotSummaries(),
      codedRoutePaths: codedRoutePaths,
      repositoriesContext: repositoriesContext,
      planMode: _planMode,
      reproduceExactMode: _reproduceExactMode,
      visibleOnlyMode: _visibleOnlyMode,
      visibleViewportContext:
          (_activeTurnSession?.visibleViewportSnapshot ??
                  (_visibleOnlyMode
                      ? _captureVisibleViewportSnapshot(
                          appearanceOverride ?? _currentAppearance,
                        )
                      : null))
              ?.toPromptContext(),
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
    List<VibeTimedTrace> timedTraces = const [],
    int? generationDurationMs,
    VibeRetryTurnPayload? retryTurn,
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
          timedTraces: timedTraces,
          generationDurationMs: generationDurationMs,
          retryTurn: retryTurn,
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
                    if (completionEvent != null &&
                        headerBadgePalette != null) ...[
                      Container(
                        key: const ValueKey(
                          'vibe-chat-header-completion-badge',
                        ),
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
                    Icon(
                      Icons.drag_indicator,
                      color: scheme.onPrimary,
                      size: 18,
                    ),
                    if (widget.onExpandedChanged != null)
                      IconButton(
                        key: const ValueKey('vibe-chat-toggle-expand'),
                        tooltip: _expanded
                            ? 'Réduire en bas à droite'
                            : 'Agrandir au centre',
                        onPressed: () => _setExpanded(!_expanded),
                        icon: Icon(
                          _expanded
                              ? Icons.close_fullscreen
                              : Icons.open_in_full,
                          color: scheme.onPrimary,
                          size: 18,
                        ),
                      ),
                    IconButton(
                      key: const ValueKey('vibe-chat-close'),
                      tooltip: 'Fermer le chat',
                      onPressed: () {
                        _cancelActiveAiCall();
                        widget.onClose();
                      },
                      icon: Icon(
                        Icons.close,
                        color: scheme.onPrimary,
                        size: 20,
                      ),
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
                            // Padding(
                            //   padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                            //   child: Text(
                            //     'Votre demande et la configuration de l’écran sont envoyées à Gemini.',
                            //     maxLines: 2,
                            //     overflow: TextOverflow.ellipsis,
                            //     style: Theme.of(context).textTheme.bodySmall,
                            //   ),
                            // ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    for (final mode in VibeAiSpeedMode.values)
                                      VibeSpeedModeChip(
                                        mode: mode,
                                        icon: _iconForSpeedMode(mode),
                                        selected: _speedMode == mode,
                                        enabled: !_isBusy,
                                        onSelected: () => _setSpeedMode(mode),
                                      ),
                                    SizedBox(
                                      height: 18,
                                      child: VerticalDivider(
                                        key: const ValueKey(
                                          'vibe-chat-speed-plan-divider',
                                        ),
                                        width: 1,
                                        thickness: 1,
                                        color: scheme.outlineVariant,
                                      ),
                                    ),
                                    VibePlanModeChip(
                                      selected: _planMode,
                                      enabled: !_isBusy,
                                      onToggle: () => _setPlanMode(!_planMode),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 2, 12, 2),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(
                                  key: const ValueKey('vibe-chat-actions-wrap'),
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    VibeReproduceExactChip(
                                      selected: _reproduceExactMode,
                                      enabled: !_isBusy,
                                      onToggle: () => _setReproduceExactMode(
                                        !_reproduceExactMode,
                                      ),
                                    ),
                                    VibeVisibleOnlyChip(
                                      selected: _visibleOnlyMode,
                                      enabled: !_isBusy,
                                      onToggle: () => _setVisibleOnlyMode(
                                        !_visibleOnlyMode,
                                      ),
                                    ),
                                    VibeVerifyRenderChip(
                                      selected: _verifyRenderEnabled,
                                      enabled: !_isBusy,
                                      onToggle: () => _setVerifyRenderEnabled(
                                        !_verifyRenderEnabled,
                                      ),
                                    ),
                                    VibeReactiveValuesChip(
                                      selected: _reactiveValuesEnabled,
                                      enabled: !_isBusy,
                                      onToggle: () => _setReactiveValuesEnabled(
                                        !_reactiveValuesEnabled,
                                      ),
                                    ),
                                    VibeAuditActionChip(
                                      enabled: !_isBusy,
                                      scoped: _scope != null,
                                      visibleOnly: _visibleOnlyMode,
                                      onPressed: _runPageAudit,
                                    ),
                                  ],
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
                                        value: _questioningLevel.index
                                            .toDouble(),
                                        min: 0,
                                        max:
                                            (VibeQuestioningLevel
                                                        .values
                                                        .length -
                                                    1)
                                                .toDouble(),
                                        divisions:
                                            VibeQuestioningLevel.values.length -
                                            1,
                                        label: _questioningLevel.label,
                                        onChanged:
                                            _isBusy || _reproduceExactMode
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
                                              _planMode
                                                  ? 'Style fidèle à la source (Design System ignoré) • Plan & lots auto'
                                                  : 'Style fidèle à la source (Design System ignoré)',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    scheme.onTertiaryContainer,
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
                                      onRestyle:
                                          _restyleWithSelectedDesignSystem,
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
                                      child: activeScope.isMultiTarget
                                          ? Tooltip(
                                              message: activeScope.allTargets
                                                  .map(
                                                    (t) =>
                                                        '• ${t.displayLabel}',
                                                  )
                                                  .join('\n'),
                                              child: Text(
                                                'Scope : ${activeScope.displayLabel}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: scheme
                                                      .onSecondaryContainer,
                                                ),
                                              ),
                                            )
                                          : Text(
                                              'Scope : ${activeScope.displayLabel}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    scheme.onSecondaryContainer,
                                              ),
                                            ),
                                    ),
                                    IconButton(
                                      key: const ValueKey(
                                        'vibe-chat-clear-scope',
                                      ),
                                      tooltip:
                                          'Retirer la restriction de scope',
                                      visualDensity: VisualDensity.compact,
                                      iconSize: 16,
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints.tightFor(
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
                          if (_sending || _activeParallelSessions.isNotEmpty)
                            VibeStreamingAssistantBubble(
                              snapshot: _streamingSnapshot,
                              onCancel: _cancelActiveAiCall,
                            ),
                          for (var i = _messages.length - 1; i >= 0; i--)
                            VibeMessageBubble(
                              message: _messages[i],
                              sending: _isBusy,
                              isActivePlan: _activePlanMessageIndex == i,
                              canRetryFinishedPlan:
                                  _messages[i].plan != null &&
                                  _activePlanMessageIndex == null &&
                                  !_messages
                                      .skip(i + 1)
                                      .any((m) => m.plan != null),
                              speechTranscriber: widget.speechTranscriber,
                              onSpeechError: (message) {
                                if (mounted) {
                                  setState(() => _attachmentError = message);
                                }
                              },
                              onSubmitAskUser: (answers) => _submitAskUser(
                                i,
                                answers,
                                usedDefaults: false,
                              ),
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
                                  : (answers) =>
                                        _submitAskMoreFromCard(i, answers),
                              onRequestMoreQuestions:
                                  _canShowMessageMoreQuestions(i)
                                  ? _requestMoreQuestionsFromChat
                                  : null,
                              onRetryTurn: _messages[i].retryTurn != null
                                  ? () => _retryFailedTurn(i)
                                  : null,
                              onStartPlan: () =>
                                  _startPlanExecution(i, parallel: false),
                              onStartPlanParallel: _planMode
                                  ? () => _startPlanExecution(i, parallel: true)
                                  : null,
                              onCancelPlan: () => _cancelPlan(i),
                              onStopPlan: () => _stopPlan(i),
                              onRetryPlanLot: () =>
                                  _retryPlanLot(i, partial: false),
                              onRetryPlanLotPartial: () =>
                                  _retryPlanLot(i, partial: true),
                              onRetryPlanAll: () => _retryPlanAll(i),
                              onResumePlan: () => _resumePlan(i),
                              onSkipPlanLot: () => _skipPlanLot(i),
                              onTogglePlanLot: (lotIndex) =>
                                  _togglePlanLot(i, lotIndex),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
                      ActionChip(
                        key: const ValueKey('vibe-chat-generate-design-md'),
                        avatar: Icon(
                          Icons.palette_outlined,
                          size: 16,
                          color: scheme.primary,
                        ),
                        label: const Text('Générer DESIGN.md'),
                        tooltip: 'Analyser les pièces jointes pour générer et ajouter un DESIGN.md à la liste des Design Systems',
                        visualDensity: VisualDensity.compact,
                        onPressed: _isBusy
                            ? null
                            : _generateDesignSystemFromAttachments,
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
                              : _planMode
                              ? 'Décris l’écran ou les changements à planifier par lots…'
                              : _visibleOnlyMode
                              ? 'Décris les ajouts ou retouches sur l’onglet et le scroll visibles…'
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
                  _isBusy
                      ? IconButton.filled(
                          key: const ValueKey('vibe-chat-cancel'),
                          tooltip: _executingPlan
                              ? 'Annuler l’appel IA et arrêter le plan'
                              : 'Annuler l’appel IA en cours',
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.errorContainer,
                            foregroundColor: scheme.onErrorContainer,
                          ),
                          onPressed: _cancelActiveAiCall,
                          icon: const Icon(Icons.stop_rounded),
                        )
                      : IconButton.filled(
                          key: const ValueKey('vibe-chat-send'),
                          tooltip: _planMode
                              ? 'Analyser et préparer le plan par lots'
                              : 'Générer et appliquer',
                          onPressed: _send,
                          icon: const Icon(Icons.send),
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

final class _LotPartialCheckpoint {
  const _LotPartialCheckpoint({
    required this.baseAppearance,
    required this.checkpointAppearance,
    required this.salvage,
    required this.pendingComponentFixes,
    required this.requiresScreenAttachment,
    required this.priorCauses,
    required this.collectedToolResults,
    required this.collectedToolAttachments,
    required this.repoTransaction,
    required this.repoSavepoint,
    required this.summary,
  });

  final Appearance baseAppearance;
  final Appearance checkpointAppearance;
  final VibeSalvageOutcome salvage;
  final Set<String> pendingComponentFixes;
  final bool requiresScreenAttachment;
  final List<String> priorCauses;
  final List<Map<String, Object?>> collectedToolResults;
  final List<VibeChatAttachment> collectedToolAttachments;
  final VibeRepositoryTurnTransaction? repoTransaction;
  final VibeRepositorySavepoint? repoSavepoint;
  final String summary;
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
    this.visibleViewportSnapshot,
  }) : checkpointAppearance = baseAppearance,
       lastPreviewAppearance = baseAppearance;

  Appearance rawInitialAppearance;
  Appearance baseAppearance;
  final Set<String>? initialInstantiatedIds;
  final EditorPageRouter? pageRouting;
  final String? initialRouteLocation;
  final Set<String> initialPageIds;
  final VibeRepositoryTurnTransaction? repoTransaction;
  final VibeVisibleViewportSnapshot? visibleViewportSnapshot;
  final VibeCancellationToken cancellationToken = VibeCancellationToken();

  Appearance checkpointAppearance;
  bool hasCheckpoint = false;
  bool requiresScreenAttachment = false;
  final Set<String> pendingComponentFixes = <String>{};
  VibeRepositorySavepoint? repoCheckpoint;

  Appearance lastPreviewAppearance;
  int lastAppliedPatchRevision = 0;
  int lastAppliedNonUsagesRevision = 0;
  int lastAppliedAliasCount = 0;
  int lastAppliedRepositoriesRevision = 0;
  int? lastPreviewApplyElapsedMs;
  int appliedPreviewStepCount = 0;
  int suppressedPreviewLogCount = 0;
  VibeIncrementalPreviewApplier? previewApplier;
  String? lastHighlightSection;
  String? lastHighlightEntryKey;
  Appearance? lastHighlightAppearance;
  Appearance? cachedSubtreeAppearance;
  VibeChatScope? cachedSubtreeScope;
  Set<String>? cachedSubtreeIds;
  VibeStreamSnapshot? deferredPreviewSnapshot;
  Timer? deferredPreviewTimer;
  VibeStreamSnapshot? pendingRepoQueueSnapshot;
  bool repoQueueDraining = false;
  Future<void> liveRepoQueue = Future<void>.value();
  bool livePreviewDisabled = false;
  bool suppressUiUpdates = false;
  void Function(VibeStreamSnapshot snapshot)? onStreamProgress;
  bool hasAppliedLivePreview = false;
  Map<String, dynamic>? lastAppliedEffectivePatch;
  String? liveNavigatedTargetKey;
  String? liveNavigatedPageId;
  bool hasNavigatedForVisualChange = false;
  DesignSystemPreset? registeredDesignSystem;
  bool registeredDesignSystemSelected = false;
  final List<VibeToolTrace> toolTraces = <VibeToolTrace>[];
  final List<VibeTimedTrace> timedTraces = <VibeTimedTrace>[];
  final Stopwatch turnStopwatch = Stopwatch()..start();
  VibeStreamSnapshot? lastStreamSnapshot;
  _LotPartialCheckpoint? preservedFailureCheckpoint;
  int attemptsExecuted = 0;
  final VibeDebugMarker turnStartMarker = VibeDebugCapture.markNow();
  final VibePreviewStateTracker previewTracker = VibePreviewStateTracker();

  void disposePreviewTimer() {
    deferredPreviewTimer?.cancel();
    deferredPreviewTimer = null;
    deferredPreviewSnapshot = null;
    pendingRepoQueueSnapshot = null;
  }
}

/// Modèle agrégé immuable du volet de conception UX en 4 étapes ([UxForgeSpec]).
library;

import 'package:flutter/foundation.dart';

import '../spec_forge_stage.dart';
import 'ux_coherence_issue.dart';
import 'ux_forge_stage.dart';
import 'ux_journey_spec.dart';
import 'ux_navigation_spec.dart';
import 'ux_screen_spec.dart';

/// Spécification UX complète d'un projet (parcours, navigation/thème, écrans et cohérence).
@immutable
class UxForgeSpec {
  /// Construit une spécification UX immuable normalisée sur les 4 étapes de [UxForgeStage].
  UxForgeSpec({
    this.currentStage = UxForgeStage.userJourneys,
    List<UxJourneySpec> journeys = const <UxJourneySpec>[],
    UxNavigationSpec? navigation,
    List<UxScreenSpec> screens = const <UxScreenSpec>[],
    Map<UxForgeStage, UxStageState>? stageStates,
    List<UxCoherenceIssue> coherenceIssues = const <UxCoherenceIssue>[],
  }) : journeys = List<UxJourneySpec>.unmodifiable(journeys),
       navigation = navigation ?? UxNavigationSpec.empty,
       screens = List<UxScreenSpec>.unmodifiable(screens),
       stageStates = Map<UxForgeStage, UxStageState>.unmodifiable(
         _normalizeStageStates(stageStates),
       ),
       coherenceIssues = List<UxCoherenceIssue>.unmodifiable(coherenceIssues);

  /// Spécification UX vide initiale.
  static final UxForgeSpec empty = UxForgeSpec();

  /// Étape actuellement sélectionnée dans le wizard UX.
  final UxForgeStage currentStage;

  /// Livrable de l'étape UX 1 : parcours utilisateurs bout-en-bout.
  final List<UxJourneySpec> journeys;

  /// Livrable de l'étape UX 2 : architecture de navigation et thème visuel.
  final UxNavigationSpec navigation;

  /// Livrable de l'étape UX 3 : schémas directeurs d'écrans, zones et actions.
  final List<UxScreenSpec> screens;

  /// Historique conversationnel et statut de chacune des 4 étapes UX.
  final Map<UxForgeStage, UxStageState> stageStates;

  /// Diagnostics de cohérence Métier↔UX relevés (locaux et/ou IA).
  final List<UxCoherenceIssue> coherenceIssues;

  /// Vrai si au moins un livrable UX, diagnostic ou échange d'étape a été amorcé.
  bool get hasContent =>
      journeys.isNotEmpty ||
      navigation.hasContent ||
      screens.isNotEmpty ||
      coherenceIssues.isNotEmpty ||
      stageStates.values.any(
        (s) =>
            s.messages.isNotEmpty ||
            s.status != SpecStageStatus.notStarted ||
            s.stageSummary.trim().isNotEmpty,
      );

  /// Retourne l'état d'une étape UX donnée (garanti non nul).
  UxStageState stageStateFor(UxForgeStage stage) =>
      stageStates[stage] ?? UxStageState(stage: stage);

  /// Retourne une copie avec l'état d'une étape UX mis à jour.
  UxForgeSpec withStageState(UxStageState nextState) {
    final nextMap = Map<UxForgeStage, UxStageState>.from(stageStates)
      ..[nextState.stage] = nextState;
    return copyWith(stageStates: nextMap);
  }

  /// Retourne une copie positionnée sur [targetStage] en validant optionnellement l'étape courante.
  UxForgeSpec moveToStage(
    UxForgeStage targetStage, {
    bool validateCurrentStage = false,
  }) {
    final nextMap = Map<UxForgeStage, UxStageState>.from(stageStates);
    if (validateCurrentStage && currentStage != targetStage) {
      final current = stageStateFor(currentStage);
      nextMap[currentStage] = current.copyWith(
        status: SpecStageStatus.validated,
      );
    }
    final target = nextMap[targetStage] ?? UxStageState(stage: targetStage);
    if (target.status == SpecStageStatus.notStarted) {
      nextMap[targetStage] = target.copyWith(
        status: SpecStageStatus.inProgress,
      );
    }
    return copyWith(currentStage: targetStage, stageStates: nextMap);
  }

  /// Recherche un parcours utilisateur par identifiant, code `JRN-xxx` ou nom (insensible à la casse).
  UxJourneySpec? findJourney(String idOrCode) {
    final needle = idOrCode.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final journey in journeys) {
      if (journey.id.toLowerCase() == needle ||
          (journey.code.isNotEmpty && journey.code.toLowerCase() == needle)) {
        return journey;
      }
    }
    for (final journey in journeys) {
      if (journey.name.toLowerCase() == needle) return journey;
    }
    return null;
  }

  /// Recherche un écran par identifiant, code `SCR-xxx`, `routeId` ou nom (insensible à la casse).
  UxScreenSpec? findScreen(String idOrCodeOrRouteId) {
    final needle = idOrCodeOrRouteId.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final screen in screens) {
      if (screen.id.toLowerCase() == needle ||
          (screen.code.isNotEmpty && screen.code.toLowerCase() == needle) ||
          (screen.routeId.isNotEmpty &&
              screen.routeId.toLowerCase() == needle)) {
        return screen;
      }
    }
    for (final screen in screens) {
      if (screen.name.toLowerCase() == needle) return screen;
    }
    return null;
  }

  /// Vérifie les invariants structurels de l'ensemble de la spécification UX.
  void validate() {
    final journeyIds = <String>{};
    for (final journey in journeys) {
      journey.validate();
      if (!journeyIds.add(journey.id)) {
        throw FormatException('Parcours UX dupliqué : ${journey.id}');
      }
    }

    navigation.validate();

    final screenIds = <String>{};
    for (final screen in screens) {
      screen.validate();
      if (!screenIds.add(screen.id)) {
        throw FormatException('Écran UX dupliqué : ${screen.id}');
      }
    }

    for (final state in stageStates.values) {
      state.validate();
    }

    final issueIds = <String>{};
    for (final issue in coherenceIssues) {
      issue.validate();
      if (!issueIds.add(issue.id)) {
        throw FormatException(
          'Diagnostic de cohérence UX dupliqué : ${issue.id}',
        );
      }
    }
  }

  /// Produit un instantané JSON concis adapté à l'injection dans le prompt de [stage].
  Map<String, Object?> toCompactContextJson(UxForgeStage stage) =>
      <String, Object?>{
        'currentUxStage': stage.name,
        'journeys': [for (final j in journeys) j.toJson()],
        if (stage.index >= UxForgeStage.iaNavigation.index ||
            navigation.hasContent)
          'navigation': navigation.toJson(),
        if (stage.index >= UxForgeStage.screenBlueprints.index ||
            screens.isNotEmpty)
          'screens': [for (final s in screens) s.toJson()],
        if (stage == UxForgeStage.uxReviewExport &&
            coherenceIssues.isNotEmpty)
          'coherenceIssues': [for (final i in coherenceIssues) i.toJson()],
      };

  /// Retourne une copie modifiée.
  UxForgeSpec copyWith({
    UxForgeStage? currentStage,
    List<UxJourneySpec>? journeys,
    UxNavigationSpec? navigation,
    List<UxScreenSpec>? screens,
    Map<UxForgeStage, UxStageState>? stageStates,
    List<UxCoherenceIssue>? coherenceIssues,
  }) => UxForgeSpec(
    currentStage: currentStage ?? this.currentStage,
    journeys: journeys ?? this.journeys,
    navigation: navigation ?? this.navigation,
    screens: screens ?? this.screens,
    stageStates: stageStates ?? this.stageStates,
    coherenceIssues: coherenceIssues ?? this.coherenceIssues,
  );

  /// Sérialise la spécification UX complète en JSON.
  Map<String, Object?> toJson() => <String, Object?>{
    'currentStage': currentStage.name,
    'journeys': [for (final j in journeys) j.toJson()],
    'navigation': navigation.toJson(),
    'screens': [for (final s in screens) s.toJson()],
    'stageStates': <String, Object?>{
      for (final entry in stageStates.entries)
        entry.key.name: entry.value.toJson(),
    },
    'coherenceIssues': [for (final i in coherenceIssues) i.toJson()],
  };

  /// Désérialise une spécification UX depuis JSON (retourne [empty] si `raw == null`).
  factory UxForgeSpec.fromJson(Object? raw) {
    if (raw == null) return UxForgeSpec.empty;
    if (raw is! Map) {
      throw const FormatException('UxForgeSpec doit être un objet JSON.');
    }

    final parsedJourneys = <UxJourneySpec>[];
    final seenJourneyIds = <String>{};
    if (raw['journeys'] is List) {
      for (final item in raw['journeys'] as List) {
        var journey = UxJourneySpec.fromJson(item);
        if (!seenJourneyIds.add(journey.id)) {
          var suffix = 2;
          while (!seenJourneyIds.add('${journey.id}_$suffix')) {
            suffix++;
          }
          journey = journey.copyWith(id: '${journey.id}_$suffix');
        }
        parsedJourneys.add(journey);
      }
    }

    final parsedScreens = <UxScreenSpec>[];
    final seenScreenIds = <String>{};
    if (raw['screens'] is List) {
      for (final item in raw['screens'] as List) {
        var screen = UxScreenSpec.fromJson(item);
        if (!seenScreenIds.add(screen.id)) {
          var suffix = 2;
          while (!seenScreenIds.add('${screen.id}_$suffix')) {
            suffix++;
          }
          screen = screen.copyWith(id: '${screen.id}_$suffix');
        }
        parsedScreens.add(screen);
      }
    }

    final rawStageStates = raw['stageStates'];
    final parsedStageStates = <UxForgeStage, UxStageState>{};
    if (rawStageStates is Map) {
      for (final stage in UxForgeStage.values) {
        final rawStage = rawStageStates[stage.name];
        if (rawStage != null) {
          parsedStageStates[stage] = UxStageState.fromJson(
            rawStage,
            fallbackStage: stage,
          );
        }
      }
    }

    final parsedIssues = <UxCoherenceIssue>[];
    final seenIssueIds = <String>{};
    if (raw['coherenceIssues'] is List) {
      for (final item in raw['coherenceIssues'] as List) {
        var issue = UxCoherenceIssue.fromJson(item);
        if (!seenIssueIds.add(issue.id)) {
          var suffix = 2;
          while (!seenIssueIds.add('${issue.id}_$suffix')) {
            suffix++;
          }
          issue = issue.copyWith(id: '${issue.id}_$suffix');
        }
        parsedIssues.add(issue);
      }
    }

    final spec = UxForgeSpec(
      currentStage: UxForgeStage.fromJson(raw['currentStage']),
      journeys: parsedJourneys,
      navigation: UxNavigationSpec.fromJson(raw['navigation']),
      screens: parsedScreens,
      stageStates: parsedStageStates,
      coherenceIssues: parsedIssues,
    );
    spec.validate();
    return spec;
  }

  static Map<UxForgeStage, UxStageState> _normalizeStageStates(
    Map<UxForgeStage, UxStageState>? source,
  ) => <UxForgeStage, UxStageState>{
    for (final stage in UxForgeStage.values)
      stage: source?[stage] ?? UxStageState(stage: stage),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UxForgeSpec &&
          other.currentStage == currentStage &&
          listEquals(other.journeys, journeys) &&
          other.navigation == navigation &&
          listEquals(other.screens, screens) &&
          mapEquals(other.stageStates, stageStates) &&
          listEquals(other.coherenceIssues, coherenceIssues);

  @override
  int get hashCode => Object.hash(
    currentStage,
    Object.hashAll(journeys),
    navigation,
    Object.hashAll(screens),
    Object.hashAll(stageStates.values),
    Object.hashAll(coherenceIssues),
  );
}

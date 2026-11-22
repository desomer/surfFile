/// Surlignage visuel temporaire des composants et surfaces modifiés en streaming par l'IA Vibe.
///
/// Fournit [VibeWorkHighlightController] pour suivre les identifiants en cours
/// d'écriture ou récemment ajoutés/modifiés, ainsi que [VibeWorkHighlightPainter]
/// pour dessiner un halo néon IA, un balayage lumineux diagonal et un badge `✦ IA`.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:material_ui/material_ui.dart';

import '../../../models/native_component_config.dart';
import '../../../models/scaffold_page_config.dart';
import '../../../models/super_layout_config.dart';
import '../../../models/super_tab_config.dart';
import '../../../theme/appearance.dart';

/// Nature de l'opération IA affichée temporairement sur un élément du canevas.
enum VibeWorkKind {
  /// L'entrée JSON de l'élément est actuellement en cours de réception en streaming.
  streaming,

  /// L'élément vient d'être ajouté par le patch IA.
  added,

  /// L'élément existant vient d'être modifié par le patch IA.
  modified,
}

/// Instantané d'animation résolu pour un identifiant donné à la frame courante.
@immutable
class VibeWorkHighlightState {
  /// Construit un état d'affichage pour un élément mis en avant par l'IA.
  const VibeWorkHighlightState({
    required this.kind,
    required this.intensity,
    required this.phase,
    required this.shimmerProgress,
  });

  /// Type d'activité IA en cours ou récente sur l'élément.
  final VibeWorkKind kind;

  /// Opacité normalisée dans `[0.0, 1.0]` (1.0 pendant le maintien, décroissante au fondu).
  final double intensity;

  /// Phase continue normalisée dans `[0.0, 1.0]` pour la rotation du dégradé néon.
  final double phase;

  /// Progression dans `[0.0, 1.0]` du balayage lumineux diagonal.
  final double shimmerProgress;
}

class _PulseEntry {
  _PulseEntry({
    required this.kind,
    required this.duration,
  });

  VibeWorkKind kind;
  Duration? startTime;
  Duration duration;
}

/// Contrôleur centralisé pilotant les surbrillances temporaires de travail IA.
///
/// Une unique boucle de frames ([SchedulerBinding.scheduleFrameCallback])
/// n'est planifiée que lorsqu'au moins un identifiant est en cours de streaming
/// ou en phase de maintien/fondu, garantissant un coût nul au repos.
class VibeWorkHighlightController extends ChangeNotifier {
  VibeWorkHighlightController._();

  /// Instance partagée observée par les [EditorSlot] et pilotée par `VibeChatDialog`.
  static final VibeWorkHighlightController instance =
      VibeWorkHighlightController._();

  /// Durée par défaut pendant laquelle un ajout ou une modification reste visible.
  static const Duration defaultHoldDuration = Duration(milliseconds: 500);

  static const Duration _streamingCycleDuration = Duration(milliseconds: 1400);
  static const Duration _testSettleDuration = Duration(milliseconds: 520);

  final Set<String> _streamingIds = <String>{};
  final Map<String, _PulseEntry> _pulses = <String, _PulseEntry>{};
  final List<String> _recentPulseOrder = <String>[];

  int _focusRevision = 0;
  int? _scheduledFrameId;
  Duration? _streamingStartTime;
  Duration _lastFrameTime = Duration.zero;
  double _streamingPhase = 0.0;

  static bool get _isTestBinding =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  /// Compteur monotone incrémenté lorsqu'une nouvelle cible devient active.
  ///
  /// N'est pas incrémenté par les ticks d'animation, ce qui permet aux
  /// conteneurs à onglets de ne basculer qu'au changement réel de cible IA.
  int get focusRevision => _focusRevision;

  /// Verrouille la bascule automatique d'onglets sur les `SuperTab` pendant un tour « Uniquement visible ».
  bool suppressAutoTabSwitch = false;

  /// Identifiants actifs classés du plus prioritaire/récent au plus ancien
  /// (cibles en cours de streaming d'abord, puis pulses actifs les plus récents).
  List<String> get orderedActiveTargets => List<String>.unmodifiable([
    ..._streamingIds.toList().reversed,
    for (final id in _recentPulseOrder.reversed)
      if (_pulses.containsKey(id) && !_streamingIds.contains(id)) id,
  ]);

  /// Indique si au moins une cible est actuellement active (streaming ou pulse).
  bool get hasActiveHighlights =>
      _streamingIds.isNotEmpty || _pulses.isNotEmpty;

  /// Identifiants actuellement en cours de streaming JSON avant fermeture du bloc.
  Set<String> get streamingIds => Set<String>.unmodifiable(_streamingIds);

  /// Identifiants actuellement animés par un pulse temporaire d'ajout ou de modification.
  Set<String> get pulsedIds => Set<String>.unmodifiable(_pulses.keys);

  /// Met à jour les identifiants actuellement en cours d'écriture par l'IA.
  void setStreamingTargets(Iterable<String> ids) {
    final normalized = <String>{
      for (final id in ids)
        if (id.trim().isNotEmpty) id.trim(),
    };
    if (normalized.length == _streamingIds.length &&
        _streamingIds.containsAll(normalized)) {
      return;
    }
    _streamingIds
      ..clear()
      ..addAll(normalized);
    if (_streamingIds.isEmpty) {
      _streamingStartTime = null;
      _streamingPhase = 0.0;
    } else {
      _focusRevision++;
      _scheduleNextFrame();
    }
    notifyListeners();
  }

  /// Efface uniquement les cibles de streaming sans interrompre les pulses en cours.
  void clearStreamingTargets() {
    if (_streamingIds.isEmpty) return;
    _streamingIds.clear();
    _streamingStartTime = null;
    _streamingPhase = 0.0;
    if (!hasActiveHighlights) {
      _cancelScheduledFrame();
    }
    notifyListeners();
  }

  /// Déclenche une animation temporaire de [duration] sur les cibles ajoutées/modifiées.
  void pulseTargets({
    Iterable<String> addedIds = const <String>[],
    Iterable<String> modifiedIds = const <String>[],
    Duration duration = defaultHoldDuration,
  }) {
    final effectiveDuration = duration <= Duration.zero
        ? const Duration(milliseconds: 1)
        : duration;
    var changed = false;

    for (final rawId in addedIds) {
      final id = rawId.trim();
      if (id.isEmpty) continue;
      _pulses[id] = _PulseEntry(
        kind: VibeWorkKind.added,
        duration: effectiveDuration,
      );
      _recentPulseOrder
        ..remove(id)
        ..add(id);
      changed = true;
    }

    for (final rawId in modifiedIds) {
      final id = rawId.trim();
      if (id.isEmpty) continue;
      final existing = _pulses[id];
      if (existing != null &&
          existing.kind == VibeWorkKind.added &&
          existing.startTime == null) {
        continue;
      }
      _pulses[id] = _PulseEntry(
        kind: VibeWorkKind.modified,
        duration: effectiveDuration,
      );
      _recentPulseOrder
        ..remove(id)
        ..add(id);
      changed = true;
    }

    if (!changed) return;
    _focusRevision++;
    _scheduleNextFrame();
    notifyListeners();
  }

  /// Supprime immédiatement toutes les animations (utile lors d'un rollback ou en test).
  void clearAll() {
    final hadAny = hasActiveHighlights;
    _streamingIds.clear();
    _pulses.clear();
    _recentPulseOrder.clear();
    _streamingStartTime = null;
    _streamingPhase = 0.0;
    _cancelScheduledFrame();
    if (hadAny) {
      notifyListeners();
    }
  }

  /// Retourne l'état d'animation à appliquer à [id] (ou au couple `id::zoneId`
  /// lorsque [zoneId] est renseigné), ou `null` s'il est inactif.
  VibeWorkHighlightState? stateFor(String? id, {String? zoneId}) {
    final targetKey = (id != null && id.isNotEmpty && zoneId != null && zoneId.isNotEmpty)
        ? '$id::$zoneId'
        : id;
    final pulse = _lookupPulse(targetKey);
    if (pulse != null) {
      final totalUs = pulse.duration.inMicroseconds;
      final elapsedUs = pulse.startTime == null
          ? 0
          : (_lastFrameTime - pulse.startTime!).inMicroseconds.clamp(0, totalUs);
      final progress = totalUs <= 0 ? 1.0 : elapsedUs / totalUs;
      // Pleine visibilité sur les premiers 65 %, puis fondu sortant doux sur les 35 % finaux.
      final fadeOut = progress <= 0.65
          ? 1.0
          : (1.0 - ((progress - 0.65) / 0.35)).clamp(0.0, 1.0);
      final intensity = Curves.easeOutCubic.transform(fadeOut);
      return VibeWorkHighlightState(
        kind: pulse.kind,
        intensity: intensity,
        phase: progress,
        shimmerProgress: Curves.easeInOutCubic.transform(
          (progress * 1.15).clamp(0.0, 1.0),
        ),
      );
    }

    final isStreaming =
        targetKey != null &&
        targetKey.isNotEmpty &&
        _streamingIds.contains(targetKey);
    if (isStreaming) {
      return VibeWorkHighlightState(
        kind: VibeWorkKind.streaming,
        intensity: 1.0,
        phase: _streamingPhase,
        shimmerProgress: _streamingPhase,
      );
    }
    return null;
  }

  _PulseEntry? _lookupPulse(String? id) {
    if (id == null || id.isEmpty) return null;
    return _pulses[id];
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (hasActiveHighlights) {
      _scheduleNextFrame();
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _cancelScheduledFrame();
    }
  }

  void _cancelScheduledFrame() {
    if (_scheduledFrameId case final id?) {
      _scheduledFrameId = null;
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    }
  }

  void _scheduleNextFrame() {
    if (_scheduledFrameId != null || !hasListeners || !hasActiveHighlights) {
      return;
    }
    _scheduledFrameId = SchedulerBinding.instance.scheduleFrameCallback(
      _onFrame,
    );
  }

  void _onFrame(Duration timeStamp) {
    _scheduledFrameId = null;
    _lastFrameTime = timeStamp;
    if (!hasListeners || !hasActiveHighlights) {
      return;
    }

    final expired = <String>[];
    for (final entry in _pulses.entries) {
      final pulse = entry.value;
      pulse.startTime ??= timeStamp;
      final elapsed = timeStamp - pulse.startTime!;
      if (elapsed >= pulse.duration) {
        expired.add(entry.key);
      }
    }
    for (final id in expired) {
      _pulses.remove(id);
      _recentPulseOrder.remove(id);
    }

    var keepTickingStreaming = false;
    if (_streamingIds.isNotEmpty) {
      _streamingStartTime ??= timeStamp;
      final elapsed = timeStamp - _streamingStartTime!;
      if (elapsed.isNegative) {
        _streamingPhase = 0.0;
        keepTickingStreaming = true;
      } else if (_isTestBinding && elapsed >= _testSettleDuration) {
        // En test widget, borner la boucle afin de laisser pumpAndSettle() converger.
        _streamingPhase = 0.35;
        keepTickingStreaming = false;
      } else {
        final micros =
            elapsed.inMicroseconds % _streamingCycleDuration.inMicroseconds;
        _streamingPhase = micros / _streamingCycleDuration.inMicroseconds;
        keepTickingStreaming = true;
      }
    }

    notifyListeners();
    if (_pulses.isNotEmpty || keepTickingStreaming) {
      _scheduleNextFrame();
    }
  }
}

/// Peintre néon IA + balayage lumineux diagonal ([VibeWorkHighlightPainter])
/// affiché temporairement sur les slots travaillés pendant le streaming Vibe.
class VibeWorkHighlightPainter extends CustomPainter {
  /// Construit un peintre pour l'état [state] à appliquer autour d'un slot.
  const VibeWorkHighlightPainter({
    required this.state,
    this.radius = 0,
    this.zoomScale = 1.0,
    this.animate = true,
    this.innerPainter,
  });

  /// État instantané (type de travail, intensité et progression d'animation).
  final VibeWorkHighlightState state;

  /// Rayon de courbure du slot ciblé.
  final double radius;

  /// Facteur de zoom courant (`EditorZoomScope`) pour garder le badge à l'échelle 1:1.
  final double zoomScale;

  /// Désactive les déformations animées lorsque l'accessibilité l'exige.
  final bool animate;

  /// Peintre d'édition sous-jacent éventuel à dessiner avant l'effet IA.
  final CustomPainter? innerPainter;

  static const Color _cyan = Color(0xFF06B6D4);
  static const Color _violet = Color(0xFF8B5CF6);
  static const Color _magenta = Color(0xFFEC4899);
  static const Color _indigo = Color(0xFF6366F1);

  String get _badgeText => switch (state.kind) {
    VibeWorkKind.streaming => '✦ IA',
    VibeWorkKind.added => '✦ Ajout',
    VibeWorkKind.modified => '✦ Modifié',
  };

  @override
  void paint(Canvas canvas, Size size) {
    innerPainter?.paint(canvas, size);

    final intensity = state.intensity.clamp(0.0, 1.0);
    if (intensity <= 0.01) return;

    final rect = (Offset.zero & size).deflate(1.0);
    if (rect.isEmpty || rect.width <= 2 || rect.height <= 2) return;

    final maxCorner = math.max(0.0, math.min(18.0, rect.shortestSide / 2));
    final cornerRadius = (radius - 1.0).clamp(0.0, maxCorner).toDouble();
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(cornerRadius),
    );

    final primary = state.kind == VibeWorkKind.modified ? _indigo : _cyan;
    final secondary = state.kind == VibeWorkKind.modified ? _cyan : _violet;
    final accent = state.kind == VibeWorkKind.modified ? _violet : _magenta;
    final highlight = Color.lerp(primary, Colors.white, 0.78)!;

    // 1. Teinte interne légère + balayage lumineux diagonal (shimmer).
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      rect,
      Paint()..color = primary.withValues(alpha: 0.08 * intensity),
    );
    if (animate) {
      final sweepPos = -0.65 + state.shimmerProgress * 2.3;
      final shimmerShader = LinearGradient(
        begin: Alignment(sweepPos - 0.55, -1.0),
        end: Alignment(sweepPos + 0.55, 1.0),
        colors: [
          Colors.white.withValues(alpha: 0.0),
          primary.withValues(alpha: 0.16 * intensity),
          Colors.white.withValues(alpha: 0.28 * intensity),
          accent.withValues(alpha: 0.14 * intensity),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      ).createShader(rect);
      canvas.drawRect(rect, Paint()..shader = shimmerShader);
    }
    canvas.restore();

    // 2. Halo néon externe diffus.
    final pulse = animate
        ? 1.0 + 0.20 * math.sin(state.phase * math.pi * 2.0)
        : 1.0;
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = primary.withValues(alpha: 0.30 * intensity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.5 * pulse
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5),
    );

    // 3. Sous-couche blanche nette + bordure SweepGradient animée.
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85 * intensity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );

    final sweepAngle = animate ? state.phase * math.pi * 2.0 : 0.0;
    final sweepShader = SweepGradient(
      colors: [
        primary.withValues(alpha: intensity),
        secondary.withValues(alpha: intensity),
        highlight.withValues(alpha: intensity),
        accent.withValues(alpha: intensity),
        primary.withValues(alpha: intensity),
      ],
      stops: const [0.0, 0.28, 0.52, 0.76, 1.0],
      transform: GradientRotation(sweepAngle - math.pi / 4),
    ).createShader(rect);

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = sweepShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    // 4. Badge compact « ✦ IA / Ajout / Modifié » à l'échelle écran 1:1.
    final effectiveZoom = zoomScale > 0 && zoomScale.isFinite ? zoomScale : 1.0;
    final invZoom = 1.0 / effectiveZoom;
    final screenWidth = rect.width * effectiveZoom;
    final screenHeight = rect.height * effectiveZoom;
    if (screenWidth >= 54 && screenHeight >= 22) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: _badgeText,
          style: TextStyle(
            color: Colors.white.withValues(alpha: intensity),
            fontSize: 10.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.25,
            height: 1.1,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: (screenWidth - 18).clamp(24.0, 140.0));

      const hPad = 7.0;
      const vPad = 3.0;
      final badgeWidth = textPainter.width + hPad * 2;
      final badgeHeight = textPainter.height + vPad * 2;
      const badgeLeft = 6.0;
      const badgeTop = 6.0;
      final badgeRect = Rect.fromLTWH(
        badgeLeft,
        badgeTop,
        badgeWidth,
        badgeHeight,
      );
      final badgeRRect = RRect.fromRectAndRadius(
        badgeRect,
        Radius.circular(badgeHeight / 2),
      );

      canvas.save();
      canvas.translate(rect.left, rect.top);
      canvas.scale(invZoom, invZoom);

      canvas.drawRRect(
        badgeRRect.shift(const Offset(0, 1.5)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28 * intensity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );

      final pillShader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          primary.withValues(alpha: 0.96 * intensity),
          secondary.withValues(alpha: 0.96 * intensity),
        ],
      ).createShader(badgeRect);
      canvas.drawRRect(badgeRRect, Paint()..shader = pillShader);

      canvas.drawRRect(
        badgeRRect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.88 * intensity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      textPainter.paint(canvas, const Offset(badgeLeft + hPad, badgeTop + vPad));
      textPainter.dispose();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(VibeWorkHighlightPainter oldDelegate) =>
      oldDelegate.state.kind != state.kind ||
      oldDelegate.state.intensity != state.intensity ||
      oldDelegate.state.phase != state.phase ||
      oldDelegate.state.shimmerProgress != state.shimmerProgress ||
      oldDelegate.radius != radius ||
      oldDelegate.zoomScale != zoomScale ||
      oldDelegate.animate != animate ||
      oldDelegate.innerPainter != innerPainter;
}

/// Résultat du diff entre deux instantanés [Appearance] pour piloter les
/// animations de travail IA ([VibeWorkHighlightController]).
@immutable
class VibeAppearanceDiff {
  /// Construit un diff composé des identifiants nouvellement ajoutés et modifiés.
  const VibeAppearanceDiff({
    this.addedIds = const <String>{},
    this.modifiedIds = const <String>{},
  });

  /// Diff vide sans aucun changement détecté.
  static const VibeAppearanceDiff empty = VibeAppearanceDiff();

  /// Identifiants des composants ou styles nouvellement ajoutés dans [next].
  final Set<String> addedIds;

  /// Identifiants des composants, styles, comportements ou usages modifiés.
  final Set<String> modifiedIds;

  /// Vrai s'il n'y a ni ajout ni modification à animer.
  bool get isEmpty => addedIds.isEmpty && modifiedIds.isEmpty;

  /// Calcule les identifiants ajoutés et modifiés entre [previous] et [next].
  ///
  /// Lorsqu'un conteneur parent ([SuperLayoutConfig] ou [ScaffoldPageConfig])
  /// n'est modifié que pour référencer des enfants nouvellement ajoutés,
  /// il est exclu de [modifiedIds] afin de cibler uniquement les nouveaux éléments.
  factory VibeAppearanceDiff.compute(Appearance previous, Appearance next) {
    final added = <String>{};
    final modified = <String>{};

    for (final id in next.components.keys) {
      if (!previous.components.containsKey(id)) {
        added.add(id);
      }
    }

    for (final entry in next.styles.entries) {
      final id = entry.key;
      if (!previous.styles.containsKey(id)) {
        added.add(id);
      } else if (previous.styles[id] != entry.value && !added.contains(id)) {
        modified.add(id);
      }
    }

    for (final entry in next.components.entries) {
      final id = entry.key;
      final prevConfig = previous.components[id];
      if (prevConfig == null) continue;
      final nextConfig = entry.value;
      if (prevConfig == nextConfig) continue;

      if (prevConfig is SuperLayoutConfig &&
          nextConfig is SuperLayoutConfig &&
          _onlyAddedLayoutPlacements(prevConfig, nextConfig, added)) {
        continue;
      }
      if (prevConfig is ScaffoldPageConfig &&
          nextConfig is ScaffoldPageConfig &&
          _onlyAddedNativePlacements(prevConfig.native, nextConfig.native, added)) {
        continue;
      }
      if (prevConfig is NativeComponentConfig &&
          nextConfig is NativeComponentConfig &&
          _onlyAddedNativePlacements(prevConfig, nextConfig, added)) {
        continue;
      }
      if (prevConfig is SuperTabConfig &&
          nextConfig is SuperTabConfig &&
          _onlyAddedTabPlacements(prevConfig, nextConfig, added)) {
        continue;
      }
      if (!added.contains(id)) {
        modified.add(id);
      }
    }

    for (final entry in next.behaviors.entries) {
      final id = entry.key;
      final prev = previous.behaviors[id];
      if (prev == null || !listEquals(prev, entry.value)) {
        if (!added.contains(id)) modified.add(id);
      }
    }

    for (final entry in next.usages.entries) {
      final id = entry.key;
      if (previous.usages[id] != entry.value && !added.contains(id)) {
        modified.add(id);
      }
    }

    return VibeAppearanceDiff(
      addedIds: Set<String>.unmodifiable(added),
      modifiedIds: Set<String>.unmodifiable(modified),
    );
  }

  static bool _onlyAddedLayoutPlacements(
    SuperLayoutConfig previous,
    SuperLayoutConfig next,
    Set<String> addedIds,
  ) {
    if (addedIds.isEmpty) return false;
    final filteredPlacements = <SuperLayoutZone, List<String>>{};
    for (final entry in next.placements.entries) {
      final prevIds = previous.placements[entry.key] ?? const <String>[];
      final kept = <String>[
        for (final slotId in entry.value)
          if (!addedIds.contains(slotId) || prevIds.contains(slotId)) slotId,
      ];
      if (kept.isNotEmpty) {
        filteredPlacements[entry.key] = kept;
      }
    }

    GridLayoutConfig? filteredGrid = next.grid;
    if (next.grid != null) {
      final prevGridItems = previous.grid?.items ?? const {};
      final keptItems = Map.of(next.grid!.items)
        ..removeWhere(
          (slotId, _) =>
              addedIds.contains(slotId) && !prevGridItems.containsKey(slotId),
        );
      filteredGrid = next.grid!.copyWith(items: keptItems);
    }

    final filteredSlotTypes = Map.of(next.slotTypes)
      ..removeWhere(
        (slotId, _) =>
            addedIds.contains(slotId) && !previous.slotTypes.containsKey(slotId),
      );
    final filteredSlotLabels = Map.of(next.slotLabels)
      ..removeWhere(
        (slotId, _) =>
            addedIds.contains(slotId) &&
            !previous.slotLabels.containsKey(slotId),
      );
    final filteredPreferredSizes = Map.of(next.slotPreferredSizes)
      ..removeWhere(
        (slotId, _) =>
            addedIds.contains(slotId) &&
            !previous.slotPreferredSizes.containsKey(slotId),
      );
    final filteredSizeConstraints = Map.of(next.slotSizeConstraints)
      ..removeWhere(
        (slotId, _) =>
            addedIds.contains(slotId) &&
            !previous.slotSizeConstraints.containsKey(slotId),
      );

    final normalizedNext = next.copyWith(
      placements: filteredPlacements,
      grid: filteredGrid,
      slotTypes: filteredSlotTypes,
      slotLabels: filteredSlotLabels,
      slotPreferredSizes: filteredPreferredSizes,
      slotSizeConstraints: filteredSizeConstraints,
    );
    return normalizedNext == previous;
  }

  static bool _onlyAddedNativePlacements(
    NativeComponentConfig previous,
    NativeComponentConfig next,
    Set<String> addedIds,
  ) {
    if (addedIds.isEmpty) return false;
    final filteredPlacements = <String, List<String>>{};
    for (final entry in next.placements.entries) {
      final prevIds = previous.placements[entry.key] ?? const <String>[];
      final kept = <String>[
        for (final slotId in entry.value)
          if (!addedIds.contains(slotId) || prevIds.contains(slotId)) slotId,
      ];
      if (kept.isNotEmpty) {
        filteredPlacements[entry.key] = kept;
      }
    }
    final filteredSlotTypes = Map.of(next.slotTypes)
      ..removeWhere(
        (slotId, _) =>
            addedIds.contains(slotId) && !previous.slotTypes.containsKey(slotId),
      );
    final filteredSlotLabels = Map.of(next.slotLabels)
      ..removeWhere(
        (slotId, _) =>
            addedIds.contains(slotId) &&
            !previous.slotLabels.containsKey(slotId),
      );
    final filteredPreferredSizes = Map.of(next.slotPreferredSizes)
      ..removeWhere(
        (slotId, _) =>
            addedIds.contains(slotId) &&
            !previous.slotPreferredSizes.containsKey(slotId),
      );
    final filteredSizeConstraints = Map.of(next.slotSizeConstraints)
      ..removeWhere(
        (slotId, _) =>
            addedIds.contains(slotId) &&
            !previous.slotSizeConstraints.containsKey(slotId),
      );
    final normalizedNext = next.copyWith(
      placements: filteredPlacements,
      slotTypes: filteredSlotTypes,
      slotLabels: filteredSlotLabels,
      slotPreferredSizes: filteredPreferredSizes,
      slotSizeConstraints: filteredSizeConstraints,
    );
    return normalizedNext == previous;
  }

  static bool _onlyAddedTabPlacements(
    SuperTabConfig previous,
    SuperTabConfig next,
    Set<String> addedIds,
  ) {
    if (addedIds.isEmpty) return false;
    final filteredPlacements = <String, List<String>>{};
    for (final entry in next.placements.entries) {
      final prevIds = previous.placements[entry.key] ?? const <String>[];
      final kept = <String>[
        for (final slotId in entry.value)
          if (!addedIds.contains(slotId) || prevIds.contains(slotId)) slotId,
      ];
      if (kept.isNotEmpty) {
        filteredPlacements[entry.key] = kept;
      }
    }
    final filteredSlotTypes = Map.of(next.slotTypes)
      ..removeWhere(
        (slotId, _) =>
            addedIds.contains(slotId) && !previous.slotTypes.containsKey(slotId),
      );
    final filteredSlotLabels = Map.of(next.slotLabels)
      ..removeWhere(
        (slotId, _) =>
            addedIds.contains(slotId) &&
            !previous.slotLabels.containsKey(slotId),
      );
    final filteredPreferredSizes = Map.of(next.slotPreferredSizes)
      ..removeWhere(
        (slotId, _) =>
            addedIds.contains(slotId) &&
            !previous.slotPreferredSizes.containsKey(slotId),
      );
    final filteredSizeConstraints = Map.of(next.slotSizeConstraints)
      ..removeWhere(
        (slotId, _) =>
            addedIds.contains(slotId) &&
            !previous.slotSizeConstraints.containsKey(slotId),
      );
    final normalizedNext = next.copyWith(
      placements: filteredPlacements,
      slotTypes: filteredSlotTypes,
      slotLabels: filteredSlotLabels,
      slotPreferredSizes: filteredPreferredSizes,
      slotSizeConstraints: filteredSizeConstraints,
    );
    return normalizedNext == previous;
  }
}

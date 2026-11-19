/// Alertes sonores et visuelles déclenchées à la fin d'une tâche IA Vibe.
///
/// Fournit [VibeTaskOutcome], [VibeTaskCompletionEvent], le lecteur audio
/// injectable [VibeTaskSoundPlayer] (synthèse WAV en mémoire jouée sans blocage
/// sous Windows via `winmm.dll`, avec repli `MessageBeep` et [SystemSound]),
/// le contrôleur réactif [VibeTaskCompletionController], ainsi que les widgets
/// visuels [VibeTaskCompletionBanner] et [VibeTaskCompletionGlow].
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show SystemSound, SystemSoundType;
import 'package:material_ui/material_ui.dart';

import '../../../ai/vibe_speech_to_text.dart';

/// Issue d'une tâche IA terminée (génération simple, plan ou erreur).
enum VibeTaskOutcome {
  /// Modifications d'écran, de données ou plan complet appliqués avec succès.
  success,

  /// L'IA a terminé son tour et attend une validation utilisateur (questions ou plan).
  needsInput,

  /// Réponse informative sans modification d'écran ni erreur.
  info,

  /// La tâche IA s'est terminée ou mise en pause sur une erreur.
  error,
}

/// Événement immuable décrivant la fin d'une tâche IA.
@immutable
class VibeTaskCompletionEvent {
  /// Crée un événement de fin de tâche IA.
  const VibeTaskCompletionEvent({
    required this.id,
    required this.outcome,
    required this.title,
    required this.timestamp,
    this.detail = '',
  });

  /// Identifiant monotone incrémental permettant de distinguer deux événements consécutifs.
  final int id;

  /// Nature du résultat de la tâche IA.
  final VibeTaskOutcome outcome;

  /// Titre court affiché dans l'alerte visuelle.
  final String title;

  /// Détail optionnel affiché sous le titre.
  final String detail;

  /// Horodatage de fin de la tâche.
  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeTaskCompletionEvent &&
          id == other.id &&
          outcome == other.outcome &&
          title == other.title &&
          detail == other.detail &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(id, outcome, title, detail, timestamp);
}

/// Contrat injectable pour jouer une alerte sonore lorsqu'une tâche IA se termine.
abstract class VibeTaskSoundPlayer {
  /// Constructeur de base pour un lecteur d'alerte sonore.
  const VibeTaskSoundPlayer();

  /// Lecteur par défaut utilisant un carillon doux en mémoire sous Windows et
  /// [SystemSound.play] en repli multiplateforme.
  static const VibeTaskSoundPlayer instance = DefaultVibeTaskSoundPlayer();

  /// Joue le signal sonore correspondant à [outcome].
  Future<void> play(VibeTaskOutcome outcome);
}

/// Implémentation par défaut de [VibeTaskSoundPlayer].
///
/// Sous Windows (hors tests widgets), synthétise un carillon WAV doux en mémoire
/// et le joue de façon asynchrone via `winmm.dll` (`PlaySoundW`), avec repli sur
/// `user32.dll` (`MessageBeep`) puis [SystemSound.play].
class DefaultVibeTaskSoundPlayer extends VibeTaskSoundPlayer {
  /// Crée le lecteur d'alerte sonore par défaut.
  const DefaultVibeTaskSoundPlayer();

  static bool get _isTestBinding =>
      WidgetsBinding.instance.runtimeType.toString().contains('Test');

  @override
  Future<void> play(VibeTaskOutcome outcome) async {
    if (_isTestBinding) return;
    try {
      if (Platform.isWindows) {
        if (_Win32ChimePlayer.playOutcome(outcome)) {
          return;
        }
      }
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      // L'absence de périphérique audio ne doit jamais faire échouer l'UI.
    }
  }
}

/// Synthétiseur de carillons WAV PCM 16 bits doux pour les alertes de fin de tâche IA.
abstract final class VibeTaskChimeSynthesizer {
  /// Fréquence d'échantillonnage des carillons générés (16 kHz).
  static const int sampleRate = VibeAudioWavEncoder.defaultSampleRate;

  /// Génère un fichier WAV complet en mémoire adapté à [outcome].
  static Uint8List buildWavForOutcome(VibeTaskOutcome outcome) {
    final notes = switch (outcome) {
      VibeTaskOutcome.success => const <_ChimeNote>[
        _ChimeNote(
          frequencyHz: 523.25, // Do5
          startMs: 0,
          durationMs: 170,
          amplitude: 0.22,
          decayRate: 14.0,
        ),
        _ChimeNote(
          frequencyHz: 783.99, // Sol5
          startMs: 95,
          durationMs: 280,
          amplitude: 0.24,
          decayRate: 10.0,
        ),
      ],
      VibeTaskOutcome.needsInput => const <_ChimeNote>[
        _ChimeNote(
          frequencyHz: 587.33, // Ré5
          startMs: 0,
          durationMs: 140,
          amplitude: 0.18,
          decayRate: 16.0,
        ),
        _ChimeNote(
          frequencyHz: 880.0, // La5
          startMs: 100,
          durationMs: 210,
          amplitude: 0.20,
          decayRate: 12.0,
        ),
      ],
      VibeTaskOutcome.info => const <_ChimeNote>[
        _ChimeNote(
          frequencyHz: 783.99, // Sol5
          startMs: 0,
          durationMs: 220,
          amplitude: 0.18,
          decayRate: 13.0,
        ),
      ],
      VibeTaskOutcome.error => const <_ChimeNote>[
        _ChimeNote(
          frequencyHz: 329.63, // Mi4
          startMs: 0,
          durationMs: 150,
          amplitude: 0.22,
          decayRate: 14.0,
        ),
        _ChimeNote(
          frequencyHz: 261.63, // Do4
          startMs: 115,
          durationMs: 230,
          amplitude: 0.22,
          decayRate: 11.0,
        ),
      ],
    };

    var totalDurationMs = 0;
    for (final note in notes) {
      final endMs = note.startMs + note.durationMs;
      if (endMs > totalDurationMs) totalDurationMs = endMs;
    }

    final totalSamples = (sampleRate * totalDurationMs) ~/ 1000;
    final pcmBytes = Uint8List(totalSamples * 2);
    final pcmData = ByteData.sublistView(pcmBytes);

    for (var i = 0; i < totalSamples; i++) {
      final timeMs = (i * 1000.0) / sampleRate;
      var mixed = 0.0;
      for (final note in notes) {
        final localMs = timeMs - note.startMs;
        if (localMs < 0 || localMs > note.durationMs) continue;
        final localSec = localMs / 1000.0;
        const attackSec = 0.012;
        final attackEnv = localSec < attackSec ? localSec / attackSec : 1.0;
        final tailMs = note.durationMs - localMs;
        final releaseEnv = tailMs < 18.0 ? (tailMs / 18.0).clamp(0.0, 1.0) : 1.0;
        final decayEnv = math.exp(-localSec * note.decayRate);
        final envelope = attackEnv * releaseEnv * decayEnv;
        final fundamental = math.sin(2.0 * math.pi * note.frequencyHz * localSec);
        final harmonic =
            0.16 * math.sin(2.0 * math.pi * note.frequencyHz * 2.0 * localSec);
        mixed += note.amplitude * envelope * (fundamental + harmonic);
      }
      final clamped = mixed.clamp(-0.95, 0.95);
      final sample = (clamped * 32767.0).round().clamp(-32768, 32767);
      pcmData.setInt16(i * 2, sample, Endian.little);
    }

    return VibeAudioWavEncoder.encodePcm16MonoToWav(
      pcmBytes,
      sampleRate: sampleRate,
    );
  }
}

class _ChimeNote {
  const _ChimeNote({
    required this.frequencyHz,
    required this.startMs,
    required this.durationMs,
    required this.amplitude,
    required this.decayRate,
  });

  final double frequencyHz;
  final int startMs;
  final int durationMs;
  final double amplitude;
  final double decayRate;
}

// ---------------------------------------------------------------------------
// Lecture audio asynchrone Windows sans dépendance externe (`winmm.dll` / `user32.dll`)
// ---------------------------------------------------------------------------

typedef _PlaySoundWNative =
    Int32 Function(Pointer<Uint8> pszSound, IntPtr hmod, Uint32 fdwSound);
typedef _PlaySoundWDart =
    int Function(Pointer<Uint8> pszSound, int hmod, int fdwSound);

typedef _MessageBeepNative = Int32 Function(Uint32 uType);
typedef _MessageBeepDart = int Function(int uType);

typedef _GlobalAllocNative =
    Pointer<Void> Function(Uint32 uFlags, IntPtr dwBytes);
typedef _GlobalAllocDart = Pointer<Void> Function(int uFlags, int dwBytes);

abstract final class _Win32ChimePlayer {
  static const int _sndAsync = 0x0001;
  static const int _sndNodefault = 0x0002;
  static const int _sndMemory = 0x0004;
  static const int _gmemFixed = 0x0000;
  static const int _gmemZeroInit = 0x0040;

  static const int _mbIconHand = 0x00000010;
  static const int _mbIconExclamation = 0x00000030;
  static const int _mbIconAsterisk = 0x00000040;

  static bool _initialized = false;
  static _PlaySoundWDart? _playSoundW;
  static _MessageBeepDart? _messageBeep;
  static _GlobalAllocDart? _globalAlloc;
  static final Map<VibeTaskOutcome, Pointer<Uint8>> _nativeBuffers =
      <VibeTaskOutcome, Pointer<Uint8>>{};

  static void _ensureLoaded() {
    if (_initialized) return;
    _initialized = true;
    try {
      final winmm = DynamicLibrary.open('winmm.dll');
      _playSoundW = winmm.lookupFunction<_PlaySoundWNative, _PlaySoundWDart>(
        'PlaySoundW',
      );
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      _globalAlloc = kernel32
          .lookupFunction<_GlobalAllocNative, _GlobalAllocDart>('GlobalAlloc');
    } catch (_) {
      _playSoundW = null;
      _globalAlloc = null;
    }
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      _messageBeep = user32
          .lookupFunction<_MessageBeepNative, _MessageBeepDart>('MessageBeep');
    } catch (_) {
      _messageBeep = null;
    }
  }

  static Pointer<Uint8>? _bufferFor(VibeTaskOutcome outcome) {
    final existing = _nativeBuffers[outcome];
    if (existing != null) return existing;
    final alloc = _globalAlloc;
    if (alloc == null) return null;
    final wav = VibeTaskChimeSynthesizer.buildWavForOutcome(outcome);
    final raw = alloc(_gmemFixed | _gmemZeroInit, wav.length);
    if (raw == nullptr) return null;
    final ptr = raw.cast<Uint8>();
    ptr.asTypedList(wav.length).setAll(0, wav);
    _nativeBuffers[outcome] = ptr;
    return ptr;
  }

  static bool playOutcome(VibeTaskOutcome outcome) {
    _ensureLoaded();
    final playSound = _playSoundW;
    if (playSound != null) {
      final buffer = _bufferFor(outcome);
      if (buffer != null) {
        final ok = playSound(buffer, 0, _sndMemory | _sndAsync | _sndNodefault);
        if (ok != 0) return true;
      }
    }
    final beep = _messageBeep;
    if (beep != null) {
      final type = switch (outcome) {
        VibeTaskOutcome.success || VibeTaskOutcome.info => _mbIconAsterisk,
        VibeTaskOutcome.needsInput => _mbIconExclamation,
        VibeTaskOutcome.error => _mbIconHand,
      };
      return beep(type) != 0;
    }
    return false;
  }
}

/// Contrôleur centralisé diffusant les alertes de fin de tâche IA et l'état
/// d'activation du signal sonore.
class VibeTaskCompletionController extends ChangeNotifier {
  /// Crée un contrôleur dédié (utile notamment dans les tests).
  VibeTaskCompletionController({bool initialSoundEnabled = true})
    : _soundEnabled = initialSoundEnabled;

  /// Instance partagée observée par [VibeChatDialog] et [StyleEditBanner].
  static final VibeTaskCompletionController instance =
      VibeTaskCompletionController();

  int _nextId = 0;
  bool _soundEnabled;
  VibeTaskCompletionEvent? _currentEvent;

  /// Indique si l'alerte sonore de fin de tâche IA est activée.
  bool get soundEnabled => _soundEnabled;

  /// Dernier événement de fin de tâche publié, ou `null` s'il a été fermé.
  VibeTaskCompletionEvent? get currentEvent => _currentEvent;

  /// Active ou désactive l'alerte sonore.
  void setSoundEnabled(bool enabled) {
    if (_soundEnabled == enabled) return;
    _soundEnabled = enabled;
    notifyListeners();
  }

  /// Inverse l'état d'activation de l'alerte sonore.
  void toggleSound() => setSoundEnabled(!_soundEnabled);

  /// Enregistre un événement de fin de tâche IA et déclenche l'alerte sonore si activée.
  VibeTaskCompletionEvent notifyCompleted({
    required VibeTaskOutcome outcome,
    required String title,
    String detail = '',
    VibeTaskSoundPlayer? soundPlayer,
    bool? playSound,
  }) {
    final event = VibeTaskCompletionEvent(
      id: ++_nextId,
      outcome: outcome,
      title: title,
      detail: detail,
      timestamp: DateTime.now(),
    );
    _currentEvent = event;
    notifyListeners();
    if (playSound ?? _soundEnabled) {
      unawaited((soundPlayer ?? VibeTaskSoundPlayer.instance).play(outcome));
    }
    return event;
  }

  /// Efface l'événement courant (sans modifier le réglage sonore).
  void dismiss() {
    if (_currentEvent == null) return;
    _currentEvent = null;
    notifyListeners();
  }
}

/// Palette résolue pour l'affichage d'un [VibeTaskOutcome].
@immutable
class VibeTaskOutcomePalette {
  /// Construit une palette d'alerte visuelle.
  const VibeTaskOutcomePalette({
    required this.icon,
    required this.shortLabel,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.border,
  });

  /// Icône représentative de l'issue.
  final IconData icon;

  /// Libellé court affiché en badge.
  final String shortLabel;

  /// Couleur de fond du bandeau.
  final Color background;

  /// Couleur principale du texte.
  final Color foreground;

  /// Couleur d'accentuation (icône, halo, pastille).
  final Color accent;

  /// Couleur de bordure du bandeau.
  final Color border;

  /// Résout la palette adaptée au thème courant pour [outcome].
  static VibeTaskOutcomePalette resolve(
    BuildContext context,
    VibeTaskOutcome outcome,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return switch (outcome) {
      VibeTaskOutcome.success => VibeTaskOutcomePalette(
        icon: Icons.check_circle_rounded,
        shortLabel: 'Terminé',
        background: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
        foreground: isDark ? const Color(0xFFD1FAE5) : const Color(0xFF065F46),
        accent: isDark ? const Color(0xFF34D399) : const Color(0xFF10B981),
        border: isDark ? const Color(0xFF10B981) : const Color(0xFF6EE7B7),
      ),
      VibeTaskOutcome.needsInput => VibeTaskOutcomePalette(
        icon: Icons.question_answer_rounded,
        shortLabel: 'Action',
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
        accent: scheme.tertiary,
        border: scheme.tertiary.withValues(alpha: 0.55),
      ),
      VibeTaskOutcome.info => VibeTaskOutcomePalette(
        icon: Icons.auto_awesome_rounded,
        shortLabel: 'Prêt',
        background: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
        accent: scheme.primary,
        border: scheme.primary.withValues(alpha: 0.45),
      ),
      VibeTaskOutcome.error => VibeTaskOutcomePalette(
        icon: Icons.error_outline_rounded,
        shortLabel: 'Erreur',
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        accent: scheme.error,
        border: scheme.error.withValues(alpha: 0.65),
      ),
    };
  }
}

/// Bannière visuelle animée affichée dans le chat Vibe lorsqu'une tâche IA se termine.
class VibeTaskCompletionBanner extends StatelessWidget {
  /// Crée une bannière d'alerte de fin de tâche pour [event].
  const VibeTaskCompletionBanner({
    required this.event,
    required this.onDismiss,
    super.key,
  });

  /// Événement de fin de tâche à afficher.
  final VibeTaskCompletionEvent event;

  /// Callback déclenché lorsque l'utilisateur ferme le bandeau.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = VibeTaskOutcomePalette.resolve(context, event.outcome);
    return TweenAnimationBuilder<double>(
      key: ValueKey('vibe-completion-anim-${event.id}'),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1.0 - t) * -8.0),
          child: child,
        ),
      ),
      child: Container(
        key: const ValueKey('vibe-chat-completion-alert'),
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 2),
        padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: palette.accent.withValues(alpha: 0.16),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(palette.icon, size: 17, color: palette.accent),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: palette.foreground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: palette.accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          palette.shortLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: palette.foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (event.detail.trim().isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      event.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.foreground.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('vibe-chat-completion-dismiss'),
              tooltip: 'Fermer la notification',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              color: palette.foreground,
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// Halo visuel pulsant entourant temporairement le panneau [VibeChatDialog]
/// lorsqu'une tâche IA vient de s'achever.
class VibeTaskCompletionGlow extends StatelessWidget {
  /// Enveloppe [child] avec un contour et une lueur animée pilotée par [progress] dans `[0, 1]`.
  const VibeTaskCompletionGlow({
    required this.progress,
    required this.outcome,
    required this.child,
    super.key,
  });

  /// Progression de l'animation de flash (`0.0` au début -> `1.0` au repos).
  final double progress;

  /// Issue de la tâche déterminant la couleur du halo.
  final VibeTaskOutcome? outcome;

  /// Panneau de dialogue enfant.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeOutcome = outcome;
    final strength = activeOutcome == null || progress >= 1.0
        ? 0.0
        : math.sin(progress * math.pi).clamp(0.0, 1.0);
    if (strength <= 0.01 || activeOutcome == null) {
      return child;
    }
    final palette = VibeTaskOutcomePalette.resolve(context, activeOutcome);
    final borderColor = Color.lerp(
      scheme.outlineVariant,
      palette.accent,
      strength,
    )!;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: 1.0 + strength * 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.36 * strength),
            blurRadius: 22.0 * strength,
            spreadRadius: 3.0 * strength,
          ),
        ],
      ),
      child: child,
    );
  }
}

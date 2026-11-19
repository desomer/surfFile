import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/editing/ai/vibe_task_completion_alert.dart';

class _RecordingSoundPlayer extends VibeTaskSoundPlayer {
  final List<VibeTaskOutcome> playedOutcomes = <VibeTaskOutcome>[];

  @override
  Future<void> play(VibeTaskOutcome outcome) async {
    playedOutcomes.add(outcome);
  }
}

void main() {
  group('VibeTaskChimeSynthesizer', () {
    test('génère un conteneur RIFF/WAVE PCM valide pour chaque issue', () {
      for (final outcome in VibeTaskOutcome.values) {
        final wav = VibeTaskChimeSynthesizer.buildWavForOutcome(outcome);
        expect(wav.length, greaterThan(44));
        expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
        expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
        expect(ascii.decode(wav.sublist(12, 16)), 'fmt ');
        expect(ascii.decode(wav.sublist(36, 40)), 'data');
        // Vérifie que la piste audio contient bien un signal non nul.
        final hasSignal = wav.sublist(44).any((b) => b != 0);
        expect(hasSignal, isTrue);
      }
    });
  });

  group('VibeTaskCompletionController', () {
    test('notifie les observateurs et joue le son uniquement si activé', () {
      final player = _RecordingSoundPlayer();
      final controller = VibeTaskCompletionController();
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      final event1 = controller.notifyCompleted(
        outcome: VibeTaskOutcome.success,
        title: 'Tâche IA terminée',
        detail: 'Écran mis à jour.',
        soundPlayer: player,
      );
      expect(event1.id, 1);
      expect(controller.currentEvent, event1);
      expect(notifications, 1);
      expect(player.playedOutcomes, [VibeTaskOutcome.success]);

      controller.toggleSound();
      expect(controller.soundEnabled, isFalse);
      expect(notifications, 2);

      final event2 = controller.notifyCompleted(
        outcome: VibeTaskOutcome.error,
        title: 'Tâche IA échouée',
        detail: 'JSON invalide.',
        soundPlayer: player,
      );
      expect(event2.id, 2);
      expect(controller.currentEvent, event2);
      expect(notifications, 3);
      // Son coupé -> aucun nouvel appel audio.
      expect(player.playedOutcomes, [VibeTaskOutcome.success]);

      controller.dismiss();
      expect(controller.currentEvent, isNull);
      expect(notifications, 4);
    });
  });

  group('VibeTaskCompletionBanner & VibeTaskCompletionGlow', () {
    testWidgets('affiche la bannière animée et permet sa fermeture manuelle', (
      tester,
    ) async {
      var dismissed = false;
      final event = VibeTaskCompletionEvent(
        id: 1,
        outcome: VibeTaskOutcome.success,
        title: 'Tâche IA terminée',
        detail: 'Tableau de bord appliqué.',
        timestamp: DateTime(2026, 11, 19),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VibeTaskCompletionGlow(
              progress: 0.5,
              outcome: event.outcome,
              child: VibeTaskCompletionBanner(
                event: event,
                onDismiss: () => dismissed = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('vibe-chat-completion-alert')),
        findsOneWidget,
      );
      expect(find.text('Tâche IA terminée'), findsOneWidget);
      expect(find.text('Tableau de bord appliqué.'), findsOneWidget);
      expect(find.text('Terminé'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('vibe-chat-completion-dismiss')),
      );
      expect(dismissed, isTrue);
    });
  });
}

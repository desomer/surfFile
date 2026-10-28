import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

const _geminiModel = 'gemini-flash-latest';

Future<String> callGemini(String prompt) async {
  final isDotenvInitialized = dotenv.isInitialized;
  final apiKey = isDotenvInitialized ? dotenv.env['GEMINI_API_KEY'] ?? '' : '';
  if (apiKey.isEmpty) {
    debugPrint(
      '[Vibe IA][Gemini] Clé GEMINI_API_KEY absente '
      '(dotenv.isInitialized=$isDotenvInitialized).',
    );
    throw Exception('GEMINI_API_KEY dotenv is not defined');
  }

  final stopwatch = Stopwatch()..start();
  debugPrint(
    '[Vibe IA][Gemini] Appel de $_geminiModel '
    '(prompt: ${prompt.length} caractères)...',
  );

  final model = GenerativeModel(model: _geminiModel, apiKey: apiKey);
  final content = [Content.text(prompt)];

  final GenerateContentResponse response;
  try {
    response = await model.generateContent(content);
  } catch (error, stackTrace) {
    stopwatch.stop();
    debugPrint(
      '[Vibe IA][Gemini] Échec de generateContent après '
      '${stopwatch.elapsedMilliseconds} ms (${error.runtimeType}) : $error\n'
      '$stackTrace',
    );
    rethrow;
  }

  stopwatch.stop();
  final usage = response.usageMetadata;
  final feedback = response.promptFeedback;
  final candidatesSummary = response.candidates
      .map(
        (c) =>
            'finishReason=${c.finishReason?.name ?? "null"}'
            '${c.finishMessage != null ? " (${c.finishMessage})" : ""}',
      )
      .join(', ');
  debugPrint(
    '[Vibe IA][Gemini] Réponse reçue en ${stopwatch.elapsedMilliseconds} ms '
    '(candidats: ${response.candidates.length}'
    '${candidatesSummary.isEmpty ? "" : " [$candidatesSummary]"}'
    '${feedback?.blockReason != null ? ", blockReason=${feedback!.blockReason!.name} (${feedback.blockReasonMessage ?? ""})" : ""}'
    '${usage != null ? ", tokens: prompt=${usage.promptTokenCount}, réponse=${usage.candidatesTokenCount}, total=${usage.totalTokenCount}" : ""}'
    ').',
  );

  try {
    final text = response.text ?? '';
    if (text.isEmpty) {
      debugPrint(
        '[Vibe IA][Gemini] Attention : response.text est vide. '
        'Candidats: $candidatesSummary, '
        'promptFeedback: ${feedback?.blockReason?.name ?? "aucun"}.',
      );
    }
    return text;
  } catch (error, stackTrace) {
    debugPrint(
      '[Vibe IA][Gemini] Impossible de lire response.text '
      '(${error.runtimeType}) : $error\n'
      'Candidats: $candidatesSummary\n'
      'PromptFeedback: blockReason=${feedback?.blockReason?.name}, '
      'message=${feedback?.blockReasonMessage}\n'
      '$stackTrace',
    );
    rethrow;
  }
}

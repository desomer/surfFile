import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<String> callGemini(String prompt) async {
  final apiKey = dotenv.isInitialized ? dotenv.env['GEMINI_API_KEY'] ?? '' : '';
  if (apiKey.isEmpty) {
    throw Exception('GEMINI_API_KEY dotenv is not defined');
  }

  final model = GenerativeModel(model: 'gemini-flash-latest', apiKey: apiKey);

  final content = [Content.text(prompt)];
  final response = await model.generateContent(content);

  return response.text ?? '';
}

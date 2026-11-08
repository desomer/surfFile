import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_container_layout/ai/call_gemini.dart';

void main() {
  test('resolveGeminiApiKey résout la clé depuis un fichier env ou l\'environnement', () async {
    final key = await resolveGeminiApiKey();
    expect(key, isNotEmpty);
    expect(dotenv.isInitialized, isTrue);
    expect(dotenv.env['GEMINI_API_KEY'], equals(key));
  });
}

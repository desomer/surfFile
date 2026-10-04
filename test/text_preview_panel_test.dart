import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/widgets/preview/text_preview_panel.dart';

void main() {
  test('recognizes text, source and dot-env files', () {
    expect(TextPreviewPanel.supports(r'C:\Code\app.dart'), isTrue);
    expect(TextPreviewPanel.supports(r'C:\Docs\notes.TXT'), isTrue);
    expect(TextPreviewPanel.supports(r'C:\Project\.env'), isTrue);
    expect(TextPreviewPanel.supports(r'C:\Videos\clip.mkv'), isFalse);
    expect(TextPreviewPanel.supports(r'C:\Docs\image.png'), isFalse);
    expect(TextPreviewPanel.supports(r'C:\Docs\no-extension'), isFalse);
  });

  test('selects a Monaco language from the file extension', () {
    expect(TextPreviewPanel.languageFor(r'C:\Code\app.dart').id, 'dart');
    expect(TextPreviewPanel.languageFor(r'C:\Data\config.json').id, 'json');
    expect(TextPreviewPanel.languageFor(r'C:\Project\.env').id, 'shell');
    expect(TextPreviewPanel.languageFor(r'C:\Docs\notes.txt').id, 'plaintext');
  });
}

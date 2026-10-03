import 'package:flutter_test/flutter_test.dart';
import 'package:pro_image_editor/core/models/editor_configs/image_generation_configs/output_formats.dart';
import 'package:surf_file/widgets/image_preview_panel.dart';

void main() {
  test('recognizes common image extensions in Windows paths', () {
    expect(ImagePreviewPanel.supports(r'C:\Photos\portrait.JPG'), isTrue);
    expect(ImagePreviewPanel.supports(r'C:\Photos\logo.png'), isTrue);
    expect(ImagePreviewPanel.supports(r'C:\Photos\animation.gif'), isTrue);
    expect(ImagePreviewPanel.supports(r'C:\Photos\unknown.svg'), isFalse);
    expect(ImagePreviewPanel.supports(r'C:\Photos\no-extension'), isFalse);
  });

  test('only enables editing for output formats supported by the editor', () {
    expect(
      ImagePreviewPanel.editableFormat(r'C:\Photos\portrait.jpeg'),
      OutputFormat.jpg,
    );
    expect(
      ImagePreviewPanel.editableFormat(r'C:\Photos\logo.png'),
      OutputFormat.png,
    );
    expect(
      ImagePreviewPanel.editableFormat(r'C:\Photos\scan.tiff'),
      OutputFormat.tiff,
    );
    expect(
      ImagePreviewPanel.editableFormat(r'C:\Photos\animation.gif'),
      isNull,
    );
  });
}

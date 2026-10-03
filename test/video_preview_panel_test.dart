import 'package:flutter_test/flutter_test.dart';
import 'package:surf_file/widgets/video_preview_panel.dart';

void main() {
  test('recognizes supported video extensions in Windows paths', () {
    expect(VideoPreviewPanel.supports(r'C:\Videos\vacances.MP4'), isTrue);
    expect(VideoPreviewPanel.supports(r'C:\Videos\film.mkv'), isTrue);
    expect(VideoPreviewPanel.supports(r'C:\Videos\notes.txt'), isFalse);
    expect(VideoPreviewPanel.supports(r'C:\Videos\sans-extension'), isFalse);
  });
}

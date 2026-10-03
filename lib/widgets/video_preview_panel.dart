import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

class VideoPreviewPanel extends StatefulWidget {
  const VideoPreviewPanel({
    required this.path,
    required this.onClose,
    required this.isExpanded,
    required this.onToggleExpanded,
    super.key,
  });

  final String? path;
  final VoidCallback onClose;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  static const _videoExtensions = {
    '.3gp',
    '.asf',
    '.avi',
    '.m4v',
    '.mkv',
    '.mov',
    '.mp4',
    '.mpeg',
    '.mpg',
    '.wmv',
  };

  static bool supports(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final extensionStart = name.lastIndexOf('.');
    if (extensionStart <= 0) return false;
    final extension = name.substring(extensionStart).toLowerCase();
    return _videoExtensions.contains(extension);
  }

  @override
  State<VideoPreviewPanel> createState() => _VideoPreviewPanelState();
}

class _VideoPreviewPanelState extends State<VideoPreviewPanel> {
  VideoPlayerController? _controller;
  String? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  @override
  void didUpdateWidget(covariant VideoPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _loadVideo();
  }

  Future<void> _loadVideo() async {
    final generation = ++_loadGeneration;
    final previousController = _controller;
    _controller = null;
    _error = null;
    await _disposeController(previousController);
    if (!mounted || generation != _loadGeneration || widget.path == null) {
      if (mounted && generation == _loadGeneration) setState(() {});
      return;
    }

    final controller = VideoPlayerController.file(File(widget.path!));
    _controller = controller;
    setState(() {});
    try {
      await controller.initialize();
      if (!mounted || generation != _loadGeneration) return;
      await controller.play();
      if (mounted && generation == _loadGeneration) setState(() {});
    } on PlatformException catch (error) {
      _setLoadError(generation, controller, error.message ?? error.code);
    } on FileSystemException catch (error) {
      _setLoadError(generation, controller, error.message);
    } on MissingPluginException catch (error) {
      _setLoadError(generation, controller, error.message ?? error.toString());
    }
  }

  void _setLoadError(
    int generation,
    VideoPlayerController controller,
    String message,
  ) {
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _controller = null;
      _error = message;
    });
    unawaited(_disposeController(controller));
  }

  Future<void> _disposeController(VideoPlayerController? controller) async {
    if (controller == null) return;
    try {
      await controller.dispose();
    } on PlatformException catch (error) {
      debugPrint('Error closing video preview: $error');
    } on MissingPluginException catch (error) {
      debugPrint('Video preview plugin unavailable while closing: $error');
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    unawaited(_disposeController(_controller));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return _buildPanel(context, null, null);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) => _buildPanel(context, controller, value),
    );
  }

  Widget _buildPanel(
    BuildContext context,
    VideoPlayerController? controller,
    VideoPlayerValue? value,
  ) {
    final colors = Theme.of(context).colorScheme;
    final initialized = value?.isInitialized ?? false;
    final duration = initialized ? value!.duration : Duration.zero;
    final position = initialized ? value!.position : Duration.zero;
    final maximum = duration.inMilliseconds
        .toDouble()
        .clamp(1, double.infinity)
        .toDouble();
    final current = position.inMilliseconds
        .toDouble()
        .clamp(0, maximum)
        .toDouble();

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.movie_outlined, color: colors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.path == null
                        ? 'Prévisualisation'
                        : File(widget.path!).uri.pathSegments.last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: widget.isExpanded
                      ? 'Réduire la prévisualisation'
                      : 'Agrandir la prévisualisation',
                  onPressed: widget.onToggleExpanded,
                  icon: Icon(
                    widget.isExpanded
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Fermer la prévisualisation',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Impossible de lire cette vidéo : $_error',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.onSurface),
                          ),
                        )
                      : widget.path == null
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Sélectionnez une vidéo prise en charge '
                            'pour la prévisualiser.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.onSurface),
                          ),
                        )
                      : !initialized
                      ? const CircularProgressIndicator()
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: AspectRatio(
                            aspectRatio: value!.aspectRatio > 0
                                ? value.aspectRatio
                                : 16 / 9,
                            child: VideoPlayer(controller!),
                          ),
                        ),
                ),
              ),
            ),
            if (initialized) ...[
              const SizedBox(height: 6),
              Slider(
                value: current,
                max: maximum,
                onChanged: (position) => controller!.seekTo(
                  Duration(milliseconds: position.round()),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: value!.isPlaying ? 'Mettre en pause' : 'Lire',
                    onPressed: () => value.isPlaying
                        ? controller!.pause()
                        : controller!.play(),
                    icon: Icon(
                      value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  Text(
                    '${_formatDuration(position)} / ${_formatDuration(duration)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

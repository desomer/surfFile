import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

class ImagePreviewPanel extends StatefulWidget {
  const ImagePreviewPanel({
    required this.path,
    required this.onClose,
    required this.isExpanded,
    required this.onToggleExpanded,
    super.key,
  });

  final String path;
  final VoidCallback onClose;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  static const _imageExtensions = {
    '.bmp',
    '.gif',
    '.jpeg',
    '.jpg',
    '.png',
    '.tif',
    '.tiff',
    '.webp',
  };

  static bool supports(String path) =>
      _imageExtensions.contains(_extension(path));

  static OutputFormat? editableFormat(String path) =>
      switch (_extension(path)) {
        '.bmp' => OutputFormat.bmp,
        '.jpeg' || '.jpg' => OutputFormat.jpg,
        '.png' => OutputFormat.png,
        '.tif' || '.tiff' => OutputFormat.tiff,
        _ => null,
      };

  static String? _extension(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot < 0 ? null : name.substring(dot).toLowerCase();
  }

  @override
  State<ImagePreviewPanel> createState() => _ImagePreviewPanelState();
}

class _ImagePreviewPanelState extends State<ImagePreviewPanel> {
  bool _editing = false;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant ImagePreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _editing = false;
      _saving = false;
    }
  }

  void _startEditing() {
    if (!widget.isExpanded) widget.onToggleExpanded();
    setState(() => _editing = true);
  }

  Future<void> _saveEditedImage(Uint8List bytes) async {
    setState(() => _saving = true);
    final file = File(widget.path);
    try {
      await file.writeAsBytes(bytes, flush: true);
      await FileImage(file).evict();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = false;
      });
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Image enregistrée.')));
    } on FileSystemException catch (error) {
      _showSaveError('Impossible d’enregistrer l’image : ${error.message}');
    } on PlatformException catch (error) {
      _showSaveError(
        'Impossible d’enregistrer l’image : ${error.message ?? error.code}',
      );
    }
  }

  void _showSaveError(String message) {
    if (!mounted) return;
    setState(() => _saving = false);
    debugPrint(message);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final format = ImagePreviewPanel.editableFormat(widget.path);
    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_editing)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                children: [
                  Icon(Icons.image_outlined, color: colors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      File(widget.path).uri.pathSegments.last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (format != null)
                    IconButton(
                      tooltip: 'Modifier l’image',
                      onPressed: _startEditing,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      visualDensity: VisualDensity.compact,
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
            ),
          Expanded(
            child: _editing
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ProImageEditor.file(
                        widget.path,
                        key: ValueKey('image-editor-${widget.path}'),
                        configs: ProImageEditorConfigs(
                          theme: Theme.of(context),
                          imageGeneration: ImageGenerationConfigs(
                            outputFormat: format!,
                          ),
                        ),
                        callbacks: ProImageEditorCallbacks(
                          onImageEditingComplete: _saveEditedImage,
                          onCloseEditor: (_) {
                            if (mounted) setState(() => _editing = false);
                          },
                        ),
                      ),
                      if (_saving)
                        const ColoredBox(
                          color: Color(0x66000000),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  )
                : ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Image.file(
                        File(widget.path),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        frameBuilder:
                            (context, child, frame, wasSynchronouslyLoaded) {
                              if (wasSynchronouslyLoaded || frame != null) {
                                return child;
                              }
                              return const CircularProgressIndicator();
                            },
                        errorBuilder: (context, error, stackTrace) => Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Impossible d’afficher cette image : $error',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.onSurface),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

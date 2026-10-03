import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../models/explorer_entry.dart';
import '../services/directory_scanner.dart';
import 'explorer_file_icon.dart';

/// Affiche une miniature de [entry] près du pointeur après un survol long :
/// l'image pour un fichier image, les premiers éléments pour un dossier. Ne
/// fait rien pour les autres fichiers.
///
/// Une fois une miniature affichée, le mode aperçu reste actif tant que le
/// pointeur passe d'une ligne à l'autre : la miniature suit la ligne survolée
/// sans nouveau délai et ne se ferme qu'en quittant les lignes (au-delà de
/// [exitGrace]), au clic ou au défilement.
class HoverPreview extends StatefulWidget {
  const HoverPreview({required this.entry, required this.child, super.key});

  final ExplorerEntry entry;
  final Widget child;

  static const delay = Duration(milliseconds: 700);
  static const exitGrace = Duration(milliseconds: 250);
  static const size = Size(260, 260);
  static const folderItems = 8;

  static const imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

  static bool supports(ExplorerEntry entry) =>
      entry.isDirectory || isImage(entry.name);

  static bool isImage(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 &&
        imageExtensions.contains(name.substring(dot + 1).toLowerCase());
  }

  /// Ferme la miniature et quitte le mode aperçu.
  static void dismiss() => _PreviewController.instance.dismiss();

  @override
  State<HoverPreview> createState() => _HoverPreviewState();
}

/// Miniature partagée par toutes les lignes.
class _PreviewController {
  _PreviewController._();

  static final instance = _PreviewController._();

  Timer? _showTimer;
  Timer? _exitTimer;
  OverlayEntry? _overlay;
  Object? _owner;
  final _shown = ValueNotifier<(ExplorerEntry, Offset)?>(null);

  bool get active => _overlay != null;

  void enter(
    Object owner,
    BuildContext context,
    ExplorerEntry entry,
    Offset position,
  ) {
    _exitTimer?.cancel();
    _owner = owner;
    if (active) {
      _show(context, entry, position);
    } else {
      _schedule(owner, context, entry, position);
    }
  }

  void hover(
    Object owner,
    BuildContext context,
    ExplorerEntry entry,
    Offset position,
  ) {
    if (active || (_owner != null && _owner != owner)) return;
    _owner = owner;
    _schedule(owner, context, entry, position);
  }

  void _schedule(
    Object owner,
    BuildContext context,
    ExplorerEntry entry,
    Offset position,
  ) {
    _showTimer?.cancel();
    _showTimer = null;
    if (!HoverPreview.supports(entry)) return;
    _showTimer = Timer(HoverPreview.delay, () {
      if (_owner == owner && context.mounted) _show(context, entry, position);
    });
  }

  void exit(Object owner) {
    if (_owner != owner) return;
    _showTimer?.cancel();
    _showTimer = null;
    _owner = null;
    if (!active) return;
    _exitTimer?.cancel();
    _exitTimer = Timer(HoverPreview.exitGrace, dismiss);
  }

  void release(Object owner) {
    if (_owner == owner) dismiss();
  }

  void _show(BuildContext context, ExplorerEntry entry, Offset position) {
    if (!HoverPreview.supports(entry)) {
      // Ligne sans aperçu : on masque la carte mais le mode reste actif.
      _shown.value = null;
      return;
    }
    final overlay = Overlay.maybeOf(context);
    final box = overlay?.context.findRenderObject() as RenderBox?;
    if (overlay == null || box == null) return;
    _shown.value = (entry, box.globalToLocal(position));
    if (_overlay != null) return;
    _overlay = OverlayEntry(
      builder: (context) => ValueListenableBuilder(
        valueListenable: _shown,
        builder: (context, shown, _) {
          if (shown == null) return const SizedBox.shrink();
          final (entry, local) = shown;
          final bounds = box.size;
          const size = HoverPreview.size;
          var left = local.dx + 16;
          if (left + size.width > bounds.width) {
            left = local.dx - size.width - 16;
          }
          final top = (local.dy + 16).clamp(
            0.0,
            (bounds.height - size.height).clamp(0.0, double.infinity),
          );
          return Positioned(
            left: left.clamp(0.0, double.infinity),
            top: top,
            child: IgnorePointer(
              child: _PreviewCard(
                key: ValueKey(entry.entity.path),
                entry: entry,
              ),
            ),
          );
        },
      ),
    );
    overlay.insert(_overlay!);
  }

  void dismiss() {
    _showTimer?.cancel();
    _exitTimer?.cancel();
    _showTimer = _exitTimer = null;
    _owner = null;
    _shown.value = null;
    _overlay?.remove();
    _overlay?.dispose();
    _overlay = null;
  }
}

class _HoverPreviewState extends State<HoverPreview> {
  _PreviewController get _controller => _PreviewController.instance;

  @override
  void didUpdateWidget(HoverPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.entity.path != widget.entry.entity.path) {
      _controller.exit(this);
    }
  }

  @override
  void dispose() {
    _controller.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (event) =>
        _controller.enter(this, context, widget.entry, event.position),
    onHover: (event) {
      if (!event.down) {
        _controller.hover(this, context, widget.entry, event.position);
      }
    },
    onExit: (_) => _controller.exit(this),
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _controller.release(this),
      onPointerSignal: (_) => _controller.release(this),
      child: widget.child,
    ),
  );
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.entry, super.key});

  final ExplorerEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduced ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 150),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: .96 + .04 * t, child: child),
      ),
      child: Material(
        key: const ValueKey('hover-preview'),
        elevation: 8,
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints.loose(HoverPreview.size),
          child: entry.isDirectory
              ? _FolderPreview(path: entry.entity.path)
              : Image.file(
                  File(entry.entity.path),
                  fit: BoxFit.contain,
                  cacheWidth: (HoverPreview.size.width * 2).round(),
                  errorBuilder: (context, _, _) => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aperçu indisponible'),
                  ),
                ),
        ),
      ),
    );
  }
}

class _FolderPreview extends StatefulWidget {
  const _FolderPreview({required this.path});

  final String path;

  @override
  State<_FolderPreview> createState() => _FolderPreviewState();
}

class _FolderPreviewState extends State<_FolderPreview> {
  late final Future<List<ExplorerEntry>> _entries =
      DirectoryScanner.scan(widget.path).then((entries) {
        sortExplorerEntries(entries, ExplorerSort.name, ascending: true);
        return entries;
      });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: .65);
    return FutureBuilder<List<ExplorerEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        final entries = snapshot.data;
        Widget message(String text) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text(text, style: TextStyle(color: muted)),
        );
        if (snapshot.hasError) return message('Accès refusé');
        if (entries == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (entries.isEmpty) return message('Dossier vide');
        final shown = entries.take(HoverPreview.folderItems);
        final rest = entries.length - HoverPreview.folderItems;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExplorerFileIcon(entry: entry, size: 16),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              if (rest > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '+ $rest autre${rest > 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

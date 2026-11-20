/// Capture raster haute résolution ([PdfRasterFallback]) pour composants complexes ou extensions.
///
/// Permet au moteur PDF hybride d'intégrer fidèlement tout widget Flutter sans
/// traducteur vectoriel dédié (`SuperChart`, `SuperCode`, effets néon, flou,
/// images/SVG complexes) sous forme d'image PNG haute densité dans le document PDF.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/registry.dart';
import '../../super_app.dart';
import '../../theme/appearance.dart';
import '../../widgets/appearance/appearance_scope.dart';
import '../../widgets/editing/slots/editor_slot.dart';
import '../inspection/vibe_mounted_slot_index.dart';
import '../repositories/json_list_scope.dart';
import '../repositories/json_repository_scope.dart';
import '../repositories/json_repository_store.dart';

/// Fonction injectable de capture raster (utile pour les tests unitaires hors écran).
typedef PdfRasterCaptureCallback =
    Future<Uint8List?> Function({
      required String componentId,
      required String slotType,
      required Size logicalSize,
      required double pixelRatio,
    });

/// Capture en image PNG haute résolution un composant ou sous-arbre Flutter.
abstract final class PdfRasterFallback {
  /// Capture le composant [componentId] (type [slotType]) à la taille [logicalSize].
  ///
  /// Utilise d'abord un `OverlayEntry` hors-écran muni des portées applicatives
  /// (sans mode édition), ou se rabat sur un slot monté hors-édition si aucun
  /// `Overlay` n'est disponible dans [context].
  static Future<Uint8List?> captureComponent({
    required BuildContext? context,
    required Appearance appearance,
    required Registry? registry,
    required JsonRepositoryStore? repositoryStore,
    required ThemeData theme,
    required String componentId,
    required String slotType,
    required Size logicalSize,
    JsonListScope? listScope,
    double pixelRatio = 3.0,
    PdfRasterCaptureCallback? customCapture,
  }) async {
    if (customCapture != null) {
      return customCapture(
        componentId: componentId,
        slotType: slotType,
        logicalSize: logicalSize,
        pixelRatio: pixelRatio,
      );
    }

    final safeSize = Size(
      logicalSize.width.clamp(16.0, 2400.0),
      logicalSize.height.clamp(16.0, 2400.0),
    );

    if (context != null) {
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay != null) {
        final widget = _buildComponentWidget(
          context: context,
          appearance: appearance,
          registry: registry,
          repositoryStore: repositoryStore,
          theme: theme,
          componentId: componentId,
          slotType: slotType,
          listScope: listScope,
        );
        if (widget != null) {
          final captured = await _captureInOverlay(
            overlay: overlay,
            child: widget,
            logicalSize: safeSize,
            pixelRatio: pixelRatio,
          );
          if (captured != null) return captured;
        }
      }
    }

    return _captureFromMountedSlot(
      componentId: componentId,
      pixelRatio: pixelRatio,
    );
  }

  static Widget? _buildComponentWidget({
    required BuildContext context,
    required Appearance appearance,
    required Registry? registry,
    required JsonRepositoryStore? repositoryStore,
    required ThemeData theme,
    required String componentId,
    required String slotType,
    JsonListScope? listScope,
  }) {
    final key = _extractRegistryKey(slotType);
    final builder = key == null ? null : registry?.registry[key];
    final registered = registry?.components[componentId];
    final Widget? rawChild =
        builder?.getWidget(XuiBuildCtx(id: componentId)) ??
        registered?.createSlot(componentId);
    if (rawChild == null) return null;

    final app = SuperApp.maybeOf(context);
    final appearanceController =
        AppearanceScope.controllerOf(context) ?? ValueNotifier(appearance);
    final ownsAppearance = AppearanceScope.controllerOf(context) == null;
    final editMode = ValueNotifier<bool>(false);

    Widget wrapped = Theme(
      data: theme,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: theme.colorScheme.onSurface),
        child: Material(type: MaterialType.transparency, child: rawChild),
      ),
    );

    if (listScope != null) {
      wrapped = JsonListScope(
        repositoryId: listScope.repositoryId,
        indices: listScope.indices,
        arrayTemplate: listScope.arrayTemplate,
        nodePath: listScope.nodePath,
        treeTemplatePath: listScope.treeTemplatePath,
        child: wrapped,
      );
    }

    if (repositoryStore != null) {
      wrapped = JsonRepositoryScope(store: repositoryStore, child: wrapped);
    }

    wrapped = StyleEditScope(
      controller: editMode,
      child: AppearanceScope(controller: appearanceController, child: wrapped),
    );

    if (app != null) {
      wrapped = SuperAppScope(
        app: app,
        appearanceToolbarPosition: SuperAppScope.toolbarPositionOf(context),
        child: wrapped,
      );
    }

    return _DisposableWrapper(
      onDispose: () {
        editMode.dispose();
        if (ownsAppearance) appearanceController.dispose();
      },
      child: wrapped,
    );
  }

  static Future<Uint8List?> _captureInOverlay({
    required OverlayState overlay,
    required Widget child,
    required Size logicalSize,
    required double pixelRatio,
  }) async {
    final boundaryKey = GlobalKey();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        width: logicalSize.width,
        height: logicalSize.height,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.005,
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: logicalSize.width,
                height: logicalSize.height,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    try {
      // Laisse au moins deux frames pour que les widgets async/layout peignent.
      await SchedulerBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await SchedulerBinding.instance.endOfFrame;

      final renderObj = boundaryKey.currentContext?.findRenderObject();
      if (renderObj is! RenderRepaintBoundary || !renderObj.hasSize) {
        return null;
      }
      final image = await renderObj.toImage(pixelRatio: pixelRatio);
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    } finally {
      entry.remove();
    }
  }

  static Future<Uint8List?> _captureFromMountedSlot({
    required String componentId,
    required double pixelRatio,
  }) async {
    final entries = VibeMountedSlotIndex.instance.entriesFor(componentId);
    if (entries.isEmpty) return null;
    final renderObj = entries.first.contentKey.currentContext?.findRenderObject();
    if (renderObj is! RenderRepaintBoundary ||
        !renderObj.hasSize ||
        renderObj.debugNeedsPaint) {
      return null;
    }
    final image = await renderObj.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  static String? _extractRegistryKey(String slotType) {
    final trimmed = slotType.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('factory:')) {
      return trimmed.substring('factory:'.length);
    }
    if (trimmed.startsWith('registry:')) {
      return Uri.decodeComponent(trimmed.substring('registry:'.length));
    }
    return trimmed;
  }
}

class _DisposableWrapper extends StatefulWidget {
  const _DisposableWrapper({required this.onDispose, required this.child});

  final VoidCallback onDispose;
  final Widget child;

  @override
  State<_DisposableWrapper> createState() => _DisposableWrapperState();
}

class _DisposableWrapperState extends State<_DisposableWrapper> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

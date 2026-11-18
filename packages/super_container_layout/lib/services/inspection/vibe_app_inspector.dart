/// Service d'introspection runtime en lecture seule ([VibeAppInspector]) pour Vibe IA.
///
/// Fournit l'implémentation concrète des outils exposés via [VibeAppToolRegistry] :
/// - `get_viewport_and_route` : dimensions fenêtre/viewport, route GoRouter, page active et scope ;
/// - `get_component_geometry` : taille réelle en dp, position, contraintes, scroll et diagnostics ;
/// - `get_runtime_tree` : arbre hiérarchique effectivement monté sur la page courante ;
/// - `query_repository_data` : catalogue, schémas, extraits paginés et sélections de [JsonRepositoryStore] ;
/// - `capture_screenshot` : capture PNG plafonnée en résolution depuis les [RenderRepaintBoundary].
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../ai/vibe_app_tools.dart';
import '../../ai/vibe_chat_attachment.dart';
import '../../models/editor_page_config.dart';
import '../../models/json_text_binding.dart';
import '../../models/native_component_config.dart';
import '../../models/registry.dart';
import '../../models/scaffold_page_config.dart';
import '../../models/super_conditional_config.dart';
import '../../models/super_layout_config.dart';
import '../../models/super_list_view_config.dart';
import '../../models/super_tab_config.dart';
import '../../models/super_table_config.dart';
import '../../models/super_tree_view_config.dart';
import '../../theme/appearance.dart';
import '../../widgets/editing/ai/vibe_scope_helpers.dart';
import '../../widgets/editing/slots/editor_context_menu.dart' show VibeChatScope;
import '../../widgets/editing/slots/editor_slot.dart' show StyleEditScope;
import '../pages/editor_page_router.dart';
import '../repositories/json_repository_store.dart';
import 'vibe_mounted_slot_index.dart';

/// Service d'introspection runtime de l'application Flutter exposé à Vibe IA.
class VibeAppInspector {
  /// Crée un inspecteur connecté à l'état courant de l'application.
  VibeAppInspector({
    required this.readAppearance,
    VibeMountedSlotIndex? slotIndex,
    this.registry,
    this.repositoryStore,
    this.pageRouting,
    this.readScope,
    this.fallbackContext,
  }) : slotIndex = slotIndex ?? VibeMountedSlotIndex.instance;

  /// Fournisseur de l'[Appearance] active (incluant les éventuels défauts runtime).
  final Appearance Function() readAppearance;

  /// Index des slots et de la racine applicative montés.
  final VibeMountedSlotIndex slotIndex;

  /// Registre optionnel des composants pour compléter les métadonnées.
  final Registry? registry;

  /// Store optionnel de repositories JSON.
  final JsonRepositoryStore? repositoryStore;

  /// Routeur GoRouter dynamique optionnel.
  final EditorPageRouter? pageRouting;

  /// Fournisseur optionnel du périmètre restreint actif dans le chat Vibe.
  final VibeChatScope? Function()? readScope;

  /// Contexte Flutter de repli (ex. celui de `VibeChatDialog`) si aucune racine `SuperApp` n'est enregistrée.
  final BuildContext? Function()? fallbackContext;

  /// Construit le [VibeAppToolRegistry] complet exposant les 5 outils en lecture seule.
  VibeAppToolRegistry buildToolRegistry() =>
      VibeAppToolRegistry.fromStandardHandlers(<String, VibeToolHandler>{
        'get_viewport_and_route': (call) async => VibeToolResult(
          callId: call.id,
          name: call.name,
          data: await getViewportAndRoute(),
        ),
        'get_component_geometry': (call) async => VibeToolResult(
          callId: call.id,
          name: call.name,
          data: await getComponentGeometry(call.arguments),
        ),
        'get_runtime_tree': (call) async => VibeToolResult(
          callId: call.id,
          name: call.name,
          data: await getRuntimeTree(call.arguments),
        ),
        'query_repository_data': (call) async => VibeToolResult(
          callId: call.id,
          name: call.name,
          data: await queryRepositoryData(call.arguments),
        ),
        'capture_screenshot': (call) =>
            captureScreenshot(call.id, call.name, call.arguments),
      });

  BuildContext? _resolvePrimaryContext() {
    final appRootCtx = slotIndex.activeAppRootKey?.currentContext;
    if (appRootCtx != null && appRootCtx.mounted) return appRootCtx;
    for (final entry in slotIndex.allEntries) {
      final ctx = entry.slotContext();
      if (ctx != null && ctx.mounted) return ctx;
    }
    final fallback = fallbackContext?.call();
    if (fallback != null && fallback.mounted) return fallback;
    return null;
  }

  Future<void> _settleFrameIfNeeded(RenderObject? target) async {
    final scheduler = SchedulerBinding.instance;
    final needsLayout = target != null && target.debugNeedsLayout;
    final missingSize = target is RenderBox && !target.hasSize;
    if ((needsLayout || missingSize) && scheduler.hasScheduledFrame) {
      try {
        await scheduler.endOfFrame.timeout(const Duration(milliseconds: 250));
      } on TimeoutException {
        // Ne bloque pas en environnement sans pompe de frames (ex. tests unitaires).
      }
    }
  }

  static double _round2(double value) => (value * 100).roundToDouble() / 100;

  static Object? _serializeBound(double value) =>
      value.isFinite ? _round2(value) : null;

  static Map<String, Object?> _rectToJson(Rect rect) => <String, Object?>{
    'left': _round2(rect.left),
    'top': _round2(rect.top),
    'width': _round2(rect.width),
    'height': _round2(rect.height),
    'right': _round2(rect.right),
    'bottom': _round2(rect.bottom),
  };

  RenderBox? _resolveRootBox(BuildContext? context) {
    final rootKeyCtx = slotIndex.activeAppRootKey?.currentContext;
    final rootObj = rootKeyCtx?.findRenderObject();
    if (rootObj is RenderBox && rootObj.attached && rootObj.hasSize) {
      return rootObj;
    }
    if (context == null || !context.mounted) return null;
    final mediaBox = context
        .findAncestorRenderObjectOfType<RenderRepaintBoundary>();
    if (mediaBox != null && mediaBox.attached && mediaBox.hasSize) {
      return mediaBox;
    }
    return null;
  }

  EditorPageConfig? _resolveActivePage(Appearance appearance) {
    final location =
        pageRouting?.router.routeInformationProvider.value.uri.path;
    final pages = appearance.pageCatalog.pages;
    if (pages.isEmpty) return null;
    if (location != null && location.isNotEmpty) {
      for (final page in pages) {
        if (page.path == location) return page;
      }
    }
    final homeId = appearance.pageCatalog.homePageId;
    if (homeId != null) {
      for (final page in pages) {
        if (page.id == homeId) return page;
      }
    }
    return pages.first;
  }

  /// Retourne l'état du viewport, de la route active, du mode édition et du scope.
  Future<Map<String, Object?>> getViewportAndRoute() async {
    final appearance = readAppearance();
    final ctx = _resolvePrimaryContext();
    final media = ctx != null ? MediaQuery.maybeOf(ctx) : null;
    final editMode = ctx != null ? StyleEditScope.controllerOf(ctx)?.value : null;
    final scope = readScope?.call();
    final activePage = _resolveActivePage(appearance);

    String? currentLocation;
    try {
      currentLocation =
          pageRouting?.router.routeInformationProvider.value.uri.toString();
    } catch (_) {
      currentLocation = null;
    }

    return <String, Object?>{
      if (media != null)
        'viewport': <String, Object?>{
          'width': _round2(media.size.width),
          'height': _round2(media.size.height),
          'devicePixelRatio': _round2(media.devicePixelRatio),
          'padding': <String, Object?>{
            'left': _round2(media.padding.left),
            'top': _round2(media.padding.top),
            'right': _round2(media.padding.right),
            'bottom': _round2(media.padding.bottom),
          },
          'viewInsetsBottom': _round2(media.viewInsets.bottom),
        },
      'route': <String, Object?>{
        'location': currentLocation,
        if (activePage != null)
          'activePage': <String, Object?>{
            'id': activePage.id,
            'name': activePage.name,
            'path': activePage.path,
          },
        'homePageId': appearance.pageCatalog.homePageId,
        'pageCount': appearance.pageCatalog.pages.length,
      },
      'editMode': ?editMode,
      if (scope != null)
        'scope': <String, Object?>{
          'componentId': scope.canonicalComponentId,
          'rawComponentId': scope.componentId,
          'zoneId': ?scope.zoneId,
          'displayLabel': scope.displayLabel,
        },
      'mountedComponentCount': slotIndex.mountedComponentIds.length,
    };
  }

  /// Mesure la géométrie réelle des composants demandés ou du périmètre actif.
  Future<Map<String, Object?>> getComponentGeometry(
    Map<String, Object?> args,
  ) async {
    final appearance = readAppearance();
    final scope = readScope?.call();
    final zoneFilter = args['zoneId'] is String && (args['zoneId'] as String).trim().isNotEmpty
        ? (args['zoneId'] as String).trim()
        : null;
    final includeScroll = args['includeScroll'] is bool
        ? args['includeScroll'] as bool
        : true;
    final includeZones = args['includeZones'] is bool
        ? args['includeZones'] as bool
        : true;

    final requestedIds = <String>[];
    final rawIds = args['ids'];
    if (rawIds is List) {
      for (final item in rawIds) {
        if (item is String && item.trim().isNotEmpty) {
          requestedIds.add(item.trim());
        }
      }
    } else if (args['id'] is String && (args['id'] as String).trim().isNotEmpty) {
      requestedIds.add((args['id'] as String).trim());
    }

    if (requestedIds.isEmpty) {
      if (scope != null) {
        requestedIds.add(scope.canonicalComponentId);
        requestedIds.addAll(
          VibeScopeHelpers.parentIdsOfScope(appearance, scope),
        );
      } else {
        final activePage = _resolveActivePage(appearance);
        if (activePage != null &&
            slotIndex.entriesFor(activePage.id).isNotEmpty) {
          requestedIds.add(activePage.id);
        } else {
          requestedIds.addAll(slotIndex.mountedComponentIds.take(20));
        }
      }
    }

    final uniqueIds = requestedIds.toSet().toList();
    final primaryCtx = _resolvePrimaryContext();
    final viewportSize =
        primaryCtx != null ? MediaQuery.maybeSizeOf(primaryCtx) : null;
    final rootBox = _resolveRootBox(primaryCtx);

    final results = <String, Object?>{};
    for (final id in uniqueIds) {
      var entries = slotIndex.entriesFor(id, zoneId: zoneFilter);
      if (zoneFilter == null && !includeZones) {
        entries = entries
            .where((e) => e.zoneId == null || e.zoneId!.isEmpty)
            .toList();
      }
      if (entries.isEmpty) {
        results[id] = <String, Object?>{
          'mounted': false,
          'configured': appearance.components.containsKey(id) ||
              appearance.styles.containsKey(id),
          'occurrences': const <Object?>[],
        };
        continue;
      }

      final occurrences = <Map<String, Object?>>[];
      for (final entry in entries) {
        final slotCtx = entry.slotContext();
        final contentCtx = entry.contentKey.currentContext;
        final targetCtx = (contentCtx != null && contentCtx.mounted)
            ? contentCtx
            : slotCtx;
        if (targetCtx == null || !targetCtx.mounted) continue;

        final renderObj = targetCtx.findRenderObject();
        await _settleFrameIfNeeded(renderObj);

        if (renderObj == null || !renderObj.attached) continue;

        final item = <String, Object?>{
          'componentId': entry.componentId,
          if (entry.zoneId != null) 'zoneId': entry.zoneId,
          'label': entry.label,
          'componentType': entry.componentType,
          'fixedWidth': entry.fixedWidth,
          'fixedHeight': entry.fixedHeight,
          'scrollable': entry.scrollable,
        };

        if (renderObj is RenderBox && renderObj.hasSize) {
          final size = renderObj.size;
          item['size'] = <String, Object?>{
            'width': _round2(size.width),
            'height': _round2(size.height),
          };
          final constraints = renderObj.constraints;
          item['constraints'] = <String, Object?>{
            'minWidth': _round2(constraints.minWidth),
            'maxWidth': _serializeBound(constraints.maxWidth),
            'minHeight': _round2(constraints.minHeight),
            'maxHeight': _serializeBound(constraints.maxHeight),
            'hasBoundedWidth': constraints.hasBoundedWidth,
            'hasBoundedHeight': constraints.hasBoundedHeight,
          };

          final origin = rootBox != null
              ? renderObj.localToGlobal(Offset.zero, ancestor: rootBox)
              : renderObj.localToGlobal(Offset.zero);
          final globalRect = origin & size;
          item['bounds'] = _rectToJson(globalRect);

          final parentObj = renderObj.parent;
          if (parentObj is RenderBox && parentObj.attached && parentObj.hasSize) {
            final localOffset = renderObj.localToGlobal(
              Offset.zero,
              ancestor: parentObj,
            );
            item['parentRelative'] = <String, Object?>{
              'left': _round2(localOffset.dx),
              'top': _round2(localOffset.dy),
              'parentWidth': _round2(parentObj.size.width),
              'parentHeight': _round2(parentObj.size.height),
            };
          }

          item['diagnostics'] = <String, Object?>{
            'isZeroSized': size.width <= 0.0 || size.height <= 0.0,
            if (viewportSize != null) ...<String, Object?>{
              'exceedsViewportWidth':
                  globalRect.right > viewportSize.width + 0.5 ||
                  globalRect.left < -0.5,
              'exceedsViewportHeight':
                  globalRect.bottom > viewportSize.height + 0.5 ||
                  globalRect.top < -0.5,
              'isOffscreen':
                  globalRect.right <= 0 ||
                  globalRect.bottom <= 0 ||
                  globalRect.left >= viewportSize.width ||
                  globalRect.top >= viewportSize.height,
            },
          };
        } else if (renderObj is RenderSliver) {
          final sliverGeo = renderObj.geometry;
          final sliverConstraints = renderObj.constraints;
          item['isSliver'] = true;
          item['sliver'] = <String, Object?>{
            'axis': sliverConstraints.axis.name,
            'crossAxisExtent': _round2(sliverConstraints.crossAxisExtent),
            'viewportMainAxisExtent': _round2(
              sliverConstraints.viewportMainAxisExtent,
            ),
            if (sliverGeo != null) ...<String, Object?>{
              'paintExtent': _round2(sliverGeo.paintExtent),
              'layoutExtent': _round2(sliverGeo.layoutExtent),
              'scrollExtent': _round2(sliverGeo.scrollExtent),
              'hasVisualOverflow': sliverGeo.hasVisualOverflow,
            },
          };
        }

        if (includeScroll && slotCtx != null && slotCtx.mounted) {
          final scrollable = Scrollable.maybeOf(slotCtx);
          if (scrollable != null && scrollable.position.hasPixels) {
            final pos = scrollable.position;
            item['scroll'] = <String, Object?>{
              'axis': axisDirectionToAxis(pos.axisDirection).name,
              'pixels': _round2(pos.pixels),
              'minScrollExtent': _round2(pos.minScrollExtent),
              'maxScrollExtent': _round2(pos.maxScrollExtent),
              'viewportDimension': _round2(pos.viewportDimension),
              'canScroll': pos.maxScrollExtent > pos.minScrollExtent,
            };
          }
        }

        occurrences.add(item);
      }

      results[id] = <String, Object?>{
        'mounted': occurrences.isNotEmpty,
        'occurrenceCount': occurrences.length,
        'occurrences': occurrences,
      };
    }

    return <String, Object?>{
      if (viewportSize != null)
        'viewport': <String, Object?>{
          'width': _round2(viewportSize.width),
          'height': _round2(viewportSize.height),
        },
      'components': results,
    };
  }

  /// Construit une vue arborescente légère des composants et zones effectivement montés.
  Future<Map<String, Object?>> getRuntimeTree(Map<String, Object?> args) async {
    final appearance = readAppearance();
    final scope = readScope?.call();
    final rawDepth = args['maxDepth'];
    final maxDepth = (rawDepth is num ? rawDepth.toInt() : 6).clamp(1, 12);

    String? rootId =
        args['rootId'] is String && (args['rootId'] as String).trim().isNotEmpty
            ? (args['rootId'] as String).trim()
            : null;
    rootId ??= scope?.canonicalComponentId;
    rootId ??= _resolveActivePage(appearance)?.id;
    if (rootId == null) {
      for (final entry in appearance.components.entries) {
        if (entry.value is ScaffoldPageConfig || entry.value is SuperLayoutConfig) {
          rootId = entry.key;
          break;
        }
      }
    }
    rootId ??= slotIndex.mountedComponentIds.firstOrNull;

    if (rootId == null) {
      return <String, Object?>{
        'rootId': null,
        'tree': null,
        'mountedIds': slotIndex.mountedComponentIds.toList(),
      };
    }

    var visitedNodes = 0;
    const maxNodes = 120;
    var truncated = false;
    final seenInBranch = <String>{};

    Map<String, Object?> buildNode(String id, int depth) {
      visitedNodes++;
      final config = appearance.components[id];
      final entries = slotIndex.entriesFor(id);
      final primaryEntry = entries
          .where((e) => e.zoneId == null || e.zoneId!.isEmpty)
          .firstOrNull ??
          entries.firstOrNull;

      Map<String, Object?>? primarySize;
      final primaryCtx =
          primaryEntry?.contentKey.currentContext ?? primaryEntry?.slotContext();
      if (primaryCtx != null && primaryCtx.mounted) {
        final ro = primaryCtx.findRenderObject();
        if (ro is RenderBox && ro.attached && ro.hasSize) {
          primarySize = <String, Object?>{
            'width': _round2(ro.size.width),
            'height': _round2(ro.size.height),
          };
        }
      }

      final node = <String, Object?>{
        'id': id,
        'type': config?.componentType ?? primaryEntry?.componentType ?? 'unknown',
        if (primaryEntry != null) 'label': primaryEntry.label,
        'mounted': entries.isNotEmpty,
        if (entries.length > 1) 'occurrenceCount': entries.length,
        'size': ?primarySize,
      };

      if (depth >= maxDepth || visitedNodes >= maxNodes) {
        if (VibeScopeHelpers.childrenOfComponent(config).isNotEmpty) {
          node['truncated'] = true;
          truncated = true;
        }
        return node;
      }

      if (!seenInBranch.add(id)) {
        node['cycle'] = true;
        return node;
      }

      try {
        if (config is SuperLayoutConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.placements.entries) {
            final zoneName = entry.key.name;
            final zoneEntries = slotIndex.entriesFor(id, zoneId: zoneName);
            final childNodes = <Map<String, Object?>>[];
            for (final childId in entry.value) {
              if (visitedNodes >= maxNodes) {
                truncated = true;
                break;
              }
              childNodes.add(buildNode(childId, depth + 1));
            }
            zones[zoneName] = <String, Object?>{
              'mounted': zoneEntries.isNotEmpty,
              if (config.collapsedSides.containsKey(entry.key))
                'collapsed': true,
              'children': childNodes,
            };
          }
          if (zones.isNotEmpty) {
            node['zones'] = zones;
          }
        } else if (config is NativeComponentConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.placements.entries) {
            final childNodes = <Map<String, Object?>>[];
            for (final childId in entry.value) {
              if (visitedNodes >= maxNodes) {
                truncated = true;
                break;
              }
              childNodes.add(buildNode(childId, depth + 1));
            }
            zones[entry.key] = childNodes;
          }
          if (zones.isNotEmpty) {
            node['placements'] = zones;
          }
        } else if (config is ScaffoldPageConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.native.placements.entries) {
            final childNodes = <Map<String, Object?>>[];
            for (final childId in entry.value) {
              if (visitedNodes >= maxNodes) {
                truncated = true;
                break;
              }
              childNodes.add(buildNode(childId, depth + 1));
            }
            zones[entry.key] = childNodes;
          }
          if (zones.isNotEmpty) {
            node['placements'] = zones;
          }
        } else if (config is SuperListViewConfig) {
          node['templateChildren'] = [
            for (final entry in config.template.placements.entries)
              for (final childId in entry.value)
                if (visitedNodes < maxNodes) buildNode(childId, depth + 1),
          ];
        } else if (config is SuperTabConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.placements.entries) {
            zones[entry.key] = [
              for (final childId in entry.value)
                if (visitedNodes < maxNodes) buildNode(childId, depth + 1),
            ];
          }
          if (zones.isNotEmpty) {
            node['placements'] = zones;
          }
        } else if (config is SuperConditionalConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.placements.entries) {
            zones[entry.key] = [
              for (final childId in entry.value)
                if (visitedNodes < maxNodes) buildNode(childId, depth + 1),
            ];
          }
          if (zones.isNotEmpty) {
            node['placements'] = zones;
          }
        } else if (config is SuperTableConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.placements.entries) {
            zones[entry.key] = [
              for (final childId in entry.value)
                if (visitedNodes < maxNodes) buildNode(childId, depth + 1),
            ];
          }
          if (zones.isNotEmpty) {
            node['placements'] = zones;
          }
        } else if (config is SuperTreeViewConfig) {
          final zones = <String, Object?>{};
          for (final entry in config.placements.entries) {
            zones[entry.key] = [
              for (final childId in entry.value)
                if (visitedNodes < maxNodes) buildNode(childId, depth + 1),
            ];
          }
          if (zones.isNotEmpty) {
            node['placements'] = zones;
          }
        } else {
          final children = VibeScopeHelpers.childrenOfComponent(config);
          if (children.isNotEmpty) {
            node['children'] = [
              for (final childId in children)
                if (visitedNodes < maxNodes) buildNode(childId, depth + 1),
            ];
          }
        }
      } finally {
        seenInBranch.remove(id);
      }

      return node;
    }

    return <String, Object?>{
      'rootId': rootId,
      'truncated': truncated,
      'tree': buildNode(rootId, 0),
    };
  }

  /// Interroge les données, schémas et sélections actives du [JsonRepositoryStore].
  Future<Map<String, Object?>> queryRepositoryData(
    Map<String, Object?> args,
  ) async {
    final store = repositoryStore;
    if (store == null) {
      return const <String, Object?>{
        'available': false,
        'error': 'Aucun JsonRepositoryStore actif dans ce contexte.',
      };
    }

    final repoId = args['repositoryId'] is String
        ? (args['repositoryId'] as String).trim()
        : '';
    final path = args['path'] is String ? (args['path'] as String).trim() : '';
    final rawOffset = args['offset'];
    final offset = rawOffset is num ? math.max(0, rawOffset.toInt()) : 0;
    final rawLimit = args['limit'];
    final limit = (rawLimit is num ? rawLimit.toInt() : 10).clamp(1, 50);

    final catalog = await store.catalog();
    if (repoId.isEmpty) {
      final list = <Map<String, Object?>>[];
      for (final entry in catalog) {
        Object? doc;
        try {
          doc = await store.readDocument(entry.id);
        } on FormatException {
          doc = null;
        }
        final binding = store.bindingOf(entry.id);
        list.add(<String, Object?>{
          'id': entry.id,
          'name': entry.name,
          'kind': store.isPersistentRepository(entry.id)
              ? 'persistent'
              : (store.isMemoryOnlyRepository(entry.id) ? 'memory' : 'file'),
          if (doc is Map)
            'rootKeys': {
              for (final k in doc.keys)
                '$k': _describeJsonShape(doc[k]),
            },
          'calculatedAttributes': [
            for (final attr in store.calculatedAttributeCatalog(entry.id))
              attr.path,
          ],
          'selections': {
            for (final arr in binding.arrays)
              if (arr.selection != null) arr.template: arr.selection,
          },
        });
      }
      return <String, Object?>{
        'available': true,
        'repositoryCount': list.length,
        'repositories': list,
      };
    }

    final entry = catalog.where((e) => e.id == repoId).firstOrNull;
    if (entry == null) {
      return <String, Object?>{
        'available': true,
        'found': false,
        'error': 'Repository "$repoId" introuvable.',
      };
    }

    final binding = store.bindingOf(repoId);
    final selections = <String, Object?>{
      for (final arr in binding.arrays)
        if (arr.selection != null) arr.template: arr.selection,
    };

    if (path.isEmpty) {
      final doc = await store.readDocument(repoId);
      return <String, Object?>{
        'available': true,
        'found': true,
        'id': entry.id,
        'name': entry.name,
        if (selections.isNotEmpty) 'selections': selections,
        'data': _paginateJsonValue(doc, offset: offset, limit: limit),
      };
    }

    final parsedPath = JsonAttributePath(path);
    if (parsedPath.calculated != null) {
      final attr = await store.readAttribute(
        JsonTextBinding(repositoryId: repoId, path: path),
      );
      return <String, Object?>{
        'available': true,
        'found': true,
        'id': entry.id,
        'path': path,
        'text': attr.text,
        if (selections.isNotEmpty) 'selections': selections,
        'value': _paginateJsonValue(attr.value, offset: offset, limit: limit),
      };
    }

    parsedPath.requireResolved();
    final doc = await store.readDocument(repoId);
    final resolvedValue = _navigateJsonPath(doc, path);
    return <String, Object?>{
      'available': true,
      'found': true,
      'id': entry.id,
      'path': path,
      if (selections.isNotEmpty) 'selections': selections,
      'value': _paginateJsonValue(resolvedValue, offset: offset, limit: limit),
    };
  }

  static final RegExp _pathTokenPattern = RegExp(r'([^.\[\]]+)|\[(\d+)\]');

  static Object? _navigateJsonPath(Object? root, String path) {
    Object? current = root;
    for (final match in _pathTokenPattern.allMatches(path)) {
      final key = match.group(1);
      final indexRaw = match.group(2);
      if (key != null) {
        if (current is! Map) {
          throw const FormatException(
            'Structure JSON incompatible avec le chemin.',
          );
        }
        current = current[key];
      } else if (indexRaw != null) {
        final index = int.parse(indexRaw);
        if (current is! List || index < 0 || index >= current.length) {
          throw const FormatException('Indice de tableau JSON inexistant.');
        }
        current = current[index];
      }
    }
    return current;
  }

  static String _describeJsonShape(Object? value) => switch (value) {
    final List list => 'array(length=${list.length})',
    final Map map => 'object(keys=${map.length})',
    final String _ => 'string',
    final num _ => 'number',
    final bool _ => 'boolean',
    null => 'null',
    _ => value.runtimeType.toString(),
  };

  static Object? _paginateJsonValue(
    Object? value, {
    required int offset,
    required int limit,
    int depth = 0,
  }) {
    if (depth > 4) return _describeJsonShape(value);
    if (value is List) {
      final safeOffset = offset.clamp(0, value.length);
      final end = math.min(value.length, safeOffset + limit);
      return <String, Object?>{
        'totalCount': value.length,
        'offset': safeOffset,
        'limit': limit,
        'items': [
          for (var i = safeOffset; i < end; i++)
            _paginateJsonValue(
              value[i],
              offset: 0,
              limit: 5,
              depth: depth + 1,
            ),
        ],
      };
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': _paginateJsonValue(
            entry.value,
            offset: offset,
            limit: limit,
            depth: depth + 1,
          ),
      };
    }
    if (value is String && value.length > 500) {
      return '${value.substring(0, 500)}…';
    }
    return value;
  }

  /// Capture une image PNG d'un composant monté ou de la vue applicative complète.
  Future<VibeToolResult> captureScreenshot(
    String callId,
    String toolName,
    Map<String, Object?> args,
  ) async {
    final componentId =
        args['componentId'] is String &&
                (args['componentId'] as String).trim().isNotEmpty
            ? (args['componentId'] as String).trim()
            : null;
    final zoneId =
        args['zoneId'] is String && (args['zoneId'] as String).trim().isNotEmpty
            ? (args['zoneId'] as String).trim()
            : null;
    final rawMaxDim = args['maxDimension'];
    final maxDimension = (rawMaxDim is num ? rawMaxDim.toInt() : 1024).clamp(
      256,
      1600,
    );

    RenderBox? targetBox;
    RenderRepaintBoundary? boundary;

    if (componentId != null) {
      final entries = slotIndex.entriesFor(componentId, zoneId: zoneId);
      if (entries.isEmpty) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'Composant "$componentId" non monté à l’écran : impossible de le capturer.',
        );
      }
      final entry = entries.first;
      final ctx = entry.contentKey.currentContext ?? entry.slotContext();
      if (ctx == null || !ctx.mounted) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message: 'Contexte du composant "$componentId" indisponible.',
        );
      }
      final renderObj = ctx.findRenderObject();
      final ancestorBoundary = ctx
          .findAncestorRenderObjectOfType<RenderRepaintBoundary>();
      await _settleFrameIfNeeded(renderObj);
      if (renderObj is! RenderBox || !renderObj.attached || !renderObj.hasSize) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'Le composant "$componentId" ne dispose pas d’une boîte de rendu mesurée.',
        );
      }
      targetBox = renderObj;
      boundary = renderObj is RenderRepaintBoundary
          ? renderObj
          : ancestorBoundary;
    } else {
      final rootCtx = _resolvePrimaryContext();
      if (rootCtx == null || !rootCtx.mounted) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message: 'Aucune vue applicative montée à capturer.',
        );
      }
      final rootObj = rootCtx.findRenderObject();
      final ancestorBoundary = rootCtx
          .findAncestorRenderObjectOfType<RenderRepaintBoundary>();
      await _settleFrameIfNeeded(rootObj);
      if (rootObj is RenderRepaintBoundary) {
        boundary = rootObj;
        targetBox = rootObj;
      } else {
        boundary = ancestorBoundary;
        if (rootObj is RenderBox && rootObj.attached && rootObj.hasSize) {
          targetBox = rootObj;
        } else {
          targetBox = boundary;
        }
      }
    }

    if (boundary == null ||
        !boundary.attached ||
        !boundary.hasSize ||
        targetBox == null ||
        !targetBox.attached ||
        !targetBox.hasSize) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Aucun RenderRepaintBoundary actif trouvé pour la capture.',
      );
    }

    if (boundary.debugNeedsPaint) {
      SchedulerBinding.instance.ensureVisualUpdate();
      try {
        await SchedulerBinding.instance.endOfFrame.timeout(
          const Duration(milliseconds: 250),
        );
      } on TimeoutException {
        // Poursuit si possible, sinon retourne une erreur propre ci-dessous.
      }
      if (boundary.debugNeedsPaint) {
        return VibeToolResult.error(
          callId: callId,
          name: toolName,
          message:
              'La surface n’a pas encore été peinte : réessaye après le rendu.',
        );
      }
    }

    final targetSize = targetBox.size;
    if (targetSize.width <= 0 || targetSize.height <= 0) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'La cible a une taille nulle (${targetSize.width}x${targetSize.height}).',
      );
    }

    final longest = math.max(targetSize.width, targetSize.height);
    final ratio = longest > maxDimension ? maxDimension / longest : 1.0;

    final ui.Image boundaryImage = await boundary.toImage(pixelRatio: ratio);
    Uint8List? pngBytes;
    try {
      if (identical(targetBox, boundary)) {
        final byteData = await boundaryImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        pngBytes = byteData?.buffer.asUint8List();
      } else {
        final relativeRect = MatrixUtils.transformRect(
          targetBox.getTransformTo(boundary),
          Offset.zero & targetSize,
        );
        final srcRect = Rect.fromLTWH(
          (relativeRect.left * ratio).clamp(0.0, boundaryImage.width.toDouble()),
          (relativeRect.top * ratio).clamp(0.0, boundaryImage.height.toDouble()),
          (relativeRect.width * ratio).clamp(1.0, boundaryImage.width.toDouble()),
          (relativeRect.height * ratio).clamp(1.0, boundaryImage.height.toDouble()),
        );
        final dstWidth = math.max(1, srcRect.width.round());
        final dstHeight = math.max(1, srcRect.height.round());
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImageRect(
          boundaryImage,
          srcRect,
          Rect.fromLTWH(0, 0, dstWidth.toDouble(), dstHeight.toDouble()),
          Paint(),
        );
        final picture = recorder.endRecording();
        final cropped = await picture.toImage(dstWidth, dstHeight);
        picture.dispose();
        try {
          final byteData = await cropped.toByteData(
            format: ui.ImageByteFormat.png,
          );
          pngBytes = byteData?.buffer.asUint8List();
        } finally {
          cropped.dispose();
        }
      }
    } finally {
      boundaryImage.dispose();
    }

    if (pngBytes == null || pngBytes.isEmpty) {
      return VibeToolResult.error(
        callId: callId,
        name: toolName,
        message: 'Échec de l’encodage PNG de la capture.',
      );
    }

    final fileLabel = componentId == null
        ? 'screenshot_viewport.png'
        : 'screenshot_$componentId${zoneId == null ? '' : '_$zoneId'}.png';

    return VibeToolResult(
      callId: callId,
      name: toolName,
      data: <String, Object?>{
        'target': componentId ?? 'viewport',
        'zoneId': ?zoneId,
        'logicalWidth': _round2(targetSize.width),
        'logicalHeight': _round2(targetSize.height),
        'pixelRatio': _round2(ratio),
        'imageAttachment': fileLabel,
      },
      attachments: <VibeChatAttachment>[
        VibeChatAttachment.image(
          name: fileLabel,
          bytes: pngBytes,
          mimeType: 'image/png',
        ),
      ],
    );
  }
}

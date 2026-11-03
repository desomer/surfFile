/// Point d'entrée de l'application autonome `super_designer`.
///
/// Combine le moteur `super_container_layout` et le catalogue d'extensions
/// `super_container_extensions` (`SuperChart`, etc.) au sein d'un même [Registry].
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:super_container_extensions/super_container_extensions.dart';
import 'package:super_container_layout/super_container_layout.dart';

import 'yaml2jsonschemas_parser.dart';

export 'json_browser.dart';
export 'yaml2jsonschemas_parser.dart';

export 'package:super_container_extensions/super_container_extensions.dart';
export 'package:super_container_layout/super_container_layout.dart';

/// Crée et initialise un [Registry] contenant tous les composants du moteur
/// (`bootstrap`) ainsi que toutes les extensions (`registerAllExtensions`).
Registry createSuperDesignerRegistry({
  List<String> availableFontFamilies = Registry.defaultAvailableFontFamilies,
}) => Registry()
  ..bootstrap(availableFontFamilies: availableFontFamilies)
  ..registerAllExtensions(availableFontFamilies: availableFontFamilies);

/// Alias conservé pour la compatibilité avec le `main.dart` de `super_container_layout`.
typedef TestApp = SuperDesignerApp;

/// Lance l'application autonome `super_designer`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var envText = '';
  final paths = [
    'env',
    'packages${Platform.pathSeparator}super_designer${Platform.pathSeparator}env',
    'packages${Platform.pathSeparator}super_container_layout${Platform.pathSeparator}env',
  ];
  for (final path in paths) {
    final file = File(path);
    if (await file.exists()) {
      envText = await file.readAsString();
      break;
    }
  }
  final environmentKey = Platform.environment['GEMINI_API_KEY'];
  dotenv.loadFromString(
    envString: envText,
    isOptional: true,
    mergeWith: environmentKey == null
        ? const {}
        : {'GEMINI_API_KEY': environmentKey},
  );
  runApp(const SuperDesignerApp());
}

/// Widget racine de l'application de démonstration et d'édition `super_designer`,
/// donnant accès au moteur `super_container_layout` et à ses extensions.
class SuperDesignerApp extends StatefulWidget {
  const SuperDesignerApp({super.key});

  @override
  State<SuperDesignerApp> createState() => _SuperDesignerAppState();
}

class _SuperDesignerAppState extends State<SuperDesignerApp> {
  final _registry = createSuperDesignerRegistry();
  final _eventBus = SuperEventBus();
  late final StreamSubscription<SuperComponentEvent> _eventSubscription;

  static const _repositoryId = '0123456789abcdef0123456789abcdef';
  static const _eastSizeBinding = JsonTextBinding(
    repositoryId: _repositoryId,
    path: 'estSize',
  );
  late final _repositoryStore = JsonRepositoryStore.defaultStore();

  /// Schéma issu du DSL YAML de `source`, patché à chaque modification pour
  /// garder les ID et les propriétés saisies dans l'IHM.
  final _schemaParser = Yaml2JsonSchemasParser();
  late final _jsonModel = _schemaParser.model('source', '');

  void _onRepositoryChanged(ChangeContext change) {
    debugPrint(
      'Repository ${change.repositoryId}: ${change.path} changed by '
      '${change.componentId ?? 'unknown component'} '
      '(${change.oldValue} -> ${change.newValue})',
    );
    if (change.path == 'source') unawaited(_validateYaml(change.newValue));
  }

  /// Patche [_jsonModel] avec le DSL de schéma de `source` : publie l'erreur
  /// dans `yamlError` et, si le parsing réussit, écrit ses nœuds dans `nodes`.
  Future<void> _validateYaml(Object? source) async {
    var message = '';
    try {
      _schemaParser.patch(_jsonModel, source is String ? source : '');
    } on FormatException catch (error) {
      message = error.message;
    }
    const errorBinding = JsonTextBinding(
      repositoryId: _repositoryId,
      path: 'yamlError',
    );
    final current = await _repositoryStore.readAttribute(errorBinding);
    if (current.value != message) {
      await _repositoryStore.writeAttribute(
        errorBinding,
        message,
        expectedValue: current.value,
        componentId: 'yaml-validator',
      );
    }
    if (message.isEmpty) {
      await _repositoryStore.replaceArray(_repositoryId, 'nodes', [
        for (final node in _jsonModel.nodes) node.toJson(),
      ], componentId: 'yaml-validator');
    }
  }

  late final EditorPageRouter _pageRouting;
  GoRouter get _router => _pageRouting.router;

  @override
  void initState() {
    super.initState();
    _eventSubscription = _eventBus
        .on('node.click')
        .asyncMap((event) async {
          final current = await _repositoryStore.readAttribute(
            _eastSizeBinding,
          );
          final size = current.value;
          if (size is! num || !size.isFinite) {
            throw StateError('estSize doit etre une taille numerique finie.');
          }
          await _repositoryStore.writeAttribute(
            _eastSizeBinding,
            size == 0 ? '300' : '0',
            expectedValue: current.value,
            componentId: event.componentId,
          );
          return event;
        })
        .listen((event) {
          debugPrint(
            'Event ${event.eventId} from ${event.componentId} '
            '(${event.trigger}): ${event.data}',
          );
        });

    var repository = RepositoryImpl(
      id: _repositoryId,
      onChanged: _onRepositoryChanged,
      json: {
        'source': '',
        'estSize': 300,
        'yamlError': '',
        'nodes': [{}],
      },
    );

    _repositoryStore.registerRepository(repository);
    unawaited(_validateYaml(repository.json['source']));
    _registry.registerComponent(
      'A',
      RegisteredComponent(
        label: 'A',
        isAvailable: (context) {
          return true;
        },
        builder: (_) => SuperLayout(
          label: 'layout',
          behaviours: [
            ComponentBehavior(
              id: 'global-node-properties-size',
              trigger: BehaviorTrigger.binding,
              action: ZoneSizeBindingAction(
                zone: SuperLayoutZone.east,
                binding: _eastSizeBinding,
              ),
            ),
          ],
          config: const SuperLayoutConfig(
            west: true,
            westSize: 320,
            east: true,
            eastSize: 300,
            autoSides: {SuperLayoutZone.center},
            sideResizing: {SuperLayoutZone.west: true},
            placements: {
              SuperLayoutZone.west: ['explorer-code'],
              SuperLayoutZone.center: ['explorer-tree'],
              SuperLayoutZone.east: ['global-node-properties'],
            },
          ),
          slots: [
            BuilderSlot(
              id: 'explorer-code',
              label: 'Code',
              builder: (_) => const SuperCode(
                id: 'explorer-code',
                config: SuperCodeConfig(
                  binding: JsonTextBinding(
                    repositoryId: _repositoryId,
                    path: 'source',
                  ),
                  errorBinding: JsonTextBinding(
                    repositoryId: _repositoryId,
                    path: 'yamlError',
                  ),
                ),
              ),
            ),
            BuilderSlot(
              id: 'global-node-properties',
              label: 'Global Node Properties',
              builder: (_) => const SuperValue(
                id: 'global-node-properties_text',
                config: SuperValueConfig(
                  binding: JsonTextBinding(
                    repositoryId: _repositoryId,
                    path: 'nodes[?].propertiesText',
                  ),
                  minLines: 5,
                  maxLines: 5,
                ),
              ),
            ),
            BuilderSlot(
              id: 'explorer-tree',
              label: 'TreeView',
              builder: (_) => SuperTreeView(
                id: 'explorer-tree',
                header: SuperLayout(
                  label: 'Node header',
                  config: const SuperLayoutConfig(
                    zoneAxes: {SuperLayoutZone.center: Axis.horizontal},
                    zoneFlows: {
                      SuperLayoutZone.center: ZoneFlowConfig(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      ),
                    },
                    placements: {
                      SuperLayoutZone.center: [
                        'tree-node-icon',
                        'tree-node-name',
                        'tree-node-separator',
                        'tree-node-type',
                      ],
                    },
                  ),
                  slots: [
                    BuilderSlot(
                      id: 'tree-node-icon',
                      label: 'Icon',
                      builder: (_) => SuperIndicator(
                        id: 'tree-node-icon',
                        config: SuperIndicatorConfig(
                          icon: 'description',
                          iconSize: 18,
                          states: IndicatorConfigStates(
                            binding: const JsonTextBinding(path: 'typeIcon'),
                            named: const {
                              'container': SuperIndicatorConfig(icon: 'folder'),
                              'value': SuperIndicatorConfig(
                                icon: 'description',
                              ),
                            },
                            namedProperties: const {
                              'container': {IndicatorStateProperty.icon},
                              'value': {IndicatorStateProperty.icon},
                            },
                          ),
                        ),
                      ),
                    ),
                    BuilderSlot(
                      id: 'tree-node-name',
                      label: 'Name',
                      builder: (_) => SuperValue(
                        id: 'tree-node-name',
                        behaviours: [
                          ComponentBehavior(
                            id: 'tree-node-name-click',
                            trigger: BehaviorTrigger.click,
                            action: EmitEventAction(eventId: 'node.click'),
                          ),
                        ],
                        config: const SuperValueConfig(
                          binding: JsonTextBinding(path: 'name'),
                        ),
                      ),
                    ),
                    BuilderSlot(
                      id: 'tree-node-separator',
                      label: 'Separator',
                      builder: (_) => const SuperSeparator(
                        id: 'tree-node-separator',
                        config: SuperSeparatorConfig(
                          kind: SuperSeparatorKind.spacer,
                        ),
                      ),
                    ),
                    BuilderSlot(
                      id: 'tree-node-type',
                      label: 'Type',
                      builder: (_) => const SuperValue(
                        id: 'tree-node-type',
                        config: SuperValueConfig(
                          binding: JsonTextBinding(path: 'type'),
                        ),
                      ),
                    ),
                  ],
                ),
                data: SuperLayout(
                  label: 'Node data',
                  config: const SuperLayoutConfig(
                    east: true,
                    eastSize: 300,
                    zoneAxes: {SuperLayoutZone.center: Axis.horizontal},
                    zoneFlows: {
                      SuperLayoutZone.center: ZoneFlowConfig(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      ),
                    },
                    placements: {
                      SuperLayoutZone.center: [
                        'tree-node-id',
                        'tree-node-properties',
                      ],
                    },
                  ),
                  slots: [
                    BuilderSlot(
                      id: 'tree-node-id',
                      label: 'ID',
                      builder: (_) => const SuperValue(
                        id: 'tree-node-id',
                        config: SuperValueConfig(
                          binding: JsonTextBinding(path: 'id'),
                        ),
                      ),
                    ),
                    BuilderSlot(
                      id: 'tree-node-properties',
                      label: 'Properties',
                      builder: (_) => const SuperValue(
                        id: 'tree-node-properties',
                        config: SuperValueConfig(
                          binding: JsonTextBinding(path: 'propertiesText'),
                        ),
                      ),
                    ),
                  ],
                ),
                config: SuperTreeViewConfig(
                  binding: const JsonTextBinding(
                    repositoryId: _repositoryId,
                    path: 'nodes',
                  ),
                  placements: const {
                    SuperTreeViewConfig.headerZone: ['header'],
                    SuperTreeViewConfig.dataZone: ['data'],
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );

    _pageRouting = EditorPageRouter(
      baseConfig: RoutingConfig(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => getRootWidget(_registry),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_eventSubscription.cancel());
    unawaited(_eventBus.close());
    _pageRouting.dispose();
    _repositoryStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SuperApp(
    router: _router,
    pageRouting: _pageRouting,
    title: 'Card Layout demo 2',
    registry: _registry,
    repositoryStore: _repositoryStore,
    eventBus: _eventBus,
  );

  /// Construit la surface racine contenant la [SuperPage] et la barre d'outils flottante.
  Widget getRootWidget(Registry registry) {
    return Builder(
      builder: (context) {
        final superapp = SuperApp.of(context);
        final superLayoutConfig = superapp.getLayoutConfigById('mainLayout');

        return EditableSurface(
          slot: AppearanceSlot(
            'Fond',
            name: 'demo-background',
            role: AppearanceSurfaceRole.applicationBackground,
            editShape: false,
            extendedLook: false,
            read: (a) => a.backgroundStyle,
            write: (a, style) => a.withStyle('background', style),
            reset: (a) => a.withStyle('background', null),
          ),
          menuIcon: Icons.wallpaper_outlined,
          decorate: false,
          applyPadding: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: SuperPage(
                  menuIcon: Icons.article_outlined,
                  child: ValueListenableBuilder<SuperLayoutConfig>(
                    valueListenable: superLayoutConfig,
                    builder: (context, config, _) => SuperLayout(
                      label: 'Main Layout',
                      config: config,
                      onChanged: (value) => superLayoutConfig.value = value,
                      menuIcon: Icons.dashboard_outlined,
                      slots: const [],
                    ),
                  ),
                ),
              ),
              const Positioned.fill(child: FloatingAppearanceToolbar()),
            ],
          ),
        );
      },
    );
  }
}

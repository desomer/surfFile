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
import 'package:super_designer/impl.dart';

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
  final sep = Platform.pathSeparator;
  final paths = [
    'env',
    '.env',
    ['packages', 'super_designer', 'env'].join(sep),
    ['packages', 'super_designer', '.env'].join(sep),
    ['packages', 'super_container_layout', 'env'].join(sep),
    ['packages', 'super_container_layout', '.env'].join(sep),
    ['..', 'super_container_layout', 'env'].join(sep),
    ['..', 'super_container_layout', '.env'].join(sep),
    ['..', 'super_designer', 'env'].join(sep),
    ['..', 'super_designer', '.env'].join(sep),
    ['..', 'env'].join(sep),
    ['..', '.env'].join(sep),
  ];
  for (final path in paths) {
    final file = File(path);
    if (await file.exists()) {
      envText = await file.readAsString();
      break;
    }
  }
  if (envText.isEmpty) {
    try {
      var dir = Directory.current;
      while (true) {
        for (final candidate in [
          'env',
          '.env',
          ['packages', 'super_designer', 'env'].join(sep),
          ['packages', 'super_container_layout', 'env'].join(sep),
        ]) {
          final file = File('${dir.path}$sep$candidate');
          if (await file.exists()) {
            envText = await file.readAsString();
            break;
          }
        }
        if (envText.isNotEmpty || dir.parent.path == dir.path) break;
        dir = dir.parent;
      }
    } catch (_) {}
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

    initRegistry(_registry);

    _registry.registerComponent(
      'model-code',
      RegisteredComponent.composable(
        label: 'model-code',
        duplication: ComponentDuplicationContract.newContainer,
        isAvailable: (context) {
          return true;
        },
        instanceBuilder: (_, id) => EditableSurface(
          id: id,
          label: 'model-code',
          menuType: 'Card',
          style: const ContainerStyle(color: Color(0xFF2B382C)),
          child: const SuperCode(
            id: 'model-code-editor',
            config: SuperCodeConfig(
              style: SuperCodeStyle(transparentBackground: true),
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
      ),
    );

    _registry.registerComponent(
      'model-header',
      RegisteredComponent.composable(
        label: 'Model Header',
        menuIcon: Icons.code,
        duplication: ComponentDuplicationContract.newLayout,
        instanceBuilder: (_, id) => SuperLayout(
          id: id,
          label: 'Node header',
          config: const SuperLayoutConfig(
            zoneAxes: {SuperLayoutZone.center: Axis.horizontal},
            zoneFlows: {
              SuperLayoutZone.center: ZoneFlowConfig(expandSlots: false),
            },
            slotSizeConstraints: {
              'tree-node-separator': SlotSizeConstraints(fitContent: false),
              'tree-node-name': SlotSizeConstraints(
                paddingInsets: EdgeInsets.fromLTRB(5, 0, 0, 0),
                percentBasis: SlotPercentBasis.layout,
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
                      'value': SuperIndicatorConfig(icon: 'description'),
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
                config: SuperSeparatorConfig(kind: SuperSeparatorKind.spacer),
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
      ),
    );

    _registry.registerComponent(
      'model-tab',
      RegisteredComponent.composable(
        label: 'model-tab',
        duplication: ComponentDuplicationContract.superTab,
        isAvailable: (context) {
          return true;
        },
        instanceBuilder: (_, id) => SuperTab(
          id: id,
          label: 'Configurer les onglets',
          config: SuperTabConfig(
            tabBarStyle: const ContainerStyle(
              radius: 12,
              elevation: 3.685863874345599,
              shadowOpacity: 0.6387434554973861,
              neon: NeonStyle(),
            ),
            indicatorKind: SuperTabIndicatorKind.box,
            indicatorRadius: 15.61465968586392,
            indicatorHorizontalPadding: 0.13403141361261248,
            indicatorVerticalPadding: 3.585340314136142,
            overlayColor: const Color(0x00979AA9),
            labelHorizontalPadding: 0,
            dividerColor: const Color(0x00C6C5D0),
            tabAlignment: TabAlignment.fill,
            slotSizeConstraints: const {
              'KlSbddMArN': SlotSizeConstraints(
                preferredWidth: SlotDimension(124, SlotSizeUnit.pixels),
                percentBasis: SlotPercentBasis.layout,
              ),
            },
            placements: const {
              'tabs': ['KlSbddMArN', 'I511oCPeBH', 'YM2KFsXQQz'],
              'content:KlSbddMArN': ['tab-content-model-impl'],
            },
            slotTypes: const {'tab-content-model-impl': 'component:model-code'},
          ),
          slots: [
            BuilderSlot(
              id: 'KlSbddMArN',
              label: 'Structure',
              builder: (_) => const SuperAction(
                id: 'KlSbddMArN',
                config: SuperActionConfig(
                  variant: SuperActionVariant.text,
                  label: 'Structure',
                ),
              ),
            ),
            BuilderSlot(
              id: 'I511oCPeBH',
              label: 'Info',
              builder: (_) => const SuperAction(
                id: 'I511oCPeBH',
                config: SuperActionConfig(
                  variant: SuperActionVariant.text,
                  label: 'Info',
                ),
              ),
            ),
            BuilderSlot(
              id: 'YM2KFsXQQz',
              label: 'Version',
              builder: (_) => const SuperAction(
                id: 'YM2KFsXQQz',
                config: SuperActionConfig(
                  variant: SuperActionVariant.text,
                  label: 'Version',
                ),
              ),
            ),
            BuilderSlot(
              id: 'tab-content-model-impl',
              label: 'tab-content-model',
              builder: (context) =>
                  SuperApp.of(context).registry!
                      .component('model-code')
                      .builder(context),
            ),
          ],
        ),
      ),
    );

    _registry.registerComponent(
      'main-tabs',
      RegisteredComponent.composable(
        label: 'main-tabs',
        duplication: ComponentDuplicationContract.superTab,
        isAvailable: (context) {
          return true;
        },
        instanceBuilder: (_, id) => SuperTab(
          id: id,
          label: 'main tabs',
          config: SuperTabConfig(
            zoneFlows: const {
              'content:tab-info': ZoneFlowConfig(
                scrollable: true,
                expandSlots: false,
                spacing: 12,
                padding: 16,
              ),
              'content:tab-validator': ZoneFlowConfig(
                scrollable: true,
                expandSlots: false,
                spacing: 12,
                padding: 16,
              ),
            },
            slotSizeConstraints: const {'_wSA5mADEd': SlotSizeConstraints()},
            placements: const {
              'tabs': ['tab-info', 'tab-validator'],
              'content:tab-info': [
                'field-description',
                'field-example',
                'field-const',
                'field-default',
                'switch-nullable',
                'switch-readonly',
                'switch-writeonly',
                'switch-deprecated',
                'switch-search-ref',
                '_wSA5mADEd',
              ],
              'content:tab-validator': ['val-placeholder'],
            },
          ),
          slots: [
            BuilderSlot(
              id: 'tab-info',
              label: 'tab-info',
              builder: (_) => const SuperAction(
                id: 'tab-info',
                config: SuperActionConfig(
                  kind: SuperActionKind.textAndIcon,
                  label: 'Info',
                  icon: 'info',
                ),
              ),
            ),
            BuilderSlot(
              id: 'tab-validator',
              label: 'tab-validator',
              builder: (_) => const SuperAction(
                id: 'tab-validator',
                config: SuperActionConfig(
                  kind: SuperActionKind.textAndIcon,
                  label: 'Validator',
                  icon: 'check_circle',
                ),
              ),
            ),
            BuilderSlot(
              id: 'field-description',
              label: 'field-description',
              builder: (_) => const SuperValue(
                id: 'field-description',
                config: SuperValueConfig(
                  mode: SuperValueMode.input,
                  label: 'Description',
                  minLines: 4,
                  maxLines: 4,
                  field: SuperTextFieldConfig(
                    variant: TextFieldVariant.outlined,
                  ),
                ),
              ),
            ),
            BuilderSlot(
              id: 'field-example',
              label: 'field-example',
              builder: (_) => const SuperValue(
                id: 'field-example',
                config: SuperValueConfig(
                  mode: SuperValueMode.input,
                  label: 'Example',
                  minLines: 4,
                  maxLines: 4,
                  field: SuperTextFieldConfig(
                    variant: TextFieldVariant.outlined,
                  ),
                ),
              ),
            ),
            BuilderSlot(
              id: 'field-const',
              label: 'field-const',
              builder: (_) => const SuperValue(
                id: 'field-const',
                config: SuperValueConfig(
                  mode: SuperValueMode.input,
                  label: 'Const',
                  field: SuperTextFieldConfig(
                    variant: TextFieldVariant.outlined,
                  ),
                ),
              ),
            ),
            BuilderSlot(
              id: 'field-default',
              label: 'field-default',
              builder: (_) => const SuperValue(
                id: 'field-default',
                config: SuperValueConfig(
                  mode: SuperValueMode.input,
                  label: 'Default',
                  field: SuperTextFieldConfig(
                    variant: TextFieldVariant.outlined,
                  ),
                ),
              ),
            ),
            BuilderSlot(
              id: 'switch-nullable',
              label: 'switch-nullable',
              builder: (_) => const SuperValue(
                id: 'switch-nullable',
                config: SuperValueConfig(
                  mode: SuperValueMode.input,
                  kind: SuperValueKind.switchControl,
                  label: 'Nullable',
                ),
              ),
            ),
            BuilderSlot(
              id: 'switch-readonly',
              label: 'switch-readonly',
              builder: (_) => const SuperValue(
                id: 'switch-readonly',
                config: SuperValueConfig(
                  mode: SuperValueMode.input,
                  kind: SuperValueKind.switchControl,
                  label: 'ReadOnly',
                ),
              ),
            ),
            BuilderSlot(
              id: 'switch-writeonly',
              label: 'switch-writeonly',
              builder: (_) => const SuperValue(
                id: 'switch-writeonly',
                config: SuperValueConfig(
                  mode: SuperValueMode.input,
                  kind: SuperValueKind.switchControl,
                  label: 'WriteOnly',
                ),
              ),
            ),
            BuilderSlot(
              id: 'switch-deprecated',
              label: 'switch-deprecated',
              builder: (_) => const SuperValue(
                id: 'switch-deprecated',
                config: SuperValueConfig(
                  mode: SuperValueMode.input,
                  kind: SuperValueKind.switchControl,
                  label: 'Deprecated',
                ),
              ),
            ),
            BuilderSlot(
              id: 'switch-search-ref',
              label: 'switch-search-ref',
              builder: (_) => const SuperValue(
                id: 'switch-search-ref',
                config: SuperValueConfig(
                  mode: SuperValueMode.input,
                  kind: SuperValueKind.switchControl,
                  label: 'Search reference',
                ),
              ),
            ),
            BuilderSlot(
              id: '_wSA5mADEd',
              label: '_wSA5mADEd',
              builder: (_) => const SuperValue(
                id: '_wSA5mADEd',
                config: SuperValueConfig(
                  mode: SuperValueMode.input,
                  label: 'Comment',
                  minLines: 4,
                  maxLines: 4,
                  field: SuperTextFieldConfig(
                    variant: TextFieldVariant.outlined,
                  ),
                ),
              ),
            ),
            BuilderSlot(
              id: 'val-placeholder',
              label: 'val-placeholder',
              builder: (_) => const SuperValue(
                id: 'val-placeholder',
                config: SuperValueConfig(
                  initialText: 'Configuration des validateurs',
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    _registry.registerComponent(
      'ModelDesc',
      RegisteredComponent.composable(
        label: 'Model Desc',
        duplication: ComponentDuplicationContract.newLayout,
        isAvailable: (context) {
          return true;
        },
        instanceBuilder: (_, id) => SuperLayout(
          id: id,
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
              SuperLayoutZone.west: ['input-code'],
              SuperLayoutZone.center: ['explorer-tree'],
              SuperLayoutZone.east: ['global-node-properties'],
            },
            slotTypes: {'input-code': 'component:model-tab'},
          ),
          slots: [
            BuilderSlot(
              id: 'input-code',
              label: 'Input Code',
              menuIcon: Icons.code,
              builder: (context) =>
                  SuperApp.of(context).registry!
                      .component('model-tab')
                      .builder(context),
            ),
            BuilderSlot(
              id: 'global-node-properties',
              label: 'Global Node Properties',
              builder: (context) =>
                  SuperApp.of(context).registry!
                      .component('main-tabs')
                      .builder(context),
            ),
            BuilderSlot(
              id: 'explorer-tree',
              label: 'TreeView',
              builder: (_) => SuperTreeView(
                id: 'explorer-tree',
                slots: [
                  BuilderSlot(
                    id: 'input-header',
                    label: 'Input Header',
                    menuIcon: Icons.code,
                    builder: (context) =>
                        SuperApp.of(context).registry!
                            .component('model-header')
                            .builder(context),
                  ),
                  BuilderSlot(
                    id: 'input-data',
                    label: 'Input Data',
                    menuIcon: Icons.code,
                    builder: (context) => SuperLayout(
                      id: 'input-data',
                      label: 'Node data',
                      config: const SuperLayoutConfig(
                        zoneAxes: {SuperLayoutZone.center: Axis.horizontal},
                        zoneFlows: {
                          SuperLayoutZone.center: ZoneFlowConfig(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          ),
                        },
                        slotSizeConstraints: {
                          'tree-node-title': SlotSizeConstraints(
                            padding: 1,
                            percentBasis: SlotPercentBasis.layout,
                          ),
                        },
                        placements: {
                          SuperLayoutZone.center: ['tree-node-title'],
                        },
                      ),
                      slots: [
                        BuilderSlot(
                          id: 'tree-node-title',
                          label: 'Title',
                          builder: (_) => const SuperValue(
                            id: 'tree-node-title',
                            config: SuperValueConfig(
                              placeholder: 'title',
                              mode: SuperValueMode.input,
                              binding: JsonTextBinding(
                                repositoryId:
                                    '0123456789abcdef0123456789abcdef',
                                path: 'nodes[?].title',
                              ),
                              field: SuperTextFieldConfig(
                                variant: TextFieldVariant.outlined,
                                borderWidth: 1,
                                horizontalPadding: 0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                config: SuperTreeViewConfig(
                  rowHeight: 28,
                  binding: const JsonTextBinding(
                    repositoryId: _repositoryId,
                    path: 'nodes',
                  ),
                  placements: const {
                    SuperTreeViewConfig.headerZone: ['input-header'],
                    SuperTreeViewConfig.dataZone: ['input-data'],
                  },
                  slotTypes: const {'input-header': 'component:model-header'},
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

import 'package:material_ui/material_ui.dart';
import 'package:super_container_extensions/models/super_code_config.dart';
import 'package:super_container_extensions/widgets/components/super_code.dart';
import 'package:super_container_layout/models/component_behavior.dart';
import 'package:super_container_layout/models/json_text_binding.dart';
import 'package:super_container_layout/models/registry.dart';
import 'package:super_container_layout/models/super_action_config.dart';
import 'package:super_container_layout/models/super_indicator_config.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/models/super_separator_config.dart';
import 'package:super_container_layout/models/super_tab_config.dart';
import 'package:super_container_layout/models/super_text_field_config.dart';
import 'package:super_container_layout/models/super_tree_view_config.dart';
import 'package:super_container_layout/models/super_value_config.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/theme/container_style.dart';
import 'package:super_container_layout/theme/style_extras.dart';
import 'package:super_container_layout/widgets/components/super_action.dart';
import 'package:super_container_layout/widgets/components/super_indicator.dart';
import 'package:super_container_layout/widgets/components/super_layout/slot_implementation.dart';
import 'package:super_container_layout/widgets/components/super_layout/super_layout.dart';
import 'package:super_container_layout/widgets/components/super_separator.dart';
import 'package:super_container_layout/widgets/components/super_tab.dart';
import 'package:super_container_layout/widgets/components/super_tree_view.dart';
import 'package:super_container_layout/widgets/components/super_value.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_surface.dart';

class SuperDesignerRegistry {
  final Registry _registry;

  SuperDesignerRegistry(this._registry);

  void addRegistryTreeAttributData() {
    _registry.registerComponent(
      'tree-attribut-data',
      RegisteredComponent(
        label: 'tree-attribut-data',
        isAvailable: (context) {
          return true;
        },
        instanceBuilder: (_, id) => SuperLayout(
          id: id,
          label: 'tree-attribut-data',
          config: const SuperLayoutConfig(
            autoSides: <Never>{},
            zoneAxes: {SuperLayoutZone.center: Axis.horizontal},
            zoneFlows: {
              SuperLayoutZone.center: ZoneFlowConfig(
                expandSlots: false,
                crossAxisAlignment: CrossAxisAlignment.center,
                spacing: 2,
              ),
            },
            slotSizeConstraints: {
              'tree-node-title': SlotSizeConstraints(
                preferredWidth: SlotDimension(250, SlotSizeUnit.pixels),
              ),
              'action-is-required': SlotSizeConstraints(
                preferredWidth: SlotDimension(22, SlotSizeUnit.pixels),
              ),
              'action-search': SlotSizeConstraints(
                preferredWidth: SlotDimension(22, SlotSizeUnit.pixels),
              ),
              'action-checklist': SlotSizeConstraints(
                preferredWidth: SlotDimension(22, SlotSizeUnit.pixels),
              ),
              'action-tune': SlotSizeConstraints(
                preferredWidth: SlotDimension(22, SlotSizeUnit.pixels),
              ),
            },
            placements: {
              SuperLayoutZone.center: [
                'tree-node-title',
                'action-is-required',
                'action-search',
                'action-checklist',
                'action-tune',
                'action-format',
              ],
            },
          ),
          slots: [
            BuilderSlot(
              id: 'tree-node-title',
              label: 'tree-node-title',
              builder: (_) => const SuperValue(
                id: 'tree-node-title',
                config: SuperValueConfig(
                  mode: SuperValueMode.input,
                  placeholder: 'title',
                  binding: JsonTextBinding(
                    repositoryId: 'pan_model_repository',
                    path: 'nodes[?].title',
                  ),
                  field: SuperTextFieldConfig(
                    variant: TextFieldVariant.outlined,
                    borderWidth: 1,
                    horizontalPadding: 0,
                    verticalPadding: 6,
                  ),
                ),
              ),
            ),
            BuilderSlot(
              id: 'action-is-required',
              label: 'action-is-required',
              builder: (_) => const SuperAction(
                id: 'action-is-required',
                behaviours: [
                  ComponentBehavior(
                    id: 'behavior-wSORuaA18y',
                    trigger: BehaviorTrigger.binding,
                    action: StateBindingAction(
                      state: BehaviorBoundState.invisible,
                      whenValue: false,
                      binding: JsonTextBinding(
                        repositoryId: 'pan_model_repository',
                        path: 'nodes[?].isRequired',
                      ),
                    ),
                  ),
                ],
                config: SuperActionConfig(
                  kind: SuperActionKind.icon,
                  variant: SuperActionVariant.icon,
                  tooltip: 'Valider',
                  icon: 'check_circle',
                  iconSize: 20,
                  horizontalPadding: 0,
                  verticalPadding: 0,
                ),
              ),
            ),
            BuilderSlot(
              id: 'action-search',
              label: 'action-search',
              builder: (_) => const SuperAction(
                id: 'action-search',
                behaviours: [
                  ComponentBehavior(
                    id: 'behavior-wSORuaA18y',
                    trigger: BehaviorTrigger.binding,
                    action: StateBindingAction(
                      state: BehaviorBoundState.invisible,
                      whenValue: false,
                      binding: JsonTextBinding(
                        repositoryId: 'pan_model_repository',
                        path: 'nodes[?].isSearchable',
                      ),
                    ),
                  ),
                ],
                config: SuperActionConfig(
                  kind: SuperActionKind.icon,
                  variant: SuperActionVariant.icon,
                  tooltip: 'Rechercher',
                  icon: 'search',
                  iconSize: 20,
                  horizontalPadding: 0,
                  verticalPadding: 0,
                ),
              ),
            ),
            BuilderSlot(
              id: 'action-checklist',
              label: 'action-checklist',
              builder: (_) => const SuperAction(
                id: 'action-checklist',
                config: SuperActionConfig(
                  kind: SuperActionKind.icon,
                  variant: SuperActionVariant.icon,
                  tooltip: 'Règles',
                  icon: 'checklist',
                  iconSize: 20,
                  horizontalPadding: 0,
                  verticalPadding: 0,
                ),
              ),
            ),
            BuilderSlot(
              id: 'action-tune',
              label: 'action-tune',
              builder: (_) => const SuperAction(
                id: 'action-tune',
                config: SuperActionConfig(
                  kind: SuperActionKind.icon,
                  variant: SuperActionVariant.icon,
                  tooltip: 'Paramètres',
                  icon: 'tune',
                  iconSize: 20,
                  horizontalPadding: 0,
                  verticalPadding: 0,
                ),
              ),
            ),
            BuilderSlot(
              id: 'action-format',
              label: 'action-format',
              builder: (_) => EditableSurface(
                id: 'action-format',
                label: 'action-format',
                menuType: 'Card',
                style: const ContainerStyle(
                  color: Color(0x00000000),
                  radius: 8,
                  borderWidth: 2,
                  paddingInsets: Quad(0, 4, 0, 4),
                  marginInsets: Quad(0, 3, 0, 3),
                ),
                child: const SuperValue(
                  id: 'fXlalroVe_',
                  config: SuperValueConfig(initialText: 'mail'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void addRegistry() {
    addRegistryTreeAttributHeader();
    addRegistryTreeAttributData();
    addRegistryPanAttrInfo();
    addRegistryPanAttrStringValidator();
    _registry.registerComponent(
      'attribut-tree',
      RegisteredComponent(
        label: 'attribut-tree',
        isAvailable: (context) {
          return true;
        },
        instanceBuilder: (_, id) => SuperTreeView(
          id: 'attribut-tree',
          slots: [
            BuilderSlot(
              id: 'input-header',
              label: 'input-header',
              builder: (context) =>
                  SuperApp.of(context).registry!
                      .component('tree-attribut-header')
                      .builder(context),
            ),
            BuilderSlot(
              id: 'input-data',
              label: 'input-data',
              builder: (context) =>
                  SuperApp.of(context).registry!
                      .component('tree-attribut-data')
                      .builder(context),
            ),
          ],
          config: SuperTreeViewConfig(
            binding: const JsonTextBinding(
              repositoryId: 'pan_model_repository',
              path: 'nodes',
            ),
            rowHeight: 28,
            placements: const {
              SuperTreeViewConfig.headerZone: ['input-header'],
              SuperTreeViewConfig.dataZone: ['input-data'],
            },
          ),
        ),
      ),
    );

    _registry.registerComponent(
      'tab-properties',
      RegisteredComponent(
        label: 'tab-properties',
        isAvailable: (context) {
          return true;
        },
        instanceBuilder: (_, id) => SuperTab(
          id: 'tab-properties',
          label: 'tab-properties',
          config: SuperTabConfig(
            // tabBarStyle: const ContainerStyle(
            //   radius: 12,
            //   elevation: 4,
            //   shadowOpacity: 0.6,
            // ),
            indicatorKind: SuperTabIndicatorKind.box,
            indicatorRadius: 15.61465968586392,
            indicatorHorizontalPadding: 0.13403141361261248,
            indicatorVerticalPadding: 3.585340314136142,
            overlayColor: const Color(0x00979AA9),
            labelHorizontalPadding: 0,
            dividerColor: const Color(0x00C6C5D0),
            tabAlignment: TabAlignment.center,
            placements: const {
              'tabs': ['tab-tree', 'tab-context', 'tab-behaviours'],
              'content:tab-tree': ['tab-content-tree'],
            },
          ),
          slots: [
            BuilderSlot(
              id: 'tab-tree',
              label: 'tab-tree',
              builder: (_) => const SuperAction(
                id: 'tab-tree',
                config: SuperActionConfig(
                  kind: SuperActionKind.textAndIcon,
                  variant: SuperActionVariant.text,
                  label: 'Properties',
                  icon: 'storage',
                ),
              ),
            ),
            BuilderSlot(
              id: 'tab-context',
              label: 'tab-context',
              builder: (_) => const SuperAction(
                id: 'tab-context',
                config: SuperActionConfig(
                  kind: SuperActionKind.textAndIcon,
                  variant: SuperActionVariant.text,
                  label: 'Documentation',
                  icon: 'menu_book',
                ),
              ),
            ),
            BuilderSlot(
              id: 'tab-behaviours',
              label: 'tab-behaviours',
              builder: (_) => const SuperAction(
                id: 'tab-behaviours',
                config: SuperActionConfig(
                  kind: SuperActionKind.textAndIcon,
                  variant: SuperActionVariant.text,
                  label: 'Behaviours',
                  icon: 'manage_accounts',
                ),
              ),
            ),
            BuilderSlot(
              id: 'tab-content-tree',
              label: 'tab-content-tree',
              builder: (context) =>
                  SuperApp.of(context).registry!
                      .component('attribut-tree')
                      .builder(context),
            ),
          ],
        ),
      ),
    );

    _registry.registerComponent(
      'panModel',
      RegisteredComponent(
        label: 'panModel',
        isAvailable: (context) {
          return true;
        },
        instanceBuilder: (_, id) => SuperLayout(
          id: id,
          label: 'panModel',
          behaviours: [
            ComponentBehavior(
              id: 'global-node-properties-size',
              trigger: BehaviorTrigger.binding,
              action: ZoneSizeBindingAction(
                zone: SuperLayoutZone.east,
                binding: const JsonTextBinding(
                  repositoryId: 'pan_model_repository',
                  path: 'estSize',
                ),
              ),
            ),
          ],
          config: const SuperLayoutConfig(
            west: true,
            east: true,
            westSize: 320,
            eastSize: 300,
            sideResizing: {SuperLayoutZone.west: true},
            autoSides: {SuperLayoutZone.center},
            placements: {
              SuperLayoutZone.west: ['input-code'],
              SuperLayoutZone.center: ['explorer-tree'],
              SuperLayoutZone.east: ['global-node-properties'],
            },
          ),
          slots: [
            BuilderSlot(
              id: 'input-code',
              label: 'input-code',
              builder: (_) => SuperTab(
                id: 'input-code',
                label: 'input-code',
                config: SuperTabConfig(
                  tabBarStyle: const ContainerStyle(
                    radius: 12,
                    elevation: 4,
                    shadowOpacity: 0.6387434554973861,
                    //neon: NeonStyle(),
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
                    'tab-structure': SlotSizeConstraints(
                      preferredWidth: SlotDimension(124, SlotSizeUnit.pixels),
                      percentBasis: SlotPercentBasis.layout,
                    ),
                  },
                  placements: const {
                    'tabs': ['tab-structure', 'tab-info', 'tab-version'],
                    'content:tab-structure': ['tab-content-model-impl'],
                  },
                ),
                slots: [
                  BuilderSlot(
                    id: 'tab-structure',
                    label: 'tab-structure',
                    builder: (_) => const SuperAction(
                      id: 'tab-structure',
                      config: SuperActionConfig(
                        kind: SuperActionKind.textAndIcon,
                        variant: SuperActionVariant.text,
                        label: 'Structure',
                        icon: 'grid_view',
                      ),
                    ),
                  ),
                  BuilderSlot(
                    id: 'tab-info',
                    label: 'tab-info',
                    builder: (_) => const SuperAction(
                      id: 'tab-info',
                      config: SuperActionConfig(
                        kind: SuperActionKind.textAndIcon,
                        variant: SuperActionVariant.text,
                        label: 'Info',
                        icon: 'info',
                      ),
                    ),
                  ),
                  BuilderSlot(
                    id: 'tab-version',
                    label: 'tab-version',
                    builder: (_) => const SuperAction(
                      id: 'tab-version',
                      config: SuperActionConfig(
                        kind: SuperActionKind.textAndIcon,
                        variant: SuperActionVariant.text,
                        label: 'Version',
                        icon: 'schedule',
                      ),
                    ),
                  ),
                  BuilderSlot(
                    id: 'tab-content-model-impl',
                    label: 'tab-content-model-impl',
                    builder: (_) => EditableSurface(
                      id: 'tab-content-model-impl',
                      label: 'tab-content-model-impl',
                      menuType: 'Card',
                      style: const ContainerStyle(color: Color(0xFF2B382C)),
                      child: const SuperCode(
                        id: 'tab-content-model-impl:child',
                        config: SuperCodeConfig(
                          binding: JsonTextBinding(
                            repositoryId: 'pan_model_repository',
                            path: 'source',
                          ),
                          errorBinding: JsonTextBinding(
                            repositoryId: 'pan_model_repository',
                            path: 'yamlError',
                          ),
                          style: SuperCodeStyle(transparentBackground: true),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            BuilderSlot(
              id: 'explorer-tree',
              label: 'explorer-tree',
              builder: (context) =>
                  SuperApp.of(context).registry!
                      .component('tab-properties')
                      .builder(context),
            ),
            BuilderSlot(
              id: 'global-node-properties',
              label: 'global-node-properties',
              builder: (context) => SuperTab(
                id: 'global-node-properties',
                label: 'global-node-properties',
                config: SuperTabConfig(
                  indicatorKind: SuperTabIndicatorKind.box,
                  indicatorRadius: 27.610471204188492,
                  overlayColor: const Color(0x00979AA9),
                  indicatorHorizontalPadding: 1.8764397905758665,
                  indicatorVerticalPadding: 3.6523560209424106,
                  zoneFlows: const {
                    'content:tab-info': ZoneFlowConfig(
                      scrollable: true,
                      expandSlots: false,
                    ),
                    'content:tab-validator': ZoneFlowConfig(
                      scrollable: true,
                      expandSlots: false,
                    ),
                  },
                  placements: const {
                    'tabs': ['tab-info', 'tab-validator'],
                    'content:tab-info': ['WBYiTwqr2a'],
                    'content:tab-validator': ['_cpAVbj6Cd'],
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
                    id: 'WBYiTwqr2a',
                    label: 'WBYiTwqr2a',
                    builder: (context) =>
                        SuperApp.of(context).registry!
                            .component('panAttrInfo')
                            .builder(context),
                  ),
                  BuilderSlot(
                    id: '_cpAVbj6Cd',
                    label: '_cpAVbj6Cd',
                    builder: (context) =>
                        SuperApp.of(context).registry!
                            .component('panAttrStringValidator')
                            .builder(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void addRegistryTreeAttributHeader() {
    _registry.registerComponent(
      'tree-attribut-header',
      RegisteredComponent(
        label: 'input-header',
        isAvailable: (context) {
          return true;
        },
        instanceBuilder: (_, id) => SuperLayout(
          id: id,
          label: 'input-header',
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
              label: 'tree-node-icon',
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
              label: 'tree-node-name',
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
              label: 'tree-node-separator',
              builder: (_) => const SuperSeparator(
                id: 'tree-node-separator',
                config: SuperSeparatorConfig(kind: SuperSeparatorKind.spacer),
              ),
            ),
            BuilderSlot(
              id: 'tree-node-type',
              label: 'tree-node-type',
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
  }

  void addRegistryPanAttrStringValidator() {
    _registry.registerComponent(
      'panAttrStringValidator',
      RegisteredComponent(
        label: 'panAttrStringValidator',
        isAvailable: (context) {
          return true;
        },
        instanceBuilder: (_, id) => EditableSurface(
          id: id,
          label: 'panAttrStringValidator',
          menuType: 'Card',
          child: SuperLayout(
            id: '_cpAVbj6Cd:child',
            label: 'Layout',
            config: const SuperLayoutConfig(
              zoneFlows: {
                SuperLayoutZone.center: ZoneFlowConfig(
                  scrollable: true,
                  expandSlots: false,
                  spacing: 10,
                  padding: 12,
                ),
              },
              placements: {
                SuperLayoutZone.center: [
                  'switch-value-object',
                  'switch-required',
                  'field-dependent-required',
                  'field-pattern',
                  'field-format',
                  'field-enum',
                  'field-min-length',
                  'field-max-length',
                  'field-content-encoding',
                  'field-content-media-type',
                  'field-link',
                ],
              },
            ),
            slots: [
              BuilderSlot(
                id: 'switch-value-object',
                label: 'switch-value-object',
                builder: (_) => const SuperValue(
                  id: 'switch-value-object',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    kind: SuperValueKind.switchControl,
                    label: 'valueObject',
                  ),
                ),
              ),
              BuilderSlot(
                id: 'switch-required',
                label: 'switch-required',
                builder: (_) => const SuperValue(
                  id: 'switch-required',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    kind: SuperValueKind.switchControl,
                    initialBool: true,
                    label: 'required',
                  ),
                ),
              ),
              BuilderSlot(
                id: 'field-dependent-required',
                label: 'field-dependent-required',
                builder: (_) => const SuperValue(
                  id: 'field-dependent-required',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    label: 'dependentRequired',
                    minLines: 4,
                    maxLines: 4,
                    field: SuperTextFieldConfig(
                      variant: TextFieldVariant.outlined,
                    ),
                  ),
                ),
              ),
              BuilderSlot(
                id: 'field-pattern',
                label: 'field-pattern',
                builder: (_) => const SuperValue(
                  id: 'field-pattern',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    label: 'pattern',
                    field: SuperTextFieldConfig(
                      variant: TextFieldVariant.outlined,
                    ),
                  ),
                ),
              ),
              BuilderSlot(
                id: 'field-format',
                label: 'field-format',
                builder: (_) => const SuperValue(
                  id: 'field-format',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    label: 'format',
                    field: SuperTextFieldConfig(
                      variant: TextFieldVariant.outlined,
                    ),
                  ),
                ),
              ),
              BuilderSlot(
                id: 'field-enum',
                label: 'field-enum',
                builder: (_) => const SuperValue(
                  id: 'field-enum',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    label: 'enum',
                    minLines: 4,
                    maxLines: 4,
                    field: SuperTextFieldConfig(
                      variant: TextFieldVariant.outlined,
                    ),
                  ),
                ),
              ),
              BuilderSlot(
                id: 'field-min-length',
                label: 'field-min-length',
                builder: (_) => const SuperValue(
                  id: 'field-min-length',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    label: 'minLength',
                    field: SuperTextFieldConfig(
                      variant: TextFieldVariant.outlined,
                    ),
                  ),
                ),
              ),
              BuilderSlot(
                id: 'field-max-length',
                label: 'field-max-length',
                builder: (_) => const SuperValue(
                  id: 'field-max-length',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    label: 'maxLength',
                    field: SuperTextFieldConfig(
                      variant: TextFieldVariant.outlined,
                    ),
                  ),
                ),
              ),
              BuilderSlot(
                id: 'field-content-encoding',
                label: 'field-content-encoding',
                builder: (_) => const SuperValue(
                  id: 'field-content-encoding',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    label: 'contentEncoding',
                    field: SuperTextFieldConfig(
                      variant: TextFieldVariant.outlined,
                    ),
                  ),
                ),
              ),
              BuilderSlot(
                id: 'field-content-media-type',
                label: 'field-content-media-type',
                builder: (_) => const SuperValue(
                  id: 'field-content-media-type',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    label: 'contentMediaType',
                    field: SuperTextFieldConfig(
                      variant: TextFieldVariant.outlined,
                    ),
                  ),
                ),
              ),
              BuilderSlot(
                id: 'field-link',
                label: 'field-link',
                builder: (_) => const SuperValue(
                  id: 'field-link',
                  config: SuperValueConfig(
                    mode: SuperValueMode.input,
                    label: 'link',
                    minLines: 3,
                    maxLines: 3,
                    field: SuperTextFieldConfig(
                      variant: TextFieldVariant.outlined,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void addRegistryPanAttrInfo() {
    _registry.registerComponent(
      'panAttrInfo',
      RegisteredComponent(
        label: 'panAttrInfo',
        isAvailable: (context) {
          return true;
        },
        instanceBuilder: (_, id) => EditableSurface(
          id: id,
          label: 'panAttrInfo',
          menuType: 'Card',
          child: SuperLayout(
            id: 'WBYiTwqr2a:child',
            label: 'Layout',
            config: const SuperLayoutConfig(
              zoneFlows: {
                SuperLayoutZone.center: ZoneFlowConfig(
                  scrollable: true,
                  expandSlots: false,
                  spacing: 12,
                  padding: 16,
                ),
              },
              slotSizeConstraints: {'_wSA5mADEd': SlotSizeConstraints()},
              placements: {
                SuperLayoutZone.center: [
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
              },
            ),
            slots: [
              BuilderSlot(
                id: 'field-description',
                label: 'field-description',
                builder: (_) => const SuperValue(
                  id: 'field-description',
                  config: SuperValueConfig(
                    binding: JsonTextBinding(
                      repositoryId: 'pan_model_repository',
                      path: 'nodes[?].properties.description',
                    ),
                    mode: SuperValueMode.input,
                    label: 'description',
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
                    binding: JsonTextBinding(
                      repositoryId: 'pan_model_repository',
                      path: 'nodes[?].properties.example',
                    ),
                    mode: SuperValueMode.input,
                    label: 'example',
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
                    label: 'const',
                    binding: JsonTextBinding(
                      repositoryId: 'pan_model_repository',
                      path: 'nodes[?].properties.const',
                    ),
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
                    label: 'default',
                    binding: JsonTextBinding(
                      repositoryId: 'pan_model_repository',
                      path: 'nodes[?].properties.default',
                    ),
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
                    label: 'nullable',
                    binding: JsonTextBinding(
                      repositoryId: 'pan_model_repository',
                      path: 'nodes[?].properties.nullable',
                    ),
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
                    label: 'read Only',
                    binding: JsonTextBinding(
                      repositoryId: 'pan_model_repository',
                      path: 'nodes[?].properties.readonly',
                    ),
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
                    label: 'write Only',
                    binding: JsonTextBinding(
                      repositoryId: 'pan_model_repository',
                      path: 'nodes[?].properties.writeonly',
                    ),
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
                    label: 'deprecated',
                    binding: JsonTextBinding(
                      repositoryId: 'pan_model_repository',
                      path: 'nodes[?].properties.deprecated',
                    ),
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
                    label: 'search reference',
                    binding: JsonTextBinding(
                      repositoryId: 'pan_model_repository',
                      path: 'nodes[?].properties.searchRef',
                    ),
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
                    label: 'comment',
                    binding: JsonTextBinding(
                      repositoryId: 'pan_model_repository',
                      path: 'nodes[?].properties.comment',
                    ),
                    minLines: 4,
                    maxLines: 4,
                    field: SuperTextFieldConfig(
                      variant: TextFieldVariant.outlined,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

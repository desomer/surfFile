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
import 'package:super_container_layout/theme/neon_style.dart';
import 'package:super_container_layout/widgets/components/super_action.dart';
import 'package:super_container_layout/widgets/components/super_indicator.dart';
import 'package:super_container_layout/widgets/components/super_layout/slot_implementation.dart';
import 'package:super_container_layout/widgets/components/super_layout/super_layout.dart';
import 'package:super_container_layout/widgets/components/super_separator.dart';
import 'package:super_container_layout/widgets/components/super_tab.dart';
import 'package:super_container_layout/widgets/components/super_tree_view.dart';
import 'package:super_container_layout/widgets/components/super_value.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_surface.dart';

void initRegistry(Registry registry) {

  registry.registerComponent(
    'panString',
    RegisteredComponent.composable(
      label: 'panString',
      isAvailable: (context) {
        return true;
      },
      instanceBuilder: (_, id) => EditableSurface(
        id: id,
        label: 'WBYiTwqr2a',
        menuType: 'Card',
        style: const ContainerStyle(color: Color(0xFFC5A9F5)),
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
                  mode: SuperValueMode.input,
                  label: 'Description',
                  minLines: 4,
                  maxLines: 4,
                  field: const SuperTextFieldConfig(
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
                  field: const SuperTextFieldConfig(
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
                  field: const SuperTextFieldConfig(
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
                  field: const SuperTextFieldConfig(
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
                  field: const SuperTextFieldConfig(
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

  registry.registerComponent(
    'ZMackpyOIZ',
    RegisteredComponent(
      label: 'ZMackpyOIZ',
      isAvailable: (context) {
        return true;
      },
      instanceBuilder: (_, id) => SuperLayout(
        id: id,
        label: 'ZMackpyOIZ',
        behaviours: [
          ComponentBehavior(
            id: 'global-node-properties-size',
            trigger: BehaviorTrigger.binding,
            action: ZoneSizeBindingAction(
              zone: SuperLayoutZone.east,
              binding: const JsonTextBinding(
                repositoryId: '0123456789abcdef0123456789abcdef',
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
              ),
              slots: [
                BuilderSlot(
                  id: 'KlSbddMArN',
                  label: 'KlSbddMArN',
                  builder: (_) => const SuperAction(
                    id: 'KlSbddMArN',
                    config: SuperActionConfig(
                      kind: SuperActionKind.textAndIcon,
                      variant: SuperActionVariant.text,
                      label: 'Structure',
                      icon: 'grid_view',
                    ),
                  ),
                ),
                BuilderSlot(
                  id: 'I511oCPeBH',
                  label: 'I511oCPeBH',
                  builder: (_) => const SuperAction(
                    id: 'I511oCPeBH',
                    config: SuperActionConfig(
                      kind: SuperActionKind.textAndIcon,
                      variant: SuperActionVariant.text,
                      label: 'Info',
                      icon: 'info',
                    ),
                  ),
                ),
                BuilderSlot(
                  id: 'YM2KFsXQQz',
                  label: 'YM2KFsXQQz',
                  builder: (_) => const SuperAction(
                    id: 'YM2KFsXQQz',
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
                          repositoryId: '0123456789abcdef0123456789abcdef',
                          path: 'source',
                        ),
                        errorBinding: JsonTextBinding(
                          repositoryId: '0123456789abcdef0123456789abcdef',
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
            builder: (_) => SuperTreeView(
              id: 'explorer-tree',
              slots: [
                BuilderSlot(
                  id: 'input-header',
                  label: 'input-header',
                  builder: (_) => SuperLayout(
                    id: 'input-header',
                    label: 'input-header',
                    config: const SuperLayoutConfig(
                      zoneAxes: {SuperLayoutZone.center: Axis.horizontal},
                      zoneFlows: {
                        SuperLayoutZone.center: ZoneFlowConfig(
                          expandSlots: false,
                        ),
                      },
                      slotSizeConstraints: {
                        'tree-node-separator': SlotSizeConstraints(
                          fitContent: false,
                        ),
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
                                'container': SuperIndicatorConfig(
                                  icon: 'folder',
                                ),
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
                          config: SuperSeparatorConfig(
                            kind: SuperSeparatorKind.spacer,
                          ),
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
                BuilderSlot(
                  id: 'input-data',
                  label: 'input-data',
                  builder: (_) => SuperLayout(
                    id: 'input-data',
                    label: 'input-data',
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
                        label: 'tree-node-title',
                        builder: (_) => const SuperValue(
                          id: 'tree-node-title',
                          config: SuperValueConfig(
                            mode: SuperValueMode.input,
                            placeholder: 'title',
                            binding: JsonTextBinding(
                              repositoryId: '0123456789abcdef0123456789abcdef',
                              path: 'nodes[?].title',
                            ),
                            field: const SuperTextFieldConfig(
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
                binding: const JsonTextBinding(
                  repositoryId: '0123456789abcdef0123456789abcdef',
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
          BuilderSlot(
            id: 'global-node-properties',
            label: 'global-node-properties',
            builder: (context) => SuperTab(
              id: 'global-node-properties',
              label: 'global-node-properties',
              config: SuperTabConfig(
                indicatorKind: SuperTabIndicatorKind.box,
                indicatorRadius: 27.610471204188492,
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
                  'content:tab-validator': [
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
                          .component('panString')
                          .builder(context),
                ),
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
                      field: const SuperTextFieldConfig(
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
                      field: const SuperTextFieldConfig(
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
                      field: const SuperTextFieldConfig(
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
                      field: const SuperTextFieldConfig(
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
                      field: const SuperTextFieldConfig(
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
                      field: const SuperTextFieldConfig(
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
                      field: const SuperTextFieldConfig(
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
                      field: const SuperTextFieldConfig(
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
                      field: const SuperTextFieldConfig(
                        variant: TextFieldVariant.outlined,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Générateur de code Dart dédié à `Card` / [EditableSurface] (`ContainerStyle` + `NativeComponentConfig`).
library;

import '../../../models/native_component_config.dart';
import '../../../theme/container_style.dart';
import '../dart_code_generator.dart';

/// Classe de génération de code Dart dédiée à `Card` / [EditableSurface] (`ContainerStyle` + `NativeComponentConfig`).
class SuperCardDartGenerator extends ComponentDartGenerator {
  const SuperCardDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final style = context.appearance.styles[id] ?? const ContainerStyle();
    final native = context.appearance.tryComponent<NativeComponentConfig>(id);
    final behaviors = context.appearance.behaviorsFor(id);

    final childIds = <String>[
      if (native != null)
        for (final regionIds in native.placements.values) ...regionIds,
    ];
    final childId = childIds.firstOrNull;
    final childWidget = childId == null
        ? null
        : context.generateComponentWidget(
            childId,
            slotType: native?.slotTypes[childId],
            label: native?.slotLabels[childId],
            indent: indent + 2,
          );

    final args = <String, String>{
      'id': context.formatInstanceId(id),
      'label': context.formatString(label ?? 'Card'),
      'menuType': context.formatString('Card'),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (style != const ContainerStyle())
        'style': context.formatContainerStyle(
          style,
          indent: indent + 2,
          includeConst: context.canContainerStyleBeConst(style),
        ),
      'child': ?childWidget,
    };

    return context.formatCall(
      'EditableSurface',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }
}

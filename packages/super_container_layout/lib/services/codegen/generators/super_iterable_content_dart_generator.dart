/// Générateur de code Dart dédié à [IterableContent].
library;

import '../../../models/super_layout_config.dart';
import '../../../theme/container_style.dart';
import '../dart_code_generator.dart';
import 'super_layout_dart_generator.dart';

/// Classe de génération de code Dart dédiée à [IterableContent].
class SuperIterableContentDartGenerator extends ComponentDartGenerator {
  const SuperIterableContentDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<SuperLayoutConfig>(id) ??
        const SuperLayoutConfig();
    final style = context.appearance.styles[id] ?? const ContainerStyle();
    final behaviors = context.appearance.behaviorsFor(id);

    final placedIds = <String>[
      for (final zoneIds in config.placements.values) ...zoneIds,
    ];
    final slotEntries = <String>[
      for (final slotId in placedIds)
        context.generateBuilderSlot(
          slotId,
          slotType: config.slotTypes[slotId],
          label: config.slotLabels[slotId],
          preferredSize: config.slotPreferredSizes[slotId],
          indent: indent + 4,
        ),
    ];

    final args = <String, String>{
      'id': context.formatInstanceId(id),
      if (label != null && label != 'Iterable Content')
        'label': context.formatString(label),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (config != const SuperLayoutConfig())
        'config': SuperLayoutDartGenerator.formatConfig(
          context,
          config,
          indent: indent + 2,
          includeConst: true,
        ),
      if (style != const ContainerStyle())
        'style': context.formatContainerStyle(
          style,
          indent: indent + 2,
          includeConst: context.canContainerStyleBeConst(style),
        ),
      if (slotEntries.isNotEmpty)
        'slots': context.formatList(
          slotEntries,
          indent: indent + 2,
          forceMultiline: true,
        ),
    };

    return context.formatCall(
      'IterableContent',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }
}

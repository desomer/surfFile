/// Générateur de code Dart dédié au composant [SuperRenderer] (`SuperRendererConfig`).
library;

import '../../../models/super_renderer_config.dart';
import '../dart_code_generator.dart';

/// Classe de génération de code Dart dédiée à [SuperRenderer] (`SuperRendererConfig`).
class SuperRendererDartGenerator extends ComponentDartGenerator {
  const SuperRendererDartGenerator();

  @override
  String generateWidget(
    DartCodegenContext context, {
    required String id,
    String? label,
    int indent = 0,
  }) {
    final config =
        context.appearance.tryComponent<SuperRendererConfig>(id) ??
        const SuperRendererConfig();
    final behaviors = context.appearance.behaviorsFor(id);
    final isDynamic = context.isDynamicInstanceId(id);
    final canBeConst = !isDynamic && behaviors.isEmpty;

    final configArgs = <String, String>{
      if (config.source.isNotEmpty)
        'source': context.formatString(config.source),
      if (config.rootId != null) 'rootId': context.formatString(config.rootId!),
    };

    final args = <String, String>{
      'id': context.formatInstanceId(id),
      if (behaviors.isNotEmpty)
        'behaviours': context.formatBehaviors(behaviors, indent: indent + 2),
      if (configArgs.isNotEmpty)
        'config': context.formatCall(
          '${canBeConst ? '' : 'const '}SuperRendererConfig',
          const [],
          configArgs,
          indent: indent + 2,
        ),
    };

    return context.formatCall(
      '${canBeConst ? 'const ' : ''}SuperRenderer',
      const [],
      args,
      indent: indent,
      forceMultiline: true,
    );
  }
}

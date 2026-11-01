/// Enregistrement déclaratif des extensions de composants (`SuperChartExtension`,
/// `superContainerExtensions`) et extensions ergonomiques sur [Registry] et [Appearance].
library;

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import 'models/super_chart_config.dart';
import 'models/super_code_config.dart';
import 'widgets/components/super_chart.dart';
import 'widgets/components/super_code.dart';
import 'widgets/editing/addition/chart_add_configurator.dart';
import 'widgets/editing/addition/code_add_configurator.dart';

/// Extension enregistrant l'editeur de code et son assistant d'ajout.
class SuperCodeExtension extends SuperComponentExtension {
  const SuperCodeExtension();

  @override
  String get registryType => 'Code';

  @override
  void registerCodecs() => ensureSuperCodeCodecsRegistered();

  @override
  void register(
    Registry registry, {
    List<String> availableFontFamilies = Registry.defaultAvailableFontFamilies,
  }) {
    registerCodecs();
    registry.registry[registryType] = ComponentBuilderDynamic(
      menuIcon: Icons.code,
      label: 'Code / YAML / JavaScript',
      duplication: ComponentDuplicationContract.component,
      tags: const {'code', 'data'},
      addConfigurator: codeAddConfigurator,
      previewBuilder: (context) => const Center(child: Icon(Icons.code, size: 40)),
      dynamicBuilder: (ctx) => SuperCode(id: ctx.id),
    );
  }
}

/// Extension enregistrant le composant `SuperChart` (`Chart`) dans `super_container_layout`.
class SuperChartExtension extends SuperComponentExtension {
  const SuperChartExtension();

  @override
  String get registryType => 'Chart';

  @override
  void registerCodecs() => ensureSuperChartCodecsRegistered();

  @override
  void register(
    Registry registry, {
    List<String> availableFontFamilies = Registry.defaultAvailableFontFamilies,
  }) {
    registerCodecs();
    registry.registry[registryType] = ComponentBuilderDynamic(
      menuIcon: Icons.insert_chart_outlined,
      label: 'Chart / Graphique',
      duplication: ComponentDuplicationContract.component,
      tags: const {'chart', 'data'},
      addConfigurator: chartAddConfigurator,
      previewBuilder: buildSuperChartPreview,
      dynamicBuilder: (ctx) => SuperChart(id: ctx.id),
    );
  }
}

/// Construit l'aperçu miniature de `SuperChart` affiché dans l'assistant d'ajout.
Widget buildSuperChartPreview(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  Widget bar(double height, Color color) => Container(
    width: 14,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
    ),
  );
  return IgnorePointer(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          bar(20, colors.primary.withValues(alpha: 0.65)),
          bar(36, colors.primary),
          bar(28, colors.tertiary),
          bar(44, colors.primary),
          bar(32, colors.secondary),
        ],
      ),
    ),
  );
}

/// Liste complète des extensions de composants fournies par `super_container_extensions`.
const List<SuperComponentExtension> superContainerExtensions = [
  SuperChartExtension(),
  SuperCodeExtension(),
];

/// Enregistre tous les codecs JSON des composants du package `super_container_extensions`.
void ensureSuperContainerExtensionCodecsRegistered() {
  for (final extension in superContainerExtensions) {
    extension.registerCodecs();
  }
}

/// Méthodes d'extension sur [Registry] pour enregistrer et piloter les composants
/// du package `super_container_extensions`.
extension SuperContainerExtensionsRegistry on Registry {
  /// Enregistre uniquement SuperCode.
  void registerSuperCode() => registerExtension(const SuperCodeExtension());

  /// Controleur de configuration synchronise avec Appearance.
  ValueNotifier<SuperCodeConfig> codeController(
    String id, {
    SuperCodeConfig fallback = const SuperCodeConfig(),
  }) {
    ensureSuperCodeCodecsRegistered();
    return componentController<SuperCodeConfig>(id, fallback: fallback);
  }

  /// Enregistre toutes les extensions de `super_container_extensions` (dont `SuperChart`).
  void registerAllExtensions({
    List<String> availableFontFamilies = Registry.defaultAvailableFontFamilies,
  }) => registerExtensions(
    superContainerExtensions,
    availableFontFamilies: availableFontFamilies,
  );

  /// Enregistre uniquement l'extension `SuperChart` dans ce [Registry].
  void registerSuperChart({
    List<String> availableFontFamilies = Registry.defaultAvailableFontFamilies,
  }) => registerExtension(
    const SuperChartExtension(),
    availableFontFamilies: availableFontFamilies,
  );

  /// Retourne le `ValueNotifier<SuperChartConfig>` synchronisé avec [Appearance] pour [id].
  ValueNotifier<SuperChartConfig> chartController(
    String id, {
    SuperChartConfig fallback = const SuperChartConfig(),
  }) {
    ensureSuperChartCodecsRegistered();
    return componentController<SuperChartConfig>(id, fallback: fallback);
  }

}

/// Acces type aux reglages de SuperCode dans l'apparence.
extension SuperCodeAppearanceExtension on Appearance {
  /// Lit les reglages de Code.
  SuperCodeConfig codeComponent(
    String id, {
    SuperCodeConfig fallback = const SuperCodeConfig(),
  }) => component<SuperCodeConfig>(id, fallback: fallback);

  /// Retourne l'apparence avec les reglages de Code remplaces.
  Appearance withCodeComponent(String id, SuperCodeConfig value) =>
      withComponent(id, value);
}

/// Méthodes d'extension sur [Appearance] pour lire et écrire un [SuperChartConfig] typé.
extension SuperChartAppearanceExtension on Appearance {
  /// Lit la configuration [SuperChartConfig] associée à [id], ou retourne [fallback].
  SuperChartConfig chartComponent(
    String id, {
    SuperChartConfig fallback = const SuperChartConfig(),
  }) => component<SuperChartConfig>(id, fallback: fallback);

  /// Retourne une copie de cette [Appearance] avec la configuration [SuperChartConfig] [value] sous [id].
  Appearance withChartComponent(String id, SuperChartConfig value) =>
      withComponent(id, value);
}

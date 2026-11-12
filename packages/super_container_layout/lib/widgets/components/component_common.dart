/// Fonctions utilitaires et mixins partagés entre les composants d'exécution (`SuperValue`, `SuperAction`, `SuperIndicator`, `SuperSeparator`, collections).
///
/// Gère notamment :
/// - la résolution des styles de lignes de collection ;
/// - la résolution d'états ([SurfaceStateBinding], survol, [AutomaticState]) ;
/// - la construction des styles typographiques et des pieds de diagnostic d'erreurs ;
/// - les transactions d'édition ([EditorHistoryScope]) et l'extraction JSON ([JsonExtractableState]).
library;

import 'package:material_ui/material_ui.dart';

import '../../models/automatic_state.dart';
import '../../models/json_syntax.dart';
import '../../models/json_text_binding.dart';
import '../../services/repositories/json_list_scope.dart';
import '../../services/repositories/json_repository_store.dart';
import '../../services/states/surface_state_binding.dart';
import '../../super_app.dart';
import '../../theme/appearance.dart';
import '../../theme/container_fill.dart';
import '../../theme/container_style.dart';
import '../../theme/theme_color.dart';
import '../editing/dialogs/super_value_json_extract_dialog.dart';
import '../editing/history/editor_history.dart';
import '../editing/slots/editor_slot.dart';

/// Resolves the fallback [ContainerStyle] for an item/row in collection components.
ContainerStyle resolveRowStyleFallback(
  BuildContext context, {
  required SuperApp? app,
  required String componentId,
  required String rowId,
  required ContainerStyle fallback,
}) {
  if (app == null) return fallback;
  final appearanceStyles = AppearanceScope.controllerOf(context)?.value.styles;
  return app.registry?.containerStyleById[rowId]?.value ??
      app.registry?.containerStyleById[componentId]?.value ??
      appearanceStyles?[rowId] ??
      appearanceStyles?[componentId] ??
      fallback;
}

/// Resolves the [ValueNotifier] controlling the item/row [ContainerStyle].
ValueNotifier<ContainerStyle> resolveRowStyleController(
  BuildContext context, {
  required SuperApp? app,
  required String componentId,
  required String rowId,
  required ContainerStyle fallback,
  required ValueNotifier<ContainerStyle> localStyle,
}) {
  final resolvedFallback = resolveRowStyleFallback(
    context,
    app: app,
    componentId: componentId,
    rowId: rowId,
    fallback: fallback,
  );
  return app?.registry?.styleController(rowId, fallback: resolvedFallback) ??
      localStyle;
}

/// Resolves both the state-resolved style (preserving outer margin) and the
/// margin-free effective indicator style for hover/selection row overlays.
({ContainerStyle resolved, ContainerStyle effective}) resolveRowIndicatorStyle(
  BuildContext context,
  ContainerStyle currentRowStyle, {
  required bool isHover,
  double? fallbackRadius,
  bool fallbackSelectedBorder = false,
}) {
  if (isHover) {
    final accent = AppearanceScope.of(context).accent;
    final hoverBase = currentRowStyle.hoverBase(accent).resolveTheme(context);
    final defaultColor = (hoverBase ?? Theme.of(context).colorScheme.onSurface)
        .withValues(alpha: 0.08);
    final hasCustomHover = currentRowStyle.states?.hover?.isEmpty == false;
    final resolved = hasCustomHover
        ? currentRowStyle.states!.resolve(currentRowStyle, isHovered: true)
        : currentRowStyle.copyWith(clearStates: true);
    final hasFill = resolved.fill.type != FillType.solid || resolved.hasImage;
    final effective = resolved.copyWith(
      clearStates: true,
      margin: 0,
      marginInsets: null,
      hoverEffect: false,
      radius: fallbackRadius != null && resolved.radius <= 0
          ? fallbackRadius
          : resolved.radius,
      color: hasCustomHover
          ? (resolved.color ?? (hasFill ? null : defaultColor))
          : defaultColor,
    );
    return (resolved: resolved, effective: effective);
  }

  final primary = Theme.of(context).colorScheme.primary;
  final defaultColor = primary.withValues(alpha: 0.14);
  final hasCustomSelected = currentRowStyle.states?.hasSelected == true;
  final resolved = hasCustomSelected
      ? currentRowStyle.states!.resolve(currentRowStyle, isSelected: true)
      : currentRowStyle.copyWith(clearStates: true);
  final hasFill = resolved.fill.type != FillType.solid || resolved.hasImage;
  final effective = resolved.copyWith(
    clearStates: true,
    margin: 0,
    marginInsets: null,
    hoverEffect: false,
    radius: fallbackRadius != null && resolved.radius <= 0
        ? fallbackRadius
        : resolved.radius,
    color: hasCustomSelected
        ? (resolved.color ?? (hasFill ? null : defaultColor))
        : defaultColor,
    borderWidth: fallbackSelectedBorder && !hasCustomSelected
        ? 1
        : resolved.borderWidth,
    borderColor: fallbackSelectedBorder && !hasCustomSelected
        ? primary.withValues(alpha: 0.6)
        : resolved.borderColor,
  );
  return (resolved: resolved, effective: effective);
}

/// Mixin gérant l'observation de [SurfaceStateBinding], l'état de survol souris
/// et les états automatiques ([AutomaticState]) pour un composant.
mixin ComponentStateResolutionMixin<W extends StatefulWidget> on State<W> {
  /// Lecteur de l'attribut JSON définissant l'état métier nommé actif.
  SurfaceStateBinding? stateReader;

  /// Indique si le pointeur survole actuellement le composant.
  bool isComponentHovered = false;

  /// Message d'erreur éventuel issu de la résolution des états.
  String? stateError;

  /// Ensemble des états automatiques actifs lors de la dernière résolution.
  Set<AutomaticState> automaticActiveStates = {};

  /// Planifie une reconstruction après changement d'état ou de focus.
  void onComponentStateChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Synchronise le [SurfaceStateBinding] avec [binding], [scope] et [store].
  void syncSurfaceStateReader(
    JsonTextBinding? binding,
    JsonListScope? scope,
    JsonRepositoryStore? store,
  ) {
    if (binding == null) {
      stateReader?.removeListener(onComponentStateChanged);
      stateReader?.dispose();
      stateReader = null;
    } else if (stateReader == null) {
      stateReader = SurfaceStateBinding(
        store: store,
        binding: binding,
        scope: scope,
        placeholder: scope?.placeholder ?? false,
      )..addListener(onComponentStateChanged);
    } else {
      stateReader!.reconfigure(
        store: store,
        binding: binding,
        scope: scope,
        placeholder: scope?.placeholder ?? false,
      );
    }
    stateError = stateReader?.error;
  }

  /// Enveloppe [child] dans une [MouseRegion] mettant à jour [isComponentHovered].
  Widget wrapWithComponentHoverRegion(Widget child) => MouseRegion(
    opaque: false,
    onEnter: (_) {
      if (!isComponentHovered) setState(() => isComponentHovered = true);
    },
    onExit: (_) {
      if (isComponentHovered) setState(() => isComponentHovered = false);
    },
    child: child,
  );

  /// Libère le [SurfaceStateBinding] actif.
  void disposeComponentStateReader() {
    stateReader?.removeListener(onComponentStateChanged);
    stateReader?.dispose();
    stateReader = null;
  }
}

/// Exécute l'ouverture d'une boîte de dialogue d'édition de composant au sein
/// d'une transaction [EditorHistoryScope] et applique le résultat sur [configuration].
Future<C?> runComponentEditorTransaction<C>({
  required BuildContext context,
  required ValueNotifier<C> configuration,
  required Future<C?> Function(C initial) showEditor,
  ValueChanged<C>? onConfigChanged,
  VoidCallback? onFinally,
}) async {
  final initial = configuration.value;
  final history = EditorHistoryScope.controllerOf(context);
  history?.beginTransaction();
  C? result;
  try {
    result = await showEditor(initial);
    if (result != null && context.mounted && result != configuration.value) {
      configuration.value = result;
      onConfigChanged?.call(result);
    }
    return result;
  } finally {
    onFinally?.call();
    if (result != null) {
      history?.commitTransaction();
    } else {
      history?.cancelTransaction();
    }
  }
}

/// Indique si [fontFamily] est absente de [availableFontFamilies].
bool isComponentFontMissing(
  String? fontFamily,
  List<String> availableFontFamilies,
) => fontFamily != null && !availableFontFamilies.contains(fontFamily);

/// Construit le [TextStyle] effectif d'un composant à partir du [DefaultTextStyle].
TextStyle buildComponentTextStyle(
  BuildContext context, {
  required String? fontFamily,
  required bool missingFont,
  double? fontSize,
  FontWeight? fontWeight,
  bool? italic,
  Color? color,
  double? lineHeight,
  double? letterSpacing,
}) {
  final base = DefaultTextStyle.of(context).style;
  return base.copyWith(
    fontFamily: missingFont ? null : fontFamily,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontStyle: italic == null
        ? null
        : italic
        ? FontStyle.italic
        : FontStyle.normal,
    color: color,
    height: lineHeight,
    letterSpacing: letterSpacing,
  );
}

/// Construit les widgets [Text] d'erreur d'état et de liaisons de propriétés (`propertyBindings`).
List<Widget> buildComponentDiagnosticErrors<P extends Enum>(
  BuildContext context, {
  required String componentPrefix,
  required String componentId,
  required String? stateError,
  required Map<P, String> propertyBindingErrors,
}) {
  if (stateError == null && propertyBindingErrors.isEmpty) return const [];
  final errorColor = Theme.of(context).colorScheme.error;
  return [
    if (stateError != null)
      Text(
        stateError,
        key: ValueKey('$componentPrefix-state-error-$componentId'),
        style: TextStyle(color: errorColor),
      ),
    for (final entry in propertyBindingErrors.entries)
      Text(
        'Liaison ${entry.key.name} : ${entry.value}',
        key: ValueKey(
          '$componentPrefix-property-binding-error-${entry.key.name}-$componentId',
        ),
        style: TextStyle(color: errorColor),
      ),
  ];
}

/// Résout la clé JSON préférée pour l'extraction d'un composant ([JsonExtractableState]).
String resolveExtractableComponentKey({
  required EditorSlotState? surface,
  required String fallbackId,
  required String configLabel,
  Set<String> ignoredLabels = const {},
  bool preferConfigLabelFirst = false,
}) {
  if (surface != null && surface.mounted && surface.hasCustomLabel) {
    final renamed = surface.titleLabel.trim();
    if (renamed.isNotEmpty) return renamed;
  }
  final trimmedConfigLabel = configLabel.trim();
  if (preferConfigLabelFirst &&
      trimmedConfigLabel.isNotEmpty &&
      !ignoredLabels.contains(trimmedConfigLabel)) {
    return trimmedConfigLabel;
  }
  final instanceLabel = surface?.componentLabel?.label.trim();
  if (instanceLabel != null &&
      instanceLabel.isNotEmpty &&
      !ignoredLabels.contains(instanceLabel)) {
    return instanceLabel;
  }
  if (!preferConfigLabelFirst &&
      trimmedConfigLabel.isNotEmpty &&
      !ignoredLabels.contains(trimmedConfigLabel)) {
    return trimmedConfigLabel;
  }
  return fallbackId;
}

/// Construit les [ExtractablePropertyOption] typographiques communes.
List<ExtractablePropertyOption> buildTypographyExtractableOptions({
  required String? fontFamily,
  required Color? color,
  String colorLabel = 'Couleur',
  Color? iconColor,
  Color? backgroundColor,
  Color? borderColor,
  required double? fontSize,
  double? iconSize,
  required FontWeight? fontWeight,
  required bool? italic,
  required TextAlign textAlign,
  required TextAlign defaultTextAlign,
  required bool hasTextAlignBinding,
  double? radius,
  double? borderWidth,
  double? elevation,
}) => [
  if (fontFamily != null && fontFamily.trim().isNotEmpty)
    ExtractablePropertyOption(
      id: 'fontFamily',
      label: 'Police',
      value: fontFamily,
    ),
  if (color != null)
    ExtractablePropertyOption(
      id: 'color',
      label: colorLabel,
      value: JsonColor.toHex(color),
    ),
  if (iconColor != null)
    ExtractablePropertyOption(
      id: 'iconColor',
      label: 'Couleur de l’icône',
      value: JsonColor.toHex(iconColor),
    ),
  if (backgroundColor != null)
    ExtractablePropertyOption(
      id: 'backgroundColor',
      label: 'Couleur de fond',
      value: JsonColor.toHex(backgroundColor),
    ),
  if (borderColor != null)
    ExtractablePropertyOption(
      id: 'borderColor',
      label: 'Couleur de bordure',
      value: JsonColor.toHex(borderColor),
    ),
  if (fontSize != null)
    ExtractablePropertyOption(
      id: 'fontSize',
      label: 'Taille de police',
      value: fontSize,
    ),
  if (iconSize != null)
    ExtractablePropertyOption(
      id: 'iconSize',
      label: 'Taille de l’icône',
      value: iconSize,
    ),
  if (fontWeight != null)
    ExtractablePropertyOption(
      id: 'fontWeight',
      label: 'Graisse',
      value: fontWeight.value,
    ),
  if (italic != null)
    ExtractablePropertyOption(id: 'italic', label: 'Italique', value: italic),
  if (textAlign != defaultTextAlign || hasTextAlignBinding)
    ExtractablePropertyOption(
      id: 'textAlign',
      label: 'Alignement',
      value: textAlign.name,
    ),
  if (radius != null)
    ExtractablePropertyOption(id: 'radius', label: 'Rayon', value: radius),
  if (borderWidth != null)
    ExtractablePropertyOption(
      id: 'borderWidth',
      label: 'Épaisseur de bordure',
      value: borderWidth,
    ),
  if (elevation != null)
    ExtractablePropertyOption(
      id: 'elevation',
      label: 'Élévation',
      value: elevation,
    ),
];

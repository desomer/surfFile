import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/theme/typed_appearance_scope.dart';
import 'package:super_container_layout/services/appearance_store.dart';

import '../services/appearance_store.dart' as app;
import 'surffile_appearance.dart';

/// Point d'entree SurfFile pour l'apparence et les preferences metier.
///
/// Le package gere le modele DefaultAppearance et son adaptation typee.
/// Ce scope lui fournit le codec SurfFile, complete le catalogue de styles
/// et de layouts, puis expose les preferences metier dans l'arbre de widgets.
class AppearanceScope extends StatefulWidget {
  const AppearanceScope({
    required this.controller,
    required this.child,
    this.preferences,
    super.key,
  });
  final ValueNotifier<DefaultAppearance> controller;
  final ValueNotifier<SurfFilePreferences>? preferences;
  final Widget child;

  /// Retourne le controleur du scope le plus proche, ou null sans scope.
  /// Le widget appelant depend du scope et suit ses notifications.
  static ValueNotifier<DefaultAppearance>? controllerOf(BuildContext context) =>
      TypedAppearanceScope.controllerOf<DefaultAppearance>(context);

  /// Sans scope, utilise les valeurs par defaut SurfFile.
  /// Un scope contenant un autre type de modele produit une StateError.
  static DefaultAppearance of(BuildContext context) {
    return TypedAppearanceScope.maybeOf<DefaultAppearance>(context) ??
        defaultSurfFileAppearance();
  }

  @override
  State<AppearanceScope> createState() => _AppearanceScopeState();
}

class _AppearanceScopeState extends State<AppearanceScope> {
  late ValueNotifier<SurfFilePreferences> _preferences;
  late app.SurfFileAppearanceCodec _codec;
  bool _ownsPreferences = false;
  @override
  void initState() {
    super.initState();
    _bindPreferences();
    _configure();
  }

  @override
  void didUpdateWidget(AppearanceScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.preferences != widget.preferences) {
      if (_ownsPreferences) _preferences.dispose();
      _bindPreferences();
      _configure();
    }
  }

  void _bindPreferences() {
    // Priorite : preferences explicites, puis celles du controleur persistant.
    // Seul le notifier de secours appartient au scope et sera dispose ici.
    final controller = widget.controller;
    final provided =
        widget.preferences ??
        (controller is app.PersistentAppearanceController
            ? controller.preferences
            : null);
    _ownsPreferences = provided == null;
    _preferences = provided ?? ValueNotifier(const SurfFilePreferences());
    _codec = app.SurfFileAppearanceCodec(preferences: _preferences);
  }

  void _configure() {
    // Complete les identifiants du catalogue manquants via le codec, sans
    // remplacer les styles et layouts deja personnalises par l'utilisateur.
    final value = widget.controller.value;
    if (!value.styles.keys.toSet().containsAll(
          SurfFileAppearanceDefaults.defaultStyles.keys,
        ) ||
        !value.layouts.keys.toSet().containsAll(
          SurfFileAppearanceDefaults.defaultLayouts.keys,
        )) {
      widget.controller.value = _codec.prepare(value);
    }
  }

  @override
  Widget build(BuildContext context) => SurfFilePreferencesScope(
    controller: _preferences,
    child: TypedAppearanceScope<DefaultAppearance>(
      controller: widget.controller,
      codec: _codec,
      child: widget.child,
    ),
  );
  @override
  void dispose() {
    if (_ownsPreferences) _preferences.dispose();
    super.dispose();
  }
}

/// Expose les preferences propres a SurfFile, hors du modele du package :
/// jauge disque et animation de navigation.
///
/// Les consommateurs sont reconstruits quand le notifier change.
class SurfFilePreferencesScope
    extends InheritedNotifier<ValueNotifier<SurfFilePreferences>> {
  const SurfFilePreferencesScope({
    required ValueNotifier<SurfFilePreferences> controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);
  static ValueNotifier<SurfFilePreferences>? maybeControllerOf(
    BuildContext context,
  ) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SurfFilePreferencesScope>();
    if (scope != null) return scope.notifier!;
    // Un dialogue peut etre hors du scope local. Les dialogues d'apparence
    // transmettent le codec, qui conserve le meme notifier de preferences.
    final codec = AppearanceServicesScope.codecOf(context);
    if (codec is app.SurfFileAppearanceCodec) return codec.preferences;
    return null;
  }

  /// Pour modifier les preferences : exige un controleur disponible.
  static ValueNotifier<SurfFilePreferences> controllerOf(
    BuildContext context,
  ) =>
      maybeControllerOf(context) ??
      (throw StateError('SurfFile preferences unavailable.'));

  /// Pour lire les preferences : utilise les valeurs par defaut sans scope.
  static SurfFilePreferences of(BuildContext context) =>
      maybeControllerOf(context)?.value ?? const SurfFilePreferences();
}

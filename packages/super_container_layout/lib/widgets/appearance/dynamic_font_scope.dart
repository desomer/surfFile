/// Portée réactive ([DynamicFontScope]) exposant un [DynamicFontManager] dans l'arbre de widgets.
///
/// Montée par [SuperApp] afin que les composants (`SuperValue`, `SuperAction`,
/// `SuperIndicator`, `SuperSeparator`), leurs éditeurs de typographie et la galerie
/// `DesignSystemCatalogDialog` se reconstruisent automatiquement dès qu'une police
/// Google Fonts termine son téléchargement ou son rechargement depuis le cache disque.
library;

import 'package:material_ui/material_ui.dart';

import '../../services/fonts/dynamic_font_manager.dart';

/// [InheritedNotifier] propageant un [DynamicFontManager] aux widgets descendants.
class DynamicFontScope extends InheritedNotifier<DynamicFontManager> {
  /// Crée une portée exposant [manager] à [child].
  const DynamicFontScope({
    required DynamicFontManager manager,
    required super.child,
    super.key,
  }) : super(notifier: manager);

  /// Retourne le [DynamicFontManager] le plus proche et abonne [context] à ses notifications.
  static DynamicFontManager? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DynamicFontScope>()?.notifier;

  /// Retourne le [DynamicFontManager] le plus proche sans abonner [context] aux reconstructions.
  static DynamicFontManager? readOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DynamicFontScope>()?.notifier;
}

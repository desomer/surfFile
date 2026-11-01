// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart' as legacy;
import 'package:material_ui/material_ui.dart' as modern;

/// [modern.MaterialUiCompatibilityBridge] only bridges Theme/Localizations,
/// it does not provide a legacy `Material` ancestor, so legacy widgets that
/// call `Material.of(context)` (InkWell splashes, etc.) still throw
/// "No Material widget found". This adds a transparent legacy [legacy.Material]
/// on top of the official bridge.
class MaterialCompatibilityBridge extends modern.StatelessWidget {
  const MaterialCompatibilityBridge({super.key, required this.child});

  final modern.Widget child;

  @override
  modern.Widget build(modern.BuildContext context) {
    return modern.MaterialUiCompatibilityBridge(
      child: legacy.Material(
        type: legacy.MaterialType.transparency,
        child: child,
      ),
    );
  }
}

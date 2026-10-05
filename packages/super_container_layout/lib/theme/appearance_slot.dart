import 'appearance.dart';
import 'container_style.dart';

enum AppearanceSurfaceRole { standard, applicationBackground }

/// Describes how an application-owned style is edited by a SuperContainer.
class AppearanceSlot {
  const AppearanceSlot(
    this.label, {
    required this.name,
    required this._read,
    required Appearance Function(Appearance, ContainerStyle) write,
    required this._reset,
    this.editShape = true,
    this.extendedLook = true,
    this.role = AppearanceSurfaceRole.standard,
    this._selectedVariant,
    this._standard,
    this._selectedVariantResolver,
  }) : _write = write;

  final String name;
  final String label;
  final bool editShape;
  final bool extendedLook;
  final AppearanceSurfaceRole role;
  final ContainerStyle Function(Appearance) _read;
  final Appearance Function(Appearance, ContainerStyle) _write;
  final Appearance Function(Appearance) _reset;
  final AppearanceSlot? _selectedVariant;
  final AppearanceSlot? _standard;
  final AppearanceSlot Function()? _selectedVariantResolver;

  AppearanceSlot? get selectedVariant =>
      _selectedVariant ?? _selectedVariantResolver?.call();

  AppearanceSlot get standard => _standard ?? this;

  bool get isSelectedVariant => standard != this;

  ContainerStyle read(Appearance appearance) => _read(appearance);

  Appearance write(Appearance appearance, ContainerStyle style) =>
      _write(appearance, style);

  Appearance reset(Appearance appearance) => _reset(appearance);
}

import 'package:flutter/foundation.dart' show immutable;

import 'native_component_config.dart';
import 'scaffold_page_config.dart';
import 'super_action_config.dart';
import 'super_chart_config.dart';
import 'super_layout_config.dart';
import 'super_list_view_config.dart';
import 'super_tab_config.dart';
import 'super_value_config.dart';

/// Declarative codec entry for a [ComponentConfig] subtype (GenUI CatalogItem pattern).
@immutable
class ComponentConfigCodec<T extends ComponentConfig> {
  const ComponentConfigCodec({
    required this.type,
    required this.fromJson,
  });

  final String type;
  final T Function(Map<String, Object?> json) fromJson;
}

/// Extensible catalog of [ComponentConfigCodec]s used to decode polymorphic
/// `Appearance.components` entries by their `'type'` discriminator.
abstract final class ComponentConfigCatalog {
  static final Map<String, ComponentConfigCodec<ComponentConfig>> _codecs = {
    'layout': ComponentConfigCodec<SuperLayoutConfig>(
      type: 'layout',
      fromJson: SuperLayoutConfig.fromJson,
    ),
    'native': ComponentConfigCodec<NativeComponentConfig>(
      type: 'native',
      fromJson: NativeComponentConfig.fromJson,
    ),
    'scaffold': ComponentConfigCodec<ScaffoldPageConfig>(
      type: 'scaffold',
      fromJson: ScaffoldPageConfig.fromJson,
    ),
    'value': ComponentConfigCodec<SuperValueConfig>(
      type: 'value',
      fromJson: SuperValueConfig.fromJson,
    ),
    'action': ComponentConfigCodec<SuperActionConfig>(
      type: 'action',
      fromJson: SuperActionConfig.fromJson,
    ),
    'list': ComponentConfigCodec<SuperListViewConfig>(
      type: 'list',
      fromJson: SuperListViewConfig.fromJson,
    ),
    'tab': ComponentConfigCodec<SuperTabConfig>(
      type: 'tab',
      fromJson: SuperTabConfig.fromJson,
    ),
    'chart': ComponentConfigCodec<SuperChartConfig>(
      type: 'chart',
      fromJson: SuperChartConfig.fromJson,
    ),
  };

  /// Registers or overrides a [ComponentConfigCodec] in the catalog.
  static void register<T extends ComponentConfig>(
    ComponentConfigCodec<T> codec,
  ) {
    final key = codec.type.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(codec.type, 'type', 'Must not be empty.');
    }
    _codecs[key] = codec;
  }

  /// Returns the registered codec for [type], or `null` if unknown.
  static ComponentConfigCodec<ComponentConfig>? of(String type) =>
      _codecs[type.trim()];

  /// All registered component config types.
  static Iterable<String> get registeredTypes => _codecs.keys;

  /// Decodes a polymorphic [ComponentConfig] from a JSON map containing `'type'`.
  static ComponentConfig decode(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid component configuration.');
    }
    final rawType = value['type'] ?? value['componentType'];
    if (rawType is! String || rawType.trim().isEmpty) {
      throw const FormatException('Missing component configuration "type".');
    }
    final codec = _codecs[rawType.trim()];
    if (codec == null) {
      throw FormatException(
        'Unknown component configuration type: "$rawType".',
      );
    }
    final payload = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String &&
            entry.key != 'type' &&
            entry.key != 'componentType')
          entry.key as String: entry.value,
    };
    return codec.fromJson(payload);
  }
}

/// Base class for all persisted component configurations stored in
/// `Appearance.components`.
@immutable
abstract class ComponentConfig {
  const ComponentConfig();

  /// Discriminator used by [toTypedJson] and [ComponentConfig.fromJson].
  String get componentType;

  /// Validates this configuration.
  void validate() {}

  /// Serializes the configuration fields without the [componentType] tag.
  Map<String, Object?> toJson();

  /// Compact serialization omitting default values.
  Map<String, Object?> toCompactJson() => toJson();

  /// Applies a partial JSON patch onto this configuration.
  ComponentConfig patchFromJson(Map<Object?, Object?> patch);

  /// Serializes this configuration with its `'type'` discriminator for
  /// `Appearance.components`.
  Map<String, Object?> toTypedJson() => {'type': componentType, ...toJson()};

  /// Compact serialization with its `'type'` discriminator.
  Map<String, Object?> toTypedCompactJson() => {
    'type': componentType,
    ...toCompactJson(),
  };

  /// Deserializes a polymorphic [ComponentConfig] using [ComponentConfigCatalog].
  factory ComponentConfig.fromJson(Object? value) =>
      ComponentConfigCatalog.decode(value);
}

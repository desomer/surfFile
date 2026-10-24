import 'package:flutter/foundation.dart' show immutable;

import 'native_component_config.dart';
import 'scaffold_page_config.dart';
import 'super_action_config.dart';
import 'super_list_view_config.dart';
import 'super_value_config.dart';

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

  /// Deserializes a polymorphic [ComponentConfig] from a JSON map containing
  /// a `'type'` (or `'componentType'`) discriminator.
  factory ComponentConfig.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid component configuration.');
    }
    final rawType = value['type'] ?? value['componentType'];
    if (rawType is! String || rawType.trim().isEmpty) {
      throw const FormatException('Missing component configuration "type".');
    }
    final payload = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String &&
            entry.key != 'type' &&
            entry.key != 'componentType')
          entry.key as String: entry.value,
    };
    return switch (rawType.trim()) {
      'native' => NativeComponentConfig.fromJson(payload),
      'scaffold' => ScaffoldPageConfig.fromJson(payload),
      'value' => SuperValueConfig.fromJson(payload),
      'action' => SuperActionConfig.fromJson(payload),
      'list' => SuperListViewConfig.fromJson(payload),
      _ => throw FormatException(
        'Unknown component configuration type: "$rawType".',
      ),
    };
  }
}

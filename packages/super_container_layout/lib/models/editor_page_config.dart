import 'package:flutter/foundation.dart';

/// A visually authored page with an identity independent of its route.
@immutable
class EditorPageConfig {
  EditorPageConfig({
    required this.id,
    required this.name,
    required this.path,
    Map<String, String> defaultParameters = const {},
  }) : defaultParameters = Map.unmodifiable(defaultParameters) {
    validate();
  }

  final String id;
  final String name;
  final String path;
  final Map<String, String> defaultParameters;

  /// Route syntax and parameter constraints are validated by the router.
  void validate() {
    if (id.trim().isEmpty ||
        name.trim().isEmpty ||
        path.trim().isEmpty ||
        !path.startsWith('/')) {
      throw ArgumentError(
        'Invalid editor page identity, name or absolute path.',
      );
    }
    if (defaultParameters.keys.any((key) => key.trim().isEmpty)) {
      throw ArgumentError('Editor page parameter names must not be empty.');
    }
  }

  EditorPageConfig copyWith({
    String? id,
    String? name,
    String? path,
    Map<String, String>? defaultParameters,
  }) => EditorPageConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    path: path ?? this.path,
    defaultParameters: defaultParameters ?? this.defaultParameters,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'defaultParameters': defaultParameters,
  };

  factory EditorPageConfig.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.keys.any(
          (key) =>
              !const {'id', 'name', 'path', 'defaultParameters'}.contains(key),
        ) ||
        value['id'] is! String ||
        value['name'] is! String ||
        value['path'] is! String) {
      throw const FormatException('Invalid editor page configuration.');
    }
    final parameters = value.containsKey('defaultParameters')
        ? value['defaultParameters']
        : const <String, String>{};
    if (parameters is! Map ||
        parameters.entries.any(
          (entry) => entry.key is! String || entry.value is! String,
        )) {
      throw const FormatException('Invalid editor page default parameters.');
    }
    try {
      return EditorPageConfig(
        id: value['id'] as String,
        name: value['name'] as String,
        path: value['path'] as String,
        defaultParameters: Map<String, String>.from(parameters),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid editor page configuration: $error');
    }
  }
}

/// Ordered editor pages and their optional startup destination.
@immutable
class EditorPageCatalog {
  EditorPageCatalog({List<EditorPageConfig> pages = const [], this.homePageId})
    : pages = List.unmodifiable(pages) {
    validate();
  }

  const EditorPageCatalog.empty() : pages = const [], homePageId = null;

  final List<EditorPageConfig> pages;
  final String? homePageId;

  void validate() {
    final ids = <String>{};
    for (final page in pages) {
      page.validate();
      if (!ids.add(page.id)) {
        throw ArgumentError('Duplicate editor page ID "${page.id}".');
      }
    }
    if (homePageId != null && !ids.contains(homePageId)) {
      throw ArgumentError('The editor home page must exist in the catalog.');
    }
  }

  EditorPageCatalog copyWith({
    List<EditorPageConfig>? pages,
    String? homePageId,
    bool clearHomePage = false,
  }) => EditorPageCatalog(
    pages: pages ?? this.pages,
    homePageId: clearHomePage ? null : homePageId ?? this.homePageId,
  );

  Map<String, Object?> toJson() => {
    'pages': [for (final page in pages) page.toJson()],
    'homePageId': homePageId,
  };

  factory EditorPageCatalog.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.keys.any((key) => !const {'pages', 'homePageId'}.contains(key)) ||
        value['pages'] is! List ||
        (value['homePageId'] != null && value['homePageId'] is! String)) {
      throw const FormatException('Invalid editor page catalog.');
    }
    try {
      return EditorPageCatalog(
        pages: [
          for (final page in value['pages'] as List)
            EditorPageConfig.fromJson(page),
        ],
        homePageId: value['homePageId'] as String?,
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid editor page catalog: $error');
    }
  }
}

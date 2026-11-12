/// Modèle de style et thèmes de coloration syntaxique pour SuperCode et CodeEditor.
library;

import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_highlight/themes/dracula.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/night-owl.dart';
import 'package:flutter_highlight/themes/nord.dart';
import 'package:flutter_highlight/themes/solarized-dark.dart';
import 'package:flutter_highlight/themes/solarized-light.dart';
import 'package:flutter_highlight/themes/tomorrow-night.dart';
import 'package:flutter_highlight/themes/vs.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:material_ui/material_ui.dart';

/// Thèmes de coloration syntaxique disponibles pour l'éditeur SuperCode.
enum SuperCodeTheme {
  monokaiSublime('Monokai Sublime', isDark: true),
  atomOneDark('Atom One Dark', isDark: true),
  atomOneLight('Atom One Light', isDark: false),
  github('GitHub', isDark: false),
  vs2015('VS 2015', isDark: true),
  vs('Visual Studio', isDark: false),
  dracula('Dracula', isDark: true),
  nord('Nord', isDark: true),
  solarizedDark('Solarized Dark', isDark: true),
  solarizedLight('Solarized Light', isDark: false),
  nightOwl('Night Owl', isDark: true),
  tomorrowNight('Tomorrow Night', isDark: true);

  const SuperCodeTheme(this.label, {required this.isDark});

  /// Libellé affiché dans les sélecteurs de style.
  final String label;

  /// Indique si le thème présente un contraste sombre.
  final bool isDark;

  /// Styles de coloration syntaxique pour `CodeTheme` / `flutter_highlight`.
  Map<String, TextStyle> get highlightTheme => switch (this) {
    SuperCodeTheme.monokaiSublime => monokaiSublimeTheme,
    SuperCodeTheme.atomOneDark => atomOneDarkTheme,
    SuperCodeTheme.atomOneLight => atomOneLightTheme,
    SuperCodeTheme.github => githubTheme,
    SuperCodeTheme.vs2015 => vs2015Theme,
    SuperCodeTheme.vs => vsTheme,
    SuperCodeTheme.dracula => draculaTheme,
    SuperCodeTheme.nord => nordTheme,
    SuperCodeTheme.solarizedDark => solarizedDarkTheme,
    SuperCodeTheme.solarizedLight => solarizedLightTheme,
    SuperCodeTheme.nightOwl => nightOwlTheme,
    SuperCodeTheme.tomorrowNight => tomorrowNightTheme,
  };
}

/// Options visuelles et typographiques configurables pour `SuperCode`.
@immutable
class SuperCodeStyle {
  const SuperCodeStyle({
    this.theme = SuperCodeTheme.monokaiSublime,
    this.fontSize = 14.0,
    this.lineHeight = 1.5,
    this.fontFamily,
    this.showLineNumbers = true,
    this.showFoldingHandles = true,
    this.transparentBackground = false,
  });

  /// Thème de coloration syntaxique.
  final SuperCodeTheme theme;

  /// Taille de la police en pixels (entre 8.0 et 48.0).
  final double fontSize;

  /// Hauteur de ligne relative (entre 1.0 et 3.0).
  final double lineHeight;

  /// Nom de la police de caractères (ex. 'Fira Code', 'Consolas').
  final String? fontFamily;

  /// Affiche ou masque les numéros de ligne dans la gouttière.
  final bool showLineNumbers;

  /// Affiche ou masque les poignées de pliage dans la gouttière.
  final bool showFoldingHandles;

  /// Rend l'arrière-plan transparent pour laisser transparaître le `ContainerStyle` parent.
  final bool transparentBackground;

  /// Taille minimale autorisée pour la police.
  static const minFontSize = 8.0;

  /// Taille maximale autorisée pour la police.
  static const maxFontSize = 48.0;

  /// Hauteur de ligne minimale autorisée.
  static const minLineHeight = 1.0;

  /// Hauteur de ligne maximale autorisée.
  static const maxLineHeight = 3.0;

  /// Valide les invariants de style.
  void validate() {
    if (fontSize < minFontSize || fontSize > maxFontSize) {
      throw const FormatException(
        'La taille de police du code doit être comprise entre 8 et 48.',
      );
    }
    if (lineHeight < minLineHeight || lineHeight > maxLineHeight) {
      throw const FormatException(
        'La hauteur de ligne du code doit être comprise entre 1.0 et 3.0.',
      );
    }
    if (fontFamily != null && fontFamily!.trim().isEmpty) {
      throw const FormatException('Le nom de police ne peut pas être vide.');
    }
  }

  /// Retourne une copie modifiée des réglages de style.
  SuperCodeStyle copyWith({
    SuperCodeTheme? theme,
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    bool clearFontFamily = false,
    bool? showLineNumbers,
    bool? showFoldingHandles,
    bool? transparentBackground,
  }) => SuperCodeStyle(
    theme: theme ?? this.theme,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    fontFamily: clearFontFamily ? null : fontFamily ?? this.fontFamily,
    showLineNumbers: showLineNumbers ?? this.showLineNumbers,
    showFoldingHandles: showFoldingHandles ?? this.showFoldingHandles,
    transparentBackground:
        transparentBackground ?? this.transparentBackground,
  );

  /// Sérialise l'ensemble des options de style.
  Map<String, Object?> toJson() {
    validate();
    return {
      'theme': theme.name,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      if (fontFamily != null) 'fontFamily': fontFamily,
      'showLineNumbers': showLineNumbers,
      'showFoldingHandles': showFoldingHandles,
      'transparentBackground': transparentBackground,
    };
  }

  /// Sérialisation compacte omettant les valeurs par défaut.
  Map<String, Object?> toCompactJson() {
    validate();
    return {
      if (theme != SuperCodeTheme.monokaiSublime) 'theme': theme.name,
      if (fontSize != 14.0) 'fontSize': fontSize,
      if (lineHeight != 1.5) 'lineHeight': lineHeight,
      if (fontFamily != null) 'fontFamily': fontFamily,
      if (!showLineNumbers) 'showLineNumbers': false,
      if (!showFoldingHandles) 'showFoldingHandles': false,
      if (transparentBackground) 'transparentBackground': true,
    };
  }

  /// Décode un style JSON validé.
  factory SuperCodeStyle.fromJson(Map<String, Object?> json) {
    for (final key in json.keys) {
      if (!const {
        'theme',
        'fontSize',
        'lineHeight',
        'fontFamily',
        'showLineNumbers',
        'showFoldingHandles',
        'transparentBackground',
      }.contains(key)) {
        throw FormatException('Propriété de style SuperCode inconnue : $key.');
      }
    }
    final rawTheme = json['theme'] ?? 'monokaiSublime';
    final theme =
        SuperCodeTheme.values.where((item) => item.name == rawTheme).firstOrNull;
    if (theme == null) {
      throw const FormatException('Thème SuperCode invalide.');
    }
    final rawFontSize = json['fontSize'];
    final fontSize =
        rawFontSize == null ? 14.0 : (rawFontSize as num).toDouble();
    final rawLineHeight = json['lineHeight'];
    final lineHeight =
        rawLineHeight == null ? 1.5 : (rawLineHeight as num).toDouble();
    final fontFamily = json['fontFamily'] as String?;
    final showLineNumbers = (json['showLineNumbers'] as bool?) ?? true;
    final showFoldingHandles = (json['showFoldingHandles'] as bool?) ?? true;
    final transparentBackground =
        (json['transparentBackground'] as bool?) ?? false;

    final result = SuperCodeStyle(
      theme: theme,
      fontSize: fontSize,
      lineHeight: lineHeight,
      fontFamily: fontFamily,
      showLineNumbers: showLineNumbers,
      showFoldingHandles: showFoldingHandles,
      transparentBackground: transparentBackground,
    );
    result.validate();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is SuperCodeStyle &&
      theme == other.theme &&
      fontSize == other.fontSize &&
      lineHeight == other.lineHeight &&
      fontFamily == other.fontFamily &&
      showLineNumbers == other.showLineNumbers &&
      showFoldingHandles == other.showFoldingHandles &&
      transparentBackground == other.transparentBackground;

  @override
  int get hashCode => Object.hash(
    theme,
    fontSize,
    lineHeight,
    fontFamily,
    showLineNumbers,
    showFoldingHandles,
    transparentBackground,
  );
}

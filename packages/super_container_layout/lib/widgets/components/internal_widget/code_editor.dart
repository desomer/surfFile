/// Éditeur de code avec coloration syntaxique (`flutter_code_editor`) et numéros de ligne ([CodeEditor]).
library;

import 'package:flutter/material.dart' as flutter_material;
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
// ignore: implementation_imports
import 'package:flutter_code_editor/src/code_field/actions/tab.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    as flutter_localizations;
import 'package:highlight/highlight_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../../models/super_code_style.dart';
import 'treeview/tree_view.dart';
import 'widget_error_banner.dart';
import 'widget_long_json_viewer.dart';
import 'yaml_browser.dart';

/// Widget d'édition de code coloré configurable via [CodeEditorConfig].
class CodeEditor extends StatefulWidget {
  const CodeEditor({super.key, required this.config, this.onSelection});
  final CodeEditorConfig config;
  final Function? onSelection;

  @override
  State<CodeEditor> createState() => CodeEditorState();
}

/// Action d'indentation de la sélection via la touche Tab.
class TabKeyIndentSelection extends Action<TabKeyIntent> {
  final CodeController controller;
  final bool Function() isReadOnly;

  TabKeyIndentSelection({required this.controller, required this.isReadOnly});

  @override
  Object? invoke(TabKeyIntent intent) {
    if (!isReadOnly()) controller.indentSelection();
    return null;
  }
}

/// Action de collage depuis le presse-papiers dans le [CodeController].
class PasteKeyAction extends Action<PasteTextIntent> {
  final CodeController controller;
  final String type;
  final bool Function() isReadOnly;

  PasteKeyAction({
    required this.controller,
    required this.type,
    required this.isReadOnly,
  });

  @override
  Object? invoke(PasteTextIntent intent) {
    if (isReadOnly()) return null;
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      if (!isReadOnly() && data?.text != null) {
        final text = data!.text!;
        final sel = controller.selection;
        controller.value = controller.value.replaced(sel, text);
      }
    });
    return null;
  }
}

/// Action de copie (et couper) de la sélection courante dans le presse-papiers.
class CopyKeyAction extends Action<CopySelectionTextIntent> {
  final CodeController controller;
  final CodeEditorState state;
  String type = '';

  CopyKeyAction({
    required this.controller,
    required this.state,
    required this.type,
  });

  @override
  Object? invoke(CopySelectionTextIntent intent) {
    if (intent.collapseSelection && state.widget.config.readOnly) return null;
    final sel = controller.selection;
    if (!sel.isCollapsed) {
      final text = controller.fullText.substring(sel.start, sel.end);

      Clipboard.setData(ClipboardData(text: text));
      if (intent.collapseSelection) {
        controller.value = controller.value.replaced(sel, '');
      }
    }
    return null;
  }
}

/// État interne du widget [CodeEditor].
class CodeEditorState extends State<CodeEditor> {
  late CodeController controller;
  late FocusNode focusNode;
  final _largeText = TextEditingController();
  String _lastText = '';

  int lastRow = -1;
  TextStyle get textStyle {
    final style = widget.config.style;
    return TextStyle(
      height: style.lineHeight,
      fontFamily: style.fontFamily,
      fontSize: style.fontSize,
    );
  }

  @override
  void initState() {
    controller = CodeController(language: widget.config.mode);
    focusNode = FocusNode();

    controller.actions[TabKeyIntent] = TabKeyIndentSelection(
      controller: controller,
      isReadOnly: () => widget.config.readOnly,
    );
    controller.actions[PasteTextIntent] = PasteKeyAction(
      controller: controller,
      type: widget.config.type,
      isReadOnly: () => widget.config.readOnly,
    );
    controller.actions[CopySelectionTextIntent] = CopyKeyAction(
      controller: controller,
      state: this,
      type: widget.config.type,
    );

    controller.popupController.enabled = false;
    controller.addListener(() {
      final text = controller.fullText;
      if (text == _lastText) return;
      _lastText = text;
      if (dispatch) widget.config.onChange(text, widget.config);
    });
    super.initState();
  }

  @override
  void didUpdateWidget(CodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.language != widget.config.mode) {
      dispatch = false;
      try {
        controller.language = widget.config.mode;
      } finally {
        dispatch = true;
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    _largeText.dispose();
    focusNode.dispose();
    super.dispose();
  }

  bool dispatch = true;
  int _lastTap = 0;

  void _handleTap() {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - _lastTap < 250) {
      _onDoubleClick();
    }

    _lastTap = now;
  }

  void _onDoubleClick() {
    onSelectedCode();
  }

  /// Positionne le curseur et la sélection sur la ligne [lineNumber].
  void scrollToLine(int lineNumber) {
    lineNumber++;
    focusNode.requestFocus();
    final text = controller.fullText;
    if (text.isEmpty) {
      controller.setCursor(0);
      return;
    }

    final lines = text.split('\n');
    final targetLine = lineNumber.clamp(1, lines.length);

    int charIndex = 0;
    for (int i = 0; i < targetLine - 1; i++) {
      charIndex += lines[i].length + 1;
    }
    int startLine = charIndex;
    int endLine = charIndex + lines[targetLine - 1].length;

    final idx = lines[targetLine - 1].indexOf(':');
    if (idx > 0) {
      charIndex += idx;
    }

    charIndex = charIndex.clamp(0, controller.fullText.length);

    controller.setCursor(charIndex);
    Future.delayed(const Duration(milliseconds: 100)).then((_) {
      controller.selection = TextSelection(
        baseOffset: startLine,
        extentOffset: endLine,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    widget.config.codeEditorState = this;

    var aText = widget.config.getText();
    if (aText == null) {
      return const SizedBox.shrink();
    }

    final style = widget.config.style;
    final rawThemeStyles = style.theme.highlightTheme;
    final themeStyles = style.transparentBackground
        ? {
            ...rawThemeStyles,
            if (rawThemeStyles.containsKey('root'))
              'root': rawThemeStyles['root']!.copyWith(
                backgroundColor: flutter_material.Colors.transparent,
              ),
          }
        : rawThemeStyles;
    final effectiveBackground = style.transparentBackground
        ? flutter_material.Colors.transparent
        : (rawThemeStyles['root']?.backgroundColor ??
            const flutter_material.Color(0xff23241f));

    if (!widget.config.useLargeTextViewer && aText.length > 50000) {
      if (_largeText.text != aText) {
        _largeText.value = TextEditingValue(
          text: aText,
          selection: TextSelection.collapsed(offset: aText.length),
        );
      }
      return Column(
        children: [
          const Text('Document volumineux : coloration syntaxique desactivee.'),
          Expanded(
            child: _withFlutterMaterial(
              flutter_material.TextField(
                controller: _largeText,
                readOnly: widget.config.readOnly,
                onChanged: (text) => widget.config.onChange(text, widget.config),
                expands: true,
                minLines: null,
                maxLines: null,
                style: textStyle.copyWith(color: themeStyles['root']?.color),
                decoration: const flutter_material.InputDecoration(
                  border: flutter_material.InputBorder.none,
                ),
              ),
              color: effectiveBackground,
            ),
          ),
          WidgetErrorBanner(error: widget.config.notifError),
        ],
      );
    }

    if (aText != controller.fullText) {
      dispatch = false;
      try {
        controller.fullText = aText;
      } finally {
        dispatch = true;
      }
    }

    if (widget.config.useLargeTextViewer && aText.length > 50000) {
      return Column(
        children: [
          Expanded(child: LongJsonViewerSelectableColored(json: aText)),
          WidgetErrorBanner(error: widget.config.notifError),
        ],
      );
    }

    final gutterWidth = style.showLineNumbers
        ? (style.fontSize * 4.2).clamp(40.0, 90.0)
        : (style.showFoldingHandles ? 24.0 : 0.0);
    Widget code = CodeField(
      gutterStyle: GutterStyle(
        textStyle: textStyle,
        margin: 0,
        width: gutterWidth,
        showErrors: true,
        showFoldingHandles: style.showFoldingHandles,
        showLineNumbers: style.showLineNumbers,
      ),
      controller: controller,
      textStyle: textStyle,
      focusNode: focusNode,
      readOnly: widget.config.readOnly,
      expands: true,
      maxLines: null,
      background: effectiveBackground,
    );

    return Column(
      children: [
        Expanded(
          child: CodeTheme(
            data: CodeThemeData(styles: themeStyles),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _handleTap(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SizedBox(
                    height: constraints.maxHeight,
                    width: constraints.maxWidth,
                    child: _withFlutterMaterial(code, color: effectiveBackground),
                  );
                },
              ),
            ),
          ),
        ),
        WidgetErrorBanner(error: widget.config.notifError),
      ],
    );
  }

  Widget _withFlutterMaterial(Widget child, {flutter_material.Color? color}) {
    if (Localizations.of<flutter_material.MaterialLocalizations>(
          context,
          flutter_material.MaterialLocalizations,
        ) == null) {
      child = Localizations.override(
        context: context,
        delegates: flutter_localizations.GlobalMaterialLocalizations.delegates,
        child: child,
      );
    }
    final style = widget.config.style;
    final fallbackColor = style.transparentBackground
        ? flutter_material.Colors.transparent
        : (style.theme.highlightTheme['root']?.backgroundColor ??
            const flutter_material.Color(0xff23241f));
    final resolvedColor = color ?? fallbackColor;
    return flutter_material.Material(
      type: resolvedColor == flutter_material.Colors.transparent
          ? flutter_material.MaterialType.transparency
          : flutter_material.MaterialType.canvas,
      color: resolvedColor,
      child: child,
    );
  }

  /// Défile jusqu'au chemin JSON/YAML [aPath].
  void scrollToJsonPath(String aPath) {
    YamlDoc docYaml = YamlDoc();
    docYaml.load(controller.fullText);
    docYaml.doAnalyse();

    for (var line in docYaml.listYamlLine) {
      YamlLine? l = line;
      String path = '';
      while (l != null) {
        if (path.isNotEmpty) {
          path = '.$path';
        }
        path = '${l.name}$path';
        l = l.parent;
      }
      path = 'root.$path';
      if (path == aPath) {
        scrollToLine(line.index);
        return;
      }
    }
  }

  /// Notifie [CodeEditor.onSelection] du chemin correspondant à la position du curseur.
  void onSelectedCode() {
    if (widget.onSelection == null) return;

    var curPos = controller.selection.baseOffset;
    YamlDoc docYaml = YamlDoc();
    docYaml.load(controller.fullText);
    docYaml.doAnalyse();

    String path = '';

    for (var line in docYaml.listYamlLine) {
      if (curPos > line.idxCharStart && curPos < line.idxCharStop) {
        YamlLine? l = line;
        int i = 0;
        while (l != null && i < 20) {
          i++;
          if (path.isNotEmpty) {
            path = '.$path';
          }
          path = '${l.name}$path';
          l = l.parent;
        }
        path = 'root.$path';
        widget.onSelection!(path);
        break;
      }
    }
  }

  /// Retourne la liste des chemins YAML sélectionnés.
  List<String> getSelectedListPath() {
    if (widget.onSelection == null) return [];

    var curPosStart = controller.selection.start;
    var curPosEnd = controller.selection.end + 1;
    YamlDoc docYaml = YamlDoc();
    docYaml.load(controller.fullText);
    docYaml.doAnalyse();

    List<String> listPath = [];

    for (var line in docYaml.listYamlLine) {
      if (line.idxCharStart >= curPosStart && line.idxCharStop <= curPosEnd) {
        YamlLine? l = line;
        int i = 0;
        String path = '';
        while (l != null && i < 20) {
          i++;
          if (path.isNotEmpty) {
            path = '>$path';
          }
          path = '${l.name}$path';
          l = l.parent;
        }
        path = 'root>$path';
        listPath.add(path);
      }
    }
    return listPath;
  }
}

/// Configuration d'exécution du widget [CodeEditor].
class CodeEditorConfig {
  CodeEditorConfig({
    required this.mode,
    required this.getText,
    required this.onChange,
    required this.notifError,
    this.readOnly = false,
    this.useLargeTextViewer = true,
    this.validateYamlKey,
    required this.type,
    this.style = const SuperCodeStyle(),
  });
  Mode mode;
  late Function onChange;
  late Function getText;
  Function? validateYamlKey;
  late ValueNotifier<String> notifError;
  bool readOnly;
  bool useLargeTextViewer;
  String type;
  SuperCodeStyle style;

  CodeEditorState? codeEditorState;
  State? treeJsonState;

  /// Force le rafraîchissement de l'éditeur de code.
  void repaintCode() {
    if (codeEditorState?.mounted ?? false) {
      // ignore: invalid_use_of_protected_member
      codeEditorState?.setState(() {});
    }
  }

  /// Force le rafraîchissement de l'arbre JSON associé.
  void repaintTree() {
    if (treeJsonState?.mounted ?? false) {
      // ignore: invalid_use_of_protected_member
      if (treeJsonState is TreeViewState) {
        (treeJsonState as TreeViewState).repaint();
      } else {
        // ignore: invalid_use_of_protected_member
        treeJsonState?.setState(() {});
      }
    }
  }
}

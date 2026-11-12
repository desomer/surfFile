/// Analyseur et navigateur de lignes YAML pour la synchronisation de position avec [CodeEditor].
library;

import 'package:material_ui/material_ui.dart';
import 'package:yaml/yaml.dart';

import 'code_editor.dart';

/// Modèle analysé d'un document YAML en lignes hiérarchisées.
class YamlDoc {
  List<YamlLine> listRoot = [];
  List<YamlLine> listYamlLine = [];
  List<String>? indexBy;
  Map<String, YamlLineIndex> index = {};
  Map<String, YamlLineIndex> refs = {};
  late YamlDocument docYaml;
  late String doc;

  /// Charge la chaîne YAML dans le document.
  void load(String aYaml) {
    if (aYaml.isNotEmpty && !aYaml.endsWith('\n')) {
      aYaml = '$aYaml\n';
    }
    doc = aYaml;
    docYaml = loadYamlDocument(aYaml);
  }

  /// Construit une liste de widgets représentant les lignes YAML colorées.
  List<Widget> doPrettyPrint() {
    List<Widget> listRows = [];
    for (var i = 0; i < listYamlLine.length; i++) {
      List<Widget> listWidget = [];
      var l = listYamlLine[i];
      if (l.name != null) {
        var withoutBlank = l.text.trimLeft();
        int nbLevel = l.text.indexOf(withoutBlank);
        if (nbLevel < 0) nbLevel = 0;
        StringBuffer sb = StringBuffer();
        for (var j = 0; j < nbLevel; j++) {
          sb.write(' ');
        }
        if (l.isItemArray) {
          sb.write('- ');
        }
        sb.write('${l.name} : ');
        listWidget.add(
          Text(
            sb.toString(),
            style: const TextStyle(color: Colors.pink, fontWeight: FontWeight.normal),
          ),
        );
        if (l.value != null && (l.value is! Map && l.value is! List)) {
          listWidget.add(
            Text(
              l.value!.toString(),
              style: TextStyle(
                color: Colors.yellow.shade400,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }
      } else {
        listWidget.add(Text(l.text));
      }
      listRows.add(Row(children: listWidget));
    }
    return listRows;
  }

  /// Analyse les nœuds et les positions des lignes du document YAML chargé.
  void doAnalyse() {
    var v = docYaml.contents;
    YamlMap val = v.value ?? YamlMap();
    var allLine = doc.split('\n');
    int i = 0;
    int nbChar = 0;
    for (var element in allLine) {
      int nbCharLine = element.length + 1;
      var yamlLine = YamlLine(index: i, endIndex: i, text: element);
      yamlLine.idxCharStart = nbChar;
      yamlLine.idxCharStop = nbChar + nbCharLine;
      listYamlLine.add(yamlLine);
      nbChar = nbChar + nbCharLine;
      i++;
    }

    _doAnalyseNode(0, val, [], -1, false);
  }

  /// Reconstruit le texte YAML complet à partir des lignes.
  String getDoc() {
    StringBuffer yaml = StringBuffer();
    var length2 = listYamlLine.length;
    for (var i = 0; i < length2; i++) {
      yaml.write(listYamlLine[i].text);
      if (i < length2 - 1) yaml.writeln();
    }
    return yaml.toString();
  }

  /// Ajoute une paire clé/valeur à la fin du document YAML.
  YamlLine addAtEnd(String key, dynamic value) {
    if (listYamlLine.length == 1 && listYamlLine.last.text.trim().isEmpty) {
      listYamlLine.removeLast();
    }

    StringBuffer nl = StringBuffer();
    nl.write('$key : $value');

    YamlLine newLine = YamlLine(
      index: listYamlLine.length,
      endIndex: listYamlLine.length,
      text: nl.toString(),
    );
    newLine.name = key;
    newLine.value = value;
    newLine.parent = null;
    newLine.level = 0;

    listYamlLine.insert(listYamlLine.length, newLine);
    return newLine;
  }

  /// Ajoute une ligne enfant sous [row].
  YamlLine addChild(YamlLine row, String key, dynamic value) {
    for (var i = 0; i < (row.child?.length ?? 0); i++) {
      var l = row.child![i];
      if (l.name == key) {
        return l;
      }
    }

    int newIdx = row.index;
    if (row.child != null) {
      newIdx = row.child!.last.endIndex;
    }

    int i = newIdx;
    if (i > 0) {
      var l = listYamlLine[i];
      var txt = l.text.trim();
      while ((txt.isEmpty || txt.startsWith('#')) && i > 0) {
        i--;
        l = listYamlLine[i];
        txt = l.text.trim();
      }
    }
    newIdx = i + 1;

    StringBuffer nl = _addValueWithTab(row, key, value);

    YamlLine newLine = YamlLine(
      index: newIdx,
      endIndex: newIdx,
      text: nl.toString(),
    );
    newLine.name = key;
    newLine.value = value;
    newLine.parent = row;
    newLine.level = row.level + 1;
    row.child ??= [];
    row.child!.add(newLine);
    listYamlLine.insert(newIdx, newLine);

    if (indexBy?.contains(key) ?? false) {
      addIndex(key, value, newLine);
    }

    for (var i = newIdx + 1; i < listYamlLine.length; i++) {
      listYamlLine[i].index++;
      listYamlLine[i].endIndex++;
    }
    row.endIndex++;
    while (row.parent != null) {
      row = row.parent!;
      row.endIndex++;
    }

    return newLine;
  }

  StringBuffer _addValueWithTab(YamlLine row, String key, dynamic value) {
    StringBuffer nl = StringBuffer();
    int nbLevel = (row.level + 1) * 3;
    if (row.child?.first != null) {
      var withoutBlank = row.child!.first.text.trimLeft();
      nbLevel = row.child!.first.text.indexOf(withoutBlank);
    }
    for (var i = 0; i < nbLevel; i++) {
      nl.write(' ');
    }
    nl.write('$key : $value');
    return nl;
  }

  int _doAnalyseNode(
    int level,
    YamlMap valYamlMap,
    List<String> path,
    int line,
    bool isItemArray,
  ) {
    var aPath = [...path];

    int searchIndex = valYamlMap.span.start.line - 0;
    if (searchIndex < 0) searchIndex = 0;
    var allLine = listYamlLine;
    for (var e in valYamlMap.entries) {
      dynamic v = e.value;
      if (v is YamlMap) {
        if (v.length == 1) {
          var vMap = v.values.first;
          if (vMap == null) {
            v = '{${v.keys.first}}';
          }
        }
      }

      if (v is YamlMap) {
        String k = e.key.toString();
        if (e.key is Map) {
          k = '{${e.key.keys.first.toString()}}';
        }

        path.add(k);
        int i = getIndexKey(searchIndex, valYamlMap, allLine, k);
        allLine[i].isItemArray = isItemArray;
        allLine[i].name = k;
        allLine[i].value = e.value;
        allLine[i].path = aPath;
        allLine[i].level = level;
        if (line > -1) {
          allLine[i].parent = allLine[line];
          allLine[line].child ??= [];
          allLine[line].child!.add(allLine[i]);
        } else {
          listRoot.add(allLine[i]);
        }
        searchIndex = _doAnalyseNode(level + 1, v, path, i, false);
        allLine[i].endIndex = searchIndex - 1;
        if (indexBy?.contains(k) ?? false) {
          addIndex(k, v, allLine[i]);
        }
        path.removeLast();
      } else if (v is List) {
        String k = e.key.toString();
        path.add(k);
        int i = getIndexKey(searchIndex, valYamlMap, allLine, k);
        allLine[i].name = k;
        allLine[i].isItemArray = isItemArray;
        allLine[i].value = e.value;
        allLine[i].path = aPath;
        allLine[i].level = level;
        if (line > -1) {
          allLine[i].parent = allLine[line];
          allLine[line].child ??= [];
          allLine[line].child!.add(allLine[i]);
        } else {
          listRoot.add(allLine[i]);
        }

        for (var item in v) {
          if (item is YamlMap) {
            searchIndex = _doAnalyseNode(level + 1, item, path, i, true);
            allLine[i].endIndex = searchIndex - 1;
            if (indexBy?.contains(k) ?? false) {
              addIndex(k, v, allLine[i]);
            }
          }
        }
        path.removeLast();
      } else {
        String k = e.key.toString();
        int i = getIndexKey(searchIndex, valYamlMap, allLine, k);
        searchIndex = i + 1;
        allLine[i].name = k;
        allLine[i].value = e.value;
        allLine[i].path = aPath;
        allLine[i].level = level;

        if (e.value is String && e.value.toString().startsWith('\$')) {
          var r = e.value.toString().substring(1);
          refs[r] ??= YamlLineIndex(key: k);
          refs[r]!.value[k] ??= [];
          refs[r]!.value[k]!.add(allLine[i]);
        }

        if (line > -1) {
          if (i != line) {
            allLine[i].parent = allLine[line];
          }
          allLine[line].child ??= [];
          allLine[line].child!.add(allLine[i]);
        } else {
          listRoot.add(allLine[i]);
        }
        if (indexBy?.contains(k) ?? false) {
          addIndex(k, v, allLine[i]);
        }
      }
    }
    return valYamlMap.span.end.line;
  }

  /// Trouve l'indice de ligne correspondant à la clé [k].
  int getIndexKey(
    int searchIndex,
    YamlMap val,
    List<YamlLine> allLine,
    String k,
  ) {
    for (var i = searchIndex; i < val.span.end.line + 1; i++) {
      var aLine = allLine[i].text;
      aLine = aLine.trimLeft();
      if (aLine.startsWith('-')) {
        aLine = aLine.substring(1).trimLeft();
      }
      if (aLine.startsWith(k)) {
        aLine = aLine.substring(k.length).trimLeft();
        if (aLine.startsWith(':')) {
          return i;
        }
      }
    }
    return -1;
  }

  /// Ajoute une entrée dans l'index par clé.
  void addIndex(String k, dynamic v, YamlLine line) {
    YamlLineIndex? ind = index[k];
    if (ind == null) {
      ind = YamlLineIndex(key: k);
      index[k] = ind;
    }
    if (v is YamlMap) {
      v = '\$';
    }
    List<YamlLine>? indVal = ind.value[v.toString()];
    indVal ??= ind.value[v.toString()] = [];
    indVal.add(line);
  }
}

/// Index des lignes YAML regroupées par valeur pour une clé donnée.
class YamlLineIndex {
  final String key;
  Map<String, List<YamlLine>> value = {};

  YamlLineIndex({required this.key});
}

/// Ligne analysée d'un document YAML.
class YamlLine {
  YamlLine({required this.index, required this.endIndex, required this.text});

  int index;
  int endIndex;
  int level = 0;
  bool isItemArray = false;
  List<String>? path;
  String text;
  String? type;
  String? name;
  dynamic value;
  YamlLine? parent;
  List<YamlLine>? child;
  int idxCharStart = 0;
  int idxCharStop = 0;
}

/// Gestionnaire d'analyse et de validation de clés YAML.
class ParseYamlManager {
  Map? mapYaml;
  Function? validateKey;

  /// Analyse la chaîne [yaml] et met à jour l'état d'erreur dans [config].
  bool doParseYaml(String yaml, CodeEditorConfig? config) {
    bool parseOk = false;
    try {
      var r = loadYaml(yaml);

      if (r == null && yaml.trim() == '') {
        mapYaml = {};
        parseOk = true;
        config?.notifError.value = '';
      } else if (r is Map) {
        mapYaml = r;
        parseOk = true;
        config?.notifError.value = '';

        if (validateKey != null) {
          browseNode(r);
        }
      } else {
        config?.notifError.value = 'no valid';
      }
    } catch (e) {
      config?.notifError.value = '$e';
    }
    return parseOk;
  }

  /// Parcourt récursivement les nœuds pour valider chaque clé.
  void browseNode(dynamic node) {
    if (node is Map) {
      node.forEach((key, value) {
        if (key is String) {
          validateKey?.call(key);
        }
        browseNode(value);
      });
    } else if (node is List) {
      for (var item in node) {
        browseNode(item);
      }
    }
  }
}

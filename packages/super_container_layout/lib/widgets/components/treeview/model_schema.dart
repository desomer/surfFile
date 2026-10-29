import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:super_container_layout/widgets/components/treeview/authorization_manager.dart';
import 'package:super_container_layout/widgets/components/treeview/browse_model.dart';
import 'package:super_container_layout/widgets/components/treeview/data_acces.dart';
import 'package:super_container_layout/widgets/components/treeview/data_event.dart';
import 'package:super_container_layout/widgets/components/treeview/json_browser.dart';
import 'package:super_container_layout/widgets/components/treeview/tree_view.dart';
import 'package:super_container_layout/widgets/components/treeview/widget_show_error.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

//int nbtesterror = -37;

class ModelVersion implements Comparable<ModelVersion> {
  ModelVersion({required this.id, required this.version, required this.data});

  String id;
  String version;
  Map<String, dynamic> data;

  @override
  int compareTo(ModelVersion other) {
    return -(int.parse(version).compareTo(int.parse(other.version)));
  }
}

//--------------------------------------------------------------------------
enum TypeModelBreadcrumb {
  businessmodel,
  component,
  request,
  env,
  domain;

  static String valString(TypeModelBreadcrumb? v) {
    if (v == null) return '';
    return ['Business models', 'Components', 'Requests & Responses'][v.index];
  }
}

typedef OnChange = void Function(dynamic histo);

class JsonComplexity {
  final int totalKeys;
  final int maxDepth;
  final int totalNodes;
  final int typeCount;

  JsonComplexity({
    required this.totalKeys,
    required this.maxDepth,
    required this.totalNodes,
    required this.typeCount,
  });

  /**On peut mesurer :
nombre de règles (type, format, pattern, enum)
nombre de combinateurs (anyOf, oneOf, allOf)
profondeur du schéma
nombre de références $ref

complexité = 
  (nombre_de_clés) 
+ (profondeur_max * 2) 
+ (nombre_de_types_différents * 3)
+ (nombre_de_combinateurs_schema * 5)

*/
}

class ModelSchemaQuality {
  double completude;
  double wordDuplicationNumber;
  int wordDuplication;
  double documentation;
  double complexity;
  List<String> recommandation = [];

  ModelSchemaQuality({
    required this.completude,
    required this.wordDuplication,
    required this.wordDuplicationNumber,
    required this.documentation,
    required this.complexity,
  });

  JsonComplexity computeJsonComplexity(Map<String, dynamic> json) {
    int totalKeys = 0;
    int maxDepth = 1;
    int totalNodes = 0;
    final Set<String> types = {};

    void explore(dynamic value, int depth) {
      maxDepth = depth > maxDepth ? depth : maxDepth;
      totalNodes++;

      if (value is Map) {
        totalKeys += value.length;
        types.add("object");

        value.forEach((key, val) {
          types.add(val.runtimeType.toString());
          explore(val, depth + 1);
        });
      } else if (value is List) {
        types.add("array");
        for (var item in value) {
          explore(item, depth + 1);
        }
      } else {
        types.add(value.runtimeType.toString());
      }
    }

    explore(json, 1);

    return JsonComplexity(
      totalKeys: totalKeys,
      maxDepth: maxDepth,
      totalNodes: totalNodes,
      typeCount: types.length,
    );
  }
}

class ModelSchema {
  ModelSchema({
    required this.category,
    required this.headerName,
    required this.id,
    required this.infoManager,
    required this.refDomain,
  });

  final String id;
  final ModelSchema? refDomain;

  int loadingTime = 0;

  final Category category; // pour la sauvegarde et certain traitement
  String headerName; // pour les export
  bool isLoadProp = false;

  NodeBrowser? lastBrowser;
  JsonBrowser? lastJsonBrowser;
  final InfoManager infoManager;

  String modelYaml = '';
  Map mapModelYaml = {};
  Map<String, dynamic> modelPropertiesByPath = {};
  final Map<String, NodeAttribut> modelPropExtended = {};

  ModelSchema? comparedModelSchema;
  ModelSchema? olderModelSchema;

  final List<ModelSchema> dependency = [];

  final List histories = [];
  bool withHistory = true;

  final Map<String, AttributInfo> mapInfoByTreePath = {};

  final Map<String, AttributInfo> mapInfoByJsonPath = {};
  final Map<String, List<AttributInfo>> mapInfoByName = {};
  final Map<String, AttributInfo> allAttributInfo = {};

  final List<AttributInfo> notUseAttributInfo = [];
  final List<AttributInfo> useAttributInfo = [];
  final Map<String, List<NodeAttribut>> nodeByMasterId = {};

  int lastNbNode = 0;
  bool first = true;
  bool isEmpty = false;
  bool autoSaveProperties = true;
  bool isReadOnlyModel = false;

  NodeAttribut? selectedAttr;

  AttributInfo? lastDeleteAttr;
  int lastDeleteEditorStartAt = 0;

  OnChange? onChange; // sur un changement du schema

  List<String> modelPath = [];
  TypeModelBreadcrumb? typeBreabcrumb;

  List<ModelVersion>? versions;
  ModelVersion? currentVersion;
  ModelVersion? olderVersion;

  String? namespace;

  bool? readOnlyApi;
  bool? isApi;
  bool isFile = false;

  ModelSchemaQuality? qualityInfo;

  Future<void> prepareChange() async {
    notUseAttributInfo.clear();
    mapInfoByName.clear();
    mapInfoByTreePath.clear();
    mapInfoByJsonPath.clear();
    allAttributInfo.clear();
    modelPropertiesByPath.clear();
    nodeByMasterId.clear();

    await bddStorage.doStoreSync();
    var rModel = loadYamlAndPropertiesSyncOrNot(cache: false);
    if (rModel is Future<ModelSchema>) {
      await rModel;
    }
  }

  NodeAttribut createExtend(AttributInfo info) {
    return NodeAttribut(
      parent: null,
      yamlNode: MapEntry('extended', 'extended'),
      info: info,
    );
  }

  NodeAttribut? getNodeFromAttributInfo(AttributInfo info) {
    var path = info.getMasterIDPath();
    if (path.isEmpty) path = info.getMasterID();
    return getNodeByMasterIdPath(path);
  }

  /// #doc  ou #example
  NodeAttribut getExtendedNode(String id) {
    NodeAttribut? exampleExtended = modelPropExtended[id];
    if (exampleExtended == null) {
      AttributInfo info = AttributInfo();
      info.masterID = id;
      info.path = id;
      info.action = 'R';
      info.properties = {};
      modelPropExtended[id] = NodeAttribut(
        parent: null,
        yamlNode: MapEntry('extended', 'extended'),
        info: info,
      );
      exampleExtended = modelPropExtended[id];
    }
    return exampleExtended!;
  }

  Future<void> addVersion() async {
    await bddStorage.prepareSaveModel(this);
    await bddStorage.doStoreSync();
    var versionNum = int.parse(versions!.first.version) + 1;
    ModelVersion version = ModelVersion(
      id: id,
      version: '$versionNum',
      data: {
        'state': 'D',
        'by': currentCompany.shortUserId,
        'versionTxt': '0.0.$versionNum',
      },
    );
    versions!.insert(0, version);
    currentVersion = version;
    await bddStorage.storeVersion(this, version);
    //String modelYaml = this.modelYaml;
    var modelProperties = [...useAttributInfo];
    var extend = {...modelPropExtended};
    clear();
    await bddStorage.duplicateVersion(
      this,
      version,
      modelYaml,
      modelProperties,
      extend,
    );
  }

  void setCurrentAttr(AttributInfo? attr) {
    if (attr == null) {
      selectedAttr = null;
      return;
    }
    attr.selected = true;
    selectedAttr = createExtend(attr);
  }

  List<AttributInfo>? getModelByRefName(String refName) {
    List<AttributInfo>? aModelByName;
    if (category == Category.api) {
      // aModelByName = currentCompany.listRequest.mapInfoByName[refName];
      // aModelByName ??= currentCompany.listComponent.mapInfoByName[refName];
      aModelByName ??= refDomain?.mapInfoByName[refName];
    } else {
      //aModelByName = currentCompany.listComponent.mapInfoByName[refName];
      aModelByName ??= refDomain?.mapInfoByName[refName];
      //aModelByName ??= currentCompany.listRequest.mapInfoByName[refName];
    }
    return aModelByName;
  }

  void clear() {
    isLoadProp = false;

    modelYaml = '';
    mapModelYaml = {};
    modelPropertiesByPath = {};
    modelPropExtended.clear();

    histories.clear();

    mapInfoByTreePath.clear();

    mapInfoByJsonPath.clear();
    mapInfoByName.clear();
    allAttributInfo.clear();

    notUseAttributInfo.clear();
    useAttributInfo.clear();
    nodeByMasterId.clear();

    lastNbNode = 0;
    first = true;
    isEmpty = false;
  }

  String getVersionId() => currentVersion?.version ?? '1';
  String getVersionText() => currentVersion?.data['versionTxt'] ?? '0.0.1';

  // void initBreadcrumb() {
  //   var version = currentCompany.currentModel!.getVersionText();
  //   stateModel.path = [
  //     TypeModelBreadcrumb.valString(typeBreabcrumb!),
  //     ...modelPath,
  //     version,
  //     "draft",
  //   ];
  //   // ignore: invalid_use_of_protected_member
  //   stateModel.keyBreadcrumb.currentState?.setState(() {});
  // }

  // void initEventListener(CodeEditorConfig textConfig) {
  //   var idEvent = '$namespace/$id';
  //   bddStorage.doEventListner[idEvent] = OnEvent(
  //     id: idEvent,
  //     onPatch: (patch) {
  //       print('receive on $idEvent event $patch');
  //       if (patch['typeEvent'] == 'PROP') {
  //         bddStorage.dispatchChangeProperties(
  //           this,
  //           patch,
  //           textConfig,
  //           patch['payload']['version'],
  //         );
  //       } else if (patch['typeEvent'] == 'YAML') {
  //         if (getVersionId() == patch['version']) {
  //           var ret = bddStorage.dispatchChangeYaml(
  //             id: idEvent,
  //             patch: patch,
  //             value: modelYaml,
  //             version: patch['version'],
  //           );
  //           if (ret != null) modelYaml = ret;
  //           doChangeAndRepaintYaml(textConfig, false, 'event');
  //         }
  //       }
  //     },
  //   );
  // }

  // void changeSelected(NodeAttribut attr) {
  //   var path = attr.info.path;
  //   if (lastBrowser?.selectedPath == null ||
  //       !lastBrowser!.selectedPath!.contains(path)) {
  //     lastBrowser?.selectedPath ??= {};
  //     lastBrowser?.selectedPath!.add(path);
  //   } else if (lastBrowser?.selectedPath != null) {
  //     lastBrowser?.selectedPath!.remove(path);
  //   }
  // }

  bool onDeleteAttr(ModelSchema model, AttributInfo attr) {
    var sel = currentYamlTree?.getTextSelection();
    //print(sel);
    if (sel?.isCollapsed ?? false) {
      lastDeleteAttr = attr;
      lastDeleteEditorStartAt = sel!.start;
    }
    return true;
  }

  void addHistory(
    NodeAttribut node,
    String path,
    ChangeOpe ope,
    dynamic propChangeValue,
    dynamic value, {
    String? master,
  }) {
    node.info.action = 'U';
    String? uuid;
    if (!withHistory || !autoSaveProperties) return;

    if (histories.isNotEmpty) {
      var last = histories.last;
      if (last?['ope'] == ope.name && last?['path'] == path) {
        propChangeValue = last?['from'];
        var h = histories.removeLast();
        uuid = h?['uuid'];
      }
      // if (ope==ChangeOpe.clear && last?['ope'] == ChangeOpe.set.name && last?['path'] == path) {
      //   propChangeValue = last?['from'];
      //   histories.removeLast();
      // }
    }

    var getMdValue = _getMdValue(value);

    var histo = {
      'node': node, // pour le glossary
      'ope': ope.name,
      'path': path,
      'from': _getMdValue(propChangeValue),
      'to': getMdValue,
      'date': DateTime.now().toIso8601String(),
      'by': currentCompany.shortUserId,
      'uuid': uuid ?? Uuid().v4(),
      'master': ?master,
    };
    if (getMdValue is String && getMdValue.length > 100) {
      histo['toReal'] = value;
    }

    histories.add(histo);
    bddStorage.saveHistory(this, histo);

    Future.delayed(Duration(milliseconds: 100)).then((value) {
      // attend que le browse soit terminer
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChange?.call(histo);
      });
    });
  }

  dynamic _getMdValue(dynamic v) {
    var string = v.toString();
    if (string.contains('\n')) {
      string = string.replaceAll('\n', ';');
      if (string.length > 100) {
        string = '${string.substring(0, 100)}...';
      }
      return string;
    }
    return v;
  }

  final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  Widget getRowHistory(
    Map ahistory,
    bool path,
    bool from,
    bool to,
    String? ope,
  ) {
    String strDateTimeISO = ahistory['date'];
    DateTime dateTime = DateTime.parse(strDateTimeISO);

    String formattedDate = dateFormat.format(
      dateTime,
    ); // You can format the date here if needed
    return Row(
      mainAxisSize: MainAxisSize.max,
      spacing: 10,
      children: [
        SizedBox(width: 200, child: Text('at $formattedDate')),
        if (path)
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
              child: Text('${ahistory['path']}'),
            ),
          ),
        if (ope != null)
          SizedBox(
            width: 60,
            child: Container(
              decoration: BoxDecoration(
                color: ope == 'SET'
                    ? Colors.green
                    : ope == 'REMOVE'
                    ? Colors.red
                    : ope == 'PATH' || ope == 'RENAME'
                    ? Colors.orange
                    : Colors.blueGrey,
                //border: Border.all(color: Colors.blueGrey),
              ),
              child: Text(
                ope,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        // if (from && to)
        //   SizedBox(
        //     //decoration: BoxDecoration(color: Colors.grey),
        //     width: 40,
        //     child: Text('from'),
        //   ),
        if (from)
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
              child: Text('${ahistory['from']}'),
            ),
          ),
        if (to && from)
          Container(
            decoration: BoxDecoration(color: Colors.grey),
            width: 40,
            child: Center(child: Text('TO')),
          ),
        if (to)
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
              child: Text('${ahistory['to']}'),
            ),
          ),
        SizedBox(width: 300, child: Text('by ${ahistory['by']}')),
      ],
    );
  }

  List<Widget> getHistoryInfo() {
    List<Widget> ret = [];
    int i = 0;
    List removeHisto = [];
    for (var h in histories) {
      var ope = h['ope'];
      dynamic from = h['from'];
      if (ope == ChangeOpe.change.name) {
        if (from == null || from.toString() == '') {
          ret.add(getRowHistory(h, true, false, true, 'SET'));
          // ret.add(
          //   Text(
          //     '* ${h['path']}   **SET**  ${h['to']}        *BY ${h['by']} **AT** ${h['date']}*',
          //   ),
          // );
        } else {
          bool add = true;
          if (i > 0) {
            var last = histories[i - 1];
            if (last['path'] == h['path'] &&
                last['ope'] == h['ope'] &&
                last['from'] == h['to']) {
              // revient à la meme valeur
              add = false;
            }
          }
          if (i < histories.length - 1) {
            var next = histories[i + 1];
            if (next['path'] == h['path'] &&
                next['ope'] == h['ope'] &&
                next['to'] == h['from'] &&
                h['toReal'] == null) {
              // revient à la meme valeur
              add = false;
            }
          }

          if (add && (from != h['to'] || h['toReal'] != null)) {
            ret.add(
              getRowHistory(h, true, true, true, "CHANGE"),
              // Text(
              //   '* ${h['path']}   **FROM**  $from  **TO**  ${h['to']}       *BY ${h['by']} **AT** ${h['date']}*',
              // ),
            );
          } else {
            removeHisto.add(h);
          }
        }
      } else if (ope == ChangeOpe.clear.name) {
        ret.add(
          getRowHistory(h, true, true, false, 'CLEAR'),
          // Text(
          //   '* ${h['path']}   **CLEAR**  $from        *BY ${h['by']} **AT** ${h['date']}*',
          // ),
        );
      } else if (ope == ChangeOpe.path.name || ope == ChangeOpe.rename.name) {
        if (from != h['to']) {
          ret.add(
            getRowHistory(h, false, true, true, ope.toString().toUpperCase()),
          );
        } else {
          removeHisto.add(h);
        }
      } else if (ope == ChangeOpe.move.name) {
        if (from != h['to']) {
          ret.add(
            getRowHistory(h, true, true, true, ope.toString().toUpperCase()),
          );
        } else {
          removeHisto.add(h);
        }
      } else {
        // add et remove
        bool add = true;
        String masterID = h['path'].toString();
        if (ope == ChangeOpe.remove.name) {
          // recherche d'un move
          for (var j = i; j < histories.length; j++) {
            var o = histories[j];
            var opeOlder = o['ope'];
            if (opeOlder == ChangeOpe.move.name) {
              String oldmasterID = o['master'].toString();
              if (masterID == oldmasterID) {
                add = false;
                break;
              }
            }
          }
        }
        if (add) {
          ret.add(
            getRowHistory(h, false, true, false, ope.toString().toUpperCase()),
            // Text(
            //   '* **${ope.toString().toUpperCase()}  ${h['from']}**     *BY ${h['by']} **AT** ${h['date']}*',
            // ),
          );
        } else {
          removeHisto.add(h);
        }
      }
      i++;
    }

    if (removeHisto.isNotEmpty) {
      for (var element in removeHisto) {
        histories.remove(element);
      }
      return getHistoryInfo();
    }

    return ret;
  }

  String getHistory({required bool toMarkdown}) {
    StringBuffer ret = StringBuffer();
    if (toMarkdown) {
      ret.writeln('## Change log\n version ${getVersionText()}\n');
    }
    int i = 0;
    List removeHisto = [];
    for (var h in histories) {
      var ope = h['ope'];
      dynamic from = h['from'];
      if (ope == ChangeOpe.change.name) {
        if (from == null || from.toString() == '') {
          if (toMarkdown) {
            ret.writeln(
              '* ${h['path']}   **SET**  ${h['to']}        *BY ${h['by']} **AT** ${h['date']}*',
            );
          }
        } else {
          bool add = true;
          if (i > 0) {
            var last = histories[i - 1];
            if (last['path'] == h['path'] &&
                last['ope'] == h['ope'] &&
                last['from'] == h['to']) {
              // revient à la meme valeur
              add = false;
            }
          }
          if (i < histories.length - 1) {
            var next = histories[i + 1];
            if (next['path'] == h['path'] &&
                next['ope'] == h['ope'] &&
                next['to'] == h['from'] &&
                h['toReal'] == null) {
              // revient à la meme valeur
              add = false;
            }
          }

          if (add && (from != h['to'] || h['toReal'] != null)) {
            if (toMarkdown) {
              ret.writeln(
                '* ${h['path']}   **FROM**  $from  **TO**  ${h['to']}       *BY ${h['by']} **AT** ${h['date']}*',
              );
            }
          } else {
            removeHisto.add(h);
          }
        }
      } else if (ope == ChangeOpe.clear.name) {
        if (toMarkdown) {
          ret.writeln(
            '* ${h['path']}   **CLEAR**  $from        *BY ${h['by']} **AT** ${h['date']}*',
          );
        }
      } else if (ope == ChangeOpe.path.name || ope == ChangeOpe.rename.name) {
        if (from != h['to']) {
          if (toMarkdown) {
            ret.writeln(
              '* **${ope.toString().toUpperCase()} FROM**  $from  **TO**  ${h['to']}       *BY ${h['by']} **AT** ${h['date']}*',
            );
          }
        } else {
          removeHisto.add(h);
        }
      } else if (ope == ChangeOpe.move.name) {
        if (from != h['to']) {
          if (toMarkdown) {
            ret.writeln(
              '* ${h['path']}  **${ope.toString().toUpperCase()} FROM**  $from  **TO**  ${h['to']}        *BY ${h['by']} **AT** ${h['date']}*',
            );
          }
        } else {
          removeHisto.add(h);
        }
      } else {
        // add et remove
        bool add = true;
        String masterID = h['path'].toString();
        if (ope == ChangeOpe.remove.name) {
          // recherche d'un move
          for (var j = i; j < histories.length; j++) {
            var o = histories[j];
            var opeOlder = o['ope'];
            if (opeOlder == ChangeOpe.move.name) {
              String oldmasterID = o['master'].toString();
              if (masterID == oldmasterID) {
                add = false;
                break;
              }
            }
          }
        }
        if (add) {
          if (toMarkdown) {
            ret.writeln(
              '* **${ope.toString().toUpperCase()}  ${h['from']}**     *BY ${h['by']} **AT** ${h['date']}*',
            );
          }
        } else {
          removeHisto.add(h);
        }
      }
      i++;
    }
    if (removeHisto.isNotEmpty) {
      for (var element in removeHisto) {
        histories.remove(element);
      }
      return getHistory(toMarkdown: toMarkdown);
    }

    return ret.toString();
  }

  dynamic getItemSync(int delay) {
    return bddStorage.getItemSync(
      model: this,
      id: id,
      delay: delay,
      version: currentVersion,
    );
  }

  // void reorgModelPropertiesPath(List<TreeNode<NodeAttribut>> all) {
  //   if (!first) {
  //     //print("************* reorg & purge properties ****************");
  //     modelProperties.clear();
  //     for (var element in all) {
  //       if (element.data!.info.isInitByRef == false) {
  //         modelProperties[element.data!.info.path] =
  //             element.data!.info.properties;
  //       } else {
  //         //print("is attr on ref ${element.data!.info.path}");
  //       }
  //     }
  //   }
  // }

  void loadSubSchema(dynamic path, ModelSchema source) {
    try {
      mapModelYaml = source.mapModelYaml[path];
    } catch (e) {
      print(e);
    }
    modelPropertiesByPath = {};
    String pa = 'root>$path>';
    for (var element in source.modelPropertiesByPath.entries) {
      if (element.key.startsWith(pa)) {
        var p = element.key.substring(pa.length);
        modelPropertiesByPath['root>$p'] = element.value;
      }
    }
    isLoadProp = true;
  }

  /// charge les informations
  ///  [cache] avec cache mémoire
  ///  [withProperties] pour les graph
  Future<ModelSchema> loadYamlAndProperties({
    required bool cache,
    required bool withProperties,
    String? ifEmpty,
    bool withOlderVersion = false,
  }) async {
    try {
      loadingTime = DateTime.now().millisecondsSinceEpoch;

      await _initVersion(withOlderVersion);

      dynamic savedYamlModel = bddStorage.getItem(
        model: this,
        id: id,
        version: currentVersion,
        delay: cache ? -1 : 0,
        setcache: withProperties,
      );

      if (savedYamlModel is Future) {
        savedYamlModel = await savedYamlModel;
      } else if (mapModelYaml.isNotEmpty) {
        loadingTime = 0;
        return this;
      }

      if (ifEmpty != null && (savedYamlModel == null || savedYamlModel == "")) {
        savedYamlModel = ifEmpty;
      }

      if (savedYamlModel != null && savedYamlModel.toString().trim() != "") {
        modelYaml = savedYamlModel;
        try {
          mapModelYaml = loadYaml(modelYaml, recover: true);
          //print("load yaml model = $id");
        } catch (e) {
          showError("error load yaml model = $id");
          print(e);
        }
      } else {
        modelYaml = '';
        mapModelYaml = {};
      }

      if (withProperties) {
        await _loadProperties(cache: cache);
        loadingTime = 0;
      } else {
        loadingTime = 0;
      }
    } catch (e) {
      showError('loadYamlAndProperties $e');
      rethrow;
    }

    return this;
  }

  Future<void> _initVersion(bool withOlderVersion) async {
    if (currentVersion == null &&
        (category == Category.model || category == Category.api)) {
      var versions = await bddStorage.getAllVersion(this);
      if (versions.isEmpty) {
        ModelVersion version = ModelVersion(
          id: id,
          version: '1',
          data: {
            'state': 'D',
            'by': currentCompany.shortUserId,
            'versionTxt': '0.0.1',
          },
        );
        versions.add(version);
        currentVersion = version;
        bddStorage.storeVersion(this, version);
      } else {
        currentVersion ??= versions.first;
        olderVersion = versions.length > 1 ? versions[1] : null;
      }
      print(
        'model $headerName $id current version = ${currentVersion!.version} version txt = ${currentVersion!.data['versionTxt']}',
      );
      bddStorage.lastVersionByMaster[id] = currentVersion!;
    }
  }

  dynamic loadYamlAndPropertiesSyncOrNot({required bool cache}) {
    dynamic saveModel = bddStorage.getItem(
      model: this,
      id: id,
      version: currentVersion,
      delay: cache ? -1 : 0,
      setcache: true,
    );
    if (saveModel is Future) {
      return loadYamlAndProperties(
        cache: cache,
        withProperties: true,
        withOlderVersion: false,
      );
    } else {}

    if (saveModel != null) {
      modelYaml = saveModel;
      try {
        mapModelYaml = loadYaml(modelYaml, recover: true);
      } catch (e) {
        print(e);
      }
      _loadPropertiesSync();
    } else {
      modelYaml = '';
      mapModelYaml = {};
    }
    return saveModel;
  }

  Future<Map<String, dynamic>> getProperties() async {
    await _loadProperties(cache: true);
    return modelPropertiesByPath;
  }

  Future _loadProperties({required bool cache}) async {
    if (cache == false) {
      isLoadProp = false;
    }
    if (!isLoadProp && withBdd) {
      var l = await bddStorage.getItem(
        model: this,
        version: currentVersion,
        id: 'json/$id',
        delay: 0, //cache ? -1 : 0,
        setcache: true,
      );
      if (l == null) {
        modelPropertiesByPath = {};
      }

      // print("load properties model = $id");
      isLoadProp = true;
    }
  }

  dynamic _loadPropertiesSync() {
    if (!isLoadProp) {
      var l = bddStorage.getItem(
        model: this,
        version: currentVersion,
        id: 'json/$id',
        delay: -1,
        setcache: true,
      );
      if (l is! Future) {
        if (l == null || (l is Map && l.isEmpty)) {
          modelPropertiesByPath = {};
          modelPropExtended.clear();
        } else {
          modelPropertiesByPath = l['prop'];
          modelPropExtended.addAll(l['extended']);
        }
        // print("load properties model = $id");
        isLoadProp = true;
      }
    }
  }

  Future<void> saveProperties() async {
    if (withBdd) {
      await bddStorage.prepareSaveModel(this);
    }
  }

  // Future<bool> saveYaml(
  //   CodeEditorConfig? config,
  //   bool save,
  //   String action,
  // ) async {
  //   var parser = ParseYamlManager()..validateKey = config?.validateKey;
  //   bool parseOk = parser.doParseYaml(modelYaml, config);

  //   if (parseOk) {
  //     mapModelYaml = parser.mapYaml!;
  //     if (save) {
  //       await bddStorage.saveYAML(model: this, type: 'YAML', value: modelYaml);
  //     }

  //     if (action == 'event' || action == 'import') {
  //       config?.repaintCode();
  //       config?.repaintTree();
  //     } else if (action != 'norepaint') {
  //       config?.repaintTree();
  //     }
  //   }

  //   return parseOk;
  // }

  // bool doChangeAndRepaintYaml(
  //   CodeEditorConfig? config,
  //   bool save,
  //   String action,
  // ) {
  //   var parser = ParseYamlManager()..validateKey = config?.validateKey;
  //   bool parseOk = parser.doParseYaml(modelYaml, config);

  //   if (parseOk) {
  //     mapModelYaml = parser.mapYaml!;
  //     if (save) {
  //       bddStorage.saveYAML(model: this, type: 'YAML', value: modelYaml);
  //     }

  //     if (action == 'event' || action == 'import') {
  //       config?.repaintCode();
  //       config?.repaintTree();
  //     } else if (action != 'norepaint') {
  //       config?.repaintTree();
  //     }
  //   }

  //   return parseOk;
  // }

  AttributInfo? getNearestAttributNotUsed(
    List<AttributInfo>? list,
    BrowserAttrInfo bi,
    bool isDependency,
  ) {
    if (list == null) return null;

    if (isDependency) {
      List<AttributInfo>? nllist = [...list];
      for (var element in nllist) {
        var idx = notUseAttributInfo.indexOf(element);
        if (idx == -1) {
          list.remove(element);
        }
      }
      if (list.isEmpty) return null;
    }

    int maxNear = 0;
    AttributInfo? sel;
    if (list.length == 1) {
      if (list.first.lastBrowseDate < bi.browser.time) {
        if (isDependency) notUseAttributInfo.remove(list.first);
        return list.first;
      } else {
        return null;
      }
    }

    for (var n in list) {
      if (n.lastBrowseDate == bi.browser.time) continue; // déja affecter
      String pathA = bi.aJsonPath;
      String pathB = n.path;
      if (pathA == pathB) {
        return n;
      }
      int nb = pathA.length;
      if (pathB.length < nb) {
        nb = pathB.length;
      }
      int nbNear = 0;
      for (var i = 0; i < nb; i++) {
        if (pathA[i] != pathB[i]) break;
        nbNear++;
      }
      if (nbNear > maxNear) {
        maxNear = nbNear;
        sel = n;
      }
    }
    if (isDependency && sel != null) notUseAttributInfo.remove(sel);
    return sel;
  }

  ModelSchema? validateSchema({
    required dynamic subNode,
    required Function validateFct,
  }) {
    ModelSchema? aSchema;
    var mapModel = mapModelYaml[subNode];
    if (mapModel != null) {
      if (mapModel is String) {
        if (mapModel.startsWith('\$')) {
          var refName = mapModel.substring(1);
          var aModelByName = getModelByRefName(refName);

          if (aModelByName != null) {
            String masterIdRef = aModelByName.first.properties?[constMasterID];
            aSchema = ModelSchema(
              category: Category.model,
              headerName: refName,
              id: masterIdRef,
              infoManager: InfoManagerModel(),
              refDomain: refDomain,
            );
            aSchema.autoSaveProperties = false;
            aSchema
                .loadYamlAndProperties(cache: false, withProperties: true)
                .then((value) {
                  validateFct(aSchema!);
                });
          }
        }
      } else {
        aSchema =
            ModelSchema(
                id: '?',
                category: Category.model,
                headerName: '',
                infoManager: InfoManagerModel(),
                refDomain: refDomain,
              )
              ..autoSaveProperties = false
              ..namespace = namespace;

        aSchema.loadSubSchema(subNode, this);
        validateFct(aSchema);
      }
    }
    return aSchema;
  }

  Future<ModelSchema?> getSubSchema({required dynamic subNode}) async {
    ModelSchema? aSchema;
    var mapModel = mapModelYaml[subNode];
    if (mapModel != null) {
      if (mapModel is String) {
        if (mapModel.startsWith('\$')) {
          var refName = mapModel.substring(1);
          var aModelByName = getModelByRefName(refName);

          if (aModelByName != null) {
            String masterIdRef = aModelByName.first.properties?[constMasterID];
            aSchema = ModelSchema(
              category: Category.model,
              headerName: refName,
              id: masterIdRef,
              infoManager: InfoManagerModel(),
              refDomain: refDomain,
            )..namespace = namespace;
            aSchema.autoSaveProperties = false;
            aSchema.isApi = isApi;
            aSchema.readOnlyApi = readOnlyApi;

            await aSchema.loadYamlAndProperties(
              cache: false,
              withProperties: true,
            );
          }
        }
      } else {
        aSchema =
            ModelSchema(
                id: '?',
                category: Category.model,
                headerName: '',
                infoManager: InfoManagerModel(),
                refDomain: refDomain,
              )
              ..namespace = namespace
              ..autoSaveProperties = false;
        aSchema.isApi = isApi;
        aSchema.readOnlyApi = readOnlyApi;
        aSchema.loadSubSchema(subNode, this);
      }
    }
    return aSchema;
  }

  NodeAttribut? getNodeByMasterJsonPath(String? jsonPath) {
    if (jsonPath == null) return null;
    for (var element in useAttributInfo) {
      if (element.getJsonPath(withType: true) == jsonPath) {
        return getNodeByMasterIdPath(element.masterID);
      }
    }
    return null;
  }

  NodeAttribut? getNodeByMasterIdPath(String? masterID) {
    if (masterID == null) return null;
    if (masterID.startsWith('#')) {
      return getExtendedNode(masterID);
    }

    String key = masterID;
    if (masterID.contains('>')) {
      key = masterID.split('>').last;
      for (NodeAttribut element in nodeByMasterId[key] ?? <NodeAttribut>[]) {
        if (element.info.getMasterIDPath() == masterID) {
          return element;
        }
      }
    }
    return nodeByMasterId[key]?.firstOrNull;
  }

  ModelSchemaQuality getModelQualityInfo() {
    double completude = 0;
    int nbAttr = useAttributInfo.length * 3;
    Map<String, int> wordCount = {};

    if (nbAttr == 0) {
      return ModelSchemaQuality(
        wordDuplication: 0,
        wordDuplicationNumber: 0,
        completude: 100,
        documentation: 100,
        complexity: 0,
      );
    }
    for (var element in useAttributInfo) {
      if (!element.name.startsWith('\$')) {
        wordCount[element.name] ??= 0;
        int count = wordCount[element.name]!;
        wordCount[element.name] = count + 1;
      }

      if (element.type.startsWith('\$')) {
        completude += 3;
      } else {
        if (element.properties != null && element.properties!.isNotEmpty) {
          if (element.properties!['description'] != null ||
              element.properties!['example'] != null ||
              element.properties!['const'] != null ||
              element.properties!['default'] != null ||
              element.properties!['enum'] != null) {
            completude += 1;
          } else {
            if (element.properties!['format'] != null ||
                element.properties!['pattern'] != null ||
                element.properties!['required'] != null ||
                element.properties!['dependentRequired'] != null) {
              completude += 1;
            }
          }

          if (element.properties!['title'] != null) {
            completude += 2;
          }
        }
      }
    }

    //wordCount sort
    var sortedWordCount = wordCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    //moyenne de duplication > 2 mots
    double wordDuplication = 0;
    int totalWords = 0;
    for (var entry in sortedWordCount) {
      if (entry.value > 1) {
        wordDuplication += entry.value;
        totalWords += 1;
      }
    }

    // Implement the logic to calculate model completude
    var ret = ModelSchemaQuality(
      wordDuplication: totalWords,
      wordDuplicationNumber: (wordDuplication / totalWords),
      completude: (completude / nbAttr) * 100,
      documentation: 0,
      complexity: 0,
    );

    // recommendation of sortedWordCount
    for (var entry in sortedWordCount) {
      if (entry.value > 1) {
        ret.recommandation.add(
          'The word "${entry.key}" is duplicated ${entry.value} times.',
        );
      }
      if (ret.recommandation.length >= 5 && entry.value < 3) {
        ret.recommandation.add(
          '... ${totalWords - ret.recommandation.length} more words are duplicated less than 3 times.',
        );
        break;
      }
    }

    return ret;
  }
}

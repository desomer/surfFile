import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/components/treeview/json_browser.dart';
import 'package:super_container_layout/widgets/components/treeview/model_schema.dart';
import 'package:super_container_layout/widgets/components/treeview/tree_view.dart';
import 'package:super_container_layout/widgets/components/treeview/widget_overflow.dart';


// Color? getColorOfType(String type) {
//   switch (type.toLowerCase()) {
//     case 'folder':
//       return null;
//     case 'model':
//       return Colors.blue;
//     case 'part':
//       return Colors.blueGrey;
//     case 'component':
//       return Colors.teal;
//     case 'createxdto':
//       return Colors.green;
//     case 'updatexdto':
//       return Colors.teal;
//     case 'xresponsedto':
//       return Colors.indigo;
//     case 'xlistitemdto':
//       return Colors.deepPurple;
//     case 'xquerydto':
//       return Colors.deepPurple;
//     case 'eventxpayloaddto':
//       return Colors.indigo;
//     case 'eventxenvelopedto':
//       return Colors.indigoAccent;
//     case 'flatfile':
//       return Colors.indigoAccent;
//     default:
//       return Colors.grey;
//   }
// }

// final List<OptionSelect> listOptionSelect = [
//   OptionSelect(
//     label: 'model',
//     name: 'model',
//     icon: Icons.data_object,
//     color: Colors.blueGrey,
//   ),
//   OptionSelect(
//     label: 'part',
//     name: 'part',
//     icon: Icons.extension,
//     color: Colors.purple,
//   ),
//   OptionSelect(
//     label: 'component',
//     name: 'component',
//     icon: Icons.build,
//     color: Colors.brown,
//   ),
//   OptionSelect(
//     label: 'createXDto',
//     name: 'createXDto',
//     icon: Icons.create,
//     color: Colors.green,
//   ),
//   OptionSelect(
//     label: 'updateXDto',
//     name: 'updateXDto',
//     icon: Icons.update,
//     color: Colors.orange,
//   ),
//   OptionSelect(
//     label: 'XResponseDto',
//     name: 'XResponseDto',
//     icon: Icons.reply,
//     color: Colors.blue,
//   ),
//   OptionSelect(
//     label: 'XListItemDto',
//     name: 'XListItemDto',
//     icon: Icons.list,
//     color: Colors.purple,
//   ),
//   OptionSelect(
//     label: 'XQueryDto',
//     name: 'XQueryDto',
//     icon: Icons.search,
//     color: Colors.cyan,
//   ),
//   OptionSelect(
//     label: 'eventXPayloadDto',
//     name: 'eventXPayloadDto',
//     icon: Icons.event,
//     color: Colors.teal,
//   ),
//   OptionSelect(
//     label: 'eventXEnvelopeDto',
//     name: 'eventXEnvelopeDto',
//     icon: Icons.mark_email_read,
//     color: Colors.indigo,
//   ),
//   OptionSelect(
//     label: 'flatFile',
//     name: 'flatFile',
//     icon: Icons.insert_drive_file,
//     color: Colors.indigoAccent,
//   ),
// ];

// Icon getIconOfType(String type) {
//   var option = listOptionSelect.firstWhere(
//     (element) => element.name.toLowerCase() == type.toLowerCase(),
//     orElse: () => OptionSelect(
//       label: '',
//       name: '',
//       icon: Icons.help_outline,
//       color: Colors.grey,
//     ),
//   );
//   return Icon(option.icon);
// }

// List<OptionSelect> getListModelType() {
//   return listOptionSelect;
// }

// void validateJsonSchemas(
//   JsonSchema validator,
//   dynamic json,
//   ValueNotifier<String> error,
// ) {
//   ValidationResults r = validator.validate(json);
//   // print("r= $r");
//   if (r.isValid) {
//     error.value = '_VALID_';
//   } else {
//     StringBuffer ret = StringBuffer();
//     for (var element in r.errors) {
//       ret.writeln('${element.instancePath} : ${element.message}');
//     }
//     error.value = ret.toString();
//   }
// }

var commentRE = RegExp(r'"(?:[^\\"]|\\[^])*"|/\*[^]*?\*/|//.*');
String removeComments(String jsonWithComments) =>
    jsonWithComments.replaceAllMapped(commentRE, (m) {
      var s = m[0]!;
      return s.startsWith('"') ? s : "";
    });

//************************************************************************* */
class BrowseModel<T extends Map> extends JsonBrowser<T> {
  BrowseModel({required super.config});

  @override
  void doTree(ModelSchema model, NodeAttribut aNodeAttribut, r) {
    if (aNodeAttribut.info.type == 'model') {
      initVersion(aNodeAttribut, r);
    }
    super.doTree(model, aNodeAttribut, r);
  }

  @override
  T? getRoot(NodeAttribut node) {
    return {} as T;
  }

  @override
  dynamic getChild(
    ModelSchema model,
    NodeAttribut parentNode,
    NodeAttribut node,
    dynamic parent,
  ) {
    if (config.isGet == true) {
      bool wr = node.info.properties?['writeOnly'] ?? false;
      if (wr) {
        return null;
      }
    }

    if (config.isApi == true &&
        !(node.info.properties?['#target']?.toString().contains('api') ??
            true)) {
      return null;
    }

    return parent;
  }

  void initVersion(NodeAttribut aNodeAttribut, r) {
    //print(aNodeAttribut.info.name);
  }
}

class BrowseSingle<T extends Map> extends JsonBrowser<T> {
  BrowseSingle({required super.config});
  List<NodeAttribut> root = [];

  @override
  T? getRoot(NodeAttribut node) {
    return {} as T;
  }

  @override
  dynamic getChild(
    ModelSchema model,
    NodeAttribut parentNode,
    NodeAttribut node,
    dynamic parent,
  ) {
    if (config.isGet == true) {
      bool wr = node.info.properties?['writeOnly'] ?? false;
      if (wr) {
        return null;
      }
    }

    if (config.isApi == true &&
        !(node.info.properties?['#target']?.toString().contains('api') ??
            true)) {
      return null;
    }

    root.add(node);
    return parent;
  }
}


class InfoManagerModel extends InfoManager {
  InfoManagerModel();

  @override
  String getTypeTitle(NodeAttribut node, String name, dynamic type) {
    String? typeStr;
    if (type is Map) {
      if (name.startsWith(constRefOn)) {
        typeStr = '\$ref';
      } else if (name.startsWith(constTypeAnyof)) {
        typeStr = '\$anyOf';
        node.bgcolor = Colors.orange.withAlpha(100);
      } else if (name.startsWith(constTypeOneof)) {
        typeStr = '\$oneOf';
        node.bgcolor = Colors.orange.withAlpha(100);
      } else if (name.endsWith('[]')) {
        node.bgcolor = Colors.blue.withAlpha(100);
        typeStr = 'array';
      } else {
        node.bgcolor = Colors.blueGrey.withAlpha(50);
        
      }
    } else if (type is List) {
      if (name.endsWith('[]')) {
        typeStr = 'array';
        node.bgcolor = Colors.blue.withAlpha(50);
      } else {
        node.bgcolor = Colors.blue.withAlpha(50);
        typeStr = 'object';
      }
    } else if (type is int) {
      typeStr = 'integer';
    } else if (type is double) {
      typeStr = 'number';
    } else if (type is String) {
      if (name.endsWith('[]')) {
        node.bgcolor = Colors.blue.withAlpha(50);
        if (type.startsWith('\$')) {
          typeStr = 'array';
        } else {
          typeStr = '$type[]';
        }
      } else if (type.startsWith('\$')) {
        typeStr = 'object';
      }
    }
    typeStr ??= '$type';
    return typeStr;
  }

  @override
  InvalidInfo? isTypeValid(
    NodeAttribut nodeAttribut,
    String name,
    dynamic type,
    String typeTitle,
  ) {
    var type = typeTitle.toLowerCase();

    if (type.endsWith('[]')) {
      type = type.substring(0, type.length - 2);
    }

    bool valid = [
      // 'folder',
      // 'model',
      'string',
      'integer',
      'number',
      'object',
      'array',
      'boolean',
      '\$ref',
      '\$anyof',
      '\$oneof',
      '\$inherit',
    ].contains(type);
    if (!valid) {
      return InvalidInfo(color: Colors.red);
    }
    return null;
  }

  // @override
  // Widget getAttributHeaderOLD(TreeNode<NodeAttribut> node) {
  //   var isRoot = node.isRoot;
  //   var isFolder = node.data!.info.type == 'folder';
  //   var isModel = node.data!.info.type == 'model';

  //   var isObject = node.data!.info.type == 'object';
  //   var isOneOf = node.data!.info.type == '\$anyOf';
  //   var isRef = node.data!.info.type == '\$ref';
  //   var isType = node.data!.info.name == constType;
  //   var isInherit = node.data!.info.name == constInherit;
  //   var isArray =
  //       node.data!.info.type == 'Array' || node.data!.info.type.endsWith('[]');
  //   String name = node.data!.yamlNode.key.toString();

  //   Widget icon = Container(width: 20);
  //   if (isRoot) {
  //     icon = Icon(Icons.business);
  //   } else if (isInherit) {
  //     icon = Icon(Icons.call_split);
  //   } else if (isFolder) {
  //     icon = Icon(Icons.lan_outlined);
  //   } else if (isModel) {
  //     icon = Icon(Icons.data_object);
  //   } else if (isObject) {
  //     icon = Icon(Icons.data_object);
  //   } else if (isRef) {
  //     icon = Icon(Icons.link);
  //     name = '\$${node.data?.info.properties?[constRefOn] ?? '?'}';
  //   } else if (isOneOf) {
  //     name = '\$anyOf';
  //     icon = Icon(Icons.looks_one_rounded);
  //   } else if (isArray) {
  //     icon = Icon(Icons.data_array);
  //   } else if (isType) {
  //     name = '\$type';
  //     icon = Icon(Icons.type_specimen_outlined);
  //   }

  //   return GetHeaderRowWidget(
  //     icon: icon,
  //     name: name,
  //     isObject: isObject,
  //     isArray: isArray,
  //   );
  // }

  @override
  Widget getRowHeader(TreeNodeData<NodeAttribut> node, BuildContext context) {
    Widget? icon;
    var isRoot = node.isRoot;
    var attr = node.data.info;
    // var isFolder = attr.type == 'folder';
    // var isModel = attr.type == 'model';

    var isObject = attr.type == 'object';
    var isAnyOf = attr.type == '\$anyOf';
    var isOneOf = attr.type == '\$oneOf';
    var isRef = attr.type == '\$ref';
    var isType = attr.name == constType;
    var isArray = attr.type == 'array' || attr.type.endsWith('[]');
    var isInherit = attr.name == constInherit;
    String name = attr.name;

    Color? iconColor = attr.isRefAttr()
        ? Colors.grey.shade800
        : Colors.blueGrey;

    if (isRoot) {
      icon = Icon(Icons.business, color: iconColor, size: 20);
    } else if (isInherit) {
      icon = Icon(Icons.call_split, color: iconColor, size: 20);
      // } else if (isFolder) {
      //   icon = Icon(Icons.folder, color: iconColor, size: 20);
      // } else if (isModel) {
      //   icon = Icon(Icons.data_object, color: iconColor, size: 20);
    } else if (isObject) {
      icon = Icon(Icons.data_object, color: iconColor, size: 20);
    } else if (isRef) {
      icon = Icon(Icons.link, color: iconColor, size: 20);
      name = '\$${node.data.info.properties?[constRefOn] ?? '?'}';
    } else if (isOneOf) {
      name = '\$oneOf';
      icon = Icon(Icons.looks_one_rounded, color: iconColor, size: 20);
    } else if (isAnyOf) {
      name = '\$anyOf';
      icon = Icon(Icons.looks_one_rounded, color: iconColor, size: 20);
    } else if (isArray) {
      icon = Icon(Icons.data_array, color: iconColor, size: 20);
    } else if (isType) {
      name = '\$type';
      icon = Icon(Icons.type_specimen_outlined, color: iconColor, size: 20);
    }

    if (attr.name.startsWith(constTypeOf)) {
      name = name.replaceFirst(constTypeOf, '');
      icon = Icon(Icons.type_specimen_outlined, color: iconColor, size: 20);
    }

    // var changeStyle = InfoManagerChangeStyle();
    // changeStyle.initStyle(modelSchema!, node);

    Color? colorText = (attr.isRefAttr() ? Colors.grey : null);
    // if (changeStyle.nameChange != null) {
    //   colorText = changeStyle.nameChange!;
    // }

    bool isDeprecated = attr.properties?['deprecated'] == true;

    return NoOverflowErrorFlex(
      direction: Axis.horizontal,
      children: [
        if (icon != null)
          GestureDetector(
            onTap: () {
              node.doToogleChild();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 2, 0),
              child: icon,
            ),
          ),
        if (icon == null)
          Container(width: 10), // to align with other rows with icon
        Expanded(
          child: InkWell(
            onTap: () {
              node.doTapHeader();
            },
            child: NoOverflowErrorFlex(
              direction: Axis.horizontal,
              children: [
                // if (changeStyle.addColor != null)
                //   Padding(
                //     padding: const EdgeInsets.only(right: 3, top: 6, bottom: 6),
                //     child: Tooltip(
                //       message: 'Added',
                //       child: Container(width: 4, color: changeStyle.addColor),
                //     ),
                //   ),
                // if (changeStyle.pathChange != null)
                //   Padding(
                //     padding: const EdgeInsets.only(right: 3, top: 6, bottom: 6),
                //     child: Tooltip(
                //       message: 'Path changed ${changeStyle.tooltipMessage}',
                //       child: Container(width: 4, color: changeStyle.pathChange),
                //     ),
                //   ), // for error display   // for error display
                // Expanded(
                //   child: _getTooltipText(
                //     null,
                //     'Name ',
                //     _getBorder(
                //       attr,
                //       Text(
                //         overflow: TextOverflow.fade,
                //         maxLines: 1,
                //         name,
                //         style: (isObject || isArray)
                //             ? TextStyle(
                //                 decoration: isDeprecated
                //                     ? TextDecoration.lineThrough
                //                     : null,
                //                 fontWeight: FontWeight.bold,
                //                 color: colorText,
                //                 fontSize: 14,
                //               )
                //             : TextStyle(
                //                 color: colorText,
                //                 fontSize: 14,
                //                 decoration: isDeprecated
                //                     ? TextDecoration.lineThrough
                //                     : null,
                //               ),
                //       ),
                //     ),
                //   ),
                // ),
                //Spacer(),
                _getWidgetType(node.data, isRoot, context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _getBorder(AttributInfo attr, Widget child) {
    if (attr.type == '\$ref') {
      return NoOverflowErrorFlex(
        direction: Axis.horizontal,
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(5, 0, 5, 0),
            decoration: BoxDecoration(
              color: Colors.grey.withAlpha(100),
              borderRadius: BorderRadius.all(Radius.circular(5)),
              border: Border.all(color: Colors.blueGrey, width: 1),
            ),
            child: child,
          ),
          Spacer(),
        ],
      );
    }

    return child;
  }


  Widget _getWidgetType(NodeAttribut attr, bool isRoot, BuildContext context) {
    if (isRoot) {
      return Text(
        '${modelSchema?.useAttributInfo.length} properties',
        style: const TextStyle(fontSize: 14),
      );
    }

    bool hasError = attr.info.error?[EnumErrorType.errorRef] != null;
    hasError = hasError || attr.info.error?[EnumErrorType.errorType] != null;

    String type = attr.info.type;

    if (type == '\$ref' ||
        attr.info.name == constInherit ||
        attr.info.name.startsWith(constTypeOf) ||
        type == '\$anyOf' ||
        type == '\$oneOf') {
      return SizedBox.shrink();
    }

    Widget w = Text(
      type,
      style: TextStyle(
        fontSize: 14,
        color: hasError ? Colors.redAccent : null,
      ),
    );
  
    bool canEditType =
        modelSchema?.isReadOnlyModel == false &&
        !isRoot &&
        attr.info.type != 'object' &&
        attr.info.type != 'array' &&
        !attr.info.isRefAttr() &&
        !attr.info.type.startsWith(r'$');
    if (canEditType) {
      return _getEditorType(attr, context, w);
    }
    return w;
  }

  Widget _getEditorType(NodeAttribut attr, BuildContext context, Widget child) {
    GlobalKey? k = GlobalKey();

    return GestureDetector(
      key: k,
      onTap: () {
       
      },
      child: child,
    );
  }

  @override
  Function? getValidateKey() {
    return (String key) {
      if (key.contains(' ')) {
        throw Exception(
          'Key "$key" is not valid.\nSpaces are not allowed in keys.',
        );
      }
    };
  }
}

class GetHeaderRowWidget extends StatelessWidget {
  const GetHeaderRowWidget({
    super.key,
    required this.icon,
    required this.name,
    required this.isObject,
    required this.isArray,
  });

  final Widget icon;
  final String name;
  final bool isObject;
  final bool isArray;

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
        child: NoOverflowErrorFlex(
          direction: Axis.horizontal,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
              child: icon,
            ),
            Text(
              name,
              style: (isObject || isArray)
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

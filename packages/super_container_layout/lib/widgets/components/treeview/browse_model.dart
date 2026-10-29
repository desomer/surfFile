import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/widgets/components/treeview/json_browser.dart';
import 'package:super_container_layout/widgets/components/treeview/model_schema.dart';
import 'package:super_container_layout/widgets/components/treeview/tree_view.dart';
import 'package:super_container_layout/widgets/components/treeview/widget_overflow.dart';

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

//---------------------------------------------------------------------------------
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
    // if (config.isGet == true) {
    //   bool wr = node.info.properties?['writeOnly'] ?? false;
    //   if (wr) {
    //     return null;
    //   }
    // }

    // if (config.isApi == true &&
    //     !(node.info.properties?['#target']?.toString().contains('api') ??
    //         true)) {
    //   return null;
    // }

    root.add(node);
    return parent;
  }
}

class InfoManagerModel extends InfoManager {
  InfoManagerModel();

  @override
  String getTypeTitle(NodeAttribut node, String name, dynamic type) {
    String? typeStr;
    node.bgcolor = Colors.blue.withAlpha(50);
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

  @override
  Widget getRowHeader(TreeNodeData<NodeAttribut> node, BuildContext context) {
    var attr = node.data.info;
    var isArray = attr.type == 'array' || attr.type.endsWith('[]');
    var isObject = attr.type == 'object';

    return GetHeaderRowWidget(
      icon: Icon(Icons.folder, color: Colors.blueGrey, size: 20),
      name: '',
      isObject: isObject,
      isArray: isArray,
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

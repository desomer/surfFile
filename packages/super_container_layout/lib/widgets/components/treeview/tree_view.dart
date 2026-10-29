import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:super_container_layout/widgets/components/treeview/authorization_manager.dart';
import 'package:super_container_layout/widgets/components/treeview/json_browser.dart';
import 'package:super_container_layout/widgets/components/treeview/widget_hover.dart';
import 'package:super_container_layout/widgets/components/treeview/widget_overflow.dart';

final ValueNotifier<int> zoom = ValueNotifier(100);
int timezoom = 0;
double scale = 0.9;
double rowHeight = 30 * scale;
PanYamlTree? currentYamlTree;

class PanYamlTree {
  TextSelection? getTextSelection() {}
}


class TreeNodeData<T> {
  List<TreeNodeData<T>>? children;
  bool isExpanded;
  bool isShow = true;
  late int depth;
  late List<bool> listParentIndicator;
  bool noTab = false;
  bool isLast = false;
  bool isRoot = false;
  Color? bgColor;

  int timeChange = 0;
  bool isToogleRequested = false;
  bool isInvisibleRequested = false;

  T data;

  // ValueNotifier<int> changed = ValueNotifier(0);
  // ValueNotifier<int> selected = ValueNotifier(0);

  String? rowCacheKey;
  Widget? rowCache;
  int numUpdate = 0;

  TreeViewState? stateCache;
  late TreeViewState tree;
  //HoverableCardState? hoverState;

  TreeNodeData({required this.data, this.children, this.isExpanded = true});

  void setCache(String key, {bool force = false}) {
    if (rowCacheKey != key || force) {
      rowCache = null;
    }
    rowCacheKey = key;
  }

  List<TreeNodeData<T>>? childrenToClear;
  void _reinitChild() {
    if (children != null) {
      childrenToClear = [...children!];
    } else {
      childrenToClear = null;
    }
    children = null;
  }

  void reinitRoot() {
    _reinitChild();
  }

  void doTapHeader() {
    tree.doTapHeader(this, 'header');
  }

  void doToogleChild() {
    tree.doToogle(this);
  }

  TreeNodeData<T> exist(T data, Function exist) {
    late TreeNodeData<T> v;
    if (childrenToClear != null) {
      v = childrenToClear!.firstWhere(
        (e) => exist(e.data) == exist(data),
        orElse: () => TreeNodeData(data: data),
      );

      childrenToClear!.remove(v);
      v._reinitChild();
    } else {
      v = TreeNodeData(data: data);
    }
    return v;
  }

  void add(TreeNodeData<T> child) {
    children ??= [];
    children!.add(child);
  }
}

typedef GetNode<T> = TreeViewData<T> Function();
typedef GetWidget<Y> = Widget Function(TreeNodeData<Y> node);
typedef OnTap<T> =
    void Function(TreeNodeData<T> node, BuildContext ctx, String type);
typedef OnBuild<T> = void Function(TreeViewState<T> state, BuildContext ctx);
typedef IsSelected<T> =
    bool Function(
      TreeNodeData<T> node,
      State? current,
      State? oldSelectedState,
    );

typedef IsRowCached<T> = int Function(TreeNodeData<T> node);
typedef OnSelectionChanged<T> = void Function(Set<TreeNodeData<T>> selected);
typedef OnCopy<T> = void Function(Set<TreeNodeData<T>> nodes);
typedef OnPaste<T> =
    void Function(Set<TreeNodeData<T>> clipboard, TreeNodeData<T> target);

class TreeViewData<T> {
  final List<TreeNodeData<T>> nodes;
  final double headerSize;

  TreeViewData({required this.nodes, required this.headerSize});
}

/// A widget that displays a tree view with expandable and collapsible nodes.

// GlobalKey<TreeViewState> keyTreeEditor = GlobalKey();

//   Widget getTree(BuildContext context) {
//     return TreeView<Map<String, dynamic>>(
//       key: keyTreeEditor,
//       isSelected: (node, cur, old) {
//         return node.data['selected'] == true;
//       },
//       onBuild: (state, ctx) {},
//       getNodes: () {
//         var main = TreeNodeData<Map<String, dynamic>>(
//           data: {'id': 'root', 'name': 'Root'},
//           children: [
//             TreeNodeData<Map<String, dynamic>>(
//               data: {'id': 'aaa', 'name': 'aaaaa'},
//             ),
//           ],
//         );
//         return TreeViewData(nodes: [main], headerSize: 100);
//       },
//       getHeader: (node) {
//         return Text(node.data['id'] ?? 'No id');
//       },
//       getDataRow: (node) {
//         return InkWell(
//           onTap: () {
//             node.data['selected'] =
//                 node.data['selected'] == true ? false : true;

//             int idcache = node.data['intCache'] ?? 0;
//             node.data['intCache'] = idcache + 1;

//             keyTreeEditor.currentState?.doTapHeader(node);
//           },
//           child: Text(node.data['name'] ?? 'No name'),
//         );
//       },
//       onTapHeader: (node, ctx) async {
//         print('tap on ${node.data['name']}');
//       },
//       isRowCached: (node) {
//         return node.data['intCache'] ?? 0;
//       },
//     );
//   }

class TreeView<T> extends StatefulWidget {
  const TreeView({
    super.key,
    required this.getNodes,
    required this.getHeader,
    required this.getDataRow,
    this.onBuild,
    this.onTapHeader,
    required this.isSelected,
    this.isRowCached,
    this.onSelectionChanged,
    this.contextMenuItems,
    this.showCheckboxes = false,
    this.onCopy,
    this.onPaste,
  });

  final GetNode<T> getNodes;
  final GetWidget<T> getHeader;
  final GetWidget<T> getDataRow;
  final OnTap<T>? onTapHeader;
  final OnBuild<T>? onBuild;
  final IsSelected<T> isSelected;
  final IsRowCached<T>? isRowCached;
  final OnSelectionChanged<T>? onSelectionChanged;
  final OnCopy? onCopy;
  final OnPaste? onPaste;

  /// Affiche une case à cocher en début de chaque ligne.
  final bool showCheckboxes;

  /// Optional extra menu items appended after the built-in actions.
  /// Each entry: {'label': String, 'icon': IconData?, 'value': String}
  final List<Map<String, dynamic>>? contextMenuItems;

  @override
  State<TreeView> createState() => TreeViewState<T>();
}

final Set<TreeNodeData> _clipboardNodes = {};

class TreeViewState<T> extends State<TreeView<T>> {
  double headerSize = -1;
  int animateDelay = 200;
  //double height = 30.0;

  IndentInfo indent = IndentInfo(
    indent: 20,
    start: 10,
    end: 0,
    height: 30.0,
    color: const Color.fromARGB(255, 73, 77, 79),
  );

  int timeBuild = 0;
  final ScrollController _scrollController = ScrollController();
  late BuildContext ctx;
  int repaintInProgess = 0;
  int openFactorInProgess = 0;
  int openFactor = 10;
  int dragInProgess = 0;
  bool isDisposed = false;

  State? currentRowSelectedState;
  String openStructureMode = 'all';
  String filterType = 'all';

  final Set<TreeNodeData<T>> selectedNodes = {};
  bool showCheckboxes = false;

  void toggleCheckboxMode() {
    setState(() {
      showCheckboxes = !showCheckboxes;
      repaintInProgess = DateTime.now().millisecondsSinceEpoch;
    });
  }

  void repaint() {
    repaintInProgess = DateTime.now().millisecondsSinceEpoch;
    // ignore: invalid_use_of_protected_member
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    showCheckboxes = widget.showCheckboxes;
  }

  @override
  void dispose() {
    isDisposed = true;
    super.dispose();
  }

  List<TreeNodeData<T>> list = [];

  int doSearch(String value, int idx) {
    var lowerCase = value.toLowerCase();
    Iterable<TreeNodeData<T>> nodes = list.where((element) {
      NodeAttribut attrData = element.data as NodeAttribut;
      String? title = attrData.info.properties?['title'];
      if (attrData.info.name.toLowerCase().contains(lowerCase)) {
        return true;
      } else if (title?.toLowerCase().contains(lowerCase) ?? false) {
        return true;
      }
      return false;
    });

    if (nodes.isNotEmpty) {
      var node = nodes.elementAt(idx % nodes.length);
      doTapHeader(node, "search");
      scrollToData(node.data);
    }
    return nodes.length;
  }

  @override
  Widget build(BuildContext context) {
    ctx = context;
    if (widget.onBuild != null) {
      widget.onBuild!(this, ctx);
    }

    TreeViewData<T> data = widget.getNodes();
    List<TreeNodeData<T>> nodes = data.nodes;
    Size size = MediaQuery.of(ctx).size;

    NodeStack stack = NodeStack();
    list = _flattenNodeTree(stack, 0, nodes);
    //openStructureMode = 'all';

    var ret = ValueListenableBuilder(
      valueListenable: zoom,
      // pour appel durant le changement de zoom
      builder: (context, value, child) {
        timeBuild = DateTime.now().millisecondsSinceEpoch;
        if (headerSize == -1 ||
            (headerSize < data.headerSize && dragInProgess == 0)) {
          headerSize = data.headerSize;
          repaintInProgess = timeBuild;
          if (headerSize > size.width - 300 - 350 - 0) {
            headerSize = size.width - 300 - 350 - 0;
          }
          if (headerSize < 100) headerSize = 100;
        }
        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true, // ✅ Toujours visible sur desktop
          child: ListView.builder(
            primary: false,
            controller: _scrollController,
            shrinkWrap: true,
            itemCount: list.length,
            itemBuilder: (context, index) {
              var node = list[index];
              node.tree = this;
              var row = _getAnimatedHeightRow(
                node,
                _buildNode(context, node),
                ValueKey('${node.hashCode}#header'),
              );
              return row;
            },
          ),
        );
      },
    );

    return ret;
  }

  List<TreeNodeData<T>> _flattenNodeTree(
    NodeStack stackLevelIndicator,
    int deep,
    List<TreeNodeData<T>> nodes,
  ) {
    List<TreeNodeData<T>> result = [];
    var millisecondsSinceEpoch2 = DateTime.now().millisecondsSinceEpoch;

    for (var node in nodes) {
      node.depth = deep;
      node.isRoot = deep == 0;
      node.isLast = node == nodes.last;

      if (millisecondsSinceEpoch2 - openFactorInProgess < 500) {
        if (openStructureMode == 'structure') {
          node.isExpanded = false;
          if (hasStructure(node)) {
            node.isExpanded = true;
          }
        } else if (openStructureMode == 'onlyStructure') {
          node.isExpanded = false;
          if (!isStructure(node)) {
            node.isShow = false;
            continue;
          }
          if (node.isRoot || hasStructure(node)) {
            node.isExpanded = true;
          }
        } else {
          node.isShow = true;
          node.isExpanded = deep < openFactor;
        }
      }

      if (node.isShow == false) {
        continue;
      }

      if (filterType != 'all') {
        if (node.data is NodeAttribut) {
          var info = (node.data as NodeAttribut).info;
          if (!(info.properties?["#target"]?.toString().contains(filterType) ??
              true)) {
            continue;
          }
        }
      }

      //bool noDisplayNodeButKeepChildren = false;
      bool noTab = false;

      if (node.data is NodeAttribut) {
        var attr = (node.data as NodeAttribut);
        var info = attr.info;
        if (info.name == constInherit) {
          // les attributs d'un $inherit sont affichés au même niveau que le $inherit lui même
          noTab = true;
        }

        // if (attr.parent?.info.name == constInherit && info.type == '\$ref') {
        //   noTab = true;
        //   //noDisplayNodeButKeepChildren = true;
        // }

        if (info.type == '\$ref') {
          noTab = true;
          //noDisplayNodeButKeepChildren = true;
        }
      }

      // if (noDisplayNodeButKeepChildren) {
      //   // on affiche pas le noeud $ref mais on affiche directement ses attributs
      //   noTab = true;
      // } else {
        result.add(node);
      //}

      var r = <bool>[];
      for (var i = 0; i < stackLevelIndicator.stack.length; i++) {
        if (stackLevelIndicator.stack[i].noTab) {
          // if (stackLevelIndicator.stack.length > i + 1) {
          //   stackLevelIndicator.stack[i + 1].isLast = false;
          // }
          continue;
        }
        r.add(stackLevelIndicator.stack[i].isLast);
      }

      node.listParentIndicator = r;

      stackLevelIndicator.push(node);

      if (noTab) {
        node.noTab = true;
        // on affiche pas le noeud $ref mais on affiche directement ses attributs
        deep--;
      }

      if (node.children != null &&
          node.children!.isNotEmpty &&
          node.isExpanded) {
        result.addAll(
          _flattenNodeTree(stackLevelIndicator, deep + 1, node.children!),
        );
      }

      if (noTab) {
        // on affiche pas le noeud $ref mais on affiche directement ses attributs
        deep++;
      }

      stackLevelIndicator.pop();
    }

    return result;
  }

  Widget getHover(TreeNodeData<T> attr, Widget child) {
    return HoverableCard(
      onHover: (isHovered) {
        if (attr.data is NodeAttribut) {
          (attr.data as NodeAttribut).info.isHoover?.value = isHovered;
        }
      },
      onBuild: (state, ctx) {
        if (attr.data is NodeAttribut) {
          (attr.data as NodeAttribut).widgetRowHoverState = state;
        }
      },
      isSelected: (State state) {
        if (attr.data is NodeAttribut) {
          (attr.data as NodeAttribut).widgetRowHoverState = state;
        }
        if (widget.onBuild != null) {
          widget.onBuild!(this, ctx);
        }

        bool isSelected = widget.isSelected(
          attr,
          state,
          currentRowSelectedState,
        );
        if (isSelected) {
          if (state != currentRowSelectedState) {
            var old = currentRowSelectedState;
            // deselectionner l'ancien
            SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
              state.setState(() {});
              if (old?.mounted == true) {
                // ignore: invalid_use_of_protected_member
                old?.setState(() {});
              }
            });
          }
          currentRowSelectedState = state;
        }
        return isSelected;
      },
      child: child,
    );
  }

  void doTapHeader(TreeNodeData<T> node, String type) {
    if (widget.onTapHeader case final OnTap<T> on) {
      on(node, ctx, type);
    }
    if (node.isExpanded) {
      setState(() {
        _showChildren(node);
      });
    }
  }

  void doToogle(TreeNodeData<T> node) {
    setState(() {
      if (node.children != null && node.children!.isNotEmpty) {
        if (node.isExpanded == false) {
          node.isExpanded = true;
          node.isToogleRequested = false;
        } else {
          node.isToogleRequested = true;
          node.timeChange = DateTime.now().millisecondsSinceEpoch;
        }

        _toogleChildren(node, node.isToogleRequested);
      }
    });
  }

  // Widget _getJsonRowCached(NodeAttribut attr, ModelSchema schema) {
  //   int time = DateTime.now().millisecondsSinceEpoch;
  //   if (dataAttr.info.cacheRowWidget != null && time - timezoom > 300) {
  //     cell = dataAttr.info.cacheRowWidget!;
  //   } else {
  //     cell = _getJsonRowCached(dataAttr, widget.modelInfo.config.getModel());
  //   }

  //   attr.info.cacheRowWidget = WidgetJsonRow(
  //     node: attr,
  //     schema: schema,
  //     fctGetRow: widget.modelInfo.config.getRow,
  //   );
  //   return attr.info.cacheRowWidget!;
  // }

  Widget _buildNode(BuildContext context, TreeNodeData<T> node) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition, node);
      },
      child: Stack(
        children: [
          getHover(node, _getRowCached(node)),
          if (node.depth > 0)
            Positioned(
              left: 0,
              top: 0,
              child: TreeConnector(node: node, indentInfo: indent),
            ),
        ],
      ),
    );
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset position,
    TreeNodeData<T> node,
  ) async {
    final bool isSelected = selectedNodes.contains(node);
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;

    final items = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'toggle_checkbox_mode',
        child: Row(
          children: [
            Icon(
              showCheckboxes
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              showCheckboxes
                  ? 'Hide selected checkboxes'
                  : 'Show selected checkboxes',
            ),
          ],
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'toggle_select',
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(isSelected ? 'Deselect' : 'Select'),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'select_all',
        child: const Row(
          children: [
            Icon(Icons.select_all, size: 18),
            SizedBox(width: 8),
            Text('Select all'),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'deselect_all',
        child: const Row(
          children: [
            Icon(Icons.deselect, size: 18),
            SizedBox(width: 8),
            Text('Deselect all'),
          ],
        ),
      ),
      if (node.children?.isNotEmpty == true) ...[
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'expand',
          child: const Row(
            children: [
              Icon(Icons.expand_more, size: 18),
              SizedBox(width: 8),
              Text('Expand'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'collapse',
          child: const Row(
            children: [
              Icon(Icons.expand_less, size: 18),
              SizedBox(width: 8),
              Text('Collapse'),
            ],
          ),
        ),
      ],
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'copyPath',
        child: Row(
          children: [
            const Icon(Icons.copy, size: 18),
            const SizedBox(width: 8),
            Text(
              selectedNodes.isEmpty
                  ? 'Copy path'
                  : 'Copy paths (${selectedNodes.length})',
            ),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'copy',
        child: Row(
          children: [
            const Icon(Icons.copy, size: 18),
            const SizedBox(width: 8),
            Text(
              selectedNodes.isEmpty
                  ? 'Copy node'
                  : 'Copy (${selectedNodes.length})',
            ),
          ],
        ),
      ),
      // PopupMenuItem<String>(
      //   enabled: _clipboardNodes.isNotEmpty,
      //   value: 'paste',
      //   child: Row(
      //     children: [
      //       Icon(
      //         Icons.paste,
      //         size: 18,
      //         color: _clipboardNodes.isEmpty ? Colors.grey : null,
      //       ),
      //       const SizedBox(width: 8),
      //       Text(
      //         _clipboardNodes.isEmpty
      //             ? 'Paste'
      //             : 'Paste (${_clipboardNodes.length})',
      //         style: TextStyle(
      //           color: _clipboardNodes.isEmpty ? Colors.grey : null,
      //         ),
      //       ),
      //     ],
      //   ),
      // ),
      if (widget.contextMenuItems != null &&
          widget.contextMenuItems!.isNotEmpty) ...[
        const PopupMenuDivider(),
        for (final item in widget.contextMenuItems!)
          PopupMenuItem<String>(
            value: item['value'] as String,
            child: Row(
              children: [
                if (item['icon'] != null) ...[
                  Icon(item['icon'] as IconData, size: 18),
                  const SizedBox(width: 8),
                ],
                Text(item['label'] as String),
              ],
            ),
          ),
      ],
    ];

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      popUpAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 80),
        reverseDuration: Duration(milliseconds: 60),
        curve: Curves.linear,
        reverseCurve: Curves.linear,
      ),
      items: items,
    );

    if (result == null) return;

    switch (result) {
      case 'toggle_checkbox_mode':
        toggleCheckboxMode();
        break;
      case 'toggle_select':
        setState(() {
          if (selectedNodes.contains(node)) {
            selectedNodes.remove(node);
          } else {
            selectedNodes.add(node);
          }
          node.numUpdate++;
        });
        widget.onSelectionChanged?.call(Set.unmodifiable(selectedNodes));
        break;
      case 'select_all':
        setState(() {
          selectedNodes.addAll(list);
          for (var element in list) {
            element.numUpdate++;
          }
        });
        widget.onSelectionChanged?.call(Set.unmodifiable(selectedNodes));
        break;
      case 'deselect_all':
        setState(() {
          for (var element in selectedNodes) {
            element.numUpdate++;
          }
          selectedNodes.clear();
        });
        widget.onSelectionChanged?.call(Set.unmodifiable(selectedNodes));
        break;

      case 'copyPath':
        StringBuffer sb = StringBuffer();
        if (selectedNodes.isEmpty) {
          sb.writeln(
            (node.data as NodeAttribut).info.getJsonPath(
              sep: '.',
              withRoot: false,
            ),
          );
        } else {
          for (var element in selectedNodes) {
            _clipboardNodes.add(element);
            if (element.data is NodeAttribut) {
              var path = (element.data as NodeAttribut).info.getJsonPath(
                sep: '.',
                withRoot: false,
              );
              sb.writeln(path);
            }
          }
        }
        Clipboard.setData(ClipboardData(text: sb.toString()));
        ScaffoldMessenger.of(
          // ignore: use_build_context_synchronously
          context,
        ).showSnackBar(SnackBar(content: Text('copied to clipboard')));
        break;

      case 'copy':
        _clipboardNodes.clear();
        String rootPath = '';
        for (var element in selectedNodes) {
          _clipboardNodes.add(element);
          if (element.data is NodeAttribut) {
            var path = (element.data as NodeAttribut).info.getJsonPath(
              sep: '>',
            );
            if (rootPath.isEmpty) {
              rootPath = path;
            } else {
              // on garde que la partie du path qui est commune à tous les éléments sélectionnés pour éviter d'avoir des chemins trop long lors du collage
              while (!path.startsWith(rootPath)) {
                int index = rootPath.lastIndexOf('>');
                if (index == -1) {
                  rootPath = '';
                  break;
                }
                rootPath = rootPath.substring(0, index);
              }
            }
          }
        }
        StringBuffer sb = StringBuffer();
        currentCompany.copiedMapInfoByName.clear();
        for (var element in _clipboardNodes) {
          if (element.data is NodeAttribut) {
            var attr = element.data as NodeAttribut;
            var path = attr.info.getJsonPath(sep: '>');
            var length = rootPath.length;
            if (length > 0) {
              length++; // pour enlever le séparateur ">" en début du path
            }
            path = path.substring(length);
            // compte le nb de > dans le path pour ajouter une indentation dans la console et mieux visualiser la hiérarchie des éléments copiés
            int indent = '>'.allMatches(path).length;
            String indentation = '\t' * indent;
            var type = attr.info.type;
            if (type == 'object' || type == 'array') {
              type = '';
            }
            sb.writeln("$indentation${attr.info.name} : $type");
            currentCompany.copiedMapInfoByName
                .putIfAbsent(attr.info.name, () => [])
                .add(attr.info.clone().prepareNewSave());
          }
        }
        print("Copied nodes:\n$sb");
        Clipboard.setData(ClipboardData(text: sb.toString()));

        widget.onCopy?.call(Set.unmodifiable(_clipboardNodes));

        setState(() {
          selectedNodes.clear();
          _clipboardNodes.clear();
        });
        ScaffoldMessenger.of(
          // ignore: use_build_context_synchronously
          context,
        ).showSnackBar(SnackBar(content: Text('copied to clipboard')));
        break;
      // case 'paste':
      //   if (_clipboardNodes.isNotEmpty) {
      //     widget.onPaste?.call(Set.unmodifiable(_clipboardNodes), node);
      //   }
      //   break;
      case 'expand':
        setState(() {
          node.isExpanded = true;
        });
        break;
      case 'collapse':
        setState(() {
          doToogle(node);
        });
        break;
      default:
        // Delegate unknown values to the caller via a dedicated callback
        // (contextMenuItems entries are identified by their 'value' key).
        break;
    }
  }

  Widget _getRowCached(TreeNodeData<T> node) {
    int numUpdate = 0;
    if (node.data is NodeAttribut) {
      numUpdate = (node.data as NodeAttribut).info.numUpdateForKey;
    } else if (widget.isRowCached != null) {
      numUpdate = widget.isRowCached!(node);
    }

    if (node.rowCache == null ||
        node.stateCache != this ||
        timeBuild - repaintInProgess < 500 ||
        timeBuild - timezoom < 500 ||
        numUpdate != node.numUpdate) {
      node.numUpdate = numUpdate;
      node.stateCache = this;
      node.rowCache = _getRow(node);
    }
    return node.rowCache!;
  }

  Widget _getRow(TreeNodeData<T> node) {
    var left = indent.indent * node.depth;
    var w = headerSize - left;
    if (w < 20) {
      w = 20;
    }
    final Color? effectiveColor = selectedNodes.contains(node)
        ? Colors.orange.withAlpha(100)
        : node.bgColor;

    return Container(
      color: effectiveColor,
      height: rowHeight,
      //width:  300,
      padding: EdgeInsets.only(left: left, right: 10),
      child: NoOverflowErrorFlex(
        direction: Axis.horizontal,
        children: [
          if (showCheckboxes)
            SizedBox(
              width: 24,
              child: Checkbox(
                value: selectedNodes.contains(node),
                onChanged: (_) {
                  setState(() {
                    if (selectedNodes.contains(node)) {
                      selectedNodes.remove(node);
                    } else {
                      selectedNodes.add(node);
                    }
                    node.numUpdate++;
                  });
                  widget.onSelectionChanged?.call(
                    Set.unmodifiable(selectedNodes),
                  );
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          SizedBox(width: w, child: widget.getHeader(node)),
          _getBtnToogle(node, node.isExpanded),
          _getDrag(rowHeight),
          Expanded(child: widget.getDataRow(node)),
        ],
      ),
    );
  }

  Widget _getDrag(double height) {
    return Draggable<String>(
      onDragUpdate: (details) {
        setState(() {
          repaintInProgess = DateTime.now().millisecondsSinceEpoch;
          dragInProgess = DateTime.now().millisecondsSinceEpoch;
          headerSize = headerSize + details.delta.dx;
          if (headerSize < 100) {
            headerSize = 100;
          }
        });
      },
      data: '',
      feedback: SizedBox(width: 10, height: height),
      childWhenDragging: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        hitTestBehavior: HitTestBehavior.opaque,
        child: SizedBox(width: 10, height: height),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        hitTestBehavior: HitTestBehavior.opaque,
        child: SizedBox(width: 10, height: height),
      ),
    );
  }

  void _toogleChildren(TreeNodeData node, bool invisible) {
    for (var element in node.children ?? const <TreeNodeData>[]) {
      element.isShow = true;
      if (invisible) {
        element.isInvisibleRequested = invisible;
      } else {
        element.isInvisibleRequested = false;
        element.isExpanded = true;
      }
      element.timeChange = DateTime.now().millisecondsSinceEpoch;
      _toogleChildren(element, invisible);
    }
  }

  void _showChildren(TreeNodeData node) {
    for (var element in node.children ?? const <TreeNodeData>[]) {
      if (element.isShow == false) {
        element.isInvisibleRequested = false;
        element.isShow = true;
        element.timeChange = DateTime.now().millisecondsSinceEpoch;
      }
      _showChildren(element);
    }
  }

  Widget _getBtnToogle(TreeNodeData<T> node, bool expanded) {
    return InkWell(
      onTap: () {
        doToogle(node);
      },
      child: SizedBox(
        width: 40,
        child: node.children?.isNotEmpty == true
            ? (expanded
                  ? const Icon(Icons.arrow_drop_down)
                  : const Icon(Icons.arrow_right_sharp))
            : const Text(''),
      ),
    );
  }

  Widget _getAnimatedHeightRow(TreeNodeData node, Widget child, Key key) {
    if (timeBuild - node.timeChange < 500) {
      node.timeChange = 0;
      if (node.isToogleRequested) {
        node.isToogleRequested = false;

        Future.delayed(Duration(milliseconds: animateDelay)).then((value) {
          setState(() {
            // les ligne sont retirer de la fin
            node.isExpanded = false;
          });
        });

        return ClipRect(
          key: key,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: animateDelay),
            builder: (context, value, child) {
              return child!;
            },
            child: child,
          ),
        );
      }

      return ClipRect(
        key: key,
        child: TweenAnimationBuilder<double>(
          tween: node.isInvisibleRequested
              ? Tween(begin: 1, end: 0)
              : Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: animateDelay),
          builder: (context, value, child) {
            return Align(heightFactor: value, child: child);
          },
          onEnd: () {
            if (node.isInvisibleRequested) {
              node.isExpanded = true;
            }
            node.isInvisibleRequested = false;
          },
          child: child,
        ),
      );
    } else {
      return child;
    }
  }

  bool hasStructure(TreeNodeData data) {
    for (var child in data.children ?? const <TreeNodeData>[]) {
      if (child.data is NodeAttribut) {
        var info = child.data as NodeAttribut;
        var type2 = info.info.type.toLowerCase();
        if (type2 == 'object' ||
            type2 == 'array' ||
            type2 == '\$ref' ||
            type2 == '\$anyof') {
          return true;
        }
      }
    }
    return false;
  }

  bool isStructure(TreeNodeData data) {
    if (data.data is NodeAttribut) {
      var info = data.data as NodeAttribut;
      var type2 = info.info.type.toLowerCase();
      if (type2 == 'root' ||
          type2 == 'object' ||
          type2 == 'array' ||
          type2 == '\$ref' ||
          type2 == '\$anyof') {
        return true;
      }
    }
    return false;
  }

  void scrollToData(T attr) {
    int? idx = _findNodeIdxByData(attr, list);
    if (idx != null) {
      idx = idx - 3;
    }
    if (idx != null && idx < 0) {
      idx = 0;
    }

    if (idx != null) {
      _scrollController.animateTo(
        rowHeight * idx,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  int? _findNodeIdxByData(T attr, List<TreeNodeData<T>> list) {
    for (int i = 0; i < list.length; i++) {
      if (list[i].data == attr) {
        return i;
      }
    }
    return null;
  }
}

class IndentInfo {
  final double indent;
  final double start;
  final double end;
  final double height;
  final Color color;

  IndentInfo({
    required this.height,
    required this.color,
    required this.indent,
    required this.start,
    required this.end,
  });
}

class TreeConnector extends StatelessWidget {
  final TreeNodeData node;
  final IndentInfo indentInfo;

  const TreeConnector({
    super.key,
    required this.indentInfo,
    required this.node,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(node.depth * indentInfo.indent, indentInfo.height),
      painter: _TreeConnectorPainter(indentInfo: indentInfo, node: node),
    );
  }
}

class _TreeConnectorPainter extends CustomPainter {
  final TreeNodeData node;
  final IndentInfo indentInfo;

  _TreeConnectorPainter({required this.indentInfo, required this.node});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = indentInfo.color
      ..strokeWidth = 1.5;

    var indentPix = indentInfo.indent * (node.depth - 1);

    final midY = size.height / 2;
    final startX = indentPix + indentInfo.start;
    final endX = indentPix + indentInfo.indent - indentInfo.end;

    // Trait vertical : ajusté si dernier
    final topY = 0.0;
    final bottomY = node.isLast ? midY : size.height;

    canvas.drawLine(Offset(startX, topY), Offset(startX, bottomY), paint);

    // Trait horizontal
    canvas.drawLine(Offset(startX, midY), Offset(endX, midY), paint);
    indentPix = indentInfo.start;
    // print('${node.data} >  ${node.lastChild}');
    for (var i = 1; i < node.listParentIndicator.length; i++) {
      indentPix = indentPix + indentInfo.indent;
      if (!node.listParentIndicator[i]) {
        final startX = indentPix - indentInfo.indent;
        final bottomY = size.height;
        canvas.drawLine(Offset(startX, topY), Offset(startX, bottomY), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class NodeStack {
  final List<TreeNodeData> stack = [];

  void push(TreeNodeData value) {
    stack.add(value);
  }

  TreeNodeData? pop() {
    if (stack.isEmpty) {
      // throw StateError('La pile est vide');
      return null;
    } else {
      return stack.removeLast();
    }
  }

  TreeNodeData peek() {
    if (stack.isEmpty) {
      throw StateError('La pile est vide');
    }
    return stack.last;
  }

  bool get isEmpty => stack.isEmpty;

  int get length => stack.length;

  void clear() => stack.clear();
}

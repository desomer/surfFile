import 'package:assorted_layout_widgets/assorted_layout_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';


class BreadCrumbNavigator extends StatefulWidget {
  //static NavigationInfo? currentNavigationInfo;
  static GlobalKey keyBreadcrumb = GlobalKey(debugLabel: 'keyBreadcrumb');

  const BreadCrumbNavigator({
    super.key,
    required this.getList,
    //required this.getShowCaseInfo,
  });
  final Function getList;
  //final ShowCaseInfo Function() getShowCaseInfo;

  @override
  State<StatefulWidget> createState() {
    return _BreadCrumbNavigatorState();
  }
}

// class BreadNode {
//   BreadNode({required this.name});
//   String name;
//   String? tooltip;
//   Function? onTap;
// }

const _textStyle = TextStyle(color: Colors.white, fontSize: 15);
const _textStyleDisable = TextStyle(color: Colors.grey, fontSize: 15);

class _BreadCrumbNavigatorState extends State<BreadCrumbNavigator> {
  @override
  Widget build(BuildContext context) {
    List<BreadNode> currentPathOnStack = [];
    List<BreadNode> listPath = widget.getList();
    int i = 0;
    for (var element in listPath) {
      currentPathOnStack.add(element..idx = i);
      i++;
    }

    List<Widget> widgets = [];
    int index = 0;
    for (BreadNode route in currentPathOnStack) {
      Widget? nestedWidget;

      // if (route.type == BreadNodeType.domain) {
      //   GlobalKey keyDomain = GlobalKey(debugLabel: 'keyDomain');
      //   nestedWidget = InkWell(
      //     onTap: () {
            
      //     },
      //     child: SizedBox(
      //       key: widget.getShowCaseInfo().keys['domain'] = keyDomain,
      //       height: 18,
      //       child: Row(
      //         spacing: 5,
      //         children: [
      //           Icon(Icons.domain, size: 18),
      //           Text(
      //             currentCompany.listDomain?.selectedAttr?.info.name ?? '?',
      //             style: _textStyle,
      //           ),
      //           Icon(Icons.arrow_drop_down, size: 20),
      //         ],
      //       ),
      //     ),
      //   );
      // }

      var enable =
          route.type == BreadNodeType.domain ||
          (route.path != null || route.onTap != null);

      Widget btn = _BreadButton(
        route.type,
        //key: route.key,
        currentPathOnStack[index].settings.name ?? '',
        index == 0,
        enable,
        child: nestedWidget,
      );

      if (route.onTap != null || route.path != null) {
        btn = InkWell(
          onTap: () {
            if (route.type == BreadNodeType.link) {
              Clipboard.setData(ClipboardData(text: route.path!));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Link copied to clipboard')),
              );
              return;
            }

            if (route.onTap != null) {
              route.onTap!();
            }
            if (route.path != null) {
              //RouteManager.goto(route.path!, context);
            }
          },
          child: btn,
        );
      }

      widgets.add(Tooltip(message: route.tooltip ?? 'help', child: btn));

      index++;
    }

    return RowSuper(
      mainAxisSize: MainAxisSize.min,
      innerDistance: -15,
      children: widgets,
    );
  }
}

enum BreadNodeType { widget, domain, link }

class BreadNode extends Route {
  BreadNode({
    super.settings,
    required this.type,
    this.icon,
    this.path,
    this.onTap,
    this.key,
  });

  int idx = 0;
  Icon? icon;
  BreadNodeType type;
  String? tooltip;
  String? path;
  Function? onTap;
  GlobalKey<State<StatefulWidget>>? key;
}

class _BreadButton extends StatelessWidget {
  final String text;
  final bool isFirstButton;
  final BreadNodeType type;
  final Widget? child;

  final bool enable;

  // ignore: unused_element_parameter
  const _BreadButton(
    this.type,
    this.text,
    this.isFirstButton,
    this.enable, {
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    var color = type == BreadNodeType.domain
        ? Colors.blue
        : enable
        ? Colors.blue.withAlpha(50)
        : Theme.of(context).highlightColor;

    if (type == BreadNodeType.link) {
      color = Colors.blue.withAlpha(50);
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 0, 0),
        child: Icon(Icons.link, color: Colors.grey),
      );
    }

    return ClipPath(
      clipper: TriangleClipper(!isFirstButton),
      child: Container(
        key: key,
        color: color,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: isFirstButton ? 8 : 30,
            end: 28,
            top: 8,
            bottom: 8,
          ),
          child:
              child ??
              Text(text, style: enable ? _textStyle : _textStyleDisable),
        ),
      ),
    );
  }
}

class TriangleClipper extends CustomClipper<Path> {
  final bool twoSideClip;

  TriangleClipper(this.twoSideClip);

  @override
  Path getClip(Size size) {
    final Path path = Path();
    if (twoSideClip) {
      path.moveTo(0, 0.0);
      path.lineTo(20.0, size.height / 2);
      path.lineTo(0, size.height);
    } else {
      path.lineTo(0, size.height);
    }
    path.lineTo(size.width - 20, size.height);
    path.lineTo(size.width, size.height / 2);
    path.lineTo(size.width - 20, 0);
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) {
    return true;
  }
}

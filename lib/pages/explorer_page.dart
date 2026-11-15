import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_page.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_surface.dart';

import '../actions/file_actions.dart';
import '../theme/surffile_appearance_slots.dart';
import '../widgets/explorer/explorer_pane.dart';
import '../widgets/file_operations/file_action_bar.dart';
import '../widgets/file_operations/transfer_panel.dart';

export '../widgets/explorer/explorer_pane.dart';

class ExplorerPage extends StatefulWidget {
  const ExplorerPage({super.key});

  @override
  State<ExplorerPage> createState() => _ExplorerPageState();
}

/// Héberge un ou deux [ExplorerPane] côte à côte (mode divisé).
class _ExplorerPageState extends State<ExplorerPage> {
  final _panes = [
    GlobalKey<ExplorerPaneState>(),
    GlobalKey<ExplorerPaneState>(),
  ];
  final _paths = <String?>[null, null];
  bool _split = false;
  int _active = 0;

  void _toggleSplit() => setState(() {
    _split = !_split;
    _active = _split ? 1 : 0;
    _paths[1] = null;
  });

  void _activate(int pane) {
    if (_active != pane) setState(() => _active = pane);
  }

  void _pathChanged(int pane, String path) {
    if (_paths[pane] != path) {
      setState(() => _paths[pane] = path);
    } else if (pane == 1) {
      _panes[0].currentState?.touch();
    }
  }

  /// Contexte des actions de la barre centrale ; `null` si un volet manque.
  FileActionContext? _actionContext() {
    final left = _panes[0].currentState;
    final right = _panes[1].currentState;
    if (left == null || right == null || !left.ready || !right.ready) {
      return null;
    }
    return FileActionContext(
      left: left.snapshot,
      right: right.snapshot,
      navigate: (leftPath, rightPath) =>
          Future.wait([left.navigate(leftPath), right.navigate(rightPath)]),
      refresh: () => Future.wait([left.refresh(), right.refresh()]),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return EditableSurface(
      slot: SurfFileAppearanceSlots.background,
      decorate: false,
      applyPadding: true,
      child: SuperPage(
        child: Stack(
          children: [
            Positioned.fill(child: _panesView()),
            const Positioned(
              top: 56,
              right: 16,
              bottom: 16,
              child: Align(
                alignment: Alignment.topRight,
                child: SingleChildScrollView(child: TransferPanel()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panesView() {
    return ExplorerPane(
      key: _panes[0],
      split: _split,
      active: _split && _active == 0,
      onActivate: () => _activate(0),
      onPathChanged: (path) => _pathChanged(0, path),
      onToggleSplit: _toggleSplit,
      sidebarPath: _split ? _paths[_active] : null,
      onSidebarLocation: _split
          ? (path) => _panes[_active].currentState?.navigate(path)
          : null,
      splitBarBuilder: (_) => FileActionBar(
        actionContext: _actionContext(),
        onMessage: _showMessage,
      ),
      splitChild: _split
          ? ExplorerPane(
              key: _panes[1],
              initialPath: _paths[0],
              showSidebar: false,
              autofocus: false,
              split: true,
              active: _active == 1,
              onActivate: () => _activate(1),
              onPathChanged: (path) => _pathChanged(1, path),
              onSelectionChanged: () => _panes[0].currentState?.touch(),
              onToggleSplit: _toggleSplit,
            )
          : null,
    );
  }
}

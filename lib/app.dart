import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/models/registry.dart';

import 'pages/explorer_page.dart';
import 'services/appearance_store.dart';
import 'theme/surffile_appearance_scope.dart';
import 'widgets/explorer/explorer_components.dart';

class SurfFileApp extends StatefulWidget {
  const SurfFileApp({super.key});

  @override
  State<SurfFileApp> createState() => _SurfFileAppState();
}

class _SurfFileAppState extends State<SurfFileApp> {
  final _registry = Registry();
  final _appearanceStore = AppearanceStore();
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    registerExplorerComponents(_registry);
    _router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => SurfFilePreferencesScope(
            controller: _appearanceStore.preferences,
            child: const ExplorerPage(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => SuperApp(
    router: _router,
    registry: _registry,
    appearanceStore: _appearanceStore,
    title: 'Surf File V 0.0.1 by Gauthier Desomer',
  );
  
  @override
  void dispose() {
    _router.dispose();
    _appearanceStore.preferences.dispose();
    super.dispose();
  }
}

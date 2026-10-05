import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/models/registry.dart';

import 'pages/explorer_page.dart';
import 'services/appearance_store.dart';
import 'widgets/explorer/explorer_components.dart';

class SurfFileApp extends StatefulWidget {
  const SurfFileApp({super.key});

  @override
  State<SurfFileApp> createState() => _SurfFileAppState();
}

class _SurfFileAppState extends State<SurfFileApp> {
  final _registry = Registry();
  final _appearanceStore = AppearanceStore();

  @override
  void initState() {
    super.initState();
    registerExplorerComponents(_registry);
  }

  @override
  Widget build(BuildContext context) => SuperApp(
    registry: _registry,
    appearanceStore: _appearanceStore,
    title: 'Surf File V 0.0.1 by Gauthier Desomer',
    home: const ExplorerPage(),
  );
  
}

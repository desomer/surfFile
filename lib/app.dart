import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_app.dart';

import 'pages/explorer_page.dart';

class SurfFileApp extends StatelessWidget {
  const SurfFileApp({super.key});

  @override
  Widget build(BuildContext context) => const SuperApp(
    title: 'Surf File V 0.0.1 by Gauthier Desomer',
    home: ExplorerPage(),
  );
  
}

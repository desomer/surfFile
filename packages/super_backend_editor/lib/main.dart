/// Point d'entrée Desktop de l'application `SuperBackendEditor`.
library;

import 'package:material_ui/material_ui.dart';

/// Lance l'application de bureau `SuperBackendEditor`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SuperBackendEditorApp());
}

/// Application racine `SuperBackendEditor` (socle initial avant intégration du shell complet).
@immutable
class SuperBackendEditorApp extends StatelessWidget {
  /// Crée l'application `SuperBackendEditor`.
  const SuperBackendEditorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SuperBackendEditor',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F766E),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: const Scaffold(
      body: Center(
        child: Text('SuperBackendEditor'),
      ),
    ),
  );
}

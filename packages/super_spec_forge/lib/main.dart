/// Point d'entrée de l'application autonome `super_spec_forge`.
///
/// Initialise la clé API Gemini via [resolveGeminiApiKey], charge le dernier
/// projet depuis [SpecProjectStore] et lance [SuperSpecForgeApp].
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:super_container_layout/super_container_layout.dart';

import 'super_spec_forge.dart';

/// Lance l'application autonome `SuperSpecForge`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final geminiKey = await resolveGeminiApiKey();
  if (!dotenv.isInitialized) {
    dotenv.loadFromString(envString: '', isOptional: true);
  }
  if (geminiKey.isNotEmpty) {
    unawaited(
      const GeminiSpecAiService().warmUp(SpecForgeStage.vision),
    );
  }
  runApp(const SuperSpecForgeApp());
}

/// Widget racine de l'application `SuperSpecForge`.
class SuperSpecForgeApp extends StatefulWidget {
  /// Crée l'application avec un contrôleur optionnel (utile pour les tests).
  const SuperSpecForgeApp({
    this.controller,
    this.restoreLastProject = true,
    super.key,
  });

  /// Contrôleur injectable pour les tests ou l'intégration hôte.
  final SpecForgeController? controller;

  /// Indique si le dernier projet actif doit être rechargé automatiquement.
  final bool restoreLastProject;

  @override
  State<SuperSpecForgeApp> createState() => _SuperSpecForgeAppState();
}

class _SuperSpecForgeAppState extends State<SuperSpecForgeApp> {
  late final SpecForgeController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? SpecForgeController();
    unawaited(
      _controller.initialize(restoreLastProject: widget.restoreLastProject),
    );
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SuperSpecForge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3F51B5),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF5C6BC0),
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: SpecForgeShell(controller: _controller),
    );
  }
}

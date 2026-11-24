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

/// Lance l'application autonome `SuperSpecForge` en capturant les journaux et erreurs.
void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = '[FLUTTER ERROR] ${details.exceptionAsString()}';
    saveError(message, details.stack);
    FlutterError.dumpErrorToConsole(details);
  };

  runZonedGuarded(
    () async {
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
    },
    (error, stack) {
      final message = '[DART ERROR] $error\n$stack';
      saveError(message, stack);
      FlutterError.dumpErrorToConsole(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        saveLog(line, null);
        parent.print(zone, line);
      },
    ),
  );
}

/// Widget racine de l'application `SuperSpecForge`.
class SuperSpecForgeApp extends StatefulWidget {
  /// Crée l'application avec un contrôleur optionnel (utile pour les tests).
  const SuperSpecForgeApp({
    this.controller,
    this.restoreLastProject = true,
    this.pickAttachments,
    this.pasteAttachments,
    this.hasClipboardMedia,
    this.pasteClipboardMedia,
    this.pickDirectory,
    super.key,
  });

  /// Contrôleur injectable pour les tests ou l'intégration hôte.
  final SpecForgeController? controller;

  /// Indique si le dernier projet actif doit être rechargé automatiquement.
  final bool restoreLastProject;

  /// Sélecteur optionnel de pièces jointes pour le chat IA.
  final Future<List<VibeChatAttachment>> Function()? pickAttachments;

  /// Lecteur optionnel du presse-papiers pour le chat IA.
  final Future<List<VibeChatAttachment>> Function()? pasteAttachments;

  /// Prédicat optionnel indiquant la présence d'un média dans le presse-papiers.
  final bool Function()? hasClipboardMedia;

  /// Lecteur optionnel d'images/fichiers du presse-papiers sur `Ctrl+V`.
  final Future<List<VibeChatAttachment>> Function()? pasteClipboardMedia;

  /// Sélecteur de dossier personnalisable pour le choix du workspace Git.
  final DirectoryPickerCallback? pickDirectory;

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
        appBarTheme: const AppBarTheme(toolbarHeight: 40),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF5C6BC0),
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(toolbarHeight: 40),
      ),
      themeMode: ThemeMode.system,
      home: SpecForgeShell(
        controller: _controller,
        pickAttachments: widget.pickAttachments,
        pasteAttachments: widget.pasteAttachments,
        hasClipboardMedia: widget.hasClipboardMedia,
        pasteClipboardMedia: widget.pasteClipboardMedia,
        pickDirectory: widget.pickDirectory,
      ),
    );
  }
}

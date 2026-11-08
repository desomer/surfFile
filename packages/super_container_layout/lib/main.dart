/// Point d'entrée de l'application autonome de démonstration de `super_container_layout`.
///
/// Charge les variables d'environnement (`flutter_dotenv`), initialise [SuperApp]
/// avec [DefaultAppearanceCodec] et monte une [SuperPage] d'exemple.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:super_container_layout/models/registry.dart';
import 'package:super_container_layout/models/super_layout_config.dart';
import 'package:super_container_layout/super_app.dart';
import 'package:super_container_layout/super_page.dart';
import 'package:super_container_layout/services/pages/editor_page_router.dart';
import 'package:super_container_layout/theme/appearance_slot.dart';
import 'package:super_container_layout/widgets/appearance/appearance_toolbar.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_surface.dart';
import 'package:super_container_layout/widgets/components/super_layout/super_layout.dart';

export 'package:super_container_layout/models/registry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var envText = '';
  final sep = Platform.pathSeparator;
  final paths = [
    'env',
    '.env',
    ['packages', 'super_container_layout', 'env'].join(sep),
    ['packages', 'super_container_layout', '.env'].join(sep),
    ['packages', 'super_designer', 'env'].join(sep),
    ['packages', 'super_designer', '.env'].join(sep),
    ['..', 'super_container_layout', 'env'].join(sep),
    ['..', 'super_container_layout', '.env'].join(sep),
    ['..', 'super_designer', 'env'].join(sep),
    ['..', 'super_designer', '.env'].join(sep),
    ['..', 'env'].join(sep),
    ['..', '.env'].join(sep),
  ];
  for (final path in paths) {
    final file = File(path);
    if (await file.exists()) {
      envText = await file.readAsString();
      break;
    }
  }
  if (envText.isEmpty) {
    try {
      var dir = Directory.current;
      while (true) {
        for (final candidate in [
          'env',
          '.env',
          ['packages', 'super_container_layout', 'env'].join(sep),
          ['packages', 'super_designer', 'env'].join(sep),
        ]) {
          final file = File('${dir.path}$sep$candidate');
          if (await file.exists()) {
            envText = await file.readAsString();
            break;
          }
        }
        if (envText.isNotEmpty || dir.parent.path == dir.path) break;
        dir = dir.parent;
      }
    } catch (_) {}
  }
  final environmentKey = Platform.environment['GEMINI_API_KEY'];
  dotenv.loadFromString(
    envString: envText,
    isOptional: true,
    mergeWith: environmentKey == null
        ? const {}
        : {'GEMINI_API_KEY': environmentKey},
  );
  runApp(const TestApp());
}

/// Widget racine de l'application de démonstration autonome du package.
class TestApp extends StatefulWidget {
  const TestApp({super.key});

  @override
  State<TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<TestApp> {
  final _registry = Registry()..bootstrap();
  late final EditorPageRouter _pageRouting;
  GoRouter get _router => _pageRouting.router;

  @override
  void initState() {
    super.initState();
    _pageRouting = EditorPageRouter(
      baseConfig: RoutingConfig(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => getRootWidget(_registry),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageRouting.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SuperApp(
    router: _router,
    pageRouting: _pageRouting,
    title: 'Card Layout demo',
    registry: _registry,
  );

  Widget getRootWidget(Registry registry) {
    return Builder(
      builder: (context) {
        final superapp = SuperApp.of(context);
        var superLayoutConfig = superapp.getLayoutConfigById('mainLayout');

        return EditableSurface(
          slot: AppearanceSlot(
            'Fond',
            name: 'demo-background',
            role: AppearanceSurfaceRole.applicationBackground,
            editShape: false,
            extendedLook: false,
            read: (a) => a.backgroundStyle,
            write: (a, style) => a.withStyle('background', style),
            reset: (a) => a.withStyle('background', null),
          ),
          menuIcon: Icons.wallpaper_outlined,
          decorate: false,
          applyPadding: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: SuperPage(
                  menuIcon: Icons.article_outlined,
                  child: ValueListenableBuilder<SuperLayoutConfig>(
                    valueListenable: superLayoutConfig,
                    builder: (context, config, _) => SuperLayout(
                      label: 'Main Layout',
                      config: config,
                      onChanged: (value) => superLayoutConfig.value = value,
                      menuIcon: Icons.dashboard_outlined,
                      slots: const [],
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: FloatingAppearanceToolbar(),
              ),
            ],
          ),
        );
      },
    );
  }
}

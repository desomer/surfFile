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
import 'package:super_container_layout/widgets/appearance/appearance_settings.dart';
import 'package:super_container_layout/widgets/editing/slots/editable_surface.dart';
import 'package:super_container_layout/widgets/editing/slots/editor_slot.dart';
import 'package:super_container_layout/widgets/super_layout/super_layout.dart';

export 'package:super_container_layout/models/registry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var envText = '';
  final paths = [
    'env',
    'packages${Platform.pathSeparator}super_container_layout${Platform.pathSeparator}env',
  ];
  for (final path in paths) {
    final file = File(path);
    if (await file.exists()) {
      envText = await file.readAsString();
      break;
    }
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

class TestApp extends StatefulWidget {
  const TestApp({super.key});

  @override
  State<TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<TestApp> {
  final _registry = Registry()..bootstrap();
  late final EditorPageRouter _pageRouting;
  GoRouter get _router => _pageRouting.router;
  _ToolbarLayout _toolbarLayout = _ToolbarLayout(null);

  @override
  void initState() {
    super.initState();
    _registry.registerFactory(
      'A',
      const EditableSurface(
        label: "AB",
        child: Center(child: Text('A')),
      ),
    );
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
        var superLayoutConfig = superapp.getLayoutConfigById('contA');

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
                      config: config,
                      onChanged: (value) => superLayoutConfig.value = value,
                      menuIcon: Icons.dashboard_outlined,
                      slots: const [],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomSingleChildLayout(
                  delegate: _toolbarLayout,
                  child: Material(
                    key: const ValueKey('appearance-toolbar'),
                    type: MaterialType.card,
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    child: SingleChildScrollView(child: overlyRight(context)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget overlyRight(BuildContext context) {
    return Builder(
      builder: (context) {
        if (StyleEditScope.controllerOf(context) case final editMode?) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'Déplacer la barre',
                child: MouseRegion(
                  cursor: SystemMouseCursors.move,
                  child: GestureDetector(
                    key: const ValueKey('appearance-toolbar-drag'),
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) => setState(() {
                      _toolbarLayout = _ToolbarLayout(
                        _toolbarLayout.resolvedPosition + details.delta,
                      );
                    }),
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(Icons.drag_indicator, size: 20),
                    ),
                  ),
                ),
              ),
              _NavigationButton(
                key: const ValueKey('style-edit-mode'),
                tooltip: editMode.value
                    ? 'Quitter l’édition du style'
                    : 'Éditer le style (clic droit sur une zone)',
                icon: Icons.brush_outlined,
                selected: editMode.value,
                onPressed: () => editMode.value = !editMode.value,
              ),
              _NavigationButton(
                key: const ValueKey('appearance-settings'),
                tooltip: 'Paramètres d’apparence',
                icon: Icons.settings_outlined,
                onPressed: () => AppearanceSettings.show(context),
              ),
            ],
          );
        }
        return const SizedBox();
      },
    );

    // Removed as it's now handled inside the Builder above.
  }
}

class _ToolbarLayout extends SingleChildLayoutDelegate {
  _ToolbarLayout(this.position) : resolvedPosition = position ?? Offset.zero;

  final Offset? position;
  Offset resolvedPosition;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final desired = position ?? Offset(size.width - childSize.width - 16, 56);
    resolvedPosition = Offset(
      desired.dx.clamp(
        0.0,
        (size.width - childSize.width).clamp(0.0, double.infinity),
      ),
      desired.dy.clamp(
        0.0,
        (size.height - childSize.height).clamp(0.0, double.infinity),
      ),
    );
    return resolvedPosition;
  }

  @override
  bool shouldRelayout(_ToolbarLayout oldDelegate) =>
      position != oldDelegate.position;
}

class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    isSelected: selected,
    icon: Icon(icon, size: 20),
    style: IconButton.styleFrom(
      minimumSize: const Size(36, 36),
      maximumSize: const Size(36, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      foregroundColor: selected
          ? Theme.of(context).colorScheme.onPrimaryContainer
          : Theme.of(context).colorScheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

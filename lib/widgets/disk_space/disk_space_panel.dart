import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surf_file/theme/surffile_appearance.dart';
import '../../theme/surffile_appearance_slots.dart';
import 'package:super_container_layout/widgets/super_container.dart';

import '../../services/disk_space.dart';
import 'disk_gauge.dart';
import 'disk_gauge_style_editor.dart';

class DiskSpacePanel extends StatefulWidget {
  const DiskSpacePanel({required this.onNavigate, this.currentPath, super.key});

  final ValueChanged<String> onNavigate;

  /// Dossier affiché : le disque qui le contient est mis en évidence.
  final String? currentPath;

  @override
  State<DiskSpacePanel> createState() => _DiskSpacePanelState();
}

class _DiskSpacePanelState extends State<DiskSpacePanel>
    with WidgetsBindingObserver {
  List<DiskSpace>? _disks;
  String? _error;
  bool _loading = false;

  /// Incrémenté à chaque lecture pour rejouer le remplissage des jauges.
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final disks = await DiskSpace.load();
      if (!mounted) return;
      setState(() {
        _disks = disks;
        _error = null;
        _revision++;
      });
    } on PlatformException catch (error) {
      _failed(error);
    } on MissingPluginException catch (error) {
      _failed(error);
    } on FormatException catch (error) {
      _failed(error);
    } on UnsupportedError catch (error) {
      _failed(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _failed(Object error) {
    debugPrint('Error loading disk space: $error');
    if (mounted) {
      setState(() => _error = 'Impossible de lire les disques.');
    }
  }

  /// Disques en cours d'éjection.
  final _ejecting = <String>{};

  Future<void> _eject(DiskSpace disk) async {
    if (!_ejecting.add(disk.path)) return;
    setState(() {});
    final messenger = ScaffoldMessenger.maybeOf(context);
    // Quitter le disque avant de l'éjecter : la vue ne doit pas le garder
    // ouvert (listage, aperçus, calcul de tailles).
    if (_selectedPath == disk.path) {
      final fallback = _disks!.where((other) => !other.ejectable).firstOrNull;
      if (fallback != null) widget.onNavigate(fallback.path);
    }
    String message;
    try {
      await DiskSpace.eject(disk.path);
      message = 'Vous pouvez retirer ${disk.path} en toute sécurité.';
    } on PlatformException catch (error) {
      message = error.code == 'in_use'
          ? 'Impossible d’éjecter ${disk.path} : des fichiers sont encore '
                'ouverts.'
          : 'Impossible d’éjecter ${disk.path} : ${error.message ?? error.code}';
    } on MissingPluginException {
      message = 'L’éjection n’est pas disponible.';
    }
    messenger?.showSnackBar(SnackBar(content: Text(message)));
    if (!mounted) return;
    setState(() => _ejecting.remove(disk.path));
    await _load();
  }

  /// Disque contenant [DiskSpacePanel.currentPath] (préfixe le plus long).
  String? get _selectedPath {
    final current = widget.currentPath?.toLowerCase();
    if (current == null || _disks == null) return null;
    String? best;
    for (final disk in _disks!) {
      final root = disk.path.toLowerCase();
      final prefix = root.endsWith('\\') ? root : '$root\\';
      if ((current == root ||
              current.startsWith(prefix) ||
              '$current\\' == prefix) &&
          (best == null || disk.path.length > best.length)) {
        best = disk.path;
      }
    }
    return best;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final appearance = AppearanceScope.of(context);
    final foreground =
        appearance.style('diskPanel').foreground ??
        appearance.style('sidebar').foreground ??
        colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: SuperContainer(
        key: const ValueKey('disk-panel-surface'),
        slot: SurfFileAppearanceSlots.diskPanel,
        fallbackColor: Colors.transparent,
        borderColor: foreground.withValues(alpha: .12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'DISQUES',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser les disques',
                  onPressed: _loading ? null : _load,
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: foreground,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (_error != null)
              Column(
                children: [
                  Text(
                    _error!,
                    style: TextStyle(color: foreground, fontSize: 12),
                  ),
                  TextButton(onPressed: _load, child: const Text('Réessayer')),
                ],
              )
            else if (_disks == null)
              const Center(child: CircularProgressIndicator())
            else if (_disks!.isEmpty)
              Text(
                'Aucun disque disponible.',
                style: TextStyle(color: foreground, fontSize: 12),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = SurfFilePreferencesScope.of(context).diskGaugeStyle.columns;
                  final selectedPath = _selectedPath;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final disk in _disks!)
                        SizedBox(
                          width:
                              (constraints.maxWidth - 8 * (columns - 1)) /
                              columns,
                          child: _DiskTile(
                            disk: disk,
                            revision: _revision,
                            selected: disk.path == selectedPath,
                            onTap: () => widget.onNavigate(disk.path),
                            ejecting: _ejecting.contains(disk.path),
                            onEject: disk.ejectable ? () => _eject(disk) : null,
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _DiskTile extends StatelessWidget {
  const _DiskTile({
    required this.disk,
    required this.revision,
    required this.selected,
    required this.onTap,
    this.ejecting = false,
    this.onEject,
  });

  final DiskSpace disk;
  final int revision;
  final bool selected;
  final VoidCallback onTap;
  final bool ejecting;

  /// Éjection du disque, `null` s'il n'est pas éjectable.
  final VoidCallback? onEject;

  String _capacity(int bytes) {
    const gib = 1024 * 1024 * 1024;
    const tib = gib * 1024;
    return bytes >= tib
        ? '${(bytes / tib).toStringAsFixed(1)} Tio'
        : '${(bytes / gib).toStringAsFixed(1)} Gio';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final appearance = AppearanceScope.of(context);
    final style =
        (selected
                ? SurfFileAppearanceSlots.selectedDiskTile
                : SurfFileAppearanceSlots.diskTile)
            .read(appearance);
    final gauge = SurfFilePreferencesScope.of(context).diskGaugeStyle;
    final foreground =
        style.foreground ??
        (selected
            ? colors.onPrimaryContainer
            : appearance.style('diskPanel').foreground ??
                  appearance.style('sidebar').foreground ??
                  colors.onSurface);
    final used = disk.usedFraction;
    final percentage = used == null ? null : (used * 100).round();
    final description = used == null
        ? 'Espace indisponible : ${disk.error}'
        : '${_capacity(disk.freeBytes!)} libres sur ${_capacity(disk.totalBytes!)}';
    return Tooltip(
      message: '${disk.path}\n$description',
      child: Semantics(
        label:
            '${disk.path}${selected ? ', sélectionné' : ''}, ${percentage == null ? description : '$percentage % occupé, $description'}',
        child: SuperContainer(
          key: ValueKey('disk-tile-${disk.path}'),
          slot: selected
              ? SurfFileAppearanceSlots.selectedDiskTile
              : SurfFileAppearanceSlots.diskTile,
          fallbackColor: selected
              ? colors.primaryContainer
              : foreground.withValues(alpha: .04),
          borderColor: selected
              ? colors.primary
              : foreground.withValues(alpha: .12),
          child: Stack(
            children: [
              InkWell(
                onTap: onTap,
                borderRadius: style.borderRadius,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                  child: Column(
                    children: [
                      SuperContainer(
                        key: ValueKey('disk-gauge-${disk.path}'),
                        decorate: false,
                        label: 'Style de la jauge des disques',
                        onEdit: () => showDiskGaugeStyleEditor(context),
                        child: DiskGauge(
                          value: used,
                          style: gauge,
                          revision: revision,
                          fillColor: gauge.fillColor ?? colors.primary,
                          alertColor: gauge.alertColor ?? colors.error,
                          trackColor:
                              gauge.trackColor ?? foreground.withValues(alpha: .12),
                          foreground: foreground,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        disk.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: gauge.nameSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        used == null
                            ? 'Indisponible'
                            : '${_capacity(disk.freeBytes!)} libres',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: foreground,
                          fontSize: gauge.captionSize,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (onEject != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: ejecting
                      ? Padding(
                          padding: const EdgeInsets.all(6),
                          child: SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: foreground,
                            ),
                          ),
                        )
                      : IconButton(
                          key: ValueKey('disk-eject-${disk.path}'),
                          tooltip: 'Éjecter ${disk.path}',
                          onPressed: onEject,
                          icon: Icon(
                            Icons.eject_rounded,
                            size: 16,
                            color: foreground,
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 26,
                            height: 26,
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

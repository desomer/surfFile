import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../services/disk_space.dart';
import '../theme/appearance.dart';

class DiskSpacePanel extends StatefulWidget {
  const DiskSpacePanel({required this.onNavigate, super.key});

  final ValueChanged<String> onNavigate;

  @override
  State<DiskSpacePanel> createState() => _DiskSpacePanelState();
}

class _DiskSpacePanelState extends State<DiskSpacePanel>
    with WidgetsBindingObserver {
  List<DiskSpace>? _disks;
  String? _error;
  bool _loading = false;

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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = AppearanceScope.of(context).sidebarStyle.foreground ??
        colors.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text('DISQUES',
                  style: TextStyle(
                      color: foreground,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1)),
            ),
            IconButton(
              tooltip: 'Actualiser les disques',
              onPressed: _loading ? null : _load,
              icon: Icon(Icons.refresh_rounded, size: 16, color: foreground),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          if (_error != null)
            Column(children: [
              Text(_error!, style: TextStyle(color: foreground, fontSize: 12)),
              TextButton(onPressed: _load, child: const Text('Réessayer')),
            ])
          else if (_disks == null)
            const Center(child: CircularProgressIndicator())
          else if (_disks!.isEmpty)
            Text('Aucun disque disponible.',
                style: TextStyle(color: foreground, fontSize: 12))
          else
            LayoutBuilder(
                builder: (context, constraints) => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final disk in _disks!)
                          SizedBox(
                            width: (constraints.maxWidth - 8) / 2,
                            child: _DiskTile(
                              disk: disk,
                              onTap: () => widget.onNavigate(disk.path),
                            ),
                          ),
                      ],
                    )),
        ],
      ),
    );
  }
}

class _DiskTile extends StatelessWidget {
  const _DiskTile({required this.disk, required this.onTap});

  final DiskSpace disk;
  final VoidCallback onTap;

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
    final foreground =
        AppearanceScope.of(context).sidebarStyle.foreground ?? colors.onSurface;
    final used = disk.usedFraction;
    final percentage = used == null ? null : (used * 100).round();
    final description = used == null
        ? 'Espace indisponible : ${disk.error}'
        : '${_capacity(disk.freeBytes!)} libres sur ${_capacity(disk.totalBytes!)}';
    return Tooltip(
      message: '${disk.path}\n$description',
      child: Semantics(
        label:
            '${disk.path}, ${percentage == null ? description : '$percentage % occupé, $description'}',
        child: Material(
          color: foreground.withValues(alpha: .04),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: foreground.withValues(alpha: .12))),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              child: Column(children: [
                SizedBox(
                  width: 62,
                  height: 62,
                  child: Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: used ?? 0,
                        strokeWidth: 5,
                        backgroundColor: foreground.withValues(alpha: .12),
                        color: used != null && used >= .9
                            ? Colors.red
                            : colors.primary,
                      ),
                    ),
                    Text(percentage == null ? '—' : '$percentage %',
                        style: TextStyle(
                            color: foreground,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
                const SizedBox(height: 10),
                Text(disk.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                    used == null
                        ? 'Indisponible'
                        : '${_capacity(disk.freeBytes!)} libres',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: foreground, fontSize: 10)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

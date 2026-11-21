/// Boîte de dialogue de sélection et création de dossier Workspace Git ([SpecWorkspaceSelectorDialog]).
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:super_container_layout/super_container_layout.dart';

import '../services/spec_forge_controller.dart';
import '../services/spec_storage_slug.dart';
import '../services/spec_workspace_store.dart';

enum _WorkspaceDialogMode { recent, openPath, create }

/// Dialogue permettant de basculer vers un autre dossier Workspace Git
/// ou d'en initialiser un nouveau.
class SpecWorkspaceSelectorDialog extends StatefulWidget {
  /// Crée le dialogue connecté au [controller].
  const SpecWorkspaceSelectorDialog({
    required this.controller,
    this.pickDirectory,
    super.key,
  });

  /// Contrôleur principal gérant le workspace actif.
  final SpecForgeController controller;

  /// Sélecteur de dossier injectable (Windows natif par défaut si `null`).
  final DirectoryPickerCallback? pickDirectory;

  /// Ouvre le dialogue modal et retourne `true` si le workspace a changé.
  static Future<bool> show(
    BuildContext context, {
    required SpecForgeController controller,
    DirectoryPickerCallback? pickDirectory,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SpecWorkspaceSelectorDialog(
        controller: controller,
        pickDirectory: pickDirectory,
      ),
    );
    return result == true;
  }

  @override
  State<SpecWorkspaceSelectorDialog> createState() =>
      _SpecWorkspaceSelectorDialogState();
}

class _SpecWorkspaceSelectorDialogState
    extends State<SpecWorkspaceSelectorDialog> {
  _WorkspaceDialogMode _mode = _WorkspaceDialogMode.recent;
  bool _busy = false;
  String? _error;
  bool _pendingNonEmptyConfirm = false;

  late final TextEditingController _openPathController;
  late final TextEditingController _createNameController;
  late final TextEditingController _createPathController;
  bool _createPathManuallyEdited = false;

  @override
  void initState() {
    super.initState();
    final currentPath = widget.controller.workspaceDirectory.path;
    _openPathController = TextEditingController(text: currentPath);
    _createNameController = TextEditingController(text: 'Mes spécifications');
    final parentPath = Directory(currentPath).parent.path;
    _createPathController = TextEditingController(
      text: '$parentPath${Platform.pathSeparator}mes-specifications',
    );
    if (widget.controller.recentWorkspaces.isEmpty) {
      _mode = _WorkspaceDialogMode.openPath;
    }
  }

  @override
  void dispose() {
    _openPathController.dispose();
    _createNameController.dispose();
    _createPathController.dispose();
    super.dispose();
  }

  Future<void> _browseFor(TextEditingController target) async {
    final picker =
        widget.pickDirectory ?? ApplicationSelectorDialog.pickDirectoryNative;
    final initial = target.text.trim().isNotEmpty
        ? target.text.trim()
        : widget.controller.workspaceDirectory.path;
    final picked = await picker(initial);
    if (!mounted || picked == null || picked.trim().isEmpty) return;
    setState(() {
      target.text = picked.trim();
      if (identical(target, _createPathController)) {
        _createPathManuallyEdited = true;
      }
      _error = null;
      _pendingNonEmptyConfirm = false;
    });
  }

  Future<void> _openDirectory(
    Directory dir, {
    bool initializeNonEmpty = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _pendingNonEmptyConfirm = false;
    });
    try {
      await widget.controller.switchWorkspace(
        dir,
        initializeNonEmpty: initializeNonEmpty,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on NonEmptyNonWorkspaceException catch (err) {
      if (mounted) {
        setState(() {
          _error = err.message;
          _pendingNonEmptyConfirm = true;
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() => _error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _createWorkspace() async {
    if (_busy) return;
    final name = _createNameController.text.trim();
    final path = _createPathController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Le nom du workspace est requis.');
      return;
    }
    if (path.isEmpty) {
      setState(() => _error = 'Le dossier de destination est requis.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.createWorkspace(
        Directory(path),
        name: name,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (err) {
      if (mounted) {
        setState(() => _error = err.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _onCreateNameChanged(String value) {
    if (_createPathManuallyEdited) return;
    final currentPath = widget.controller.workspaceDirectory.path;
    final parentPath = Directory(currentPath).parent.path;
    final slug = SpecStorageSlug.slugify(value, fallback: 'spec-workspace');
    _createPathController.text = '$parentPath${Platform.pathSeparator}$slug';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final currentDir = widget.controller.workspaceDirectory;
    final currentName =
        widget.controller.workspaceMetadata?.name ?? 'Workspace actif';
    final recents = widget.controller.recentWorkspaces;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.folder_copy_rounded, color: colors.primary),
          const SizedBox(width: 10),
          const Expanded(child: Text('Dossier Workspace (dépôt Git)')),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dossier actif : $currentName',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    currentDir.path,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Contient workspace.json, .gitignore, glossary/, dictionary/ et projects/<slug>/.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<_WorkspaceDialogMode>(
              segments: const [
                ButtonSegment(
                  value: _WorkspaceDialogMode.recent,
                  icon: Icon(Icons.history_rounded, size: 16),
                  label: Text('Récents'),
                ),
                ButtonSegment(
                  value: _WorkspaceDialogMode.openPath,
                  icon: Icon(Icons.folder_open_rounded, size: 16),
                  label: Text('Ouvrir un dossier'),
                ),
                ButtonSegment(
                  value: _WorkspaceDialogMode.create,
                  icon: Icon(Icons.create_new_folder_outlined, size: 16),
                  label: Text('Nouveau'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _busy
                  ? null
                  : (selection) => setState(() {
                      _mode = selection.first;
                      _error = null;
                      _pendingNonEmptyConfirm = false;
                    }),
            ),
            const SizedBox(height: 14),
            if (_mode == _WorkspaceDialogMode.recent) ...[
              if (recents.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Aucun autre workspace récent mémorisé.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: recents.length,
                    itemBuilder: (context, index) {
                      final entry = recents[index];
                      final isCurrent =
                          entry.path.toLowerCase() ==
                          currentDir.path.toLowerCase();
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isCurrent
                              ? Icons.check_circle_rounded
                              : Icons.folder_rounded,
                          color: isCurrent ? colors.primary : null,
                        ),
                        title: Text(entry.name),
                        subtitle: Text(
                          entry.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isCurrent
                            ? const Chip(label: Text('Actif'))
                            : TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _openDirectory(
                                        Directory(entry.path),
                                      ),
                                child: const Text('Ouvrir'),
                              ),
                      );
                    },
                  ),
                ),
            ] else if (_mode == _WorkspaceDialogMode.openPath) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('workspace-open-path-field'),
                      controller: _openPathController,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Chemin du dossier workspace ou dépôt Git',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('workspace-open-browse-btn'),
                    onPressed: _busy
                        ? null
                        : () => _browseFor(_openPathController),
                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                    label: const Text('Parcourir…'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const ValueKey('workspace-open-submit-btn'),
                  onPressed: _busy
                      ? null
                      : () {
                          final raw = _openPathController.text.trim();
                          if (raw.isEmpty) {
                            setState(
                              () => _error = 'Indiquez un chemin de dossier.',
                            );
                            return;
                          }
                          _openDirectory(Directory(raw));
                        },
                  icon: const Icon(Icons.login_rounded, size: 16),
                  label: const Text('Ouvrir ce dossier'),
                ),
              ),
            ] else ...[
              TextField(
                key: const ValueKey('workspace-create-name-field'),
                controller: _createNameController,
                enabled: !_busy,
                onChanged: _onCreateNameChanged,
                decoration: const InputDecoration(
                  labelText: 'Nom du workspace',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('workspace-create-path-field'),
                      controller: _createPathController,
                      enabled: !_busy,
                      onChanged: (_) => _createPathManuallyEdited = true,
                      decoration: const InputDecoration(
                        labelText: 'Dossier cible (créé si inexistant)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('workspace-create-browse-btn'),
                    onPressed: _busy
                        ? null
                        : () => _browseFor(_createPathController),
                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                    label: const Text('Parcourir…'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const ValueKey('workspace-create-submit-btn'),
                  onPressed: _busy ? null : _createWorkspace,
                  icon: const Icon(Icons.create_new_folder_rounded, size: 16),
                  label: const Text('Créer et ouvrir'),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                    ),
                    if (_pendingNonEmptyConfirm) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          key: const ValueKey('workspace-confirm-init-nonempty'),
                          onPressed: _busy
                              ? null
                              : () => _openDirectory(
                                  Directory(_openPathController.text.trim()),
                                  initializeNonEmpty: true,
                                ),
                          child: const Text('Initialiser un workspace ici'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

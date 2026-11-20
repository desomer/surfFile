/// Boîte de dialogue de sélection et création d'application sandboxée ([ApplicationSelectorDialog]).
///
/// Permet de visualiser l'application active, de basculer vers une application
/// récente, d'ouvrir un dossier arbitraire sur le disque ou de créer une
/// nouvelle application (vide ou clonée depuis l'application courante).
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../services/applications/sandboxed_application_store.dart';
import '../editing/dialogs/editor_dialog.dart';
import '../editing/dialogs/editor_dialog_header.dart';

/// Signature d'un sélecteur de dossier (retourne le chemin choisi ou `null`).
typedef DirectoryPickerCallback = Future<String?> Function(
  String? initialDirectory,
);

/// Dialogue de gestion et de sélection d'une application sandboxée.
class ApplicationSelectorDialog extends StatefulWidget {
  const ApplicationSelectorDialog({
    required this.store,
    required this.currentDirectory,
    required this.onSelectDirectory,
    required this.onCreateApplication,
    this.currentName,
    this.canCloneCurrent = true,
    this.pickDirectory,
    super.key,
  });

  /// Magasin gérant la liste des applications récentes et les dossiers.
  final SandboxedApplicationStore store;

  /// Dossier de l'application actuellement ouverte, ou `null` si non persistée.
  final Directory? currentDirectory;

  /// Nom affiché de l'application active.
  final String? currentName;

  /// Callback exécuté pour ouvrir un dossier d'application existant.
  final Future<void> Function(
    Directory directory, {
    required bool initializeNonEmpty,
  })
  onSelectDirectory;

  /// Callback exécuté pour créer une nouvelle application (vide ou clonée).
  final Future<void> Function(
    Directory directory, {
    required String name,
    required bool cloneCurrent,
  })
  onCreateApplication;

  /// Indique si le clonage de l'application courante est disponible.
  final bool canCloneCurrent;

  /// Sélecteur de dossier personnalisable (Windows natif par défaut si `null`).
  final DirectoryPickerCallback? pickDirectory;

  /// Affiche la boîte de dialogue de sélection d'application.
  static Future<void> show(
    BuildContext context, {
    required SandboxedApplicationStore store,
    required Directory? currentDirectory,
    required Future<void> Function(
      Directory directory, {
      required bool initializeNonEmpty,
    })
    onSelectDirectory,
    required Future<void> Function(
      Directory directory, {
      required String name,
      required bool cloneCurrent,
    })
    onCreateApplication,
    String? currentName,
    bool canCloneCurrent = true,
    DirectoryPickerCallback? pickDirectory,
  }) => showEditorDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ApplicationSelectorDialog(
      store: store,
      currentDirectory: currentDirectory,
      currentName: currentName,
      onSelectDirectory: onSelectDirectory,
      onCreateApplication: onCreateApplication,
      canCloneCurrent: canCloneCurrent,
      pickDirectory: pickDirectory,
    ),
  );

  /// Ouvre le sélecteur de dossier natif Windows via `FolderBrowserDialog`.
  static Future<String?> pickDirectoryNative(String? initialDirectory) async {
    if (!Platform.isWindows) return null;
    final initial = initialDirectory?.trim() ?? '';
    final hasInitial = initial.isNotEmpty && Directory(initial).existsSync();
    final escaped = initial.replaceAll("'", "''");
    final script =
        'Add-Type -AssemblyName System.Windows.Forms; '
        r'$d = New-Object System.Windows.Forms.FolderBrowserDialog; '
        r"$d.Description = 'Sélectionner un dossier d''application'; "
        r'$d.ShowNewFolderButton = $true; '
        '${hasInitial ? "\$d.SelectedPath = '$escaped'; " : ''}'
        r'if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { '
        r'Write-Output $d.SelectedPath }';
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-STA',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) return null;
    final chosen = (result.stdout as String).trim();
    return chosen.isEmpty ? null : chosen;
  }

  @override
  State<ApplicationSelectorDialog> createState() =>
      _ApplicationSelectorDialogState();
}

enum _SelectorMode { list, openPath, create }

class _ApplicationSelectorDialogState extends State<ApplicationSelectorDialog> {
  _SelectorMode _mode = _SelectorMode.list;
  List<SandboxedApplicationEntry> _recent = const [];
  bool _loadingRecent = true;
  bool _busy = false;
  String? _error;

  late final TextEditingController _openPathController;
  late final TextEditingController _createNameController;
  late final TextEditingController _createPathController;
  bool _createPathManuallyEdited = false;
  bool _cloneCurrent = false;

  @override
  void initState() {
    super.initState();
    _openPathController = TextEditingController(
      text: widget.currentDirectory?.path ?? '',
    );
    _createNameController = TextEditingController(text: 'Nouvelle application');
    _createPathController = TextEditingController(
      text: _defaultNewAppPath('Nouvelle application'),
    );
    _cloneCurrent = widget.canCloneCurrent && widget.currentDirectory != null;
    _loadRecent();
  }

  @override
  void dispose() {
    _openPathController.dispose();
    _createNameController.dispose();
    _createPathController.dispose();
    super.dispose();
  }

  String _defaultNewAppPath(String name) {
    final slug = SandboxedApplicationStore.suggestFolderName(name);
    try {
      final root = SandboxedApplicationStore.defaultAppsRootDirectory().path;
      return '$root${Platform.pathSeparator}$slug';
    } on FileSystemException {
      return '${Directory.current.path}${Platform.pathSeparator}$slug';
    }
  }

  Future<void> _loadRecent() async {
    setState(() => _loadingRecent = true);
    try {
      final entries = await widget.store.loadRecentApplications();
      if (!mounted) return;
      setState(() {
        _recent = entries;
        _loadingRecent = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingRecent = false;
        _error = 'Impossible de charger les applications récentes : $error';
      });
    }
  }

  Future<String?> _browseFolder(String? initialDirectory) async {
    if (widget.pickDirectory != null) {
      return widget.pickDirectory!(initialDirectory);
    }
    return ApplicationSelectorDialog.pickDirectoryNative(initialDirectory);
  }

  bool _isCurrent(String path) {
    final current = widget.currentDirectory;
    if (current == null) return false;
    return SandboxedApplicationStore.samePath(path, current.path);
  }

  Future<void> _openDirectory(Directory dir) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSelectDirectory(dir, initializeNonEmpty: false);
      if (mounted) Navigator.of(context).pop();
    } on NonEmptyNonAppDirectoryException {
      if (!mounted) return;
      setState(() => _busy = false);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Initialiser ce dossier ?'),
          content: Text(
            'Le dossier « ${dir.path} » contient déjà d’autres fichiers et ne '
            'contient pas encore de projet sandboxé.\n\n'
            'Souhaitez-vous y initialiser les fichiers de l’application '
            '(app.json, appearance.json, repositories/) ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('app-selector-confirm-init-non-empty'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Initialiser et ouvrir'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        setState(() {
          _busy = true;
          _error = null;
        });
        try {
          await widget.onSelectDirectory(dir, initializeNonEmpty: true);
          if (mounted) Navigator.of(context).pop();
        } catch (error) {
          if (mounted) {
            setState(() {
              _busy = false;
              _error = _formatError(error);
            });
          }
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _formatError(error);
        });
      }
    }
  }

  Future<void> _browseAndOpenFolder() async {
    if (_busy) return;
    final chosen = await _browseFolder(widget.currentDirectory?.path);
    if (!mounted) return;
    if (chosen == null || chosen.trim().isEmpty) {
      setState(() {
        _mode = _SelectorMode.openPath;
        _error = null;
      });
      return;
    }
    _openPathController.text = chosen;
    await _openDirectory(Directory(chosen));
  }

  Future<void> _submitOpenPath() async {
    final path = _openPathController.text.trim();
    if (path.isEmpty) {
      setState(() => _error = 'Indiquez le chemin d’un dossier.');
      return;
    }
    await _openDirectory(Directory(path));
  }

  Future<void> _browseParentForCreate() async {
    final currentTarget = _createPathController.text.trim();
    final initial = currentTarget.isNotEmpty
        ? Directory(currentTarget).parent.path
        : widget.currentDirectory?.parent.path;
    final chosen = await _browseFolder(initial);
    if (!mounted || chosen == null || chosen.trim().isEmpty) return;
    final slug = SandboxedApplicationStore.suggestFolderName(
      _createNameController.text,
    );
    setState(() {
      _createPathManuallyEdited = true;
      _createPathController.text =
          '${SandboxedApplicationStore.normalizePath(chosen)}'
          '${Platform.pathSeparator}$slug';
      _error = null;
    });
  }

  Future<void> _submitCreate() async {
    if (_busy) return;
    final name = _createNameController.text.trim();
    final path = _createPathController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Indiquez un nom pour l’application.');
      return;
    }
    if (path.isEmpty) {
      setState(() => _error = 'Indiquez un dossier de destination.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onCreateApplication(
        Directory(path),
        name: name,
        cloneCurrent: _cloneCurrent && widget.canCloneCurrent,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _formatError(error);
        });
      }
    }
  }

  Future<void> _removeRecent(String path) async {
    if (_busy) return;
    final updated = await widget.store.removeRecentApplication(path);
    if (!mounted) return;
    setState(() => _recent = updated);
  }

  static String _formatError(Object error) => switch (error) {
    FormatException(:final message) => message,
    FileSystemException(:final message, :final path) =>
      path == null ? message : '$message ($path)',
    _ => '$error',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activeDir = widget.currentDirectory;
    final activeTitle =
        widget.currentName ??
        (activeDir == null
            ? 'Session en mémoire'
            : SandboxedApplicationStore.fallbackNameForDirectory(activeDir));

    return AlertDialog(
      key: const ValueKey('application-selector-dialog'),
      title: const EditorDialogHeader(label: 'Applications'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                key: const ValueKey('application-selector-current'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_special_outlined,
                      color: scheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  activeTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Active',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            activeDir?.path ??
                                'Aucun dossier sandboxé actif',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_error != null) ...[
                Container(
                  key: const ValueKey('application-selector-error'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_mode == _SelectorMode.list) _buildListMode(context),
              if (_mode == _SelectorMode.openPath) _buildOpenPathMode(context),
              if (_mode == _SelectorMode.create) _buildCreateMode(context),
            ],
          ),
        ),
      ),
      actions: [
        if (_mode != _SelectorMode.list)
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _mode = _SelectorMode.list;
                    _error = null;
                  }),
            child: const Text('Retour'),
          ),
        TextButton(
          key: const ValueKey('application-selector-close'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }

  Widget _buildListMode(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canBrowse = Platform.isWindows || widget.pickDirectory != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('application-selector-new'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _mode = _SelectorMode.create;
                      _error = null;
                      _cloneCurrent =
                          widget.canCloneCurrent &&
                          widget.currentDirectory != null;
                    }),
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('Nouvelle application…'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('application-selector-open-folder'),
              onPressed: _busy
                  ? null
                  : (canBrowse
                        ? _browseAndOpenFolder
                        : () => setState(() {
                            _mode = _SelectorMode.openPath;
                            _error = null;
                          })),
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text('Ouvrir un dossier…'),
            ),
            if (canBrowse)
              TextButton.icon(
                key: const ValueKey('application-selector-open-path-toggle'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _mode = _SelectorMode.openPath;
                        _error = null;
                      }),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Saisir un chemin'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Applications récentes',
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingRecent)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Aucune application récente enregistrée.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _recent.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final entry = _recent[index];
                final isCurrent = _isCurrent(entry.path);
                final exists = entry.exists;
                return Material(
                  color: isCurrent
                      ? scheme.primaryContainer.withValues(alpha: 0.35)
                      : scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  child: ListTile(
                    key: ValueKey('application-recent-item-$index'),
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isCurrent
                            ? scheme.primary
                            : scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    leading: Icon(
                      exists
                          ? (isCurrent
                                ? Icons.folder_open
                                : Icons.folder_outlined)
                          : Icons.folder_off_outlined,
                      color: exists ? scheme.primary : scheme.error,
                    ),
                    title: Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      exists ? entry.path : 'Dossier introuvable : ${entry.path}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: exists
                            ? scheme.onSurfaceVariant
                            : scheme.error,
                      ),
                    ),
                    enabled: !_busy && exists && !isCurrent,
                    onTap: exists && !isCurrent
                        ? () => _openDirectory(Directory(entry.path))
                        : null,
                    trailing: isCurrent
                        ? null
                        : IconButton(
                            key: ValueKey('application-recent-remove-$index'),
                            tooltip: 'Retirer de la liste',
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: _busy
                                ? null
                                : () => _removeRecent(entry.path),
                          ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildOpenPathMode(BuildContext context) {
    final canBrowse = Platform.isWindows || widget.pickDirectory != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ouvrir un dossier d’application',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('application-open-path-input'),
                controller: _openPathController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Chemin du dossier',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _submitOpenPath(),
              ),
            ),
            if (canBrowse) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('application-open-browse-button'),
                onPressed: _busy ? null : _browseAndOpenFolder,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Parcourir…'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const ValueKey('application-open-submit'),
            onPressed: _busy ? null : _submitOpenPath,
            child: const Text('Ouvrir cette application'),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateMode(BuildContext context) {
    final theme = Theme.of(context);
    final canBrowse = Platform.isWindows || widget.pickDirectory != null;
    final canClone = widget.canCloneCurrent && widget.currentDirectory != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Nouvelle application', style: theme.textTheme.titleSmall),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('application-create-name-input'),
          controller: _createNameController,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: 'Nom de l’application',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) {
            if (!_createPathManuallyEdited) {
              _createPathController.text = _defaultNewAppPath(value);
            }
          },
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('application-create-path-input'),
                controller: _createPathController,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Dossier de destination',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => _createPathManuallyEdited = true,
              ),
            ),
            if (canBrowse) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('application-create-browse-button'),
                onPressed: _busy ? null : _browseParentForCreate,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Parcourir…'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Contenu initial',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          key: const ValueKey('application-create-template-selector'),
          segments: [
            const ButtonSegment<bool>(
              value: false,
              icon: Icon(Icons.note_add_outlined, size: 18),
              label: Text('Application vide'),
            ),
            ButtonSegment<bool>(
              value: true,
              enabled: canClone,
              icon: const Icon(Icons.file_copy_outlined, size: 18),
              label: const Text('Cloner l’actuelle'),
            ),
          ],
          selected: {_cloneCurrent && canClone},
          onSelectionChanged: _busy
              ? null
              : (values) => setState(() => _cloneCurrent = values.single),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const ValueKey('application-create-submit'),
            onPressed: _busy ? null : _submitCreate,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Créer et ouvrir'),
          ),
        ),
      ],
    );
  }
}

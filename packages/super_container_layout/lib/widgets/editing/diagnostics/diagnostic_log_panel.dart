/// Panneau et bouton de consultation des journaux d'erreurs typés ([DiagnosticLogPanel], [DiagnosticLogBannerButton]).
///
/// Permet d'inspecter en temps réel le tampon [debugEntries] filtré par niveau
/// d'importance ([DebugSeverity]), catégorie ([DebugErrorCategory]) et présence
/// en rouge dans l'IHM (`visibleInUi`), avec copie et réinitialisation.
library;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';

import '../../../services/diagnostics/debug_entry.dart';
import '../../../services/inspection/vibe_debug_capture.dart';
import '../dialogs/editor_dialog.dart';
import '../dialogs/editor_dialog_header.dart';

/// Retourne la couleur d'accent associée à un niveau d'importance [severity].
Color diagnosticSeverityColor(DebugSeverity severity, ColorScheme scheme) =>
    switch (severity) {
      DebugSeverity.critical => const Color(0xFFD32F2F),
      DebugSeverity.error => scheme.error,
      DebugSeverity.warning => const Color(0xFFED6C02),
      DebugSeverity.info => scheme.primary,
    };

/// Retourne l'icône associée à un niveau d'importance [severity].
IconData diagnosticSeverityIcon(DebugSeverity severity) => switch (severity) {
  DebugSeverity.critical => Icons.dangerous_outlined,
  DebugSeverity.error => Icons.error_outline,
  DebugSeverity.warning => Icons.warning_amber_rounded,
  DebugSeverity.info => Icons.info_outline,
};

/// Retourne l'icône associée à une catégorie fonctionnelle [category].
IconData diagnosticCategoryIcon(DebugErrorCategory category) =>
    switch (category) {
      DebugErrorCategory.binding => Icons.link_off,
      DebugErrorCategory.javascript => Icons.javascript,
      DebugErrorCategory.font => Icons.font_download_off_outlined,
      DebugErrorCategory.userInput => Icons.edit_off_outlined,
      DebugErrorCategory.rendering => Icons.layers_clear_outlined,
      DebugErrorCategory.system => Icons.bug_report_outlined,
    };

/// Ouvre le panneau modal de diagnostic des erreurs typées.
Future<void> showDiagnosticLogDialog(
  BuildContext context, {
  ValueChanged<String>? onSelectComponent,
}) => showEditorDialog<void>(
  context: context,
  preferredWidth: ValueNotifier<double>(820),
  builder: (dialogContext) => AlertDialog(
    contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    title: EditorDialogHeader(
      label: 'Journal des erreurs & diagnostics',
      actions: [
        IconButton(
          tooltip: 'Fermer',
          icon: const Icon(Icons.close, size: 18),
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
    content: SizedBox(
      width: 780,
      height: 540,
      child: DiagnosticLogPanel(
        onSelectComponent: onSelectComponent == null
            ? null
            : (id) {
                Navigator.of(dialogContext).pop();
                onSelectComponent(id);
              },
      ),
    ),
  ),
);

/// Bouton compact avec badge coloré par gravité maximale pour [StyleEditBanner].
class DiagnosticLogBannerButton extends StatelessWidget {
  /// Crée un bouton de journal d'erreurs avec badge temps réel.
  const DiagnosticLogBannerButton({
    required this.onPressed,
    this.foregroundColor,
    super.key,
  });

  /// Action déclenchée au clic (ouverture du panneau de diagnostic).
  final VoidCallback onPressed;

  /// Couleur d'icône par défaut lorsqu'aucune erreur n'est active.
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: debugEntriesRevision,
      builder: (context, _, _) {
        var errorCount = 0;
        DebugSeverity? highest;
        for (final entry in debugEntries) {
          if (entry.type != DebugEntryType.error) continue;
          if (VibeDebugCapture.isVibeInternalMessage(entry.message)) continue;
          errorCount++;
          if (highest == null || entry.severity.rank > highest.rank) {
            highest = entry.severity;
          }
        }
        final badgeColor = highest == null
            ? null
            : diagnosticSeverityColor(highest, scheme);
        final tooltip = errorCount == 0
            ? 'Journal d’erreurs (aucune erreur)'
            : 'Journal d’erreurs ($errorCount — gravité max : ${highest!.label})';
        return IconButton(
          key: const ValueKey('style-edit-banner-diagnostics'),
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          color: foregroundColor ?? scheme.onPrimary,
          onPressed: onPressed,
          icon: errorCount == 0
              ? const Icon(Icons.bug_report_outlined)
              : Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.bug_report_outlined),
                    Positioned(
                      right: -6,
                      top: -5,
                      child: Container(
                        key: const ValueKey(
                          'style-edit-banner-diagnostics-badge',
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 14,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: scheme.surface,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          errorCount > 99 ? '99+' : '$errorCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// Panneau interactif de visualisation et filtrage des entrées de [debugEntries].
class DiagnosticLogPanel extends StatefulWidget {
  /// Crée un panneau de journaux de diagnostic temps réel.
  const DiagnosticLogPanel({
    this.onSelectComponent,
    this.includeLogsByDefault = false,
    super.key,
  });

  /// Rappel optionnel lorsqu'un utilisateur clique sur l'ID d'un composant.
  final ValueChanged<String>? onSelectComponent;

  /// Indique si les logs standards (`DebugEntryType.log`) sont affichés par défaut.
  final bool includeLogsByDefault;

  @override
  State<DiagnosticLogPanel> createState() => _DiagnosticLogPanelState();
}

class _DiagnosticLogPanelState extends State<DiagnosticLogPanel> {
  final TextEditingController _searchController = TextEditingController();
  DebugSeverity? _selectedSeverity;
  DebugErrorCategory? _selectedCategory;
  bool _onlyVisibleInUi = false;
  late bool _includeLogs = widget.includeLogsByDefault;
  final Set<int> _expandedStackIndices = <int>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DebugEntry> _filteredEntries() {
    final query = _searchController.text.trim().toLowerCase();
    final result = <DebugEntry>[];
    for (final entry in debugEntries.reversed) {
      if (VibeDebugCapture.isVibeInternalMessage(entry.message)) continue;
      if (!_includeLogs && entry.type != DebugEntryType.error) continue;
      if (_selectedSeverity != null && entry.severity != _selectedSeverity) {
        continue;
      }
      if (_selectedCategory != null && entry.category != _selectedCategory) {
        continue;
      }
      if (_onlyVisibleInUi && !entry.visibleInUi) continue;
      if (query.isNotEmpty) {
        final haystack =
            '${entry.message} ${entry.componentId ?? ''} ${entry.source ?? ''} '
            '${entry.category.label} ${entry.severity.label}'
                .toLowerCase();
        if (!haystack.contains(query)) continue;
      }
      result.add(entry);
    }
    return result;
  }

  Future<void> _copyEntries(List<DebugEntry> entries) async {
    final text = entries
        .map((e) {
          final ts = e.timestamp.toIso8601String();
          final line = '$ts ${VibeDebugCapture.formatEntryForAi(e)}';
          return e.stackTrace != null ? '$line\n${e.stackTrace}' : line;
        })
        .join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('${entries.length} entrée(s) copiée(s).'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: debugEntriesRevision,
      builder: (context, _, _) {
        final countsBySeverity = <DebugSeverity, int>{
          for (final s in DebugSeverity.values) s: 0,
        };
        for (final entry in debugEntries) {
          if (VibeDebugCapture.isVibeInternalMessage(entry.message)) continue;
          if (!_includeLogs && entry.type != DebugEntryType.error) continue;
          countsBySeverity[entry.severity] =
              (countsBySeverity[entry.severity] ?? 0) + 1;
        }
        final filtered = _filteredEntries();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('diagnostic-log-search'),
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Filtrer par message, composant ou source…',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Effacer le filtre',
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const ValueKey('diagnostic-log-copy-all'),
                  onPressed: filtered.isEmpty
                      ? null
                      : () => _copyEntries(filtered),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copier'),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  key: const ValueKey('diagnostic-log-clear'),
                  onPressed: debugEntries.isEmpty
                      ? null
                      : () {
                          _expandedStackIndices.clear();
                          clearDebugEntries();
                        },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Effacer'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final severity in const [
                  DebugSeverity.critical,
                  DebugSeverity.error,
                  DebugSeverity.warning,
                  DebugSeverity.info,
                ])
                  FilterChip(
                    key: ValueKey('diagnostic-severity-${severity.name}'),
                    selected: _selectedSeverity == severity,
                    showCheckmark: false,
                    avatar: Icon(
                      diagnosticSeverityIcon(severity),
                      size: 15,
                      color: diagnosticSeverityColor(severity, scheme),
                    ),
                    label: Text(
                      '${severity.label} (${countsBySeverity[severity] ?? 0})',
                    ),
                    onSelected: (selected) => setState(
                      () => _selectedSeverity = selected ? severity : null,
                    ),
                  ),
                FilterChip(
                  key: const ValueKey('diagnostic-filter-ui-only'),
                  selected: _onlyVisibleInUi,
                  label: const Text('IHM rouge'),
                  onSelected: (selected) =>
                      setState(() => _onlyVisibleInUi = selected),
                ),
                FilterChip(
                  key: const ValueKey('diagnostic-filter-include-logs'),
                  selected: _includeLogs,
                  label: const Text('Inclure logs'),
                  onSelected: (selected) =>
                      setState(() => _includeLogs = selected),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  key: const ValueKey('diagnostic-category-all'),
                  selected: _selectedCategory == null,
                  label: const Text('Toutes catégories'),
                  onSelected: (_) => setState(() => _selectedCategory = null),
                ),
                for (final category in DebugErrorCategory.values)
                  ChoiceChip(
                    key: ValueKey('diagnostic-category-${category.name}'),
                    selected: _selectedCategory == category,
                    avatar: Icon(diagnosticCategoryIcon(category), size: 15),
                    label: Text(category.label),
                    onSelected: (selected) => setState(
                      () => _selectedCategory = selected ? category : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 36,
                            color: scheme.primary,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Aucune erreur correspondant aux filtres.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      key: const ValueKey('diagnostic-log-list'),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final entry = filtered[index];
                        final accent = diagnosticSeverityColor(
                          entry.severity,
                          scheme,
                        );
                        final isExpanded = _expandedStackIndices.contains(
                          index,
                        );
                        return Container(
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.35),
                            ),
                          ),
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Icon(
                                    diagnosticSeverityIcon(entry.severity),
                                    size: 16,
                                    color: accent,
                                  ),
                                  _DiagnosticTag(
                                    label: entry.severity.label.toUpperCase(),
                                    background: accent,
                                    foreground: Colors.white,
                                  ),
                                  _DiagnosticTag(
                                    label: entry.category.label,
                                    background:
                                        scheme.surfaceContainerHighest,
                                    foreground: scheme.onSurface,
                                  ),
                                  if (entry.visibleInUi)
                                    _DiagnosticTag(
                                      label: 'IHM',
                                      background: scheme.errorContainer,
                                      foreground: scheme.onErrorContainer,
                                    ),
                                  if (entry.componentId case final cid?)
                                    InkWell(
                                      onTap: widget.onSelectComponent == null
                                          ? null
                                          : () => widget.onSelectComponent!(
                                              cid,
                                            ),
                                      borderRadius: BorderRadius.circular(4),
                                      child: _DiagnosticTag(
                                        label: 'comp:$cid',
                                        background: scheme.primaryContainer,
                                        foreground: scheme.onPrimaryContainer,
                                      ),
                                    ),
                                  if (entry.source case final src?)
                                    Text(
                                      src,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  Text(
                                    _formatTime(entry.timestamp),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'Consolas',
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                entry.message,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: entry.severity.rank >=
                                          DebugSeverity.error.rank
                                      ? accent
                                      : scheme.onSurface,
                                  fontWeight: entry.severity ==
                                          DebugSeverity.critical
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              if (entry.stackTrace != null) ...[
                                const SizedBox(height: 4),
                                InkWell(
                                  onTap: () => setState(() {
                                    if (isExpanded) {
                                      _expandedStackIndices.remove(index);
                                    } else {
                                      _expandedStackIndices.add(index);
                                    }
                                  }),
                                  child: Text(
                                    isExpanded
                                        ? 'Masquer la pile d’appels'
                                        : 'Afficher la pile d’appels',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                if (isExpanded) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerLowest,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: SelectableText(
                                      entry.stackTrace!,
                                      style: const TextStyle(
                                        fontFamily: 'Consolas',
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _DiagnosticTag extends StatelessWidget {
  const _DiagnosticTag({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
    ),
  );
}

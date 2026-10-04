import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../services/file_operations.dart';
import '../services/folder_size_service.dart';
import 'explorer_entries_view.dart' show formatExplorerSize;
import 'transfer_panel.dart' show formatDuration;

class FolderSizeCard extends StatefulWidget {
  const FolderSizeCard({required this.jobs, super.key});

  final List<FolderSizeJob> jobs;

  @override
  State<FolderSizeCard> createState() => _FolderSizeCardState();
}

class _FolderSizeCardState extends State<FolderSizeCard> {
  Timer? _ticker;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.jobs.any(
        (job) => job.status == FolderSizeJobStatus.running,
      )) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(widget.jobs),
    builder: (context, _) {
      final jobs = widget.jobs;
      final active = jobs.where(
        (job) => job.status == FolderSizeJobStatus.running,
      ).toList();
      final failures = jobs.where(
        (job) => job.status == FolderSizeJobStatus.failed,
      ).toList();
      final cancelled = jobs.where(
        (job) => job.status == FolderSizeJobStatus.cancelled,
      ).length;
      final completed = jobs.where(
        (job) => job.status == FolderSizeJobStatus.done,
      ).length;
      final total = jobs.length + FolderSizeService.queued.value;
      final bytes = jobs.fold(0, (sum, job) => sum + job.latest.bytes);
      final files = jobs.fold(0, (sum, job) => sum + job.latest.files);
      final folders = jobs.fold(0, (sum, job) => sum + job.latest.folders);
      final skipped = jobs.fold(0, (sum, job) => sum + job.latest.skipped);
      final current = (active.isEmpty ? jobs.last : active.last);
      final startedAt = jobs.map((job) => job.startedAt).reduce(
        (a, b) => a.isBefore(b) ? a : b,
      );
      final colors = Theme.of(context).colorScheme;
      final running = active.isNotEmpty || FolderSizeService.queued.value > 0;
      final endedAt = running
          ? DateTime.now()
          : jobs.map((job) => job.startedAt.add(job.elapsed)).reduce(
              (a, b) => a.isAfter(b) ? a : b,
            );
      final state = running
          ? FolderSizeJobStatus.running
          : failures.isNotEmpty
          ? FolderSizeJobStatus.failed
          : cancelled > 0
          ? FolderSizeJobStatus.cancelled
          : FolderSizeJobStatus.done;
      final accent = switch (state) {
        FolderSizeJobStatus.running => colors.primary,
        FolderSizeJobStatus.done => Colors.green.shade500,
        FolderSizeJobStatus.cancelled => colors.outline,
        FolderSizeJobStatus.failed => colors.error,
      };
      final status = switch (state) {
        FolderSizeJobStatus.running => 'Parcours en cours',
        FolderSizeJobStatus.done => skipped == 0
            ? 'Calcul terminé'
            : 'Calcul terminé · taille partielle',
        FolderSizeJobStatus.cancelled => 'Calcul annulé',
        FolderSizeJobStatus.failed => 'Échec du calcul',
      };
      return Material(
        key: const ValueKey('folder-size-card'),
        color: colors.surfaceContainerHigh.withValues(alpha: .97),
        elevation: 10,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: accent.withValues(alpha: .45)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.calculate_outlined, color: accent, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Calcul de taille',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: _expanded ? 'Réduire' : 'Détails',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                    ),
                  ),
                  IconButton(
                    key: ValueKey(
                      running ? 'folder-size-job-cancel' : 'folder-size-dismiss',
                    ),
                    tooltip: running ? 'Tout annuler' : 'Fermer',
                    visualDensity: VisualDensity.compact,
                    onPressed: running
                        ? FolderSizeService.cancelAll
                        : FolderSizeService.dismissAll,
                    icon: Icon(
                      running ? Icons.stop_circle_outlined : Icons.close,
                    ),
                  ),
                ],
              ),
              Tooltip(
                message: current.path,
                child: Text(
                  jobs.length == 1
                      ? FileOperations.name(current.path)
                      : '$total dossiers à calculer',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              Text('$status · ${formatExplorerSize(bytes)}'),
              Text('$completed / $total dossiers terminés'),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                key: const ValueKey('folder-size-job-progress'),
                value: running ? null : completed / total,
                color: accent,
                backgroundColor: accent.withValues(alpha: .15),
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                Tooltip(
                  message: current.latest.currentPath,
                  child: Text(
                    current.latest.currentPath,
                    key: const ValueKey('folder-size-current-path'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$files fichiers · $folders dossiers',
                ),
                Text('Écoulé : ${formatDuration(endedAt.difference(startedAt))}'),
                if (active.length > 1)
                  Text('${active.length} calculs simultanés'),
                if (running)
                  const Text(
                    'Total inconnu pendant le parcours',
                    style: TextStyle(fontSize: 12),
                  ),
              ],
              if (skipped > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '$skipped éléments inaccessibles ignorés',
                  style: TextStyle(color: colors.error),
                ),
              ],
              for (final job in failures) ...[
                const SizedBox(height: 8),
                Text(
                  '${FileOperations.name(job.path)} : ${job.error}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.error),
                ),
              ],
              if (cancelled > 0)
                Text('$cancelled calculs annulés'),
            ],
          ),
        ),
      );
    },
  );
}

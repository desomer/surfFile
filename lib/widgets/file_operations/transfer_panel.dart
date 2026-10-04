import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../services/file_operations.dart';
import '../../services/folder_size_service.dart';
import '../folder_size/folder_size_card.dart';

/// Panneau flottant (en haut à droite) listant les transferts en cours :
/// fich ier traité, vitesse, courbe de vitesse, temps restant…
class TransferPanel extends StatelessWidget {
  const TransferPanel({super.key});

  static const double width = 360;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        FileJobs.active,
        FolderSizeService.jobs,
        FolderSizeService.queued,
      ]),
      builder: (context, _) => AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topRight,
        child: SizedBox(
          width:
              FileJobs.active.value.isEmpty &&
                  FolderSizeService.jobs.value.isEmpty
              ? 0
              : width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final job in FileJobs.active.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TransferCard(key: ObjectKey(job), job: job),
                ),
              if (FolderSizeService.jobs.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FolderSizeCard(jobs: FolderSizeService.jobs.value),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TransferCard extends StatefulWidget {
  const TransferCard({required this.job, super.key});

  final FileJob job;

  @override
  State<TransferCard> createState() => _TransferCardState();
}

class _TransferCardState extends State<TransferCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();
  Timer? _ticker;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    // Rafraîchit le temps écoulé même sans nouvelle progression.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (widget.job.isDone) {
        _ticker?.cancel();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _entrance,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(.15, 0),
          end: Offset.zero,
        ).animate(curved),
        child: ListenableBuilder(
          listenable: widget.job,
          builder: (context, _) => _card(context),
        ),
      ),
    );
  }

  Widget _card(BuildContext context) {
    final job = widget.job;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final progress = job.latest;
    final status = job.status;
    final accent = switch (status) {
      FileJobStatus.failed => colors.error,
      FileJobStatus.cancelled => colors.outline,
      FileJobStatus.done => Colors.green.shade500,
      FileJobStatus.running => colors.primary,
    };
    final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 12);

    return Material(
      key: ValueKey('transfer-card-${job.hashCode}'),
      color: colors.surfaceContainerHigh.withValues(alpha: .97),
      elevation: 10,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: .45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(_icon(job), size: 18, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title(job),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'vers ${FileOperations.name(job.destination)}',
                        style: muted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _expanded ? 'Réduire' : 'Détails',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                ),
                if (job.isDone)
                  IconButton(
                    key: const ValueKey('transfer-dismiss'),
                    tooltip: 'Fermer',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    onPressed: () => FileJobs.dismiss(job),
                    icon: const Icon(Icons.close_rounded),
                  )
                else
                  IconButton(
                    key: const ValueKey('transfer-cancel'),
                    tooltip: job.isCancelling ? 'Annulation…' : 'Annuler',
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    color: colors.error,
                    onPressed: job.isCancelling ? null : job.cancel,
                    icon: const Icon(Icons.stop_circle_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _currentLine(job),
                          style: muted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        progress?.fraction == null
                            ? '…'
                            : '${(progress!.fraction! * 100).floor()} %',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: accent,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(
                        end: status == FileJobStatus.done
                            ? 1
                            : progress?.fraction ?? 0,
                      ),
                      duration: const Duration(milliseconds: 250),
                      builder: (context, value, _) => LinearProgressIndicator(
                        key: const ValueKey('transfer-progress'),
                        value: progress == null && !job.isDone ? null : value,
                        minHeight: 6,
                        color: accent,
                        backgroundColor: accent.withValues(alpha: .15),
                      ),
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: _expanded
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: _details(context, accent),
                    secondChild: const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _details(BuildContext context, Color accent) {
    final job = widget.job;
    final progress = job.latest;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: RepaintBoundary(
            child: CustomPaint(
              key: const ValueKey('transfer-speed-graph'),
              painter: SpeedGraphPainter(
                samples: job.samples,
                average: job.averageSpeed,
                color: accent,
                grid: colors.outlineVariant.withValues(alpha: .5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _stat(
              context,
              Icons.speed_rounded,
              'Vitesse',
              job.isDone ? '—' : '${formatBytes(job.speed)}/s',
              key: 'transfer-speed',
            ),
            _stat(
              context,
              Icons.hourglass_bottom_rounded,
              'Restant',
              job.isDone ? '—' : formatDuration(job.remaining),
              key: 'transfer-remaining',
            ),
            _stat(
              context,
              Icons.data_usage_rounded,
              'Transféré',
              progress == null
                  ? '—'
                  : '${formatBytes(progress.doneBytes.toDouble())}'
                        ' / ${formatBytes(progress.totalBytes.toDouble())}',
            ),
            _stat(
              context,
              Icons.description_outlined,
              'Fichiers',
              progress == null
                  ? '—'
                  : '${progress.doneItems} / ${progress.totalItems}',
            ),
            _stat(
              context,
              Icons.timer_outlined,
              'Écoulé',
              formatDuration(job.elapsed),
            ),
            _stat(
              context,
              Icons.trending_up_rounded,
              'Moy. / pic',
              '${formatBytes(job.averageSpeed)}/s · '
                  '${formatBytes(job.peakSpeed)}/s',
            ),
          ],
        ),
      ],
    );
  }

  Widget _stat(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    String? key,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: (TransferPanel.width - 14 - 14 - 16) / 2,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  key: key == null ? null : ValueKey(key),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _icon(FileJob job) => switch (job.status) {
    FileJobStatus.done => Icons.check_rounded,
    FileJobStatus.failed => Icons.error_outline_rounded,
    FileJobStatus.cancelled => Icons.block_rounded,
    FileJobStatus.running =>
      job.kind == FileTransfer.copy
          ? Icons.copy_all_rounded
          : Icons.drive_file_move_outline,
  };

  static String _title(FileJob job) {
    final count = job.sources.length;
    final what = count == 1
        ? FileOperations.name(job.sources.first)
        : '$count éléments';
    final verb = job.kind == FileTransfer.copy ? 'Copie' : 'Déplacement';
    return switch (job.status) {
      FileJobStatus.running => '$verb de $what',
      FileJobStatus.done => '$verb terminé${verb == 'Copie' ? 'e' : ''}',
      FileJobStatus.cancelled => '$verb annulé${verb == 'Copie' ? 'e' : ''}',
      FileJobStatus.failed => '$verb impossible',
    };
  }

  static String _currentLine(FileJob job) {
    switch (job.status) {
      case FileJobStatus.failed:
        final error = job.error;
        return error is FileSystemException ? error.message : '$error';
      case FileJobStatus.done:
        final count = job.latest?.doneItems ?? job.sources.length;
        return '$count élément(s) traité(s) en ${formatDuration(job.elapsed)}';
      case FileJobStatus.cancelled:
        return 'Arrêté par l’utilisateur';
      case FileJobStatus.running:
        if (job.isCancelling) return 'Annulation en cours…';
        return job.current ??
            (job.latest == null ? 'Analyse…' : 'Préparation…');
    }
  }
}

/// Courbe de vitesse remplie, avec une ligne pointillée pour la moyenne.
class SpeedGraphPainter extends CustomPainter {
  SpeedGraphPainter({
    required this.samples,
    required this.average,
    required this.color,
    required this.grid,
  });

  final List<SpeedSample> samples;
  final double average;
  final Color color;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (samples.length < 2) return;
    final peak = samples.map((s) => s.bytesPerSecond).fold(average, math.max);
    if (peak <= 0) return;
    final max = peak * 1.15;
    final step = size.width / (FileJob.maxSamples - 1);
    final offset = (FileJob.maxSamples - samples.length) * step;
    Offset point(int i) => Offset(
      offset + i * step,
      size.height - samples[i].bytesPerSecond / max * size.height,
    );

    final line = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < samples.length; i++) {
      final previous = point(i - 1);
      final current = point(i);
      final mid = (previous.dx + current.dx) / 2;
      line.cubicTo(mid, previous.dy, mid, current.dy, current.dx, current.dy);
    }
    final area = Path.from(line)
      ..lineTo(point(samples.length - 1).dx, size.height)
      ..lineTo(offset, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .4), color.withValues(alpha: .02)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    final last = point(samples.length - 1);
    canvas.drawCircle(last, 3.5, Paint()..color = color);

    if (average > 0) {
      final y = size.height - average / max * size.height;
      final dash = Paint()
        ..color = color.withValues(alpha: .7)
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, size.width), y),
          dash,
        );
      }
    }
  }

  @override
  bool shouldRepaint(SpeedGraphPainter old) =>
      old.samples.length != samples.length ||
      (samples.isNotEmpty && old.samples.last != samples.last) ||
      old.average != average ||
      old.color != color ||
      old.grid != grid;
}

/// `1,2 Go`, `850 Ko`…
String formatBytes(double bytes) {
  const units = ['o', 'Ko', 'Mo', 'Go', 'To'];
  var value = bytes;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits).replaceAll('.', ',')} ${units[unit]}';
}

/// `1 h 05 min`, `2 min 07 s`, `12 s` ; `—` si inconnu.
String formatDuration(Duration? duration) {
  if (duration == null) return '—';
  final seconds = duration.inSeconds;
  if (seconds < 60) return '$seconds s';
  final minutes = duration.inMinutes;
  if (minutes < 60) {
    return '$minutes min ${(seconds % 60).toString().padLeft(2, '0')} s';
  }
  return '${duration.inHours} h ${(minutes % 60).toString().padLeft(2, '0')} min';
}

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// Type de transfert exécuté par [FileOperations.start].
enum FileTransfer { copy, move }

/// Avancement d'une opération lancée en arrière-plan.
class FileProgress {
  const FileProgress({
    required this.doneBytes,
    required this.totalBytes,
    required this.doneItems,
    required this.totalItems,
    this.current,
  });

  final int doneBytes;
  final int totalBytes;
  final int doneItems;
  final int totalItems;

  /// Nom de l'élément en cours de traitement.
  final String? current;

  /// Entre 0 et 1, ou `null` tant que le volume total est inconnu.
  double? get fraction {
    if (totalBytes > 0) return (doneBytes / totalBytes).clamp(0.0, 1.0);
    if (totalItems > 0) return (doneItems / totalItems).clamp(0.0, 1.0);
    return null;
  }
}

/// Levée par [FileJob.result] lorsque l'opération a été annulée.
class FileOperationCancelled implements Exception {
  const FileOperationCancelled();

  @override
  String toString() => 'Opération annulée';
}

/// État d'une [FileJob].
enum FileJobStatus { running, done, cancelled, failed }

/// Point de la courbe de vitesse : instant (depuis le début) et octets/s.
typedef SpeedSample = ({Duration at, double bytesPerSecond});

/// Opération disque exécutée dans un isolate dédié, sans bloquer l'interface.
///
/// Notifie ses écouteurs à chaque progression et garde les statistiques
/// (vitesse lissée, pic, historique, temps restant) pour le panneau de suivi.
class FileJob extends ChangeNotifier {
  FileJob._(this.kind, this.sources, this.destination);

  static const maxSamples = 120;
  static const _sampleInterval = Duration(milliseconds: 250);

  final FileTransfer kind;
  final List<String> sources;
  final String destination;
  final DateTime startedAt = DateTime.now();

  final _progress = StreamController<FileProgress>.broadcast();
  final _result = Completer<List<String>>();
  final _clock = Stopwatch()..start();
  final _samples = <SpeedSample>[];
  SendPort? _control;
  bool _cancelRequested = false;
  FileProgress? _latest;
  String? _current;
  FileJobStatus _status = FileJobStatus.running;
  Object? _error;
  double _speed = 0;
  double _peak = 0;
  Duration _lastSampleAt = Duration.zero;
  int _lastSampleBytes = 0;

  Stream<FileProgress> get progress => _progress.stream;
  FileProgress? get latest => _latest;

  /// Dernier élément traité (conservé entre deux rapports sans nom).
  String? get current => _current;
  FileJobStatus get status => _status;
  Object? get error => _error;

  /// Chemins créés, dans l'ordre des sources.
  Future<List<String>> get result => _result.future;

  bool get isCancelling => _cancelRequested && !isDone;
  bool get isDone => _result.isCompleted;

  Duration get elapsed => _clock.elapsed;

  /// Vitesse lissée en octets par seconde.
  double get speed => _speed;
  double get peakSpeed => _peak;
  double get averageSpeed {
    final seconds = elapsed.inMicroseconds / 1e6;
    return seconds <= 0 ? 0 : (_latest?.doneBytes ?? 0) / seconds;
  }

  List<SpeedSample> get samples => List.unmodifiable(_samples);

  /// `null` tant que la vitesse ou le volume ne sont pas connus.
  Duration? get remaining {
    final latest = _latest;
    if (latest == null || isDone || latest.totalBytes <= 0) return null;
    final rate = _speed > 0 ? _speed : averageSpeed;
    if (rate <= 0) return null;
    final left = (latest.totalBytes - latest.doneBytes).clamp(0, 1 << 62);
    return Duration(milliseconds: (left / rate * 1000).round());
  }

  /// Les éléments déjà terminés sont conservés, l'élément en cours est retiré.
  void cancel() {
    if (_cancelRequested || isDone) return;
    _cancelRequested = true;
    _control?.send(true);
    notifyListeners();
  }

  void _report(FileProgress progress) {
    _latest = progress;
    if (progress.current != null) _current = progress.current;
    _sample(progress.doneBytes);
    if (!_progress.isClosed) _progress.add(progress);
    notifyListeners();
  }

  void _sample(int doneBytes) {
    final now = _clock.elapsed;
    final delta = now - _lastSampleAt;
    if (delta < _sampleInterval) return;
    final instant =
        (doneBytes - _lastSampleBytes) / (delta.inMicroseconds / 1e6);
    _speed = _samples.isEmpty ? instant : _speed * .6 + instant * .4;
    if (_speed > _peak) _peak = _speed;
    _samples.add((at: now, bytesPerSecond: _speed));
    if (_samples.length > maxSamples) _samples.removeAt(0);
    _lastSampleAt = now;
    _lastSampleBytes = doneBytes;
  }

  void _complete(List<String> paths) {
    if (isDone) return;
    _finish(FileJobStatus.done);
    _result.complete(paths);
  }

  void _fail(Object error) {
    if (isDone) return;
    _error = error;
    _finish(
      error is FileOperationCancelled
          ? FileJobStatus.cancelled
          : FileJobStatus.failed,
    );
    _result.completeError(error);
  }

  void _finish(FileJobStatus status) {
    _clock.stop();
    _status = status;
    _speed = 0;
    _progress.close();
    notifyListeners();
    FileJobs._finished(this);
  }
}

/// Registre des opérations en cours, affichées par le panneau de transferts.
class FileJobs {
  const FileJobs._();

  /// Délai avant de retirer une opération terminée du panneau.
  static Duration keepFinished = const Duration(seconds: 6);

  static final active = ValueNotifier<List<FileJob>>(const []);

  static void _add(FileJob job) => active.value = [...active.value, job];

  static void dismiss(FileJob job) {
    if (!active.value.contains(job)) return;
    active.value = [
      for (final other in active.value)
        if (other != job) other,
    ];
  }

  static void _finished(FileJob job) {
    if (job.status == FileJobStatus.failed) return;
    Timer(keepFinished, () => dismiss(job));
  }
}

class _Done {
  const _Done(this.paths);
  final List<String> paths;
}

class _Failed {
  const _Failed(this.error);
  final Object error;
}

/// Opérations disque utilisées par les actions sur fichiers.
class FileOperations {
  const FileOperations._();

  static const _chunkThreshold = 4 << 20;
  static const _chunkSize = 1 << 20;

  /// Copie [source] (fichier ou dossier) dans [destinationDir] et renvoie le
  /// chemin créé. Le nom est suffixé (`nom (2).ext`) s'il existe déjà.
  static Future<String> copy(String source, String destinationDir) =>
      _transfer(FileTransfer.copy, source, destinationDir, null, null);

  /// Déplace [source] dans [destinationDir] et renvoie le nouveau chemin.
  static Future<String> move(String source, String destinationDir) =>
      _transfer(FileTransfer.move, source, destinationDir, null, null);

  /// Lance le transfert de [sources] vers [destinationDir] dans un isolate.
  static FileJob start(
    FileTransfer kind,
    List<String> sources,
    String destinationDir,
  ) {
    final job = FileJob._(kind, List.unmodifiable(sources), destinationDir);
    FileJobs._add(job);
    final port = ReceivePort();
    port.listen((message) {
      switch (message) {
        case SendPort control:
          job._control = control;
          if (job._cancelRequested) control.send(true);
        case FileProgress progress:
          job._report(progress);
        case _Done(:final paths):
          job._complete(paths);
          port.close();
        case _Failed(:final error):
          job._fail(error);
          port.close();
        case null:
          job._fail(const FileSystemException('Opération interrompue'));
          port.close();
      }
    });
    Isolate.spawn(
      _worker,
      (port.sendPort, kind, List.of(sources), destinationDir),
      onExit: port.sendPort,
      debugName: 'file-${kind.name}',
    ).then(
      (_) {},
      onError: (Object error) {
        job._fail(error);
        port.close();
      },
    );
    return job;
  }

  static Future<void> _worker(
    (SendPort, FileTransfer, List<String>, String) args,
  ) async {
    final (out, kind, sources, destination) = args;
    final control = ReceivePort();
    var cancelled = false;
    control.listen((_) => cancelled = true);
    out.send(control.sendPort);
    final tracker = _Tracker(out.send, () => cancelled);
    try {
      final sizes = <(int, int)>[];
      for (final source in sources) {
        tracker.check();
        final size = await _measure(source);
        sizes.add(size);
        tracker.totalBytes += size.$1;
        tracker.totalItems += size.$2;
      }
      tracker.add(force: true);
      final results = <String>[];
      for (var i = 0; i < sources.length; i++) {
        results.add(
          await _transfer(kind, sources[i], destination, tracker, sizes[i]),
        );
      }
      tracker.add(force: true);
      out.send(_Done(results));
    } catch (error) {
      out.send(_Failed(error));
    } finally {
      control.close();
    }
  }

  static Future<String> _transfer(
    FileTransfer kind,
    String source,
    String destinationDir,
    _Tracker? tracker,
    (int, int)? size,
  ) async {
    _checkTarget(source, destinationDir);
    if (kind == FileTransfer.move && _same(parent(source), destinationDir)) {
      tracker?.add(bytes: size?.$1 ?? 0, items: size?.$2 ?? 0);
      return source;
    }
    final target = await uniquePath(destinationDir, name(source));
    try {
      if (kind == FileTransfer.copy) {
        await _copy(source, target, tracker);
      } else {
        await _relocate(source, target, tracker, size);
      }
    } on FileOperationCancelled {
      await _discard(target);
      rethrow;
    }
    return target;
  }

  static Future<void> _relocate(
    String source,
    String target,
    _Tracker? tracker,
    (int, int)? size,
  ) async {
    final type = await FileSystemEntity.type(source, followLinks: false);
    try {
      await _entity(source, type).rename(target);
      tracker?.add(bytes: size?.$1 ?? 0, items: size?.$2 ?? 0);
    } on FileSystemException {
      // Volumes différents : copie puis suppression.
      await _copy(source, target, tracker);
      await _entity(source, type).delete(recursive: true);
    }
  }

  static Future<String> uniquePath(String directory, String fileName) async {
    final dot = fileName.lastIndexOf('.');
    final hasExtension = dot > 0;
    final base = hasExtension ? fileName.substring(0, dot) : fileName;
    final extension = hasExtension ? fileName.substring(dot) : '';
    var candidate = join(directory, fileName);
    for (var i = 2; await _exists(candidate); i++) {
      candidate = join(directory, '$base ($i)$extension');
    }
    return candidate;
  }

  static String name(String path) {
    final parts = path
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  static String parent(String path) => File(path).parent.path;

  static String join(String directory, String child) =>
      '$directory${directory.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}$child';

  static void _checkTarget(String source, String destinationDir) {
    final from = _normalize(source);
    final to = _normalize(destinationDir);
    if (to == from || to.startsWith('$from/')) {
      throw FileSystemException(
        'Impossible de placer un dossier dans lui-même',
        source,
      );
    }
  }

  static bool _same(String a, String b) => _normalize(a) == _normalize(b);

  static String _normalize(String path) {
    var value = path.replaceAll('\\', '/');
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return Platform.isWindows ? value.toLowerCase() : value;
  }

  static Future<bool> _exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  static FileSystemEntity _entity(String path, FileSystemEntityType type) =>
      switch (type) {
        FileSystemEntityType.directory => Directory(path),
        FileSystemEntityType.link => Link(path),
        FileSystemEntityType.notFound => throw FileSystemException(
          'Élément introuvable',
          path,
        ),
        _ => File(path),
      };

  /// Octets et nombre d'éléments à traiter sous [path].
  static Future<(int, int)> _measure(String path) async {
    switch (await FileSystemEntity.type(path, followLinks: false)) {
      case FileSystemEntityType.directory:
        var bytes = 0;
        var items = 0;
        await for (final entity in Directory(
          path,
        ).list(recursive: true, followLinks: false)) {
          if (entity is File) {
            items++;
            try {
              bytes += await entity.length();
            } on FileSystemException {
              // Taille inconnue : seule la progression en éléments compte.
            }
          } else if (entity is Link) {
            items++;
          }
        }
        return (bytes, items);
      case FileSystemEntityType.file:
        return (await File(path).length(), 1);
      default:
        return (0, 1);
    }
  }

  static Future<void> _discard(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    try {
      await _entity(path, type).delete(recursive: true);
    } on FileSystemException {
      // Nettoyage au mieux.
    }
  }

  static Future<void> _copy(
    String source,
    String target,
    _Tracker? tracker,
  ) async {
    tracker?.check();
    final type = await FileSystemEntity.type(source, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(target).create();
        await for (final child in Directory(source).list(followLinks: false)) {
          await _copy(child.path, join(target, name(child.path)), tracker);
        }
      case FileSystemEntityType.link:
        await Link(target).create(await Link(source).target());
        tracker?.add(items: 1, current: name(source));
      case FileSystemEntityType.notFound:
        throw FileSystemException('Élément introuvable', source);
      default:
        await _copyFile(File(source), target, tracker);
    }
  }

  static Future<void> _copyFile(
    File source,
    String target,
    _Tracker? tracker,
  ) async {
    if (tracker == null) {
      await source.copy(target);
      return;
    }
    final fileName = name(source.path);
    final length = await source.length();
    if (length < _chunkThreshold) {
      await source.copy(target);
      tracker.add(bytes: length, items: 1, current: fileName);
      return;
    }
    // Copie par blocs : progression fine et annulation en cours de fichier.
    final input = await source.open();
    final output = await File(target).open(mode: FileMode.writeOnly);
    var complete = false;
    try {
      while (true) {
        tracker.check();
        final chunk = await input.read(_chunkSize);
        if (chunk.isEmpty) break;
        await output.writeFrom(chunk);
        tracker.add(bytes: chunk.length, current: fileName);
      }
      complete = true;
    } finally {
      await input.close();
      await output.close();
      if (!complete) await _discard(target);
    }
    await File(target).setLastModified(await source.lastModified());
    tracker.add(items: 1, current: fileName, force: true);
  }
}

class _Tracker {
  _Tracker(this._send, this._cancelled);

  final void Function(FileProgress) _send;
  final bool Function() _cancelled;
  final _clock = Stopwatch()..start();
  int totalBytes = 0;
  int totalItems = 0;
  int _doneBytes = 0;
  int _doneItems = 0;

  void check() {
    if (_cancelled()) throw const FileOperationCancelled();
  }

  /// Les messages sont limités pour ne pas saturer l'isolate de l'interface.
  void add({
    int bytes = 0,
    int items = 0,
    String? current,
    bool force = false,
  }) {
    _doneBytes += bytes;
    _doneItems += items;
    if (!force && _clock.elapsedMilliseconds < 60) return;
    _clock.reset();
    _send(
      FileProgress(
        doneBytes: _doneBytes,
        totalBytes: totalBytes,
        doneItems: _doneItems,
        totalItems: totalItems,
        current: current,
      ),
    );
  }
}

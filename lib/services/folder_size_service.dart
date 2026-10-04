import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// État du calcul de la taille d'un dossier.
@immutable
class FolderSizeState {
  const FolderSizeState._(this.bytes, {this.computing = false});

  static const idle = FolderSizeState._(null);
  static const pending = FolderSizeState._(null, computing: true);

  const FolderSizeState.done(int bytes) : this._(bytes);

  /// Taille totale, `null` tant qu'elle n'a pas été calculée.
  final int? bytes;
  final bool computing;
}

/// Calcule la taille des dossiers à la demande, dans un isolate, et garde
/// les résultats en mémoire pour la session.
class FolderSizeService {
  FolderSizeService._();

  static final _states = <String, ValueNotifier<FolderSizeState>>{};

  /// Incrémenté à chaque taille calculée, pour réordonner les listes triées
  /// par taille.
  static final revision = ValueNotifier<int>(0);
  static final jobs = ValueNotifier<List<FolderSizeJob>>(const []);
  static final queued = ValueNotifier<int>(0);
  static final _queues = <List<String>>[];

  static void cancelAll() {
    for (final queue in _queues) {
      queue.clear();
    }
    queued.value = 0;
    for (final job in jobs.value) {
      job.cancel();
    }
  }

  static void dismissAll() {
    if (queued.value > 0 ||
        jobs.value.any((job) => job.status == FolderSizeJobStatus.running)) {
      return;
    }
    jobs.value = const [];
  }

  static void dismiss(FolderSizeJob job) {
    if (job.status == FolderSizeJobStatus.running) return;
    jobs.value = [for (final other in jobs.value) if (other != job) other];
  }

  /// Taille calculée du dossier [path], `null` si inconnue.
  static int? bytesOf(String path) => _states[path]?.value.bytes;

  static ValueListenable<FolderSizeState> of(String path) =>
      _states.putIfAbsent(path, () => ValueNotifier(FolderSizeState.idle));

  /// Lance (ou relance) le calcul ; ignoré si un calcul est déjà en cours.
  /// Renvoie `false` si le calcul n'a pas abouti (annulé ou en erreur).
  static Future<bool> compute(String path) async {
    final state = of(path) as ValueNotifier<FolderSizeState>;
    if (state.value.computing) return false;
    final previous = state.value;
    state.value = FolderSizeState.pending;
    final job = FolderSizeJob._(path);
    _running[path] = job;
    jobs.value = [
      for (final previousJob in jobs.value)
        if (previousJob.path != path) previousJob,
      job,
    ];
    final int? bytes;
    try {
      bytes = await job.run(path);
    } finally {
      _running.remove(path);
    }
    if (bytes == null) {
      state.value = previous;
      return false;
    }
    state.value = FolderSizeState.done(bytes);
    revision.value++;
    return true;
  }

  /// Interrompt le calcul en cours de [path] et restaure la taille précédente.
  static void cancel(String path) => _running[path]?.cancel();

  static final _running = <String, FolderSizeJob>{};

  /// Chemins dont la taille n'est ni calculée ni en cours de calcul.
  static List<String> uncomputed(Iterable<String> paths) => [
    for (final path in paths)
      if (of(path).value.bytes == null && !of(path).value.computing) path,
  ];

  /// Calcule les tailles de [paths], quelques dossiers à la fois.
  static Future<void> computeAll(
    Iterable<String> paths, {
    int concurrency = 4,
  }) async {
    if (concurrency < 1) {
      throw ArgumentError.value(concurrency, 'concurrency', 'Must be positive');
    }
    final queue = paths.toSet().toList().reversed.toList();
    _queues.add(queue);
    queued.value += queue.length;
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final path = queue.removeLast();
        queued.value--;
        await compute(path);
      }
    }

    try {
      await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    } finally {
      queued.value -= queue.length;
      _queues.remove(queue);
    }
  }

  @visibleForTesting
  static void reset() {
    cancelAll();
    for (final job in _running.values) {
      job.cancel();
    }
    _states.clear();
    jobs.value = const [];
  }

  /// Somme des tailles des fichiers sous [path], sans suivre les liens ; les
  /// sous-dossiers inaccessibles sont ignorés.
  static int folderSizeSync(String path) => _scan(path).bytes;

  static FolderSizeProgress _scan(
    String path, {
    void Function(FolderSizeProgress)? onProgress,
  }) {
    var total = 0;
    var files = 0;
    var folders = 0;
    var skipped = 0;
    var currentPath = path;
    final clock = Stopwatch()..start();
    var lastReport = Duration.zero;
    FolderSizeProgress snapshot() => FolderSizeProgress(
      bytes: total,
      files: files,
      folders: folders,
      skipped: skipped,
      currentPath: currentPath,
    );
    void report() {
      if (clock.elapsed - lastReport < const Duration(milliseconds: 100)) {
        return;
      }
      lastReport = clock.elapsed;
      onProgress?.call(snapshot());
    }

    final pending = [Directory(path)];
    while (pending.isNotEmpty) {
      final directory = pending.removeLast();
      currentPath = directory.path;
      final List<FileSystemEntity> children;
      try {
        children = directory.listSync(followLinks: false);
      } on FileSystemException {
        if (directory.path == path) rethrow;
        skipped++;
        report();
        continue;
      }
      folders++;
      for (final child in children) {
        currentPath = child.path;
        if (child is Directory) {
          pending.add(child);
        } else if (child is File) {
          try {
            total += child.lengthSync();
            files++;
          } on FileSystemException {
            skipped++;
          }
        }
        report();
      }
      report();
    }
    final progress = snapshot();
    onProgress?.call(progress);
    return progress;
  }
}

enum FolderSizeJobStatus { running, done, cancelled, failed }

@immutable
class FolderSizeProgress {
  const FolderSizeProgress({
    this.bytes = 0,
    this.files = 0,
    this.folders = 0,
    this.skipped = 0,
    required this.currentPath,
  });

  final int bytes;
  final int files;
  final int folders;
  final int skipped;
  final String currentPath;
}

class FolderSizeJob extends ChangeNotifier {
  FolderSizeJob._(this.path)
    : latest = FolderSizeProgress(currentPath: path);

  final String path;
  final DateTime startedAt = DateTime.now();
  FolderSizeProgress latest;
  FolderSizeJobStatus status = FolderSizeJobStatus.running;
  String? error;
  final _clock = Stopwatch()..start();
  Duration get elapsed => _clock.elapsed;

  final _result = Completer<int?>();
  final _port = ReceivePort();
  Isolate? _isolate;
  bool _cancelled = false;

  Future<int?> run(String path) {
    _port.listen((message) {
      if (_result.isCompleted) return;
      switch (message) {
        case FolderSizeProgress progress:
          latest = progress;
          notifyListeners();
        case int bytes:
          _complete(FolderSizeJobStatus.done, bytes: bytes);
        case List<dynamic> details:
          error = details.first.toString();
          _complete(FolderSizeJobStatus.failed);
        case null:
          error = 'Le calcul a été interrompu.';
          _complete(FolderSizeJobStatus.failed);
      }
    });
    // Le résultat n'attend pas le démarrage : une annulation immédiate suffit.
    Isolate.spawn(
      _entry,
      (_port.sendPort, path),
      onExit: _port.sendPort,
      onError: _port.sendPort,
      debugName: 'folder-size',
    ).then(
      (isolate) {
        if (_cancelled) {
          isolate.kill(priority: Isolate.immediate);
        } else {
          _isolate = isolate;
        }
      },
      onError: (Object failure, StackTrace stack) {
        if (_result.isCompleted) return;
        error = failure.toString();
        _complete(FolderSizeJobStatus.failed);
      },
    );
    return _result.future.whenComplete(_port.close);
  }

  void cancel() {
    if (_result.isCompleted) return;
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _complete(FolderSizeJobStatus.cancelled);
  }

  void _complete(FolderSizeJobStatus value, {int? bytes}) {
    status = value;
    _clock.stop();
    _result.complete(bytes);
    notifyListeners();
  }

  static void _entry((SendPort, String) args) {
    final (port, path) = args;
    final progress = FolderSizeService._scan(path, onProgress: port.send);
    port.send(progress.bytes);
  }
}

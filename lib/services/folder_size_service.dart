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
    final job = _Job();
    _running[path] = job;
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

  static final _running = <String, _Job>{};

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
    final queue = paths.toList().reversed.toList();
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        await compute(queue.removeLast());
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  }

  @visibleForTesting
  static void reset() => _states.clear();

  /// Somme des tailles des fichiers sous [path], sans suivre les liens ; les
  /// sous-dossiers inaccessibles sont ignorés.
  static int folderSizeSync(String path) {
    var total = 0;
    final pending = [Directory(path)];
    while (pending.isNotEmpty) {
      final List<FileSystemEntity> children;
      try {
        children = pending.removeLast().listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final child in children) {
        if (child is Directory) {
          pending.add(child);
        } else if (child is File) {
          try {
            total += child.lengthSync();
          } on FileSystemException {
            // Fichier verrouillé ou supprimé entre-temps.
          }
        }
      }
    }
    return total;
  }
}

/// Calcul dans un isolate qu'on peut tuer ; le résultat est `null` s'il a été
/// annulé ou a échoué.
class _Job {
  final _result = Completer<int?>();
  final _port = ReceivePort();
  Isolate? _isolate;
  bool _cancelled = false;

  Future<int?> run(String path) {
    _port.listen((message) {
      if (!_result.isCompleted) {
        _result.complete(message is int ? message : null);
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
      onError: (_) {
        if (!_result.isCompleted) _result.complete(null);
      },
    );
    return _result.future.whenComplete(_port.close);
  }

  void cancel() {
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    if (!_result.isCompleted) _result.complete(null);
  }

  static void _entry((SendPort, String) args) {
    final (port, path) = args;
    port.send(FolderSizeService.folderSizeSync(path));
  }
}

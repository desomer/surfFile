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

  static ValueListenable<FolderSizeState> of(String path) =>
      _states.putIfAbsent(path, () => ValueNotifier(FolderSizeState.idle));

  /// Lance (ou relance) le calcul ; ignoré si un calcul est déjà en cours.
  static Future<void> compute(String path) async {
    final state = of(path) as ValueNotifier<FolderSizeState>;
    if (state.value.computing) return;
    final previous = state.value;
    state.value = FolderSizeState.pending;
    try {
      final bytes = await Isolate.run(
        () => folderSizeSync(path),
        debugName: 'folder-size',
      );
      state.value = FolderSizeState.done(bytes);
    } catch (_) {
      state.value = previous;
    }
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

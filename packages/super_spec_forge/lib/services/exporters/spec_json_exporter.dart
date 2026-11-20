/// Exportateur JSON structuré complet d'un [SpecForgeProject] ([SpecJsonExporter]).
library;

import 'dart:convert';

import '../../models/spec_forge_project.dart';

/// Sérialise un [SpecForgeProject] en JSON indenté réimportable.
abstract final class SpecJsonExporter {
  /// Retourne la représentation JSON formatée de [project].
  static String export(SpecForgeProject project, {bool pretty = true}) {
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(project.toJson());
  }
}

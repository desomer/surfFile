/// Moteur de masques de saisie/affichage, formatage numérique/date et
/// validation JSON Schema pour [SuperTextFieldConfig] et [SuperValue].
///
/// Fournit :
/// - [TextFieldValueType] et [TextFieldFormat] (typage et formats JSON Schema) ;
/// - [PatternMask] : masques à motifs (`#`, `A`, `U`, `L`, `*`, littéraux, `\`) ;
/// - [NumberFieldFormat] : formatage/déformatage numérique (`decimalDigits`,
///   `decimalSeparator`, `thousandsSeparator`) ;
/// - [DateFieldFormat] : conversion bidirectionnelle ISO 8601 ↔ `DateFormat` ;
/// - [TextFieldConstraintValidator] : validation des contraintes JSON Schema
///   (`required`, `minLength`, `maxLength`, `validationPattern`, `format`,
///   `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`, `multipleOf`,
///   `enumValues`, `constValue`).
library;

import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

/// Type de valeur attendu par la validation JSON Schema d'un champ texte.
enum TextFieldValueType {
  string('Texte'),
  integer('Entier'),
  number('Nombre');

  const TextFieldValueType(this.displayLabel);

  /// Libellé lisible affiché dans les éditeurs visuels.
  final String displayLabel;
}

/// Format JSON Schema standard reconnu par la validation d'un champ texte.
enum TextFieldFormat {
  none('Aucun', 'none'),
  email('E-mail', 'email'),
  uri('URI / URL', 'uri'),
  uuid('UUID', 'uuid'),
  date('Date (ISO)', 'date'),
  dateTime('Date et heure (ISO)', 'date-time'),
  time('Heure', 'time'),
  ipv4('Adresse IPv4', 'ipv4'),
  ipv6('Adresse IPv6', 'ipv6'),
  hostname('Nom d’hôte', 'hostname'),
  phone('Téléphone', 'phone');

  const TextFieldFormat(this.displayLabel, this.schemaName);

  /// Libellé affiché dans l'éditeur visuel.
  final String displayLabel;

  /// Nom canonique JSON Schema (`date-time`, `uri`, etc.).
  final String schemaName;

  /// Résout un [TextFieldFormat] depuis son nom Dart ou JSON Schema.
  static TextFieldFormat? tryParse(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase();
    return switch (normalized) {
      'none' || '' => TextFieldFormat.none,
      'email' => TextFieldFormat.email,
      'uri' || 'url' => TextFieldFormat.uri,
      'uuid' => TextFieldFormat.uuid,
      'date' => TextFieldFormat.date,
      'datetime' || 'date-time' => TextFieldFormat.dateTime,
      'time' => TextFieldFormat.time,
      'ipv4' => TextFieldFormat.ipv4,
      'ipv6' => TextFieldFormat.ipv6,
      'hostname' => TextFieldFormat.hostname,
      'phone' => TextFieldFormat.phone,
      _ => null,
    };
  }
}

/// Nature d'un emplacement dynamique dans un [PatternMask].
enum MaskSlotKind {
  /// `#` : chiffre ASCII `0-9`.
  digit,

  /// `A` : lettre Unicode (`\p{L}`).
  letter,

  /// `U` : lettre Unicode convertie en majuscule.
  upperLetter,

  /// `L` : lettre Unicode convertie en minuscule.
  lowerLetter,

  /// `*` : alphanumérique Unicode (`[\p{L}0-9]`).
  alphanumeric,
}

sealed class _MaskToken {
  const _MaskToken();
}

final class _SlotToken extends _MaskToken {
  const _SlotToken(this.kind);
  final MaskSlotKind kind;
}

final class _LiteralToken extends _MaskToken {
  const _LiteralToken(this.literal);
  final String literal;
}

/// Résultat d'une édition sous [PatternMask] (texte formaté et position curseur).
@immutable
class MaskEditOutcome {
  const MaskEditOutcome({required this.text, required this.cursorOffset});

  final String text;
  final int cursorOffset;
}

/// Masque à motifs pour la saisie et l'affichage (`#`, `A`, `U`, `L`, `*`, `\`).
class PatternMask {
  PatternMask(this.pattern) : _tokens = _compile(pattern);

  /// Motif brut configuré (ex. `##/##/####`, `UU-###-UU`).
  final String pattern;
  final List<_MaskToken> _tokens;

  static final _digitRegExp = RegExp(r'^[0-9]$');
  static final _letterRegExp = RegExp(r'^\p{L}$', unicode: true);
  static final _alnumRegExp = RegExp(r'^[\p{L}0-9]$', unicode: true);

  /// Nombre d'emplacements saisissables dans ce masque.
  int get slotCount => _tokens.whereType<_SlotToken>().length;

  /// Vrai si le motif contient au moins un emplacement saisissable.
  bool get hasSlots => slotCount > 0;

  /// Vérifie la validité syntaxique du masque non vide.
  static void validatePattern(String pattern) {
    if (pattern.isEmpty) return;
    final mask = PatternMask(pattern);
    if (!mask.hasSlots) {
      throw const FormatException(
        'Le masque doit contenir au moins un emplacement (#, A, U, L ou *).',
      );
    }
  }

  static List<_MaskToken> _compile(String pattern) {
    if (pattern.isEmpty) return const [];
    final tokens = <_MaskToken>[];
    final chars = pattern.characters.toList();
    for (var i = 0; i < chars.length; i++) {
      final ch = chars[i];
      if (ch == r'\') {
        if (i + 1 >= chars.length) {
          throw const FormatException(
            'Échappement "\\" incomplet en fin de masque.',
          );
        }
        tokens.add(_LiteralToken(chars[++i]));
        continue;
      }
      tokens.add(switch (ch) {
        '#' => const _SlotToken(MaskSlotKind.digit),
        'A' => const _SlotToken(MaskSlotKind.letter),
        'U' => const _SlotToken(MaskSlotKind.upperLetter),
        'L' => const _SlotToken(MaskSlotKind.lowerLetter),
        '*' => const _SlotToken(MaskSlotKind.alphanumeric),
        _ => _LiteralToken(ch),
      });
    }
    return List.unmodifiable(tokens);
  }

  static String? _matchSlot(MaskSlotKind kind, String ch) {
    switch (kind) {
      case MaskSlotKind.digit:
        return _digitRegExp.hasMatch(ch) ? ch : null;
      case MaskSlotKind.letter:
        return _letterRegExp.hasMatch(ch) ? ch : null;
      case MaskSlotKind.upperLetter:
        return _letterRegExp.hasMatch(ch) ? ch.toUpperCase() : null;
      case MaskSlotKind.lowerLetter:
        return _letterRegExp.hasMatch(ch) ? ch.toLowerCase() : null;
      case MaskSlotKind.alphanumeric:
        return _alnumRegExp.hasMatch(ch) ? ch : null;
    }
  }

  int? _nextSlotIndex(int start) {
    for (var i = start; i < _tokens.length; i++) {
      if (_tokens[i] is _SlotToken) return i;
    }
    return null;
  }

  /// Extrait uniquement les caractères de slots valides depuis [input] (en
  /// sautant les littéraux correspondants ou les caractères incompatibles).
  String strip(String input) {
    if (_tokens.isEmpty || input.isEmpty) return '';
    final buffer = StringBuffer();
    var tokenIndex = 0;
    for (final ch in input.characters) {
      if (tokenIndex >= _tokens.length) break;
      final token = _tokens[tokenIndex];
      if (token is _LiteralToken) {
        if (ch == token.literal) {
          tokenIndex++;
          continue;
        }
        final nextSlot = _nextSlotIndex(tokenIndex + 1);
        if (nextSlot == null) break;
        final slot = _tokens[nextSlot] as _SlotToken;
        final normalized = _matchSlot(slot.kind, ch);
        if (normalized != null) {
          buffer.write(normalized);
          tokenIndex = nextSlot + 1;
        }
      } else if (token is _SlotToken) {
        final normalized = _matchSlot(token.kind, ch);
        if (normalized != null) {
          buffer.write(normalized);
          tokenIndex++;
        }
      }
    }
    return buffer.toString();
  }

  /// Formate [input] (brut ou déjà partiellement masqué) selon ce masque.
  String format(String input) {
    if (_tokens.isEmpty) return input;
    final raw = strip(input).characters.toList();
    if (raw.isEmpty) return '';
    return _formatRawChars(raw).text;
  }

  MaskEditOutcome _formatRawChars(List<String> raw, {int? rawCursor}) {
    if (raw.isEmpty) {
      return const MaskEditOutcome(text: '', cursorOffset: 0);
    }
    final buffer = StringBuffer();
    var rawIndex = 0;
    var tokenIndex = 0;
    int? resolvedCursor = rawCursor == 0 ? 0 : null;
    while (rawIndex < raw.length && tokenIndex < _tokens.length) {
      final token = _tokens[tokenIndex];
      if (token is _LiteralToken) {
        buffer.write(token.literal);
        tokenIndex++;
      } else if (token is _SlotToken) {
        final normalized = _matchSlot(token.kind, raw[rawIndex]);
        if (normalized != null) {
          buffer.write(normalized);
          rawIndex++;
          tokenIndex++;
          if (rawCursor != null && rawIndex == rawCursor) {
            resolvedCursor = buffer.length;
          }
        } else {
          rawIndex++;
        }
      }
    }
    final text = buffer.toString();
    return MaskEditOutcome(
      text: text,
      cursorOffset: resolvedCursor ?? text.length,
    );
  }

  /// Indique si [input] remplit tous les emplacements du masque.
  bool isComplete(String input) =>
      _tokens.isEmpty || strip(input).characters.length >= slotCount;

  /// Compte combien de caractères de slots valides précèdent [codeUnitOffset]
  /// dans [text].
  int _countRawBefore(String text, int codeUnitOffset) {
    if (codeUnitOffset <= 0 || text.isEmpty) return 0;
    final clamped = codeUnitOffset.clamp(0, text.length);
    return strip(text.substring(0, clamped)).characters.length;
  }

  /// Calcule la nouvelle valeur masquée et la position de curseur adaptée
  /// lors d'une frappe, d'un collage ou d'une suppression.
  MaskEditOutcome edit({
    required String oldText,
    required String newText,
    required int oldCursor,
    required int newCursor,
    required bool oldSelectionCollapsed,
    required bool newSelectionCollapsed,
  }) {
    final oldRaw = strip(oldText);
    var newRawChars = strip(newText).characters.toList();
    var rawCursor = newCursor < 0
        ? newRawChars.length
        : _countRawBefore(newText, newCursor);

    // Si l'utilisateur a pressé Retour arrière directement sur un littéral du
    // masque, on supprime le caractère de slot qui précédait ce littéral.
    if (newText.length < oldText.length &&
        newRawChars.join() == oldRaw &&
        oldSelectionCollapsed &&
        newSelectionCollapsed &&
        oldCursor > 0 &&
        rawCursor > 0 &&
        rawCursor <= newRawChars.length) {
      newRawChars = List<String>.of(newRawChars)..removeAt(rawCursor - 1);
      rawCursor--;
    }

    return _formatRawChars(newRawChars, rawCursor: rawCursor);
  }
}

/// Formatage et déformatage de nombres pour affichage et saisie.
abstract final class NumberFieldFormat {
  static final _canonicalPattern = RegExp(r'^[+-]?\d+(?:\.\d+)?$');

  /// Convertit un texte saisi ou formaté (avec éventuels séparateurs de
  /// milliers et virgule décimale) vers sa forme canonique JSON (`1234.5`).
  static String toStorage(
    String input, {
    String decimalSeparator = '.',
    String thousandsSeparator = '',
  }) {
    var text = input.trim();
    if (text.isEmpty) return '';
    if (thousandsSeparator.isNotEmpty) {
      text = text.replaceAll(thousandsSeparator, '');
      if (thousandsSeparator == '\u00A0' || thousandsSeparator == ' ') {
        text = text.replaceAll(' ', '').replaceAll('\u00A0', '');
      }
    }
    if (decimalSeparator != '.') {
      text = text.replaceAll(decimalSeparator, '.');
    }
    return text;
  }

  /// Formate [storageText] pour l'affichage (hors focus ou en mode `display`).
  ///
  /// Lorsque [focused] vaut `true`, supprime les séparateurs de milliers et
  /// conserve uniquement [decimalSeparator] sans imposer de zéros finaux.
  static String formatDisplay(
    String storageText, {
    int? decimalDigits,
    String decimalSeparator = '.',
    String thousandsSeparator = '',
    bool focused = false,
  }) {
    final canonical = toStorage(
      storageText,
      decimalSeparator: decimalSeparator,
      thousandsSeparator: thousandsSeparator,
    );
    if (canonical.isEmpty) return '';
    if (!_canonicalPattern.hasMatch(canonical)) {
      return storageText;
    }
    final parsed = double.tryParse(canonical);
    if (parsed == null || !parsed.isFinite) {
      return storageText;
    }

    if (focused) {
      return decimalSeparator == '.'
          ? canonical
          : canonical.replaceAll('.', decimalSeparator);
    }

    final String fixed;
    if (decimalDigits != null) {
      fixed = parsed.toStringAsFixed(decimalDigits);
    } else {
      fixed = canonical;
    }

    final sign = fixed.startsWith('-') || fixed.startsWith('+')
        ? fixed.substring(0, 1)
        : '';
    final unsigned = sign.isEmpty ? fixed : fixed.substring(1);
    final dotIndex = unsigned.indexOf('.');
    final intPart = dotIndex == -1 ? unsigned : unsigned.substring(0, dotIndex);
    final fracPart = dotIndex == -1 ? '' : unsigned.substring(dotIndex + 1);

    final groupedInt = thousandsSeparator.isEmpty
        ? intPart
        : _groupThousands(intPart, thousandsSeparator);

    if (fracPart.isEmpty) {
      return '$sign$groupedInt';
    }
    return '$sign$groupedInt$decimalSeparator$fracPart';
  }

  static String _groupThousands(String digits, String separator) {
    if (digits.length <= 3) return digits;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final remaining = digits.length - i;
      if (i > 0 && remaining % 3 == 0) {
        buffer.write(separator);
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// Conversion bidirectionnelle entre dates ISO 8601 (stockage) et format
/// d'affichage `intl` (`dateFormat`).
abstract final class DateFieldFormat {
  static final _timePattern = RegExp(r'[HhmsS]');
  static final _isoDatePrefix = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _isoDateTimePrefix = RegExp(r'^\d{4}-\d{2}-\d{2}[Tt ]');

  /// Vérifie que [pattern] est un motif `DateFormat` utilisable.
  static void validatePattern(String pattern) {
    if (pattern.isEmpty) return;
    if (pattern.trim().isEmpty) {
      throw const FormatException('Le format de date ne peut pas être vide.');
    }
    try {
      DateFormat(pattern).format(DateTime(2026, 1, 15, 14, 30));
    } on FormatException {
      throw const FormatException('Format de date invalide.');
    } on ArgumentError {
      throw const FormatException('Format de date invalide.');
    }
  }

  /// Indique si [pattern] inclut une composante horaire.
  static bool includesTime(String pattern) => _timePattern.hasMatch(pattern);

  /// Formate une date ISO stockée vers le motif d'affichage [pattern].
  static String formatDisplay(String storageText, String pattern) {
    final trimmed = storageText.trim();
    if (trimmed.isEmpty || pattern.isEmpty) return storageText;
    final parsed = _parseIso(trimmed) ?? _tryParsePattern(trimmed, pattern);
    if (parsed == null) return storageText;
    final local = parsed.isUtc ? parsed.toLocal() : parsed;
    return DateFormat(pattern).format(local);
  }

  /// Convertit une saisie affichée selon [pattern] vers ISO 8601.
  ///
  /// Retourne `null` si [displayText] ne correspond pas strictement à [pattern].
  static String? tryToIso(
    String displayText,
    String pattern, {
    bool forceDateTime = false,
  }) {
    final trimmed = displayText.trim();
    if (trimmed.isEmpty) return '';
    if (pattern.isEmpty) return trimmed;
    final parsed = _tryParsePattern(trimmed, pattern);
    if (parsed == null) return null;
    if (forceDateTime || includesTime(pattern)) {
      return parsed.toUtc().toIso8601String();
    }
    final y = parsed.year.toString().padLeft(4, '0');
    final m = parsed.month.toString().padLeft(2, '0');
    final d = parsed.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static DateTime? _parseIso(String text) {
    if (_isoDatePrefix.hasMatch(text)) {
      return _parseStrictIsoDate(text);
    }
    if (_isoDateTimePrefix.hasMatch(text)) {
      if (_parseStrictIsoDate(text.substring(0, 10)) == null) return null;
      return DateTime.tryParse(text);
    }
    return null;
  }

  static DateTime? _tryParsePattern(String text, String pattern) {
    try {
      final formatter = DateFormat(pattern);
      final parsed = formatter.parseStrict(text);
      // Vérifie que la représentation formatée correspond à l'année attendue
      // (évite les années tronquées du type `26` pour `yyyy`).
      if (pattern.contains('yyyy') && parsed.year < 1000) return null;
      return parsed;
    } on FormatException {
      return null;
    }
  }

  static DateTime? _parseStrictIsoDate(String text) {
    final parts = text.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null || m < 1 || m > 12 || d < 1) {
      return null;
    }
    final dt = DateTime(y, m, d);
    if (dt.year != y || dt.month != m || dt.day != d) return null;
    return dt;
  }
}

/// Moteur de validation JSON Schema pour les valeurs de [SuperTextFieldConfig].
abstract final class TextFieldConstraintValidator {
  static final _uuidRegExp = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _emailRegExp = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
  );
  static final _timeRegExp = RegExp(
    r'^([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d)(?:\.\d{1,6})?)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)?$',
  );
  static final _isoDateRegExp = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final _isoDateTimeRegExp = RegExp(
    r'^\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:[Zz]|[+-]\d{2}:\d{2})?$',
  );
  static final _hostnameLabelRegExp = RegExp(
    r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$',
  );
  static final _phoneCharsRegExp = RegExp(r'^\+?[0-9\s\-\.\(\)]{6,24}$');

  /// Valide [storageValue] (et éventuellement [displayValue] pour un champ
  /// masqué ou formaté en date) selon les contraintes fournies.
  ///
  /// Retourne `null` si valide, sinon le message d'erreur approprié.
  static String? validate({
    required String storageValue,
    String? displayValue,
    bool obscureText = false,
    String mask = '',
    String dateFormat = '',
    TextFieldValueType valueType = TextFieldValueType.string,
    bool required = false,
    int? minLength,
    int? maxLength,
    String validationPattern = '',
    TextFieldFormat format = TextFieldFormat.none,
    double? minimum,
    double? maximum,
    double? exclusiveMinimum,
    double? exclusiveMaximum,
    double? multipleOf,
    List<String> enumValues = const [],
    String? constValue,
    String validationMessage = '',
    String decimalSeparator = '.',
    String thousandsSeparator = '',
  }) {
    String fail(String fallback) =>
        validationMessage.trim().isNotEmpty ? validationMessage.trim() : fallback;

    final isEmpty =
        storageValue.isEmpty || (!obscureText && storageValue.trim().isEmpty);
    if (required && isEmpty) {
      return fail('Ce champ est obligatoire.');
    }
    if (isEmpty) {
      return null;
    }

    if (mask.isNotEmpty) {
      final candidate = displayValue ?? storageValue;
      if (!PatternMask(mask).isComplete(candidate)) {
        return fail('Saisie incomplète selon le masque ($mask).');
      }
    }

    if (dateFormat.isNotEmpty) {
      final candidate = (displayValue ?? storageValue).trim();
      final isoFromDisplay = DateFieldFormat.tryToIso(
        candidate,
        dateFormat,
        forceDateTime: format == TextFieldFormat.dateTime,
      );
      final isoValid = DateFieldFormat._parseIso(storageValue.trim()) != null;
      if (isoFromDisplay == null && !isoValid) {
        return fail('Date invalide (format attendu : $dateFormat).');
      }
    }

    final charLength = storageValue.characters.length;
    if (minLength != null && charLength < minLength) {
      return fail('Longueur minimale : $minLength caractère(s).');
    }
    if (maxLength != null && charLength > maxLength) {
      return fail('Longueur maximale : $maxLength caractère(s).');
    }

    final hasNumericBounds =
        minimum != null ||
        maximum != null ||
        exclusiveMinimum != null ||
        exclusiveMaximum != null ||
        multipleOf != null;
    if (valueType != TextFieldValueType.string || hasNumericBounds) {
      final canonical = NumberFieldFormat.toStorage(
        storageValue,
        decimalSeparator: decimalSeparator,
        thousandsSeparator: thousandsSeparator,
      );
      final parsed = num.tryParse(canonical);
      if (parsed == null || !parsed.isFinite) {
        return fail(
          valueType == TextFieldValueType.integer
              ? 'Nombre entier valide requis.'
              : 'Nombre valide requis.',
        );
      }
      if (valueType == TextFieldValueType.integer &&
          parsed != parsed.roundToDouble()) {
        return fail('Nombre entier valide requis.');
      }
      final asDouble = parsed.toDouble();
      if (minimum != null && asDouble < minimum) {
        return fail('La valeur doit être supérieure ou égale à ${_fmt(minimum)}.');
      }
      if (exclusiveMinimum != null && asDouble <= exclusiveMinimum) {
        return fail(
          'La valeur doit être strictement supérieure à ${_fmt(exclusiveMinimum)}.',
        );
      }
      if (maximum != null && asDouble > maximum) {
        return fail('La valeur doit être inférieure ou égale à ${_fmt(maximum)}.');
      }
      if (exclusiveMaximum != null && asDouble >= exclusiveMaximum) {
        return fail(
          'La valeur doit être strictement inférieure à ${_fmt(exclusiveMaximum)}.',
        );
      }
      if (multipleOf != null) {
        final ratio = asDouble / multipleOf;
        if ((ratio - ratio.round()).abs() > 1e-9) {
          return fail('La valeur doit être un multiple de ${_fmt(multipleOf)}.');
        }
      }
    }

    if (validationPattern.isNotEmpty) {
      if (!RegExp(validationPattern, unicode: true).hasMatch(storageValue)) {
        return fail('Le format ne correspond pas au motif requis.');
      }
    }

    if (format != TextFieldFormat.none) {
      final formatError = _validateFormat(format, storageValue);
      if (formatError != null) {
        return fail(formatError);
      }
    }

    if (constValue != null && storageValue != constValue) {
      return fail('La valeur attendue est « $constValue ».');
    }

    if (enumValues.isNotEmpty && !enumValues.contains(storageValue)) {
      return fail('Valeur non autorisée.');
    }

    return null;
  }

  static String? _validateFormat(TextFieldFormat format, String value) {
    final trimmed = value.trim();
    switch (format) {
      case TextFieldFormat.none:
        return null;
      case TextFieldFormat.email:
        if (!_emailRegExp.hasMatch(trimmed)) {
          return 'Adresse e-mail invalide.';
        }
        return null;
      case TextFieldFormat.uri:
        final uri = Uri.tryParse(trimmed);
        if (uri == null ||
            !uri.hasScheme ||
            ((uri.scheme == 'http' || uri.scheme == 'https') &&
                uri.host.isEmpty)) {
          return 'URI ou URL invalide.';
        }
        return null;
      case TextFieldFormat.uuid:
        if (!_uuidRegExp.hasMatch(trimmed)) {
          return 'Identifiant UUID invalide.';
        }
        return null;
      case TextFieldFormat.date:
        if (!_isValidIsoDate(trimmed)) {
          return 'Date invalide (format attendu : AAAA-MM-JJ).';
        }
        return null;
      case TextFieldFormat.dateTime:
        if (!_isoDateTimeRegExp.hasMatch(trimmed)) {
          return 'Date et heure ISO invalides.';
        }
        final datePart = trimmed.substring(0, 10);
        if (!_isValidIsoDate(datePart) || DateTime.tryParse(trimmed) == null) {
          return 'Date et heure ISO invalides.';
        }
        return null;
      case TextFieldFormat.time:
        if (!_timeRegExp.hasMatch(trimmed)) {
          return 'Heure invalide (format attendu : HH:MM ou HH:MM:SS).';
        }
        return null;
      case TextFieldFormat.ipv4:
        if (!_isValidIpv4(trimmed)) {
          return 'Adresse IPv4 invalide.';
        }
        return null;
      case TextFieldFormat.ipv6:
        try {
          Uri.parseIPv6Address(trimmed);
          return null;
        } on FormatException {
          return 'Adresse IPv6 invalide.';
        }
      case TextFieldFormat.hostname:
        if (!_isValidHostname(trimmed)) {
          return 'Nom d’hôte invalide.';
        }
        return null;
      case TextFieldFormat.phone:
        if (!_isValidPhone(trimmed)) {
          return 'Numéro de téléphone invalide.';
        }
        return null;
    }
  }

  static bool _isValidIsoDate(String value) {
    final match = _isoDateRegExp.firstMatch(value);
    if (match == null) return false;
    final y = int.tryParse(match[1]!);
    final m = int.tryParse(match[2]!);
    final d = int.tryParse(match[3]!);
    if (y == null || m == null || d == null || m < 1 || m > 12 || d < 1) {
      return false;
    }
    final dt = DateTime(y, m, d);
    return dt.year == y && dt.month == m && dt.day == d;
  }

  static bool _isValidIpv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      if (part.isEmpty || part.length > 3) return false;
      if (part.length > 1 && part.startsWith('0')) return false;
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return false;
    }
    return true;
  }

  static bool _isValidHostname(String value) {
    if (value.isEmpty || value.length > 253) return false;
    final labels = value.split('.');
    if (labels.any((label) => !_hostnameLabelRegExp.hasMatch(label))) {
      return false;
    }
    return true;
  }

  static bool _isValidPhone(String value) {
    if (!_phoneCharsRegExp.hasMatch(value)) return false;
    final digits = RegExp(r'\d').allMatches(value).length;
    return digits >= 6 && digits <= 15;
  }

  static String _fmt(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

/// Profil de contraintes et de masques extrait d'un JSON Schema de repository
/// pour un attribut donné.
@immutable
class SchemaFieldProfile {
  /// Crée un [SchemaFieldProfile].
  const SchemaFieldProfile({
    this.valueType = TextFieldValueType.string,
    this.required = false,
    this.minLength,
    this.maxLength,
    this.validationPattern = '',
    this.format = TextFieldFormat.none,
    this.minimum,
    this.maximum,
    this.exclusiveMinimum,
    this.exclusiveMaximum,
    this.multipleOf,
    this.enumValues = const [],
    this.constValue,
    this.validationMessage,
    this.mask,
    this.maskIncludeLiterals,
    this.dateFormat,
    this.decimalDigits,
    this.decimalSeparator,
    this.thousandsSeparator,
    this.lockedKeys = const {},
  });

  final TextFieldValueType valueType;
  final bool required;
  final int? minLength;
  final int? maxLength;
  final String validationPattern;
  final TextFieldFormat format;
  final double? minimum;
  final double? maximum;
  final double? exclusiveMinimum;
  final double? exclusiveMaximum;
  final double? multipleOf;
  final List<String> enumValues;
  final String? constValue;
  final String? validationMessage;

  final String? mask;
  final bool? maskIncludeLiterals;
  final String? dateFormat;
  final int? decimalDigits;
  final String? decimalSeparator;
  final String? thousandsSeparator;

  /// Clés de `SuperTextFieldConfig` imposées par le JSON Schema et grisées dans
  /// le wizard de propriétés lorsque l'héritage est actif.
  final Set<String> lockedKeys;

  @override
  bool operator ==(Object other) =>
      other is SchemaFieldProfile &&
      valueType == other.valueType &&
      required == other.required &&
      minLength == other.minLength &&
      maxLength == other.maxLength &&
      validationPattern == other.validationPattern &&
      format == other.format &&
      minimum == other.minimum &&
      maximum == other.maximum &&
      exclusiveMinimum == other.exclusiveMinimum &&
      exclusiveMaximum == other.exclusiveMaximum &&
      multipleOf == other.multipleOf &&
      listEquals(enumValues, other.enumValues) &&
      constValue == other.constValue &&
      validationMessage == other.validationMessage &&
      mask == other.mask &&
      maskIncludeLiterals == other.maskIncludeLiterals &&
      dateFormat == other.dateFormat &&
      decimalDigits == other.decimalDigits &&
      decimalSeparator == other.decimalSeparator &&
      thousandsSeparator == other.thousandsSeparator &&
      setEquals(lockedKeys, other.lockedKeys);

  @override
  int get hashCode => Object.hashAll([
    valueType,
    required,
    minLength,
    maxLength,
    validationPattern,
    format,
    minimum,
    maximum,
    exclusiveMinimum,
    exclusiveMaximum,
    multipleOf,
    Object.hashAll(enumValues),
    constValue,
    validationMessage,
    mask,
    maskIncludeLiterals,
    dateFormat,
    decimalDigits,
    decimalSeparator,
    thousandsSeparator,
    Object.hashAllUnordered(lockedKeys),
  ]);
}


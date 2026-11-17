/// Analyseur incrémental de flux JSON SSE ([VibeIncrementalStreamParser]) pour le chat Vibe IA.
///
/// Extrait en temps réel le champ texte de premier niveau `"message"`,
/// les entrées complètes du patch `"vibe"` (`partialVibePatch`, `patchRevision`,
/// `hasVibeObject`, `estimatedComponentCount`) et la détection du questionnaire
/// `"askUser"` (`hasAskUserObject`) au fil de l'arrivée des fragments texte bruts,
/// avant la fin complète du flux JSON.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// État instantané immuable décodé par [VibeIncrementalStreamParser] pendant le streaming SSE.
@immutable
class VibeStreamSnapshot {
  /// Construit un instantané immuable de progression du flux Vibe IA.
  const VibeStreamSnapshot({
    this.message,
    this.isMessageComplete = false,
    this.hasVibeObject = false,
    this.hasAskUserObject = false,
    this.estimatedComponentCount = 0,
    this.receivedChars = 0,
    this.partialVibePatch,
    this.patchRevision = 0,
  });

  /// Instantané initial vide avant réception de tout fragment.
  static const VibeStreamSnapshot empty = VibeStreamSnapshot();

  /// Caractères décodés du champ `"message"` de premier niveau reçus jusqu'ici,
  /// ou `null` tant que le guillemet ouvrant de sa valeur chaîne n'a pas été atteint.
  final String? message;

  /// Indique si le guillemet fermant non échappé du champ `"message"` de premier niveau a été atteint.
  final bool isMessageComplete;

  /// Indique si un champ `"vibe"` de premier niveau débutant par `{` a été détecté.
  ///
  /// Reste `false` lorsque `"vibe"` vaut `null` ou est absent.
  final bool hasVibeObject;

  /// Indique si un champ `"askUser"` de premier niveau débutant par `{` ou `[` a été détecté.
  ///
  /// Reste `false` lorsque `"askUser"` vaut `null`, un primitif ou est absent.
  final bool hasAskUserObject;

  /// Nombre en direct de clés directes détectées dans `"vibe" -> "components"`
  /// (ou `"vibe" -> "data" -> "components"`).
  final int estimatedComponentCount;

  /// Nombre total de caractères bruts accumulés dans le tampon depuis le début du flux.
  final int receivedChars;

  /// Patch cumulatif immuable contenant toutes les entrées de `"vibe"` déjà
  /// complètement fermées dans le flux JSON, ou `null` tant qu'aucune entrée n'est complète.
  final Map<String, dynamic>? partialVibePatch;

  /// Compteur monotone incrémenté à chaque nouvelle entrée complète ajoutée à [partialVibePatch].
  final int patchRevision;

  /// Retourne une copie modifiée de cet instantané.
  VibeStreamSnapshot copyWith({
    String? message,
    bool clearMessage = false,
    bool? isMessageComplete,
    bool? hasVibeObject,
    bool? hasAskUserObject,
    int? estimatedComponentCount,
    int? receivedChars,
    Map<String, dynamic>? partialVibePatch,
    bool clearPartialVibePatch = false,
    int? patchRevision,
  }) => VibeStreamSnapshot(
    message: clearMessage ? null : (message ?? this.message),
    isMessageComplete: isMessageComplete ?? this.isMessageComplete,
    hasVibeObject: hasVibeObject ?? this.hasVibeObject,
    hasAskUserObject: hasAskUserObject ?? this.hasAskUserObject,
    estimatedComponentCount:
        estimatedComponentCount ?? this.estimatedComponentCount,
    receivedChars: receivedChars ?? this.receivedChars,
    partialVibePatch: clearPartialVibePatch
        ? null
        : (partialVibePatch ?? this.partialVibePatch),
    patchRevision: patchRevision ?? this.patchRevision,
  );

  /// Compare deux instantanés par égalité de valeur.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VibeStreamSnapshot &&
          other.message == message &&
          other.isMessageComplete == isMessageComplete &&
          other.hasVibeObject == hasVibeObject &&
          other.hasAskUserObject == hasAskUserObject &&
          other.estimatedComponentCount == estimatedComponentCount &&
          other.receivedChars == receivedChars &&
          other.patchRevision == patchRevision &&
          (other.partialVibePatch == null) == (partialVibePatch == null);

  /// Code de hachage cohérent avec [operator ==].
  @override
  int get hashCode => Object.hash(
    message,
    isMessageComplete,
    hasVibeObject,
    hasAskUserObject,
    estimatedComponentCount,
    receivedChars,
    patchRevision,
    partialVibePatch != null,
  );

  /// Représentation textuelle de diagnostic de l'instantané.
  @override
  String toString() =>
      'VibeStreamSnapshot('
      'message: $message, '
      'isMessageComplete: $isMessageComplete, '
      'hasVibeObject: $hasVibeObject, '
      'hasAskUserObject: $hasAskUserObject, '
      'estimatedComponentCount: $estimatedComponentCount, '
      'receivedChars: $receivedChars, '
      'patchRevision: $patchRevision'
      ')';
}

/// Automate d'analyse JSON incrémentale caractère par caractère pour les réponses SSE Vibe IA.
///
/// Conserve son état interne entre les appels à [addChunk] afin de décoder sans
/// relecture intégrale les séquences d'échappement JSON (`\"`, `\\`, `\n`, `\uXXXX`,
/// paires de substitution UTF-16) et de suivre la profondeur structurelle exacte.
class VibeIncrementalStreamParser {
  /// Crée un nouvel analyseur incrémental positionné à l'état initial vide.
  VibeIncrementalStreamParser();

  final StringBuffer _rawBuffer = StringBuffer();
  String? _cachedRawBuffer = '';
  int _receivedChars = 0;

  _ParserStage _stage = _ParserStage.leadingWhitespace;
  int _fenceTickCount = 0;

  final List<_ContainerFrame> _stack = <_ContainerFrame>[];

  bool _inString = false;
  _StringTarget _stringTarget = _StringTarget.skip;
  _StrMode _strMode = _StrMode.normal;
  int _unicodeDigits = 0;
  int _unicodeValue = 0;
  int? _pendingHighSurrogate;

  bool _inPrimitive = false;

  final StringBuffer _keyBuffer = StringBuffer();
  bool _keyOverflow = false;

  final StringBuffer _messageBuffer = StringBuffer();
  String? _cachedMessage;
  bool _hasMessageStarted = false;
  bool _isMessageComplete = false;

  static const Set<String> _sectionMapKeys = <String>{
    'components',
    'styles',
    'behaviors',
    'usages',
  };

  static const Set<String> _ignoredMetaKeys = <String>{
    'version',
    'vibe',
    'merge',
    'format',
    'groups',
    'data',
  };

  static const Set<String> _directRootPatchKeys = <String>{
    'mode',
    'accent',
    'backgroundOpacity',
    'windowOpacity',
    'windowEffect',
    'pageCatalog',
  };

  bool _hasVibeObject = false;
  bool _hasAskUserObject = false;
  final Set<String> _seenComponentIds = <String>{};
  int _estimatedComponentCount = 0;

  _ActiveValueCapture? _activeCapture;
  final Map<String, Object?> _rootPatchEntries = <String, Object?>{};
  final Map<String, Map<String, Object?>> _sectionPatchEntries =
      <String, Map<String, Object?>>{};
  Map<String, dynamic>? _cachedPartialPatch;
  int _patchRevision = 0;

  VibeStreamSnapshot _current = VibeStreamSnapshot.empty;

  /// Dernier instantané décodé du flux en cours.
  VibeStreamSnapshot get current => _current;

  /// Texte brut complet accumulé depuis le début ou le dernier appel à [reset].
  String get rawBuffer => _cachedRawBuffer ??= _rawBuffer.toString();

  /// Réinitialise intégralement l'analyseur et vide le tampon brut.
  void reset() {
    _rawBuffer.clear();
    _cachedRawBuffer = '';
    _receivedChars = 0;
    _stage = _ParserStage.leadingWhitespace;
    _fenceTickCount = 0;
    _stack.clear();
    _inString = false;
    _stringTarget = _StringTarget.skip;
    _strMode = _StrMode.normal;
    _unicodeDigits = 0;
    _unicodeValue = 0;
    _pendingHighSurrogate = null;
    _inPrimitive = false;
    _keyBuffer.clear();
    _keyOverflow = false;
    _messageBuffer.clear();
    _cachedMessage = null;
    _hasMessageStarted = false;
    _isMessageComplete = false;
    _hasVibeObject = false;
    _hasAskUserObject = false;
    _seenComponentIds.clear();
    _estimatedComponentCount = 0;
    _activeCapture = null;
    _rootPatchEntries.clear();
    _sectionPatchEntries.clear();
    _cachedPartialPatch = null;
    _patchRevision = 0;
    _current = VibeStreamSnapshot.empty;
  }

  /// Ajoute incrémentalement [chunk] au flux et retourne le nouvel instantané [current].
  VibeStreamSnapshot addChunk(String chunk) {
    if (chunk.isEmpty) return _current;

    _rawBuffer.write(chunk);
    _cachedRawBuffer = null;
    _receivedChars += chunk.length;

    for (var i = 0; i < chunk.length; i++) {
      final cu = chunk.codeUnitAt(i);
      switch (_stage) {
        case _ParserStage.leadingWhitespace:
          if (cu == 0x7B) {
            // '{'
            _enterRootObject();
          } else if (cu == 0x60) {
            // '`'
            _fenceTickCount = 1;
            _stage = _ParserStage.fenceTicks;
          }
        case _ParserStage.fenceTicks:
          if (cu == 0x60) {
            _fenceTickCount++;
            if (_fenceTickCount >= 3) {
              _stage = _ParserStage.fenceInfoLine;
            }
          } else if (cu == 0x7B) {
            _enterRootObject();
          } else {
            _fenceTickCount = 0;
            _stage = _ParserStage.leadingWhitespace;
          }
        case _ParserStage.fenceInfoLine:
          if (cu == 0x0A) {
            // '\n'
            _stage = _ParserStage.leadingWhitespace;
          } else if (cu == 0x7B) {
            _enterRootObject();
          }
        case _ParserStage.json:
          _consumeJsonCodeUnit(cu);
        case _ParserStage.done:
          break;
      }
    }

    _current = VibeStreamSnapshot(
      message: _hasMessageStarted
          ? (_cachedMessage ??= _messageBuffer.toString())
          : null,
      isMessageComplete: _isMessageComplete,
      hasVibeObject: _hasVibeObject,
      hasAskUserObject: _hasAskUserObject,
      estimatedComponentCount: _estimatedComponentCount,
      receivedChars: _receivedChars,
      partialVibePatch: _patchRevision == 0
          ? null
          : (_cachedPartialPatch ??= _buildFrozenPartialPatch()),
      patchRevision: _patchRevision,
    );
    return _current;
  }

  Map<String, dynamic> _buildFrozenPartialPatch() =>
      Map<String, dynamic>.unmodifiable({
        ..._rootPatchEntries,
        for (final entry in _sectionPatchEntries.entries)
          if (entry.value.isNotEmpty)
            entry.key: Map<String, dynamic>.unmodifiable(entry.value),
      });

  void _enterRootObject() {
    _stage = _ParserStage.json;
    _stack.add(
      _ContainerFrame(
        kind: _FrameKind.rootObject,
        phase: _ContainerPhase.expectKeyOrEnd,
      ),
    );
  }

  void _consumeJsonCodeUnit(int cu) {
    if (_inString) {
      _activeCapture?.buffer.writeCharCode(cu);
      _consumeStringCodeUnit(cu);
      return;
    }

    if (_inPrimitive) {
      if (_isPrimitiveTerminator(cu)) {
        _inPrimitive = false;
        if (_activeCapture?.kind == _CaptureKind.primitive) {
          _completeCapture();
        }
      } else {
        _activeCapture?.buffer.writeCharCode(cu);
        return;
      }
    }

    if (_activeCapture != null) {
      _activeCapture!.buffer.writeCharCode(cu);
    }

    if (_isWhitespace(cu)) {
      return;
    }

    if (_stack.isEmpty) {
      _stage = _ParserStage.done;
      return;
    }

    final frame = _stack.last;
    if (frame.kind == _FrameKind.array) {
      switch (frame.phase) {
        case _ContainerPhase.expectValueOrEnd:
          if (cu == 0x5D) {
            // ']'
            _popFrame();
          } else {
            _startValue(frame, cu);
          }
        case _ContainerPhase.expectCommaOrEnd:
          if (cu == 0x2C) {
            // ','
            frame.phase = _ContainerPhase.expectValueOrEnd;
          } else if (cu == 0x5D) {
            // ']'
            _popFrame();
          }
        case _ContainerPhase.expectKeyOrEnd:
        case _ContainerPhase.expectColon:
        case _ContainerPhase.expectValue:
          break;
      }
      return;
    }

    switch (frame.phase) {
      case _ContainerPhase.expectKeyOrEnd:
        if (cu == 0x7D) {
          // '}'
          _popFrame();
        } else if (cu == 0x22) {
          // '"'
          _startKeyString(frame);
        }
      case _ContainerPhase.expectColon:
        if (cu == 0x3A) {
          // ':'
          frame.phase = _ContainerPhase.expectValue;
        }
      case _ContainerPhase.expectValue:
        if (cu == 0x7D) {
          frame.pendingKey = null;
          _popFrame();
        } else {
          _startValue(frame, cu);
        }
      case _ContainerPhase.expectCommaOrEnd:
        if (cu == 0x2C) {
          // ','
          frame.phase = _ContainerPhase.expectKeyOrEnd;
        } else if (cu == 0x7D) {
          // '}'
          _popFrame();
        }
      case _ContainerPhase.expectValueOrEnd:
        break;
    }
  }

  void _startKeyString(_ContainerFrame frame) {
    switch (frame.kind) {
      case _FrameKind.componentsObject:
        _keyBuffer.clear();
        _keyOverflow = false;
        _stringTarget = _StringTarget.componentKey;
      case _FrameKind.sectionMapObject:
        _keyBuffer.clear();
        _keyOverflow = false;
        _stringTarget = _StringTarget.sectionEntryKey;
      case _FrameKind.otherObject:
      case _FrameKind.array:
        _stringTarget = _StringTarget.otherKey;
      case _FrameKind.rootObject:
      case _FrameKind.vibeObject:
      case _FrameKind.vibeDataObject:
        _keyBuffer.clear();
        _keyOverflow = false;
        _stringTarget = _StringTarget.key;
    }
    _inString = true;
    _strMode = _StrMode.normal;
    _pendingHighSurrogate = null;
  }

  bool _isPatchContainerFrame(_FrameKind kind) =>
      kind == _FrameKind.vibeObject || kind == _FrameKind.vibeDataObject;

  bool _shouldCaptureDirectPatchKey(_FrameKind parentKind, String key) {
    if (key.isEmpty || _ignoredMetaKeys.contains(key)) return false;
    if (_isPatchContainerFrame(parentKind)) {
      return !_sectionMapKeys.contains(key);
    }
    if (parentKind == _FrameKind.rootObject) {
      return _directRootPatchKeys.contains(key);
    }
    return false;
  }

  void _beginCapture({
    required String? section,
    required String entryKey,
    required _CaptureKind kind,
    required int firstCodeUnit,
    int targetStackDepth = 0,
  }) {
    final capture = _ActiveValueCapture(
      section: section,
      entryKey: entryKey,
      kind: kind,
      targetStackDepth: targetStackDepth,
    )..buffer.writeCharCode(firstCodeUnit);
    _activeCapture = capture;
  }

  void _completeCapture() {
    final capture = _activeCapture;
    if (capture == null) return;
    _activeCapture = null;
    final rawValue = capture.buffer.toString();
    final Object? decoded;
    try {
      decoded = jsonDecode(rawValue);
    } on FormatException {
      return;
    }
    if (capture.section case final section?) {
      final map = _sectionPatchEntries.putIfAbsent(
        section,
        () => <String, Object?>{},
      );
      map[capture.entryKey] = decoded;
    } else {
      _rootPatchEntries[capture.entryKey] = decoded;
    }
    _patchRevision++;
    _cachedPartialPatch = null;
  }

  void _startValue(_ContainerFrame parent, int cu) {
    final key = parent.pendingKey;
    parent.pendingKey = null;
    parent.phase = _ContainerPhase.expectCommaOrEnd;

    final String? captureSection;
    final String? captureKey;
    if (_activeCapture == null && key != null && key.isNotEmpty) {
      if (parent.kind == _FrameKind.componentsObject) {
        captureSection = 'components';
        captureKey = key;
      } else if (parent.kind == _FrameKind.sectionMapObject &&
          parent.sectionName != null) {
        captureSection = parent.sectionName;
        captureKey = key;
      } else if (_shouldCaptureDirectPatchKey(parent.kind, key)) {
        if (parent.kind == _FrameKind.rootObject) {
          _hasVibeObject = true;
        }
        captureSection = null;
        captureKey = key;
      } else {
        captureSection = null;
        captureKey = null;
      }
    } else {
      captureSection = null;
      captureKey = null;
    }

    if (cu == 0x7B) {
      // '{'
      _FrameKind childKind = _FrameKind.otherObject;
      String? childSection;
      if (parent.kind == _FrameKind.rootObject && key == 'vibe') {
        _hasVibeObject = true;
        childKind = _FrameKind.vibeObject;
      } else if (parent.kind == _FrameKind.rootObject && key == 'askUser') {
        _hasAskUserObject = true;
      } else if ((_isPatchContainerFrame(parent.kind) ||
              parent.kind == _FrameKind.rootObject) &&
          key != null &&
          _sectionMapKeys.contains(key)) {
        _hasVibeObject = true;
        if (key == 'components') {
          childKind = _FrameKind.componentsObject;
        } else {
          childKind = _FrameKind.sectionMapObject;
          childSection = key;
        }
      } else if (_isPatchContainerFrame(parent.kind) && key == 'data') {
        childKind = _FrameKind.vibeDataObject;
      }
      _stack.add(
        _ContainerFrame(
          kind: childKind,
          phase: _ContainerPhase.expectKeyOrEnd,
          sectionName: childSection,
        ),
      );
      if (captureKey != null) {
        _beginCapture(
          section: captureSection,
          entryKey: captureKey,
          kind: _CaptureKind.container,
          firstCodeUnit: cu,
          targetStackDepth: _stack.length,
        );
      }
    } else if (cu == 0x5B) {
      // '['
      if (parent.kind == _FrameKind.rootObject && key == 'askUser') {
        _hasAskUserObject = true;
      }
      _stack.add(
        _ContainerFrame(
          kind: _FrameKind.array,
          phase: _ContainerPhase.expectValueOrEnd,
        ),
      );
      if (captureKey != null) {
        _beginCapture(
          section: captureSection,
          entryKey: captureKey,
          kind: _CaptureKind.container,
          firstCodeUnit: cu,
          targetStackDepth: _stack.length,
        );
      }
    } else if (cu == 0x22) {
      // '"'
      if (parent.kind == _FrameKind.rootObject &&
          key == 'message' &&
          !_hasMessageStarted) {
        _hasMessageStarted = true;
        _cachedMessage = null;
        _stringTarget = _StringTarget.messageValue;
      } else {
        _stringTarget = _StringTarget.skip;
      }
      _inString = true;
      _strMode = _StrMode.normal;
      _pendingHighSurrogate = null;
      if (captureKey != null) {
        _beginCapture(
          section: captureSection,
          entryKey: captureKey,
          kind: _CaptureKind.string,
          firstCodeUnit: cu,
        );
      }
    } else {
      _inPrimitive = true;
      if (captureKey != null) {
        _beginCapture(
          section: captureSection,
          entryKey: captureKey,
          kind: _CaptureKind.primitive,
          firstCodeUnit: cu,
        );
      }
    }
  }

  void _consumeStringCodeUnit(int cu) {
    switch (_strMode) {
      case _StrMode.normal:
        if (cu == 0x22) {
          // '"'
          _flushPendingHighSurrogate();
          _finishString();
          return;
        }
        if (cu == 0x5C) {
          // '\'
          _strMode = _StrMode.escape;
          return;
        }
        _handleDecodedUnit(cu);
      case _StrMode.escape:
        if (cu == 0x75) {
          // 'u'
          _unicodeDigits = 0;
          _unicodeValue = 0;
          _strMode = _StrMode.unicode;
          return;
        }
        _flushPendingHighSurrogate();
        final decoded = switch (cu) {
          0x22 => 0x22, // \"
          0x5C => 0x5C, // \\
          0x2F => 0x2F, // \/
          0x62 => 0x08, // \b
          0x66 => 0x0C, // \f
          0x6E => 0x0A, // \n
          0x72 => 0x0D, // \r
          0x74 => 0x09, // \t
          _ => cu,
        };
        _emitCodePoint(decoded);
        _strMode = _StrMode.normal;
      case _StrMode.unicode:
        final hex = _hexDigitValue(cu);
        if (hex < 0) {
          _flushPendingHighSurrogate();
          _emitCodePoint(0xFFFD);
          _strMode = _StrMode.normal;
          _consumeStringCodeUnit(cu);
          return;
        }
        _unicodeValue = (_unicodeValue << 4) | hex;
        _unicodeDigits++;
        if (_unicodeDigits == 4) {
          _strMode = _StrMode.normal;
          _handleDecodedUnit(_unicodeValue);
        }
    }
  }

  void _handleDecodedUnit(int unit) {
    final high = _pendingHighSurrogate;
    if (high != null) {
      if (unit >= 0xDC00 && unit <= 0xDFFF) {
        final scalar = 0x10000 + ((high - 0xD800) << 10) + (unit - 0xDC00);
        _pendingHighSurrogate = null;
        _emitCodePoint(scalar);
        return;
      }
      _pendingHighSurrogate = null;
      _emitCodePoint(high);
    }

    if (unit >= 0xD800 && unit <= 0xDBFF) {
      _pendingHighSurrogate = unit;
    } else {
      _emitCodePoint(unit);
    }
  }

  void _flushPendingHighSurrogate() {
    final high = _pendingHighSurrogate;
    if (high != null) {
      _pendingHighSurrogate = null;
      _emitCodePoint(high);
    }
  }

  void _emitCodePoint(int codePoint) {
    switch (_stringTarget) {
      case _StringTarget.messageValue:
        _messageBuffer.writeCharCode(codePoint);
        _cachedMessage = null;
      case _StringTarget.key:
        if (!_keyOverflow) {
          if (_keyBuffer.length >= 128) {
            _keyOverflow = true;
          } else {
            _keyBuffer.writeCharCode(codePoint);
          }
        }
      case _StringTarget.componentKey:
      case _StringTarget.sectionEntryKey:
        _keyBuffer.writeCharCode(codePoint);
      case _StringTarget.otherKey:
      case _StringTarget.skip:
        break;
    }
  }

  void _finishString() {
    _inString = false;
    switch (_stringTarget) {
      case _StringTarget.key:
        final frame = _stack.last;
        frame.pendingKey = _keyOverflow ? '' : _keyBuffer.toString();
        frame.phase = _ContainerPhase.expectColon;
      case _StringTarget.componentKey:
        final frame = _stack.last;
        final key = _keyBuffer.toString();
        _seenComponentIds.add(key);
        _estimatedComponentCount = _seenComponentIds.length;
        frame.pendingKey = key;
        frame.phase = _ContainerPhase.expectColon;
      case _StringTarget.sectionEntryKey:
        final frame = _stack.last;
        frame.pendingKey = _keyBuffer.toString();
        frame.phase = _ContainerPhase.expectColon;
      case _StringTarget.otherKey:
        _stack.last.phase = _ContainerPhase.expectColon;
      case _StringTarget.messageValue:
        _isMessageComplete = true;
        _cachedMessage = null;
      case _StringTarget.skip:
        break;
    }
    if (_activeCapture?.kind == _CaptureKind.string) {
      _completeCapture();
    }
  }

  void _popFrame() {
    _stack.removeLast();
    if (_activeCapture != null &&
        _activeCapture!.kind == _CaptureKind.container &&
        _stack.length < _activeCapture!.targetStackDepth) {
      _completeCapture();
    }
    if (_stack.isEmpty) {
      _stage = _ParserStage.done;
    }
  }

  static bool _isWhitespace(int cu) =>
      cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D || cu == 0xFEFF;

  static bool _isPrimitiveTerminator(int cu) =>
      _isWhitespace(cu) ||
      cu == 0x2C || // ,
      cu == 0x7D || // }
      cu == 0x5D || // ]
      cu == 0x7B || // {
      cu == 0x5B || // [
      cu == 0x22 || // "
      cu == 0x3A; // :

  static int _hexDigitValue(int cu) {
    if (cu >= 0x30 && cu <= 0x39) return cu - 0x30;
    if (cu >= 0x41 && cu <= 0x46) return cu - 0x41 + 10;
    if (cu >= 0x61 && cu <= 0x66) return cu - 0x61 + 10;
    return -1;
  }
}

enum _ParserStage { leadingWhitespace, fenceTicks, fenceInfoLine, json, done }

enum _FrameKind {
  rootObject,
  vibeObject,
  vibeDataObject,
  componentsObject,
  sectionMapObject,
  otherObject,
  array,
}

enum _ContainerPhase {
  expectKeyOrEnd,
  expectColon,
  expectValue,
  expectValueOrEnd,
  expectCommaOrEnd,
}

enum _StringTarget {
  key,
  componentKey,
  sectionEntryKey,
  otherKey,
  messageValue,
  skip,
}

enum _StrMode { normal, escape, unicode }

enum _CaptureKind { container, string, primitive }

final class _ContainerFrame {
  _ContainerFrame({
    required this.kind,
    required this.phase,
    this.sectionName,
  });

  final _FrameKind kind;
  final String? sectionName;
  _ContainerPhase phase;
  String? pendingKey;
}

final class _ActiveValueCapture {
  _ActiveValueCapture({
    required this.section,
    required this.entryKey,
    required this.kind,
    required this.targetStackDepth,
  });

  final String? section;
  final String entryKey;
  final _CaptureKind kind;
  final int targetStackDepth;
  final StringBuffer buffer = StringBuffer();
}

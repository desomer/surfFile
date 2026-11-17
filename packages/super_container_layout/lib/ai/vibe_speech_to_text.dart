/// Capture vocale microphone et transcription Speech-to-Text pour l'assistant Vibe IA.
///
/// Fournit le contrat injectable [VibeSpeechTranscriber] / [VibeSpeechSession],
/// la capture audio native Windows sans dépendance externe (`winmm.dll` via `dart:ffi`)
/// avec détection automatique de fin de phrase après un silence (VAD), ainsi que
/// la transcription hybride via Gemini Audio ([transcribeSpeechWithGemini]) et repli
/// local Windows (`System.Speech`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart'
    show TextEditingController, TextEditingValue, TextSelection;

import 'call_gemini.dart';

/// État d'avancement d'une session de dictée vocale.
enum VibeSpeechState {
  /// Le microphone écoute activement l'utilisateur (arrêt auto après silence ou au 2e clic).
  listening,

  /// La capture audio est terminée et la transcription en texte est en cours.
  transcribing,

  /// La session est terminée (transcrite, annulée ou en erreur).
  completed,
}

/// Session active d'écoute vocale pouvant s'arrêter automatiquement après un silence
/// ou manuellement lors d'un second clic sur le bouton microphone.
abstract class VibeSpeechSession {
  /// Constructeur de base pour une session d'écoute vocale.
  const VibeSpeechSession();

  /// État réactif courant de la session ([VibeSpeechState]).
  ValueListenable<VibeSpeechState> get state;

  /// Futur complété avec le texte transcrit (ou une chaîne vide si aucune parole n'est détectée).
  Future<String> get result;

  /// Arrête immédiatement la capture audio et lance la transcription de l'audio déjà enregistré.
  Future<void> stop();

  /// Annule immédiatement la session sans transcrire.
  Future<void> cancel();
}

/// Implémentation de [VibeSpeechSession] pilotable par callbacks ou [Completer] (utile pour les tests).
class ControllableVibeSpeechSession extends VibeSpeechSession {
  /// Crée une session de dictée vocale contrôlable.
  ControllableVibeSpeechSession({this.onStopAndTranscribe, this.onCancel});

  /// Callback optionnel invoqué lorsque [stop] est appelé pour fournir la transcription.
  final Future<String> Function()? onStopAndTranscribe;

  /// Callback optionnel invoqué lorsque [cancel] est appelé.
  final Future<void> Function()? onCancel;
  final ValueNotifier<VibeSpeechState> _state = ValueNotifier<VibeSpeechState>(
    VibeSpeechState.listening,
  );
  final Completer<String> _completer = Completer<String>();
  bool _closed = false;

  @override
  ValueListenable<VibeSpeechState> get state => _state;

  @override
  Future<String> get result => _completer.future;

  /// Complète directement la session avec [transcript] (ex. arrêt automatique après silence).
  void completeWithTranscript(String transcript) {
    if (_closed) return;
    _closed = true;
    _state.value = VibeSpeechState.completed;
    if (!_completer.isCompleted) {
      _completer.complete(transcript);
    }
  }

  /// Complète la session avec une erreur [error].
  void completeWithError(Object error, [StackTrace? stackTrace]) {
    if (_closed) return;
    _closed = true;
    _state.value = VibeSpeechState.completed;
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
  }

  /// Passe l'état de la session en [VibeSpeechState.transcribing].
  void markTranscribing() {
    if (!_closed && _state.value == VibeSpeechState.listening) {
      _state.value = VibeSpeechState.transcribing;
    }
  }

  @override
  Future<void> stop() async {
    if (_closed) return;
    markTranscribing();
    final callback = onStopAndTranscribe;
    if (callback != null) {
      try {
        final text = await callback();
        completeWithTranscript(text);
      } catch (error, stack) {
        completeWithError(error, stack);
      }
    }
  }

  @override
  Future<void> cancel() async {
    if (_closed) return;
    _closed = true;
    _state.value = VibeSpeechState.completed;
    try {
      await onCancel?.call();
    } catch (_) {}
    if (!_completer.isCompleted) {
      _completer.complete('');
    }
  }
}

/// Contrat de service de dictée vocale (Speech-to-Text) pour le wizard Vibe IA.
abstract class VibeSpeechTranscriber {
  /// Constructeur de base pour un transcripteur vocal.
  const VibeSpeechTranscriber();

  /// Instance partagée par défaut (capture micro native Windows + transcription Gemini / Windows).
  static const VibeSpeechTranscriber instance = DefaultVibeSpeechTranscriber();

  /// Démarre une session d'écoute vocale qui s'arrête automatiquement après un silence
  /// ou lorsque [VibeSpeechSession.stop] est appelé.
  Future<VibeSpeechSession> startListening();
}

/// Utilitaires d'encodage WAV PCM 16 bits et d'analyse de niveau sonore (RMS) pour la détection de silence.
abstract final class VibeAudioWavEncoder {
  /// Fréquence d'échantillonnage par défaut (16 kHz) pour la reconnaissance vocale.
  static const int defaultSampleRate = 16000;

  /// Encode des échantillons PCM 16 bits signés little-endian mono en conteneur RIFF/WAV.
  static Uint8List encodePcm16MonoToWav(
    Uint8List pcmBytes, {
    int sampleRate = defaultSampleRate,
  }) {
    final dataLength = pcmBytes.length - (pcmBytes.length % 2);
    final totalLength = 44 + dataLength;
    final wav = Uint8List(totalLength);
    final header = ByteData.sublistView(wav, 0, 44);

    // "RIFF"
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, 36 + dataLength, Endian.little);
    // "WAVE"
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    // "fmt "
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (PCM)
    header.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
    header.setUint16(22, 1, Endian.little); // NumChannels = 1 (Mono)
    header.setUint32(24, sampleRate, Endian.little); // SampleRate
    header.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
    header.setUint16(32, 2, Endian.little); // BlockAlign
    header.setUint16(34, 16, Endian.little); // BitsPerSample
    // "data"
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataLength, Endian.little);

    wav.setRange(44, 44 + dataLength, pcmBytes);
    return wav;
  }

  /// Calcule le niveau RMS normalisé (`0.0` à `1.0`) d'un tampon PCM 16 bits signé little-endian.
  static double computeNormalizedRms(Uint8List pcmBytes, [int? validBytes]) {
    final byteCount = ((validBytes ?? pcmBytes.length).clamp(
      0,
      pcmBytes.length,
    ));
    final sampleCount = byteCount ~/ 2;
    if (sampleCount <= 0) return 0.0;

    final data = ByteData.sublistView(pcmBytes, 0, sampleCount * 2);
    var sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = data.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / sampleCount).clamp(0.0, 1.0);
  }
}

/// Utilitaires d'insertion de texte dicté dans un [TextEditingController].
abstract final class VibeSpeechTextInsertion {
  /// Insère [transcript] à la position courante du curseur dans [controller]
  /// (ou à la fin du texte s'il n'y a pas de sélection valide), en gérant les espaces.
  static void insertTranscript(
    TextEditingController controller,
    String transcript,
  ) {
    final cleaned = transcript.trim();
    if (cleaned.isEmpty) return;

    final currentText = controller.text;
    final selection = controller.selection;
    if (!selection.isValid ||
        selection.start < 0 ||
        selection.end > currentText.length) {
      final separator =
          currentText.isNotEmpty && !RegExp(r'\s$').hasMatch(currentText)
          ? ' '
          : '';
      final updated = '$currentText$separator$cleaned';
      controller.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: updated.length),
      );
      return;
    }

    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final before = currentText.substring(0, start);
    final after = currentText.substring(end);

    final prefixSpace = before.isNotEmpty && !RegExp(r'\s$').hasMatch(before)
        ? ' '
        : '';
    final suffixSpace =
        after.isNotEmpty && !RegExp(r'^[\s.,;:!?)]').hasMatch(after) ? ' ' : '';

    final inserted = '$prefixSpace$cleaned$suffixSpace';
    final nextText = '$before$inserted$after';
    final nextOffset = before.length + prefixSpace.length + cleaned.length;

    controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
  }
}

/// Implémentation par défaut de [VibeSpeechTranscriber] combinant la capture audio
/// native Windows (`winmm.dll`) avec arrêt automatique sur silence et la transcription
/// Gemini Audio (avec repli sur `System.Speech` de Windows).
class DefaultVibeSpeechTranscriber extends VibeSpeechTranscriber {
  /// Crée une instance du transcripteur vocal par défaut.
  const DefaultVibeSpeechTranscriber({
    this.silenceDuration = const Duration(milliseconds: 1300),
    this.initialSilenceTimeout = const Duration(seconds: 7),
    this.maxListeningDuration = const Duration(seconds: 30),
    this.speechRmsThreshold = 0.016,
    this.audioTranscriber,
  });

  /// Durée de silence continu après une prise de parole déclenchant l'arrêt automatique.
  final Duration silenceDuration;

  /// Délai maximal d'attente avant le début de la prise de parole.
  final Duration initialSilenceTimeout;

  /// Durée maximale totale d'une prise de parole.
  final Duration maxListeningDuration;

  /// Seuil minimal d'amplitude RMS normalisée (`0.0` à `1.0`) pour détecter la voix.
  final double speechRmsThreshold;

  /// Fonction optionnelle de transcription d'un buffer WAV en texte.
  final Future<String> Function(Uint8List wavBytes)? audioTranscriber;

  @override
  Future<VibeSpeechSession> startListening() async {
    if (!Platform.isWindows) {
      throw const FormatException(
        'La dictée vocale native n’est prise en charge que sous Windows.',
      );
    }
    return _Win32WaveInSpeechSession.start(
      silenceDuration: silenceDuration,
      initialSilenceTimeout: initialSilenceTimeout,
      maxListeningDuration: maxListeningDuration,
      speechRmsThreshold: speechRmsThreshold,
      transcribeWav: audioTranscriber ?? _defaultTranscribeWav,
    );
  }

  static Future<String> _defaultTranscribeWav(Uint8List wavBytes) async {
    final apiKey = await resolveGeminiApiKey();
    if (apiKey.trim().isNotEmpty) {
      try {
        final transcript = await transcribeSpeechWithGemini(wavBytes);
        return transcript.trim();
      } catch (error) {
        debugPrint(
          '[Vibe IA][Speech] Échec de transcription Gemini ($error), '
          'tentative de repli local Windows System.Speech.',
        );
      }
    }
    return _transcribeWavWithWindowsSpeech(wavBytes);
  }

  static Future<String> _transcribeWavWithWindowsSpeech(
    Uint8List wavBytes,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('vibe_speech_');
    final wavFile = File('${tempDir.path}${Platform.pathSeparator}input.wav');
    try {
      await wavFile.writeAsBytes(wavBytes, flush: true);
      final escapedPath = wavFile.path.replaceAll("'", "''");
      final script =
          '''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Speech
\$wavPath = '$escapedPath'
\$engine = \$null
try {
  \$installed = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
  if (\$installed -eq \$null -or \$installed.Count -eq 0) {
    throw 'Aucun moteur de reconnaissance vocale Windows installé et clé GEMINI_API_KEY absente.'
  }
  \$fr = \$installed | Where-Object { \$_.Culture.Name -like 'fr*' } | Select-Object -First 1
  if (\$fr -ne \$null) {
    \$engine = New-Object System.Speech.Recognition.SpeechRecognitionEngine(\$fr.Id)
  } else {
    \$engine = New-Object System.Speech.Recognition.SpeechRecognitionEngine(\$installed[0].Id)
  }
  \$engine.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
  \$engine.SetInputToWaveFile(\$wavPath)
  \$parts = New-Object System.Collections.Generic.List[string]
  while (\$true) {
    \$res = \$engine.Recognize()
    if (\$res -eq \$null) { break }
    if (-not [string]::IsNullOrWhiteSpace(\$res.Text)) {
      \$parts.Add(\$res.Text.Trim())
    }
  }
  Write-Output (\$parts -join ' ')
} finally {
  if (\$engine -ne \$null) { \$engine.Dispose() }
}
''';
      final result = await Process.run(
        'powershell',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          script,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(seconds: 15));
      if (result.exitCode != 0) {
        final err = (result.stderr as String).trim();
        throw FormatException(
          err.isNotEmpty
              ? err
              : 'Impossible de transcrire l’enregistrement vocal.',
        );
      }
      return (result.stdout as String).trim();
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

// ---------------------------------------------------------------------------
// Implémentation Win32 FFI `winmm.dll` (waveInOpen / polling sans callback thread)
// ---------------------------------------------------------------------------

const int _waveMapper = 0xFFFFFFFF;
const int _waveFormatPcm = 1;
const int _callbackNull = 0x00000000;
const int _whdrDone = 0x00000001;
const int _whdrPrepared = 0x00000002;
const int _mmsyserrNoerror = 0;
const int _gmemFixed = 0x0000;
const int _gmemZeroInit = 0x0040;

@Packed(1)
final class _WaveFormatEx extends Struct {
  @Uint16()
  external int wFormatTag;
  @Uint16()
  external int nChannels;
  @Uint32()
  external int nSamplesPerSec;
  @Uint32()
  external int nAvgBytesPerSec;
  @Uint16()
  external int nBlockAlign;
  @Uint16()
  external int wBitsPerSample;
  @Uint16()
  external int cbSize;
}

final class _WaveHdr extends Struct {
  external Pointer<Uint8> lpData;
  @Uint32()
  external int dwBufferLength;
  @Uint32()
  external int dwBytesRecorded;
  @IntPtr()
  external int dwUser;
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int dwLoops;
  external Pointer<Void> lpNext;
  @IntPtr()
  external int reserved;
}

typedef _WaveInGetNumDevsNative = Uint32 Function();
typedef _WaveInGetNumDevsDart = int Function();

typedef _WaveInOpenNative = Uint32 Function(
  Pointer<IntPtr> phwi,
  Uint32 uDeviceID,
  Pointer<_WaveFormatEx> pwfx,
  IntPtr dwCallback,
  IntPtr dwInstance,
  Uint32 fdwOpen,
);
typedef _WaveInOpenDart = int Function(
  Pointer<IntPtr> phwi,
  int uDeviceID,
  Pointer<_WaveFormatEx> pwfx,
  int dwCallback,
  int dwInstance,
  int fdwOpen,
);

typedef _WaveInHeaderNative = Uint32 Function(
  IntPtr hwi,
  Pointer<_WaveHdr> pwh,
  Uint32 cbwh,
);
typedef _WaveInHeaderDart = int Function(
  int hwi,
  Pointer<_WaveHdr> pwh,
  int cbwh,
);

typedef _WaveInHandleNative = Uint32 Function(IntPtr hwi);
typedef _WaveInHandleDart = int Function(int hwi);

typedef _GlobalAllocNative = Pointer<Void> Function(
  Uint32 uFlags,
  IntPtr dwBytes,
);
typedef _GlobalAllocDart = Pointer<Void> Function(int uFlags, int dwBytes);

typedef _GlobalFreeNative = Pointer<Void> Function(Pointer<Void> hMem);
typedef _GlobalFreeDart = Pointer<Void> Function(Pointer<Void> hMem);

class _Win32WaveInSpeechSession extends VibeSpeechSession {
  _Win32WaveInSpeechSession._({
    required this.silenceDuration,
    required this.initialSilenceTimeout,
    required this.maxListeningDuration,
    required this.speechRmsThreshold,
    required this.transcribeWav,
  });

  static const int _sampleRate = VibeAudioWavEncoder.defaultSampleRate;
  static const int _chunkDurationMs = 100;
  static const int _chunkByteSize =
      (_sampleRate * 2 * _chunkDurationMs) ~/ 1000;
  static const int _bufferCount = 6;

  final Duration silenceDuration;
  final Duration initialSilenceTimeout;
  final Duration maxListeningDuration;
  final double speechRmsThreshold;
  final Future<String> Function(Uint8List wavBytes) transcribeWav;

  final ValueNotifier<VibeSpeechState> _state = ValueNotifier<VibeSpeechState>(
    VibeSpeechState.listening,
  );
  final Completer<String> _completer = Completer<String>();
  final BytesBuilder _recordedPcm = BytesBuilder(copy: false);

  late final DynamicLibrary _winmm;
  late final DynamicLibrary _kernel32;
  late final _GlobalAllocDart _globalAlloc;
  late final _GlobalFreeDart _globalFree;
  late final _WaveInHeaderDart _waveInPrepareHeader;
  late final _WaveInHeaderDart _waveInUnprepareHeader;
  late final _WaveInHeaderDart _waveInAddBuffer;
  late final _WaveInHandleDart _waveInStart;
  late final _WaveInHandleDart _waveInStop;
  late final _WaveInHandleDart _waveInReset;
  late final _WaveInHandleDart _waveInClose;

  int _hWaveIn = 0;
  Pointer<IntPtr>? _phWaveIn;
  Pointer<_WaveFormatEx>? _formatPtr;
  final List<Pointer<_WaveHdr>> _headers = <Pointer<_WaveHdr>>[];
  final List<Pointer<Uint8>> _buffers = <Pointer<Uint8>>[];

  Timer? _pollTimer;
  final Stopwatch _totalStopwatch = Stopwatch();
  DateTime? _lastSpeechAt;
  bool _hasDetectedSpeech = false;
  int _consecutiveSpeechChunks = 0;
  double _noiseFloorRms = 0.0;
  int _noiseSamples = 0;
  bool _stoppingOrClosed = false;
  bool _resourcesReleased = false;

  @override
  ValueListenable<VibeSpeechState> get state => _state;

  @override
  Future<String> get result => _completer.future;

  static Future<_Win32WaveInSpeechSession> start({
    required Duration silenceDuration,
    required Duration initialSilenceTimeout,
    required Duration maxListeningDuration,
    required double speechRmsThreshold,
    required Future<String> Function(Uint8List wavBytes) transcribeWav,
  }) async {
    final session = _Win32WaveInSpeechSession._(
      silenceDuration: silenceDuration,
      initialSilenceTimeout: initialSilenceTimeout,
      maxListeningDuration: maxListeningDuration,
      speechRmsThreshold: speechRmsThreshold,
      transcribeWav: transcribeWav,
    );
    session._openAndStart();
    return session;
  }

  Pointer<T> _allocZeroed<T extends NativeType>(int byteCount) =>
      _globalAlloc(_gmemFixed | _gmemZeroInit, byteCount).cast<T>();

  void _freePtr(Pointer<NativeType>? ptr) {
    if (ptr != null && ptr.address != 0) {
      _globalFree(ptr.cast<Void>());
    }
  }

  void _openAndStart() {
    _winmm = DynamicLibrary.open('winmm.dll');
    _kernel32 = DynamicLibrary.open('kernel32.dll');
    _globalAlloc = _kernel32
        .lookupFunction<_GlobalAllocNative, _GlobalAllocDart>('GlobalAlloc');
    _globalFree = _kernel32.lookupFunction<_GlobalFreeNative, _GlobalFreeDart>(
      'GlobalFree',
    );

    final waveInGetNumDevs = _winmm
        .lookupFunction<_WaveInGetNumDevsNative, _WaveInGetNumDevsDart>(
          'waveInGetNumDevs',
        );
    final waveInOpen = _winmm
        .lookupFunction<_WaveInOpenNative, _WaveInOpenDart>('waveInOpen');
    _waveInPrepareHeader = _winmm
        .lookupFunction<_WaveInHeaderNative, _WaveInHeaderDart>(
          'waveInPrepareHeader',
        );
    _waveInUnprepareHeader = _winmm
        .lookupFunction<_WaveInHeaderNative, _WaveInHeaderDart>(
          'waveInUnprepareHeader',
        );
    _waveInAddBuffer = _winmm
        .lookupFunction<_WaveInHeaderNative, _WaveInHeaderDart>(
          'waveInAddBuffer',
        );
    _waveInStart = _winmm
        .lookupFunction<_WaveInHandleNative, _WaveInHandleDart>('waveInStart');
    _waveInStop = _winmm.lookupFunction<_WaveInHandleNative, _WaveInHandleDart>(
      'waveInStop',
    );
    _waveInReset = _winmm
        .lookupFunction<_WaveInHandleNative, _WaveInHandleDart>('waveInReset');
    _waveInClose = _winmm
        .lookupFunction<_WaveInHandleNative, _WaveInHandleDart>('waveInClose');

    final numDevs = waveInGetNumDevs();
    if (numDevs <= 0) {
      throw const FormatException(
        'Aucun microphone détecté sur cet ordinateur.',
      );
    }

    _phWaveIn = _allocZeroed<IntPtr>(sizeOf<IntPtr>());
    _formatPtr = _allocZeroed<_WaveFormatEx>(sizeOf<_WaveFormatEx>());
    _formatPtr!.ref
      ..wFormatTag = _waveFormatPcm
      ..nChannels = 1
      ..nSamplesPerSec = _sampleRate
      ..nAvgBytesPerSec = _sampleRate * 2
      ..nBlockAlign = 2
      ..wBitsPerSample = 16
      ..cbSize = 0;

    final openResult = waveInOpen(
      _phWaveIn!,
      _waveMapper,
      _formatPtr!,
      0,
      0,
      _callbackNull,
    );
    if (openResult != _mmsyserrNoerror || _phWaveIn!.value == 0) {
      _releaseNativeResources();
      throw FormatException(
        'Impossible d’ouvrir le microphone Windows (code waveInOpen: $openResult).',
      );
    }
    _hWaveIn = _phWaveIn!.value;

    final hdrSize = sizeOf<_WaveHdr>();
    for (var i = 0; i < _bufferCount; i++) {
      final dataPtr = _allocZeroed<Uint8>(_chunkByteSize);
      final hdrPtr = _allocZeroed<_WaveHdr>(hdrSize);
      hdrPtr.ref
        ..lpData = dataPtr
        ..dwBufferLength = _chunkByteSize
        ..dwBytesRecorded = 0
        ..dwFlags = 0;
      final prep = _waveInPrepareHeader(_hWaveIn, hdrPtr, hdrSize);
      if (prep != _mmsyserrNoerror) {
        _freePtr(dataPtr);
        _freePtr(hdrPtr);
        _releaseNativeResources();
        throw FormatException(
          'Impossible d’initialiser le tampon audio (code: $prep).',
        );
      }
      final add = _waveInAddBuffer(_hWaveIn, hdrPtr, hdrSize);
      if (add != _mmsyserrNoerror) {
        _waveInUnprepareHeader(_hWaveIn, hdrPtr, hdrSize);
        _freePtr(dataPtr);
        _freePtr(hdrPtr);
        _releaseNativeResources();
        throw FormatException(
          'Impossible d’enregistrer le tampon audio (code: $add).',
        );
      }
      _buffers.add(dataPtr);
      _headers.add(hdrPtr);
    }

    final startResult = _waveInStart(_hWaveIn);
    if (startResult != _mmsyserrNoerror) {
      _releaseNativeResources();
      throw FormatException(
        'Impossible de démarrer l’écoute du microphone (code: $startResult).',
      );
    }

    _totalStopwatch.start();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _pollBuffers(),
    );
  }

  void _pollBuffers() {
    if (_stoppingOrClosed || _resourcesReleased) return;

    final hdrSize = sizeOf<_WaveHdr>();
    final now = DateTime.now();

    for (var i = 0; i < _headers.length; i++) {
      final hdrPtr = _headers[i];
      final flags = hdrPtr.ref.dwFlags;
      if ((flags & _whdrDone) == 0) continue;

      final recorded = hdrPtr.ref.dwBytesRecorded.clamp(0, _chunkByteSize);
      if (recorded > 0) {
        final chunk = Uint8List.fromList(
          hdrPtr.ref.lpData.asTypedList(recorded),
        );
        _recordedPcm.add(chunk);
        _analyzeChunkRms(chunk, now);
      }

      // Ré-enfile le tampon pour continuer l'écoute.
      hdrPtr.ref
        ..dwBytesRecorded = 0
        ..dwFlags = flags & ~_whdrDone;
      _waveInAddBuffer(_hWaveIn, hdrPtr, hdrSize);
    }

    final elapsed = _totalStopwatch.elapsed;
    if (elapsed >= maxListeningDuration) {
      unawaited(stop());
      return;
    }

    if (!_hasDetectedSpeech) {
      if (elapsed >= initialSilenceTimeout) {
        unawaited(stop());
      }
    } else if (_lastSpeechAt != null &&
        now.difference(_lastSpeechAt!) >= silenceDuration) {
      unawaited(stop());
    }
  }

  void _analyzeChunkRms(Uint8List chunk, DateTime now) {
    final rms = VibeAudioWavEncoder.computeNormalizedRms(chunk);
    final effectiveThreshold = math.max(
      speechRmsThreshold,
      _noiseFloorRms * 2.4,
    );

    if (rms >= effectiveThreshold) {
      _consecutiveSpeechChunks++;
      if (_consecutiveSpeechChunks >= 2 || _hasDetectedSpeech) {
        _hasDetectedSpeech = true;
        _lastSpeechAt = now;
      }
    } else {
      _consecutiveSpeechChunks = 0;
      if (!_hasDetectedSpeech && _noiseSamples < 6) {
        _noiseSamples++;
        _noiseFloorRms =
            ((_noiseFloorRms * (_noiseSamples - 1)) + rms) / _noiseSamples;
      }
    }
  }

  void _drainRemainingBuffers() {
    if (_resourcesReleased || _hWaveIn == 0) return;
    for (var i = 0; i < _headers.length; i++) {
      final hdrPtr = _headers[i];
      final recorded = hdrPtr.ref.dwBytesRecorded.clamp(0, _chunkByteSize);
      if (recorded > 0) {
        final chunk = Uint8List.fromList(
          hdrPtr.ref.lpData.asTypedList(recorded),
        );
        _recordedPcm.add(chunk);
        hdrPtr.ref.dwBytesRecorded = 0;
      }
    }
  }

  void _releaseNativeResources() {
    if (_resourcesReleased) return;
    _resourcesReleased = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _totalStopwatch.stop();

    if (_hWaveIn != 0) {
      try {
        _waveInStop(_hWaveIn);
      } catch (_) {}
      try {
        _waveInReset(_hWaveIn);
      } catch (_) {}
      try {
        _drainRemainingBuffers();
      } catch (_) {}

      final hdrSize = sizeOf<_WaveHdr>();
      for (final hdrPtr in _headers) {
        try {
          if ((hdrPtr.ref.dwFlags & _whdrPrepared) != 0) {
            _waveInUnprepareHeader(_hWaveIn, hdrPtr, hdrSize);
          }
        } catch (_) {}
      }
      try {
        _waveInClose(_hWaveIn);
      } catch (_) {}
      _hWaveIn = 0;
    }

    for (final hdrPtr in _headers) {
      _freePtr(hdrPtr);
    }
    _headers.clear();
    for (final dataPtr in _buffers) {
      _freePtr(dataPtr);
    }
    _buffers.clear();
    _freePtr(_formatPtr);
    _formatPtr = null;
    _freePtr(_phWaveIn);
    _phWaveIn = null;
  }

  @override
  Future<void> stop() async {
    if (_stoppingOrClosed) return;
    _stoppingOrClosed = true;
    _releaseNativeResources();

    final pcmBytes = _recordedPcm.takeBytes();
    final overallRms = VibeAudioWavEncoder.computeNormalizedRms(pcmBytes);
    final hasMeaningfulAudio =
        pcmBytes.length >= (_sampleRate * 2 ~/ 4) &&
        (_hasDetectedSpeech || overallRms >= speechRmsThreshold * 0.75);

    if (!hasMeaningfulAudio) {
      _state.value = VibeSpeechState.completed;
      if (!_completer.isCompleted) {
        _completer.complete('');
      }
      return;
    }

    _state.value = VibeSpeechState.transcribing;
    try {
      final wavBytes = VibeAudioWavEncoder.encodePcm16MonoToWav(
        pcmBytes,
        sampleRate: _sampleRate,
      );
      final transcript = await transcribeWav(wavBytes);
      _state.value = VibeSpeechState.completed;
      if (!_completer.isCompleted) {
        _completer.complete(transcript.trim());
      }
    } catch (error, stack) {
      _state.value = VibeSpeechState.completed;
      if (!_completer.isCompleted) {
        _completer.completeError(error, stack);
      }
    }
  }

  @override
  Future<void> cancel() async {
    if (_stoppingOrClosed) return;
    _stoppingOrClosed = true;
    _releaseNativeResources();
    _recordedPcm.clear();
    _state.value = VibeSpeechState.completed;
    if (!_completer.isCompleted) {
      _completer.complete('');
    }
  }
}

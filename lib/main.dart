import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'audio/wav_engine.dart';
import 'audio/wav_window_reader.dart';
import 'audio/midi_engine.dart';
import 'audio/metronome_synth.dart';
import 'audio/multitrack_engine.dart';
import 'audio/multitrack_midi.dart';
import 'audio/rhythm_engine.dart';
import 'audio/stem_extractor.dart';
import 'score/score_engine.dart';
import 'score/score_sheet.dart';
import 'score/note_lab.dart';
import 'score/reference_score.dart';
import 'ui/multitrack_panel.dart';
import 'services/chatgpt_service.dart';
import 'services/local_audio_import.dart';
import 'services/app_updates.dart';
import 'services/song_lookup.dart';

void main() => runApp(const AmpyScoreApp());

class AmpyScoreApp extends StatelessWidget {
  const AmpyScoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF62DFC3);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AmpyScore AI',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101820),
        colorScheme: ColorScheme.fromSeed(
          seedColor: teal,
          brightness: Brightness.dark,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(145, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
      home: const StudioPage(),
    );
  }
}

enum _PlaybackMode { original, midi, both }

class StudioPage extends StatefulWidget {
  const StudioPage({super.key});

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer(); // Original recording.
  final _midiPlayer = AudioPlayer(); // Muted audio clock when SF2 is active.
  final _synth = MidiPro();
  int? _soundfontId;
  bool _soundfontReady = false;
  final _notePlayer = AudioPlayer(); // One MIDI pitch at a time.
  final _stemPlayer = AudioPlayer(); // Optional spectral focus WAV.
  final _metronomePlayer = AudioPlayer();
  final _apiKey = TextEditingController();
  final _songQuery = TextEditingController();
  Timer? _transportTimer;

  List<DetectedNote> _notes = const [];
  bool _multitrackMode = true;
  List<InstrumentPart> _parts = const [];
  InstrumentFamily? _selectedFamily;
  InstrumentFamily? _soloFamily;
  Map<InstrumentFamily, double>? _savedBeforeSolo;
  RhythmReport? _rhythm;
  ScoreProject? _score;
  int? _selectedNoteId;
  PaperTone _paperTone = PaperTone.ivory;
  int? _tempoOverride;
  double _tempoSlider = 120;
  FocusStem _focusStem = FocusStem.vocalCandidate;
  String? _stemPath;
  String? _lastMixPath;
  final Map<InstrumentFamily, int> _gmPrograms = {
    InstrumentFamily.bass: 32,
    InstrumentFamily.harmony: 0,
    InstrumentFamily.melody: 65,
  };
  static const Map<int, String> _gmNames = {
    0: 'Pianoforte', 1: 'Pianoforte brillante',
    24: 'Chitarra nylon', 25: 'Chitarra acustica',
    26: 'Chitarra elettrica', 32: 'Contrabbasso',
    33: 'Basso elettrico', 40: 'Violino',
    48: 'Archi', 56: 'Tromba', 57: 'Trombone',
    65: 'Sax contralto', 66: 'Sax tenore',
    73: 'Flauto', 80: 'Sintetizzatore',
  };
  final Map<InstrumentFamily, double> _partGains = {
    for (final family in InstrumentFamily.values) family: 0.90,
  };
  String? _trackPath;
  String? _analysisPath;
  int _pageIndex = 0;
  String _trackName = 'Nessuna traccia';
  String _status = 'Importa una canzone o registra una melodia.';
  String? _assistantAnswer;
  bool _metronomeEnabled = false;
  bool _metronomeReady = false;
  int _metronomeBpm = 120;
  int _metronomeSubdivisions = 1;
  double _metronomeVolume = .56;
  bool _forceScoreFullScreen = false;
  bool _immersive = false;
  bool _searching = false;
  List<SongCandidate> _songResults = const [];
  bool _recording = false;
  bool _busy = false;
  bool _playing = false;
  bool _midiReady = false;
  bool _originalUsesFallback = false;
  double _analysisProgress = 0;
  double _analysisDuration = 0;
  int _beatsPerBar = 4;
  bool _resyncing = false;
  _PlaybackMode? _mode;
  Duration _cursor = Duration.zero;
  DateTime _lastResync = DateTime.fromMillisecondsSinceEpoch(0);
  int _activeIndex = -1;
  double _originalVolume = 1.0;
  double _midiVolume = 0.65;

  @override
  void initState() {
    super.initState();
    _transportTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) => _updateTransport(),
    );
    unawaited(_player.setVolume(_originalVolume));
    unawaited(_midiPlayer.setVolume(_midiVolume));
  }

  @override
  void dispose() {
    _transportTimer?.cancel();
    _apiKey.dispose();
    _songQuery.dispose();
    if (_immersive) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    _recorder.dispose();
    _player.dispose();
    _midiPlayer.dispose();
    if (_synth.isInitialized) unawaited(_synth.dispose());
    _notePlayer.dispose();
    _stemPlayer.dispose();
    _metronomePlayer.dispose();
    super.dispose();
  }

  Future<void> _execute(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Errore: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_status)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load(String path, String name, {String? analysisPath}) async {
    await _pauseTransport();
    await _player.stop();
    await _midiPlayer.stop();
    if (_soundfontReady) await _synth.stopMidi();
    _soundfontReady = false;
    await _notePlayer.stop();
    await _stemPlayer.stop();
    await _metronomePlayer.stop();
    _metronomeReady = false;
    try {
      await _player.setFilePath(path);
      _originalUsesFallback = false;
    } catch (_) {
      // Some platform codecs decode successfully but cannot be played
      // directly by the native media player; use the local PCM fallback.
      if (analysisPath == null || analysisPath == path) rethrow;
      await _player.setFilePath(analysisPath);
      _originalUsesFallback = true;
    }
    if (!mounted) return;
    setState(() {
      _trackPath = path;
      _analysisPath = analysisPath ?? path;
      _trackName = name;
      _beatsPerBar = RegExp(r'take[ _-]?five|take[ _-]?5',
          caseSensitive: false).hasMatch(name) ? 5 : 4;
      _songQuery.text = SongLookup.filenameTitle(name) ?? '';
      _songResults = const [];
      _notes = const [];
      _parts = const [];
      _rhythm = null;
      _score = null;
      _selectedNoteId = null;
      _stemPath = null;
      _selectedFamily = null;
      _soloFamily = null;
      _savedBeforeSolo = null;
      _assistantAnswer = null;
      _cursor = Duration.zero;
      _activeIndex = -1;
      _midiReady = false;
      _status = 'Brano pronto.';
      _analysisProgress = 0;
      _analysisDuration = 0;
      _analysisProgress = 0;
      _analysisDuration = 0;
    });
  }

  Future<void> _demo() => _execute(() async {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/ampyscore_demo.wav');
        await file.writeAsBytes(DemoWav.create(), flush: true);
        await _load(file.path, 'Demo: Do Re Mi Sol');
        await _analyseInternal();
        _buildScoreAfterAnalysis();
      });

  Future<void> _multiDemo() => _execute(() async {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/ampyscore_multitrack_demo.wav');
        await file.writeAsBytes(MultiInstrumentDemo.create(), flush: true);
        _multitrackMode = true;
        await _load(file.path, 'Demo multistrumento');
        await _analyseInternal();
        _buildScoreAfterAnalysis();
      });

  Future<void> _import() => _execute(() async {
    final converted = await LocalAudioImport.pickAndConvert();
    if (converted == null) return;
    await _load(
      converted.playbackPath,
      converted.displayName,
      analysisPath: converted.analysisWavPath,
    );
    await _analyseInternal();
    _buildScoreAfterAnalysis();
  });

  Future<void> _toggleRecording() => _execute(() async {
        if (_recording) {
          final path = await _recorder.stop();
          if (mounted) setState(() => _recording = false);
          if (path == null) {
            throw StateError('Nessuna registrazione prodotta.');
          }
          await _load(path, 'Registrazione microfono');
          await _analyseInternal();
          _buildScoreAfterAnalysis();
          return;
        }
        if (!await _recorder.hasPermission()) {
          throw StateError('Permesso microfono negato.');
        }
        await _pauseTransport();
        await _player.stop();
        await _midiPlayer.stop();
        await _notePlayer.stop();
        await _stemPlayer.stop();
        final dir = await getApplicationDocumentsDirectory();
        final path =
            '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
            autoGain: false,
          ),
          path: path,
        );
        if (mounted) {
          setState(() {
            _recording = true;
            _status = 'Registrazione in corso. Premi Stop e analizza.';
          });
        }
      });

  /// Complete song analysis, bounded 16-second PCM chunks in worker isolates.
  Future<void> _analyseInternal() async {
    await _pauseTransport();
    if (_analysisPath == null) throw StateError('Apri un brano.');
    final reader = await WavWindowReader.open(File(_analysisPath!));
    final duration = reader.durationSeconds;
    if (duration <= 0) throw const FormatException('Audio vuoto.');
    await _midiPlayer.stop();
    const windowSize = 16.0, overlap = 0.45;
    final lanes = <InstrumentFamily, List<DetectedNote>>{};
    final allMono = <DetectedNote>[];
    var completed = 0.0;
    for (var base = 0.0; base < duration; base += windowSize) {
      final end = math.min(duration, base + windowSize);
      final from = math.max(0.0, base - overlap);
      final until = math.min(duration, end + overlap);
      final bytes = await reader.window(from, until - from);
      if (bytes.isEmpty) break;
      if (_multitrackMode) {
        final chunk = await compute(MultiTrackAnalyzer.analyze, bytes);
        for (final part in chunk.parts) {
          final items = lanes.putIfAbsent(part.family, () => []);
          for (final note in part.notes) {
            final first = math.max(base, from + note.startSeconds);
            final last = math.min(end, from + note.endSeconds);
            if (last <= first) continue;
            if (items.isNotEmpty && items.last.midi == note.midi &&
                first - items.last.endSeconds < .11) {
              final previous = items.removeLast();
              items.add(DetectedNote(midi: note.midi,
                startSeconds: previous.startSeconds, endSeconds: last,
                confidence: (previous.confidence + note.confidence) / 2));
            } else {
              items.add(DetectedNote(midi: note.midi,
                startSeconds: first, endSeconds: last,
                confidence: note.confidence));
            }
          }
        }
      } else {
        final mono = await compute(WavTranscriber.transcribe, bytes);
        for (final note in mono) {
          final first = math.max(base, from + note.startSeconds);
          final last = math.min(end, from + note.endSeconds);
          if (last <= first) continue;
          if (allMono.isNotEmpty && allMono.last.midi == note.midi &&
              first - allMono.last.endSeconds < .11) {
            final previous = allMono.removeLast();
            allMono.add(DetectedNote(midi: note.midi,
              startSeconds: previous.startSeconds, endSeconds: last,
              confidence: (previous.confidence + note.confidence) / 2));
          } else {
            allMono.add(DetectedNote(midi: note.midi,
              startSeconds: first, endSeconds: last,
              confidence: note.confidence));
          }
        }
      }
      completed = end;
      if (mounted) setState(() {
        _analysisProgress = end / duration;
        _status = 'Analisi ${(end * 100 / duration).round()}% · '
          '${_clock(end)} / ${_clock(duration)}';
      });
    }
    final parts = _multitrackMode
      ? <InstrumentPart>[
          for (final family in InstrumentFamily.values)
            if ((lanes[family] ?? const <DetectedNote>[]).isNotEmpty)
              InstrumentPart(family: family, notes: lanes[family]!,
                confidence: switch(family) {
                  InstrumentFamily.bass => .60,
                  InstrumentFamily.harmony => .43,
                  InstrumentFamily.melody => .54,
                  InstrumentFamily.drums => .35,
                }),
        ]
      : <InstrumentPart>[
          InstrumentPart(family: InstrumentFamily.melody,
            notes: allMono, confidence: .6),
        ];
    final wanted = parts.where((p) => p.family == InstrumentFamily.melody);
    final selected = wanted.isNotEmpty ? wanted.first :
        (parts.isNotEmpty ? parts.first : null);
    final rhythm = RhythmAnalyzer.estimate(parts);
    final allNotes = parts.any((p) => p.notes.isNotEmpty);
    _analysisDuration = duration;
    if (allNotes) {
      await _renderMultiPreview(parts, duration);
      await _loadSoundfontMidi(parts, rhythm.bpm);
    }
    await _player.seek(Duration.zero);
    if (mounted) setState(() {
      _parts = parts;
      _notes = selected?.notes ?? const [];
      _selectedFamily = selected?.family;
      _rhythm = rhythm;
      _midiReady = allNotes;
      _assistantAnswer = null;
      _cursor = Duration.zero;
      _activeIndex = -1;
      _soloFamily = null;
      _savedBeforeSolo = null;
      _analysisProgress = 1;
      _status = allNotes
          ? 'Trascritti ${_clock(completed)} · ≈ ${rhythm.bpm} BPM'
          : 'Nessuna nota affidabile rilevata.';
    });
  }

  static String _clock(double seconds) {
    final n = seconds.floor();
    return '${n ~/ 60}:${(n % 60).toString().padLeft(2, "0")}';
  }

  void _buildScoreAfterAnalysis() {
    final parts = _parts.isNotEmpty ? _parts : [
      InstrumentPart(
        family: InstrumentFamily.melody,
        notes: _notes,
        confidence: 0.6,
      ),
    ];
    final bpm = _tempoOverride ?? _rhythm?.bpm ?? 120;
    final project = ScoreProject.fromTranscription(parts, bpm,
        beatsPerBar: _beatsPerBar,
        minimumDurationSeconds: _analysisDuration);
    _metronomeBpm = project.bpm;
    _metronomeReady = false;
    if (mounted) {
      setState(() {
        _score = project;
        _tempoSlider = project.bpm.toDouble();
        _selectedNoteId = null;
      });
    }
  }

  void _onScoreEdit() {
    final project = _score;
    if (project == null) return;
    final chosen = _selectedFamily ?? project.parts.first.family;
    final lane = project.forFamily(chosen);
    setState(() {
      _notes = [
        for (final item in lane)
          if (!item.isRest) DetectedNote(
            midi: item.midi,
            startSeconds: project.timeOf(item),
            endSeconds: project.timeOf(item) +
                item.length * 60 / (project.bpm * ticksPerQuarter),
            confidence: item.evidence,
          ),
      ];
    });
  }

  List<InstrumentPart> _withPrograms(List<InstrumentPart> parts) => [
    for (final p in parts)
      InstrumentPart(
        family: p.family, notes: p.notes, confidence: p.confidence,
        programOverride: _gmPrograms[p.family] ?? p.programOverride,
      ),
  ];

  List<InstrumentPart> _editedParts() {
    final score = _score;
    if (score == null) return _parts;
    return [
      for (final part in score.parts)
        InstrumentPart(
          family: part.family,
          confidence: part.confidence,
          programOverride: _gmPrograms[part.family] ?? part.programOverride,
          notes: [
            for (final item in score.forFamily(part.family))
              if (!item.isRest) DetectedNote(
                midi: item.midi,
                startSeconds: score.timeOf(item),
                endSeconds: score.timeOf(item) +
                    item.length * 60 / (score.bpm * ticksPerQuarter),
                confidence: item.evidence,
              ),
          ],
        ),
    ];
  }

  Future<void> _rebuildMidiFromScore() => _execute(() async {
    final score = _score;
    if (score == null) return;
    final oldCursor = _cursor;
    await _pauseTransport();
    await _midiPlayer.stop();
    final parts = _editedParts();
    await _renderMultiPreview(parts, score.durationSeconds);
    await _loadSoundfontMidi(parts, score.bpm);
    await _seekTransport(oldCursor);
    if (mounted) {
      setState(() {
        _midiReady = parts.any((part) => part.notes.isNotEmpty);
        _status = 'MIDI rigenerato da NoteLab (modifiche locali).';
      });
    }
  });

  Future<void> _retranscribeAtBpm() async {
    _tempoOverride = _tempoSlider.round();
    await _analyse();
  }

  Future<void> _exportMusicXml() => _execute(() async {
    final score = _score;
    if (score == null) return;
    final xml = MusicXmlWriter.export(score);
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Esporta lo spartito MusicXML',
      fileName: 'AmpyScore_Studio.musicxml',
      type: FileType.custom,
      allowedExtensions: ['musicxml'],
      bytes: Uint8List.fromList(utf8.encode(xml)),
    );
    if (mounted && saved != null) {
      setState(() => _status = 'MusicXML esportato: $saved');
    }
  });

  Future<void> _prepareStem() async {
    final path = _analysisPath;
    if (path == null) throw StateError('Carica prima un brano.');
    await _stemPlayer.stop();
    final source = await File(path).readAsBytes();
    final bytes = await compute(
      StemExtractor.focus,
      StemRequest(source, _focusStem),
    );
    final dir = await getApplicationDocumentsDirectory();
    final output = File('${dir.path}/ampyscore_filtro_${_focusStem.name}.wav');
    await output.writeAsBytes(bytes, flush: true);
    await _stemPlayer.setFilePath(output.path);
    _stemPath = output.path;
  }

  Future<void> _playStem() => _execute(() async {
    await _pauseTransport();
    await _prepareStem();
    unawaited(_stemPlayer.play());
    if (mounted) {
      setState(() => _status =
        'Filtro frequenze: ${_focusStem.title}. '
        'Non è una separazione vocale o strumentale tramite IA.');
    }
  });

  Future<void> _exportStem() => _execute(() async {
    await _prepareStem();
    final bytes = await File(_stemPath!).readAsBytes();
    final saved = await FilePicker.saveFile(
      dialogTitle: 'Esporta la traccia filtrata',
      fileName: 'AmpyScore_${_focusStem.name}.wav',
      type: FileType.custom,
      allowedExtensions: ['wav'],
      bytes: bytes,
    );
    if (mounted && saved != null) {
      setState(() => _status = 'Filtro WAV esportato: $saved');
    }
  });

  /// Writes a full-length PCM comparison to disk without allocating a
  /// full-song Float32List or cutting the MIDI at 40 seconds.
  Future<void> _loadSoundfontMidi(
      List<InstrumentPart> parts, int bpm) async {
    if (!Platform.isAndroid) return;
    try {
      if (!_synth.isInitialized) {
        await _synth.init(sampleRate: 44100, polyphony: 128);
      }
      _soundfontId ??= await _synth.loadSoundfontAsset(
        assetPath: 'assets/soundfonts/GeneralUser-GS.sf2');
      await _synth.loadMidiData(
        data: MultiTrackMidi.export(_withPrograms(parts), bpm: bpm,
          beatsPerBar: _beatsPerBar, gains: _partGains),
        sfId: _soundfontId!,
      );
      await _synth.setMasterGain(_midiVolume);
      _soundfontReady = true;
      await _midiPlayer.setVolume(0);
    } catch (error) {
      _soundfontReady = false;
      await _midiPlayer.setVolume(_midiVolume);
      if (mounted) setState(() =>
        _status = 'SoundFont non disponibile; audio di riserva: $error');
    }
  }

  Future<void> _renderMultiPreview(
    List<InstrumentPart> parts, double duration,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final newFile = File('${dir.path}/ampyscore_mix_'
        '${DateTime.now().microsecondsSinceEpoch}.wav');
    final writer = await newFile.open(mode: FileMode.write);
    var written = 0;
    Uint8List? header;
    try {
      const segmentSeconds = 12.0;
      // Reserve WAV header first; write PCM bytes sequentially.
      await writer.writeFrom(Uint8List(44));
      for (var start = 0.0; start < duration; start += segmentSeconds) {
        final seconds = math.min(segmentSeconds, duration - start);
        final segmentParts = <InstrumentPart>[
          for (final part in parts)
            InstrumentPart(
              family: part.family, confidence: part.confidence,
              notes: [
                for (final note in part.notes)
                  if (note.endSeconds > start &&
                      note.startSeconds < start + seconds)
                    DetectedNote(
                      midi: note.midi,
                      startSeconds: math.max(0, note.startSeconds - start),
                      endSeconds: math.min(seconds, note.endSeconds - start),
                      confidence: note.confidence),
              ],
            ),
        ];
        final wav = await compute(
          MultiTrackMidi.renderMix,
          TrackMix(segmentParts, Map.of(_partGains),
              durationSeconds: seconds),
        );
        header ??= Uint8List.fromList(wav.sublist(0, 44));
        await writer.writeFrom(wav, 44);
        written += wav.length - 44;
      }
      if (header == null) throw const FormatException('MIDI vuoto.');
      final view = ByteData.sublistView(header);
      view.setUint32(4, written + 36, Endian.little);
      view.setUint32(40, written, Endian.little);
      await writer.setPosition(0);
      await writer.writeFrom(header);
      await writer.flush();
    } finally {
      await writer.close();
    }
    final old = _lastMixPath;
    await _midiPlayer.setFilePath(newFile.path);
    await _midiPlayer.setVolume(_soundfontReady ? 0 : _midiVolume);
    _lastMixPath = newFile.path;
    if (old != null) {
      try { await File(old).delete(); } catch (_) {}
    }
  }

  Future<void> _prepareMetronome() async {
    if (!_metronomeEnabled || _trackPath == null) return;
    await _metronomePlayer.stop();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/metro_'
        '${DateTime.now().microsecondsSinceEpoch}.wav');
    final writer = await file.open(mode: FileMode.write);
    Uint8List? header;
    var pcmLength = 0;
    try {
      await writer.writeFrom(Uint8List(44));
      const segment = 12.0;
      final duration = _durationSeconds + .3;
      for (var start = 0.0; start < duration; start += segment) {
        final chunk = await compute(
          MetronomeSynth.render,
          MetronomeSettings(
            bpm: _metronomeBpm,
            subdivisions: _metronomeSubdivisions,
            durationSeconds: math.min(segment, duration - start),
            beatsPerBar: _beatsPerBar,
            startSeconds: start,
          ),
        );
        header ??= Uint8List.fromList(chunk.sublist(0, 44));
        await writer.writeFrom(chunk, 44);
        pcmLength += chunk.length - 44;
      }
      if (header == null) return;
      final view = ByteData.sublistView(header);
      view.setUint32(4, pcmLength + 36, Endian.little);
      view.setUint32(40, pcmLength, Endian.little);
      await writer.setPosition(0);
      await writer.writeFrom(header);
      await writer.flush();
    } finally {
      await writer.close();
    }
    await _metronomePlayer.setFilePath(file.path);
    await _metronomePlayer.setVolume(_metronomeVolume);
    _metronomeReady = true;
  }

  Future<void> _configureMetronome({
    bool? enabled,
    int? bpm,
    int? subdivisions,
  }) async {
    if (_busy) return;
    final previousMode = _playing ? _mode : null;
    final oldPosition = _cursor;
    if (previousMode != null) await _pauseTransport();
    if (mounted) {
      setState(() {
        if (enabled != null) _metronomeEnabled = enabled;
        if (bpm != null) _metronomeBpm = bpm;
        if (subdivisions != null) _metronomeSubdivisions = subdivisions;
        _metronomeReady = false;
      });
    }
    if (_metronomeEnabled && _trackPath != null) {
      await _prepareMetronome();
      await _metronomePlayer.seek(oldPosition);
    } else {
      await _metronomePlayer.pause();
    }
    if (previousMode != null) {
      await _togglePlaybackMode(previousMode);
    }
  }

  Future<void> _jumpToNote(ScoreNote note) async {
    if (_busy || _trackPath == null) return;
    final mode = _mode ??
        (_midiReady ? _PlaybackMode.both : _PlaybackMode.original);
    await _pauseTransport();
    if (mounted) setState(() {
      _selectedNoteId = note.id;
      _selectedFamily = note.family;
    });
    await _seekTransport(Duration(
      microseconds: (_score!.timeOf(note) * 1000000).round(),
    ));
    await _togglePlaybackMode(mode);
  }

  Future<void> _checkForUpdates() => _execute(() async {
    final update = await AppUpdates.check();
    if (!mounted) return;
    final target = update?.url ?? AppUpdates.releases;
    final title = update == null
        ? 'Nessuna release pubblicata'
        : update.hasNewVersion
            ? 'Disponibile ${update.version}'
            : 'Versione aggiornata';
    final open = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(update == null
          ? 'Puoi verificare le release GitHub.'
          : 'Le nuove versioni si installano dal browser. '
            'Per aggiornare mantenendo i dati serve la stessa firma APK.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Chiudi')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Apri GitHub')),
        ],
      ),
    );
    if (open == true) await AppUpdates.openReleases(url: target);
  });

  Future<void> _findSongOnline() async {
    if (_searching) return;
    setState(() => _searching = true);
    List<SongCandidate> matches = const [];
    try {
      // MusicBrainz is only metadata search; score libraries open externally.
      try {
        matches = await SongLookup.find('${_songQuery.text.trim()}.mp3');
      } catch (_) {
        // Metadata service unavailable: public score searches still work.
      }
      if (!mounted) return;
      setState(() => _songResults = matches);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Cerca partiture · ${_songResults.length} brani'),
          content: SizedBox(
            width: 470,
            child: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(spacing: 7, runSpacing: 7, children: [
                  for (final lib in SheetLibrary.values)
                    ActionChip(
                      label: Text(lib.label),
                      avatar: const Icon(Icons.open_in_new, size: 16),
                      onPressed: () => unawaited(launchUrl(
                        lib.searchFor(_songQuery.text),
                        mode: LaunchMode.externalApplication)),
                    ),
                ]),
                if (matches.isNotEmpty) ...[
                  const Divider(height: 25),
                  const Text('Registrazioni trovate'),
                  for (final song in matches.take(6))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(song.title),
                      subtitle: Text(song.artist),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => unawaited(launchUrl(song.url,
                        mode: LaunchMode.externalApplication)),
                    ),
                ],
              ],
            )),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Chiudi')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _analyse() => _execute(() async {
    await _analyseInternal();
    _buildScoreAfterAnalysis();
  });

  double get _durationSeconds {
    final duration = _player.duration;
    if (duration != null && duration.inMilliseconds > 0) {
      return duration.inMilliseconds / 1000.0;
    }
    if (_analysisDuration > 0) return _analysisDuration;
    if (_notes.isNotEmpty) return _notes.last.endSeconds;
    return 1;
  }

  int _noteAt(double seconds) => _notes.indexWhere(
        (note) => seconds >= note.startSeconds &&
            seconds < note.endSeconds,
      );

  void _updateTransport() {
    if (!mounted || !_playing || _mode == null) return;
    final leader =
        _mode == _PlaybackMode.midi ? _midiPlayer : _player;
    if (leader.processingState == ProcessingState.completed) {
      setState(() {
        _playing = false;
        _mode = null;
      });
      unawaited(_midiPlayer.pause());
      unawaited(_player.pause());
      unawaited(_metronomePlayer.pause());
      return;
    }

    final time = leader.position;
    if (_mode == _PlaybackMode.both &&
        !_resyncing &&
        DateTime.now().difference(_lastResync).inMilliseconds > 700) {
      final drift = (time - _midiPlayer.position).inMilliseconds.abs();
      if (drift > 130) {
        _resyncing = true;
        _lastResync = DateTime.now();
        unawaited(_midiPlayer.seek(time).whenComplete(() {
          _resyncing = false;
        }));
      }
    }
    if (_metronomeEnabled && _metronomeReady) {
      final drift = (time - _metronomePlayer.position).inMilliseconds.abs();
      if (drift > 140 && !_resyncing) {
        unawaited(_metronomePlayer.seek(time));
      }
    }
    final index = _noteAt(time.inMicroseconds / 1000000.0);
    if ((time - _cursor).inMilliseconds.abs() >= 40 ||
        index != _activeIndex) {
      setState(() {
        _cursor = time;
        _activeIndex = index;
      });
    }
  }

  Future<void> _pauseTransport() async {
    if (mounted) {
      setState(() {
        _playing = false;
        _mode = null;
      });
    }
    await Future.wait([_player.pause(), _midiPlayer.pause(), _metronomePlayer.pause()]);
    if (_soundfontReady) await _synth.pauseMidi();
  }

  Future<void> _seekTransport(Duration cursor) async {
    final end = Duration(microseconds: (_durationSeconds * 1000000).round());
    final newTime = cursor > end ? end : (cursor.isNegative ? Duration.zero : cursor);
    if (mounted) {
      setState(() {
        _cursor = newTime;
        _activeIndex = _noteAt(newTime.inMicroseconds / 1000000);
      });
    }
    try {
      await _player.seek(newTime);
      if (_midiReady) await _midiPlayer.seek(newTime);
      if (_soundfontReady) {
        final tick = (newTime.inMicroseconds / 1000000 *
            ((_score?.bpm ?? _rhythm?.bpm ?? 120) * 480 / 60)).round();
        await _synth.seekMidi(tick);
      }
      if (_metronomeEnabled && _metronomeReady) {
        await _metronomePlayer.seek(newTime);
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'Posizionamento: $error');
    }
  }

  Future<void> _togglePlaybackMode(_PlaybackMode requested) async {
    if (_busy || _recording || _trackPath == null) return;
    if (requested != _PlaybackMode.original && !_midiReady) return;
    try {
      if (_playing && _mode == requested) {
        await _pauseTransport();
        return;
      }
      await _pauseTransport();
      await _notePlayer.stop();
      if (_metronomeEnabled && !_metronomeReady) {
        await _prepareMetronome();
      }
      var newTime = _cursor;
      if (newTime.inMilliseconds >= (_durationSeconds * 1000).floor() - 80) {
        newTime = Duration.zero;
      }
      await _seekTransport(newTime);
      if (!mounted) return;
      setState(() {
        _mode = requested;
        _playing = true;
      });
      if (requested != _PlaybackMode.midi) {
        unawaited(_player.play());
      }
      if (requested != _PlaybackMode.original) {
        unawaited(_midiPlayer.play());
        if (_soundfontReady) await _synth.playMidi();
      }
      if (_metronomeEnabled && _metronomeReady) {
        unawaited(_metronomePlayer.play());
      }
    } catch (error) {
      if (mounted) setState(() {
        _mode = null;
        _playing = false;
        _status = 'Riproduzione: $error';
      });
    }
  }

  Future<void> _playOneNote(int index) async {
    if (_busy || _recording || index < 0 || index >= _notes.length) return;
    try {
      await _pauseTransport();
      final note = _notes[index];
      final position = Duration(
        microseconds: (note.startSeconds * 1000000).round(),
      );
      await _seekTransport(position);
      await _notePlayer.stop();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/ampyscore_solo_note.wav');
      await file.writeAsBytes(MidiEngine.renderOneNote(note.midi));
      await _notePlayer.setFilePath(file.path);
      await _notePlayer.setVolume(_midiVolume);
      if (!mounted) return;
      setState(() {
        _activeIndex = index;
        _status = 'Ascolto singolo: ${note.label} '
            '(${note.durationSeconds.toStringAsFixed(2)} s nell’originale).';
      });
      unawaited(_notePlayer.play());
    } catch (error) {
      if (mounted) setState(() => _status = 'Nota: $error');
    }
  }

  void _selectFamily(InstrumentFamily family) {
    if (_parts.isEmpty || _busy) return;
    final match = _editedParts().where((part) => part.family == family);
    if (match.isEmpty) return;
    setState(() {
      _selectedFamily = family;
      _notes = match.first.notes;
      _activeIndex = _noteAt(_cursor.inMicroseconds / 1000000.0);
    });
  }

  Future<void> _remix() => _execute(() async {
        if (_parts.isEmpty || !_midiReady) return;
        final resume = _playing;
        final previousMode = _mode;
        final oldCursor = _cursor;
        await _pauseTransport();
        await _midiPlayer.stop();
        final adjusted = _editedParts();
        await _renderMultiPreview(adjusted,
            _score?.durationSeconds ?? _durationSeconds);
        await _loadSoundfontMidi(adjusted,
            _score?.bpm ?? _rhythm?.bpm ?? 120);
        await _seekTransport(oldCursor);
        if (resume && previousMode != null && mounted) {
          setState(() {
            _mode = previousMode;
            _playing = true;
          });
          if (previousMode != _PlaybackMode.midi) {
            unawaited(_player.play());
          }
          if (previousMode != _PlaybackMode.original) {
            unawaited(_midiPlayer.play());
            if (_soundfontReady) unawaited(_synth.playMidi());
          }
        }
      });

  Future<void> _toggleSolo(InstrumentFamily family) async {
    if (_busy || _parts.isEmpty) return;
    if (_soloFamily == family && _savedBeforeSolo != null) {
      setState(() {
        _partGains.addAll(_savedBeforeSolo!);
        _savedBeforeSolo = null;
        _soloFamily = null;
      });
    } else {
      final previous = _savedBeforeSolo ?? Map.of(_partGains);
      setState(() {
        _savedBeforeSolo = previous;
        _soloFamily = family;
        for (final part in _parts) {
          _partGains[part.family] =
              part.family == family ? (previous[family] ?? .9) : 0;
        }
      });
    }
    await _remix();
  }

  Future<void> _exportMidi() => _execute(() async {
        if (_notes.isEmpty) return;
        final score = _score;
    final bytes = score != null
        ? MultiTrackMidi.export(_withPrograms(_editedParts()), bpm: score.bpm,
            beatsPerBar: _beatsPerBar)
        : _parts.isEmpty
            ? MidiEngine.exportMidi(_notes)
            : MultiTrackMidi.export(_withPrograms(_parts), bpm: _rhythm?.bpm ?? 120,
            beatsPerBar: _beatsPerBar);
        final output = await FilePicker.saveFile(
          dialogTitle: 'Esporta la trascrizione MIDI',
          fileName: _parts.isEmpty
              ? 'AmpyScore_trascrizione.mid'
              : 'AmpyScore_multitraccia.mid',
          type: FileType.custom,
          allowedExtensions: ['mid'],
          bytes: bytes,
        );
        if (mounted && output != null) {
          setState(() => _status = 'MIDI esportato: $output');
        }
      });

  Future<void> _askChatGpt() => _execute(() async {
        if (_notes.isEmpty) {
          throw StateError('Analizza prima una melodia.');
        }
        final result = await ChatGptService.explain(
          notes: _notes,
          apiKey: _apiKey.text,
        );
        if (mounted) setState(() => _assistantAnswer = result);
      });

  @override
  Widget build(BuildContext context) {
    final ready = !_busy && !_recording && _trackPath != null;
    final scoreOnly = _score != null &&
        (_forceScoreFullScreen ||
            (MediaQuery.orientationOf(context) == Orientation.landscape
              && _playing));
    if (scoreOnly != _immersive) {
      _immersive = scoreOnly;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await SystemChrome.setEnabledSystemUIMode(scoreOnly
            ? SystemUiMode.immersiveSticky
            : SystemUiMode.edgeToEdge);
      });
    }
    if (scoreOnly) {
      return Scaffold(
        backgroundColor: _paperTone == PaperTone.sepia
            ? const Color(0xFFF2E5CA) : const Color(0xFFFAFAF8),
        body: SafeArea(
          child: Stack(children: [
            Positioned.fill(
              child: StudioScore(
                project: _score!,
                positionSeconds: _cursor.inMicroseconds / 1000000.0,
                tone: _paperTone,
                activeNoteId: _selectedNoteId,
                fullScreen: true,
                onFullScreen: () => setState(() =>
                    _forceScoreFullScreen = false),
                onTapNote: (note) => unawaited(_jumpToNote(note)),
              ),
            ),
            Positioned(
              top: 8, right: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xEE1B2B30),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: _playing ? 'Pausa' : 'Riprendi',
                    color: Colors.white,
                    onPressed: _playing ? _pauseTransport :
                        () => _togglePlaybackMode(
                          _midiReady ? _PlaybackMode.both :
                          _PlaybackMode.original),
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  ),
                  IconButton(
                    tooltip: 'Esci dallo schermo intero',
                    color: Colors.white,
                    onPressed: () {
                      unawaited(_pauseTransport());
                      setState(() => _forceScoreFullScreen = false);
                    },
                    icon: const Icon(Icons.fullscreen_exit),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF101820),
        title: const Row(children: [
          Icon(Icons.graphic_eq_rounded, color: Color(0xFF62DFC3)),
          SizedBox(width: 10),
          Text('AmpyScore Studio',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_alt),
            tooltip: 'Aggiornamenti',
            onPressed: _busy ? null : _checkForUpdates,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pageIndex,
        onDestinationSelected: (value) => setState(() => _pageIndex = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music), label: 'Studio'),
          NavigationDestination(icon: Icon(Icons.edit_note_outlined),
              selectedIcon: Icon(Icons.edit_note), label: 'NoteLab'),
          NavigationDestination(icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune), label: 'Tracce'),
          NavigationDestination(icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings), label: 'Opzioni'),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
          children: [
            if (_pageIndex == 0) _importToolbar(),
            if (_busy) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(minHeight: 3,
                value: _analysisProgress > 0 ? _analysisProgress : null),
            ],
            if (!_busy && _trackPath != null && _pageIndex == 0) ...[
              const SizedBox(height: 8),
              Text(_status,
                style: const TextStyle(fontSize: 12, color: Color(0xFFA2B6C1)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 12),
            if (_pageIndex == 0) _studioView(ready),
            if (_pageIndex == 1) _noteLabView(),
            if (_pageIndex == 2) _tracksView(),
            if (_pageIndex == 3) _settingsView(),
          ],
        ),
      ),
    );
  }

  Widget _importToolbar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy || _recording ? null : _import,
            icon: const Icon(Icons.folder_open),
            label: const Text('Apri brano'),
          ),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _toggleRecording,
            icon: Icon(_recording ? Icons.stop_circle : Icons.mic),
            label: Text(_recording ? 'Stop' : 'Registra'),
          ),

        ]),
        if (_trackPath != null) ...[
          const SizedBox(height: 9),
          Text(
            _trackName,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _studioView(bool ready) {
    final score = _score;
    final length = _durationSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Expanded(
            child: Text('Partitura',
                style: TextStyle(fontSize: 20,
                    fontWeight: FontWeight.w700)),
          ),
          if (_rhythm != null)
            Text('≈ ${_rhythm!.bpm} BPM',
                style: const TextStyle(color: Color(0xFF62DFC3))),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Carta bianca / seppia',
            onPressed: score == null ? null :
                () => setState(() => _paperTone =
                    _paperTone == PaperTone.ivory
                        ? PaperTone.sepia : PaperTone.ivory),
            icon: const Icon(Icons.palette_outlined),
          ),
        ]),
        const SizedBox(height: 8),
        if (_originalUsesFallback)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('Codec originale non supportato dal dispositivo: '
              'riproduzione PCM mono di compatibilità.',
              style: TextStyle(color: Color(0xFFEF9C57),
                  fontSize: 12)),
          ),
        if (score == null)
          _section(
            icon: Icons.music_note,
            title: 'Nessuna partitura',
            child: const Text('Apri un brano o prova una demo.'),
          )
        else ...[
          StudioScore(
            project: score,
            positionSeconds: _cursor.inMicroseconds / 1000000.0,
            tone: _paperTone,
            activeNoteId: _selectedNoteId,
            onFullScreen: () =>
                setState(() => _forceScoreFullScreen = true),
            onTapNote: (note) => unawaited(_jumpToNote(note)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.schedule, size: 17),
            const SizedBox(width: 5),
            Text('${(_cursor.inMilliseconds / 1000).toStringAsFixed(1)} s'),
            const Spacer(),
            Text('${length.toStringAsFixed(1)} s'),
          ]),
          Slider(
            value: (_cursor.inMilliseconds / 1000.0).clamp(0, length),
            min: 0, max: length,
            onChanged: ready ? (value) => setState(() {
              _cursor = Duration(milliseconds: (value * 1000).round());
              _activeIndex = _noteAt(value);
            }) : null,
            onChangeEnd: ready ? (value) =>
                unawaited(_seekTransport(
                    Duration(milliseconds: (value * 1000).round()))) : null,
          ),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
            onPressed: ready ? () =>
              _togglePlaybackMode(_PlaybackMode.original) : null,
            icon: Icon(_playing && _mode == _PlaybackMode.original
                ? Icons.pause : Icons.play_arrow),
            label: const Text('Audio'),
          ),
          FilledButton.tonalIcon(
            onPressed: ready && _midiReady ? () =>
              _togglePlaybackMode(_PlaybackMode.midi) : null,
            icon: Icon(_playing && _mode == _PlaybackMode.midi
                ? Icons.pause : Icons.piano),
            label: const Text('MIDI'),
          ),
          FilledButton.icon(
            onPressed: ready && _midiReady ? () =>
              _togglePlaybackMode(_PlaybackMode.both) : null,
            icon: Icon(_playing && _mode == _PlaybackMode.both
                ? Icons.pause : Icons.library_music),
            label: const Text('Insieme'),
          ),
          IconButton.filledTonal(
            tooltip: 'Pausa',
            onPressed: _playing ? _pauseTransport : null,
            icon: const Icon(Icons.pause),
          ),
          IconButton.filledTonal(
            tooltip: 'Ascolta singola nota',
            onPressed: !_busy && _activeIndex >= 0 &&
                    _activeIndex < _notes.length
                ? () => _playOneNote(_activeIndex) : null,
            icon: const Icon(Icons.music_note),
          ),
        ]),
        const SizedBox(height: 13),
        _volumeRow(
          'Brano',
          _originalVolume,
          Icons.multitrack_audio,
          (value) {
            setState(() => _originalVolume = value);
            unawaited(_player.setVolume(value));
          },
        ),
        _volumeRow(
          'MIDI',
          _midiVolume,
          Icons.piano,
          (value) {
            setState(() => _midiVolume = value);
            unawaited(_midiPlayer.setVolume(_soundfontReady ? 0 : value));
            if (_soundfontReady) unawaited(_synth.setMasterGain(value));
            unawaited(_notePlayer.setVolume(value));
          },
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _midiReady && !_busy ? _exportMidi : null,
            icon: const Icon(Icons.download_outlined),
            label: const Text('MIDI'),
          ),
          OutlinedButton.icon(
            onPressed: score != null && !_busy
                ? _exportMusicXml : null,
            icon: const Icon(Icons.description_outlined),
            label: const Text('MusicXML'),
          ),
          if (ready)
            TextButton(
              onPressed: _analyse,
              child: const Text('Rianalizza'),
            ),
          if (score != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.travel_explore),
              onPressed: _searching ? null : _openSongSearch,
              label: const Text('Confronta online'),
            ),
          if (score != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.compare_arrows),
              onPressed: _busy ? null : _compareReference,
              label: const Text('Confronta MusicXML'),
            ),
        ]),

      ],
    );
  }

  Widget _volumeRow(String label, double value, IconData icon,
      ValueChanged<double> change) {
    return Row(children: [
      Icon(icon, size: 18),
      const SizedBox(width: 8),
      SizedBox(width: 55, child: Text(label)),
      Expanded(child: Slider(value: value,
          min: 0, max: 1, onChanged: change)),
      SizedBox(width: 42,
          child: Text('${(value * 100).round()}%')),
    ]);
  }

  Widget _noteLabView() {
    final score = _score;
    if (score == null) return const Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text('Apri un brano per usare NoteLab.'),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Expanded(child: Text('NoteLab',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          Text('${_tempoSlider.round()} BPM'),
          IconButton(
            tooltip: 'Schermo intero',
            onPressed: () => setState(() => _forceScoreFullScreen = true),
            icon: const Icon(Icons.fullscreen),
          ),
        ]),
        StudioScore(
          project: score,
          positionSeconds: _cursor.inMicroseconds / 1000000,
          tone: _paperTone,
          activeNoteId: _selectedNoteId,
          onFullScreen: () => setState(() => _forceScoreFullScreen = true),
          onTapNote: (note) {
            _selectFamily(note.family);
            setState(() => _selectedNoteId = note.id);
          },
        ),
        const SizedBox(height: 14),
        _section(
          icon: Icons.edit_note,
          title: 'Modifica nota',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NoteLab(
                score: score,
                selectedFamily: _selectedFamily,
                selectedNoteId: _selectedNoteId,
                onSelect: (note) => setState(() {
                  _selectedNoteId = note.id;
                  _selectedFamily = note.family;
                }),
                onChanged: _onScoreEdit,
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _rebuildMidiFromScore,
                  icon: const Icon(Icons.piano),
                  label: const Text('Aggiorna MIDI'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _retranscribeAtBpm,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Ritrascrivi'),
                ),
              ]),
              Slider(
                value: _tempoSlider, min: 50, max: 220, divisions: 170,
                label: '${_tempoSlider.round()} BPM',
                onChanged: _busy ? null :
                    (v) => setState(() => _tempoSlider = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tracksView() {
    return Column(
      children: [
        _section(
          icon: Icons.graphic_eq,
          title: 'Tracce MIDI',
          child: MultiTrackPanel(
            parts: _parts,
            rhythm: _rhythm,
            selected: _selectedFamily,
            gains: _partGains,
            solo: _soloFamily,
            enabled: !_busy && !_recording,
            onSelect: _selectFamily,
            onSolo: (family) => unawaited(_toggleSolo(family)),
            onGain: (family, value) => setState(() {
              _partGains[family] = value;
              if (_savedBeforeSolo != null) {
                _savedBeforeSolo![family] = value;
              }
            }),
            onGainDone: () => unawaited(_remix()),
          ),
        ),
        if (_parts.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final part in _parts)
            if (!part.percussion)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(part.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _gmPrograms[part.family] ?? part.midiProgram,
                    items: [
                      for (final entry in _gmNames.entries)
                        DropdownMenuItem<int>(
                          value: entry.key,
                          child: Text(entry.value,
                            style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                    onChanged: _busy ? null : (program) {
                      if (program == null) return;
                      setState(() => _gmPrograms[part.family] = program);
                      unawaited(_remix());
                    },
                  ),
                ]),
              ),
        ],
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text('Filtri audio sperimentali'),
          leading: const Icon(Icons.equalizer),
          childrenPadding: const EdgeInsets.all(10),
          children: [
            DropdownButton<FocusStem>(
              isExpanded: true, value: _focusStem,
              items: [
                for (final stem in FocusStem.values)
                  DropdownMenuItem(value: stem, child: Text(stem.title)),
              ],
              onChanged: _busy ? null : (value) {
                if (value != null) setState(() => _focusStem = value);
              },
            ),
            Wrap(spacing: 8, children: [
              FilledButton.tonalIcon(
                onPressed: _busy || _trackPath == null ? null : _playStem,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Ascolta'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || _trackPath == null ? null : _exportStem,
                icon: const Icon(Icons.save_alt),
                label: const Text('Esporta WAV'),
              ),
            ]),
            const Text('Filtri per frequenze, non separazione IA degli strumenti.',
                style: TextStyle(fontSize: 11, color: Color(0xFFAFBEC9))),
          ],
        ),
        ExpansionTile(
          title: const Text('ChatGPT (opzionale)'),
          leading: const Icon(Icons.smart_toy_outlined),
          childrenPadding: const EdgeInsets.all(10),
          children: [
            const Text('Solo note testuali inviate online. '
                'Richiede una chiave API con costi separati.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: _apiKey, obscureText: true,
              enableSuggestions: false, autocorrect: false,
              decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'Chiave API OpenAI',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _notes.isEmpty || _busy ? null : _askChatGpt,
              child: const Text('Analizza le note'),
            ),
            if (_assistantAnswer != null)
              SelectableText(_assistantAnswer!),
          ],
        ),
      ],
    );
  }

  Future<void> _compareReference() => _execute(() async {
    final project = _score;
    if (project == null) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['musicxml', 'xml'],
    );
    if (file == null) return;
    final raw = await file.readAsBytes();
    if (raw.length > 12 * 1024 * 1024) {
      throw const FormatException('MusicXML troppo grande.');
    }
    final xml = utf8.decode(raw, allowMalformed: false);
    final comparison = ReferenceScore.compare(project, xml);
    if (!mounted) return;
    final action = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confronto MusicXML'),
        content: Text('Coincidenze intonazione/attacco: '
          '${(100 * comparison.f1).toStringAsFixed(1)}% F1.\n'
          '${comparison.matched} note abbinate su '
          '${comparison.transcribed} rilevate e '
          '${comparison.reference} di riferimento.\n'
          'Tolleranza: 1/16 (2 scatti di 1/32).'
          '${comparison.meter == null ? "" : "\\nMetrica riferimento: ${comparison.meter}/4"}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Chiudi')),
          if (comparison.meter != null && comparison.meter != _beatsPerBar &&
              comparison.meter! >= 2 && comparison.meter! <= 12)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Usa ${comparison.meter}/4')),
        ],
      ),
    );
    if (action == true) {
      setState(() {
        _beatsPerBar = comparison.meter!;
        _score!.beatsPerBar = comparison.meter!;
        _metronomeReady = false;
      });
    }
  });

  Future<void> _openSongSearch() async {
    final input = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerca partitura online'),
        content: TextField(
          controller: _songQuery,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Titolo o artista', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla')),
          FilledButton(
            onPressed: () => Navigator.pop(context, _songQuery.text.trim()),
            child: const Text('Cerca')),
        ],
      ),
    );
    if (input == null || input.length < 4 || !mounted) return;
    _songQuery.text = input;
    await _findSongOnline();
  }

  Widget _settingsView() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _section(
        icon: Icons.tune,
        title: 'Visualizzazione',
        child: Column(children: [
          SegmentedButton<PaperTone>(
            segments: const [
              ButtonSegment(value: PaperTone.ivory, label: Text('Bianco')),
              ButtonSegment(value: PaperTone.sepia, label: Text('Seppia')),
            ],
            selected: {_paperTone},
            onSelectionChanged: (set) =>
                setState(() => _paperTone = set.first),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Multitraccia'),
            value: _multitrackMode,
            onChanged: _busy ? null : (value) {
              setState(() => _multitrackMode = value);
              if (_trackPath != null) unawaited(_analyse());
            },
          ),
        ]),
      ),
      const SizedBox(height: 12),
      _section(
        icon: Icons.queue_music,
        title: 'Tempo in chiave',
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 3, label: Text('3/4')),
            ButtonSegment(value: 4, label: Text('4/4')),
            ButtonSegment(value: 5, label: Text('5/4')),
            ButtonSegment(value: 6, label: Text('6/4')),
          ],
          selected: {_beatsPerBar},
          onSelectionChanged: (value) {
            setState(() {
              _beatsPerBar = value.first;
              _score?.beatsPerBar = value.first;
              _metronomeReady = false;
            });
            if (_metronomeEnabled) {
              unawaited(_configureMetronome());
            }
          },
        ),
      ),
      const SizedBox(height: 12),
      _section(
        icon: Icons.av_timer,
        title: 'Metronomo',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _metronomeEnabled,
            title: const Text('Attivo durante la riproduzione'),
            onChanged: _busy ? null :
                (value) => unawaited(
                    _configureMetronome(enabled: value)),
          ),
          Text('Tempo: $_metronomeBpm BPM'),
          Slider(
            min: 40, max: 240, divisions: 200,
            value: _metronomeBpm.toDouble(),
            label: '$_metronomeBpm BPM',
            onChanged: _busy ? null :
                (v) => setState(() => _metronomeBpm = v.round()),
            onChangeEnd: _busy ? null :
                (v) => unawaited(
                  _configureMetronome(bpm: v.round())),
          ),
          Wrap(spacing: 8, children: [
            for (final subdivision in [1, 2, 4, 8])
              ChoiceChip(
                selected: _metronomeSubdivisions == subdivision,
                label: Text(switch (subdivision) {
                  1 => '1/4', 2 => '1/8', 4 => '1/16', _ => '1/32'
                }),
                onSelected: _busy ? null : (_) => unawaited(
                  _configureMetronome(subdivisions: subdivision)),
              ),
          ]),
          const Text('Volume'),
          Slider(
            value: _metronomeVolume,
            onChanged: (value) {
              setState(() => _metronomeVolume = value);
              unawaited(_metronomePlayer.setVolume(value));
            },
          ),
        ]),
      ),
      const SizedBox(height: 12),
      _section(
        icon: Icons.music_note,
        title: 'Esempi',
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
            onPressed: _busy ? null : _multiDemo,
            child: const Text('Demo multitraccia')),
          OutlinedButton(
            onPressed: _busy ? null : _demo,
            child: const Text('Demo melodia')),
        ]),
      ),
      const SizedBox(height: 12),
      _section(
        icon: Icons.system_update_alt,
        title: 'Aggiornamenti',
        child: FilledButton.tonalIcon(
          onPressed: _busy ? null : _checkForUpdates,
          icon: const Icon(Icons.update),
          label: const Text('Controlla su GitHub'),
        ),
      ),
    ],
  );


  Widget _section({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF17222E),
        border: Border.all(color: const Color(0xFF2B3C48)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: const Color(0xFF62DFC3)),
            const SizedBox(width: 9),
            Expanded(child: Text(title, style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

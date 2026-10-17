import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'audio/wav_engine.dart';
import 'audio/midi_engine.dart';
import 'audio/multitrack_engine.dart';
import 'audio/multitrack_midi.dart';
import 'audio/rhythm_engine.dart';
import 'audio/stem_extractor.dart';
import 'score/score_engine.dart';
import 'score/score_sheet.dart';
import 'score/note_lab.dart';
import 'ui/multitrack_panel.dart';
import 'services/chatgpt_service.dart';

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
  final _midiPlayer = AudioPlayer(); // Synthesized preview WAV.
  final _notePlayer = AudioPlayer(); // One MIDI pitch at a time.
  final _stemPlayer = AudioPlayer(); // Optional spectral focus WAV.
  final _apiKey = TextEditingController();
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
  final Map<InstrumentFamily, double> _partGains = {
    for (final family in InstrumentFamily.values) family: 0.90,
  };
  String? _trackPath;
  String _trackName = 'Nessuna traccia';
  String _status = 'Pronto per una registrazione o un file WAV.';
  String? _assistantAnswer;
  bool _recording = false;
  bool _busy = false;
  bool _playing = false;
  bool _midiReady = false;
  bool _resyncing = false;
  _PlaybackMode? _mode;
  Duration _cursor = Duration.zero;
  DateTime _lastResync = DateTime.fromMillisecondsSinceEpoch(0);
  int _activeIndex = -1;
  double _originalVolume = 0.70;
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
    _recorder.dispose();
    _player.dispose();
    _midiPlayer.dispose();
    _notePlayer.dispose();
    _stemPlayer.dispose();
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

  Future<void> _load(String path, String name) async {
    await _pauseTransport();
    await _player.stop();
    await _midiPlayer.stop();
    await _notePlayer.stop();
    await _stemPlayer.stop();
    await _player.setFilePath(path);
    if (!mounted) return;
    setState(() {
      _trackPath = path;
      _trackName = name;
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
      _status = 'WAV caricato. Premi Analizza WAV per riconoscere le note.';
    });
  }

  Future<void> _demo() => _execute(() async {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/ampyscore_demo.wav');
        await file.writeAsBytes(DemoWav.create(), flush: true);
        await _load(file.path, 'Demo: Do Re Mi Sol');
      });

  Future<void> _multiDemo() => _execute(() async {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/ampyscore_multitrack_demo.wav');
        await file.writeAsBytes(MultiInstrumentDemo.create(), flush: true);
        await _load(file.path, 'Demo multistrumento: basso, armonia, melodia, beat');
        if (mounted) {
          setState(() {
            _multitrackMode = true;
            _status = 'Demo multistrumento caricata. Premi Analizza WAV.';
          });
        }
      });

  Future<void> _import() => _execute(() async {
        final selected = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['wav'],
        );
        if (selected == null) return;
        final fileBytes = await selected.readAsBytes();
        if (fileBytes.length > 32 * 1024 * 1024) {
          throw const FormatException('WAV troppo grande (limite 32 MB).');
        }
        final dir = await getApplicationDocumentsDirectory();
        final destination = File(
            '${dir.path}/import_${DateTime.now().millisecondsSinceEpoch}.wav');
        await destination.writeAsBytes(fileBytes, flush: true);
        await _load(destination.path, selected.name);
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

  Future<void> _analyseInternal() async {
    await _pauseTransport();
    final path = _trackPath;
    if (path == null) {
      throw StateError('Seleziona una traccia WAV o la demo.');
    }
    final bytes = await File(path).readAsBytes();
    if (bytes.length > 32 * 1024 * 1024) {
      throw const FormatException('WAV troppo grande (limite 32 MB).');
    }
    if (mounted) setState(() => _status = 'Trascrizione in corso sul dispositivo...');
    await _midiPlayer.stop();
    if (_multitrackMode) {
      final result = await compute(MultiTrackAnalyzer.analyze, bytes);
      final rhythm = RhythmAnalyzer.estimate(result.parts);
      final wanted = result.parts.where(
        (p) => p.family == InstrumentFamily.melody,
      );
      final selected = wanted.isNotEmpty
          ? wanted.first
          : (result.parts.isNotEmpty ? result.parts.first : null);
      if (result.hasNotes) {
        await _renderMultiPreview(result.parts, result.durationSeconds);
      }
      await _player.seek(Duration.zero);
      if (mounted) {
        setState(() {
          _parts = result.parts;
          _selectedFamily = selected?.family;
          _rhythm = rhythm;
          _notes = selected?.notes ?? const [];
          _assistantAnswer = null;
          _midiReady = result.hasNotes;
          _cursor = Duration.zero;
          _activeIndex = -1;
          _soloFamily = null;
          _savedBeforeSolo = null;
          _status = !result.hasNotes
              ? 'Nessun registro rilevato. Prova la demo multistrumento.'
              : '${result.parts.length} registri sonori stimati, '
                'tempo ≈ ${rhythm.bpm} BPM. '
                'Il metodo non identifica strumenti reali con certezza.';
        });
      }
    } else {
      final detected = await compute(WavTranscriber.transcribe, bytes);
      if (detected.isNotEmpty) {
        final rendered = await compute(MidiEngine.renderWav, detected);
        final dir = await getApplicationDocumentsDirectory();
        final preview = File('${dir.path}/ampyscore_midi_preview.wav');
        await preview.writeAsBytes(rendered, flush: true);
        await _midiPlayer.setFilePath(preview.path);
        await _midiPlayer.setVolume(_midiVolume);
      }
      await _player.seek(Duration.zero);
      final rhythm = RhythmAnalyzer.estimate([
        InstrumentPart(family: InstrumentFamily.melody,
            notes: detected, confidence: 0.6),
      ]);
      if (mounted) {
        setState(() {
          _notes = detected;
          _parts = const [];
          _rhythm = rhythm;
          _selectedFamily = null;
          _assistantAnswer = null;
          _midiReady = detected.isNotEmpty;
          _cursor = Duration.zero;
          _activeIndex = -1;
          _status = detected.isEmpty
              ? 'Non ho trovato note abbastanza chiare.'
              : '${detected.length} note. Tempo ≈ ${rhythm.bpm} BPM.';
        });
      }
    }
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
    final project = ScoreProject.fromTranscription(parts, bpm);
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
          DetectedNote(
            midi: item.midi,
            startSeconds: project.timeOf(item),
            endSeconds: project.timeOf(item) +
                item.length * 60 / (project.bpm * 4),
            confidence: item.evidence,
          ),
      ];
    });
  }

  List<InstrumentPart> _editedParts() {
    final score = _score;
    if (score == null) return _parts;
    return [
      for (final part in score.parts)
        InstrumentPart(
          family: part.family,
          confidence: part.confidence,
          notes: [
            for (final item in score.forFamily(part.family))
              DetectedNote(
                midi: item.midi,
                startSeconds: score.timeOf(item),
                endSeconds: score.timeOf(item) +
                    item.length * 60 / (score.bpm * 4),
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
    final path = _trackPath;
    if (path == null) throw StateError('Carica prima un WAV.');
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

  Future<void> _renderMultiPreview(
    List<InstrumentPart> parts, double duration,
  ) async {
    final data = await compute(
      MultiTrackMidi.renderMix,
      TrackMix(parts, Map.of(_partGains), durationSeconds: duration),
    );
    final dir = await getApplicationDocumentsDirectory();
    final newFile = File('${dir.path}/ampyscore_mix_'
        '${DateTime.now().microsecondsSinceEpoch}.wav');
    await newFile.writeAsBytes(data, flush: true);
    final old = _lastMixPath;
    await _midiPlayer.setFilePath(newFile.path);
    await _midiPlayer.setVolume(_midiVolume);
    _lastMixPath = newFile.path;
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {
        // OS may still hold the last playback file.
      }
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
    if (_notes.isNotEmpty) {
      return _notes.last.endSeconds;
    }
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
    await Future.wait([_player.pause(), _midiPlayer.pause()]);
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
      if (_midiReady) {
        await _midiPlayer.seek(newTime);
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
    final match = _parts.where((part) => part.family == family);
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
        await _renderMultiPreview(_parts, _durationSeconds);
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
        ? MultiTrackMidi.export(_editedParts(), bpm: score.bpm)
        : _parts.isEmpty
            ? MidiEngine.exportMidi(_notes)
            : MultiTrackMidi.export(_parts, bpm: _rhythm?.bpm ?? 120);
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
    final canPlay = !_busy && !_recording && _trackPath != null;
    final canAnalyze = canPlay;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF101820),
        title: const Row(children: [
          Icon(Icons.graphic_eq_rounded, color: Color(0xFF62DFC3)),
          SizedBox(width: 10),
          Text('AmpyScore AI', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 18),
            child: Center(
              child: Text('v0.4', style: TextStyle(color: Color(0xFF9DAABA))),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 42),
          children: [
            const Text(
              'Il tuo studio musicale,\nsul telefono.',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800,
                  height: 1.12),
            ),
            const SizedBox(height: 9),
            const Text(
              'Studio multitraccia · partitura 4/4 · NoteLab.',
              style: TextStyle(color: Color(0xFF9DAABA)),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _toggleRecording,
                  icon: Icon(_recording ? Icons.stop_circle_outlined : Icons.mic),
                  label: Text(_recording ? 'Stop e analizza' : 'Registra'),
                  style: _recording
                      ? FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFB85E70),
                          foregroundColor: Colors.white,
                        )
                      : null,
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _recording ? null : _demo,
                  icon: const Icon(Icons.music_note),
                  label: const Text('Demo musicale'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _recording ? null : _multiDemo,
                  icon: const Icon(Icons.library_music_outlined),
                  label: const Text('Demo multistrumento'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _recording ? null : _import,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Importa WAV'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _section(
              icon: Icons.multitrack_audio,
              title: 'Traccia audio',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_trackName, maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 11),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _multitrackMode,
                    onChanged: _busy || _recording ? null : (value) {
                      unawaited(_pauseTransport());
                      setState(() {
                        _multitrackMode = value;
                        _notes = const [];
                        _parts = const [];
                        _rhythm = null;
                        _midiReady = false;
                        _selectedFamily = null;
                        _activeIndex = -1;
                        _status = 'Modalità cambiata. Premi Analizza WAV.';
                      });
                    },
                    title: const Text('Analisi multitraccia'),
                    subtitle: const Text('Sperimentale: per registro, non per timbro',
                      style: TextStyle(fontSize: 12)),
                  ),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    FilledButton.tonalIcon(
                      onPressed: canPlay
                          ? () => _togglePlaybackMode(_PlaybackMode.original)
                          : null,
                      icon: Icon(_playing && _mode == _PlaybackMode.original
                          ? Icons.pause : Icons.play_arrow),
                      label: const Text('Solo brano'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: canAnalyze ? _analyse : null,
                      icon: const Icon(Icons.auto_graph),
                      label: const Text('Analizza WAV'),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text(_status, style: const TextStyle(
                      fontSize: 13, color: Color(0xFFA5B6C2))),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(minHeight: 3),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            _section(
              icon: Icons.graphic_eq_outlined,
              title: 'Registri e ritmo · identificazione preliminare',
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
            const SizedBox(height: 20),
            _section(
              icon: Icons.piano,
              title: 'Confronto audio / MIDI',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Il MIDI è ricostruito dalle note riconosciute con un '
                    'timbro sintetico. Puoi sentire le due tracce separate '
                    'oppure sovrapposte e regolarle indipendentemente.',
                    style: TextStyle(color: Color(0xFFAFBDCA), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.tonalIcon(
                      onPressed: !_busy && _midiReady && !_recording
                          ? () => _togglePlaybackMode(_PlaybackMode.midi)
                          : null,
                      icon: Icon(_playing && _mode == _PlaybackMode.midi
                          ? Icons.pause : Icons.piano),
                      label: const Text('Solo MIDI'),
                    ),
                    FilledButton.icon(
                      onPressed: !_busy && _midiReady && !_recording
                          ? () => _togglePlaybackMode(_PlaybackMode.both)
                          : null,
                      icon: Icon(_playing && _mode == _PlaybackMode.both
                          ? Icons.pause : Icons.library_music),
                      label: const Text('Ascolta insieme'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _playing ? _pauseTransport : null,
                      icon: const Icon(Icons.pause_circle_outline),
                      label: const Text('Pausa'),
                    ),
                    OutlinedButton.icon(
                      onPressed: !_busy && _midiReady
                          ? _exportMidi : null,
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('Esporta .mid'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Text(
                    'Posizione: ${_cursor.inMilliseconds / 1000.0 < 0 ? 0 : (_cursor.inMilliseconds / 1000).toStringAsFixed(1)} s'
                    ' / ${_durationSeconds.toStringAsFixed(1)} s',
                  ),
                  Slider(
                    value: (_cursor.inMilliseconds / 1000.0)
                        .clamp(0.0, _durationSeconds),
                    min: 0,
                    max: _durationSeconds,
                    onChanged: canPlay
                        ? (value) => setState(() {
                            _cursor = Duration(
                                milliseconds: (value * 1000).round());
                            _activeIndex = _noteAt(value);
                          })
                        : null,
                    onChangeEnd: canPlay
                        ? (value) => unawaited(_seekTransport(Duration(
                            milliseconds: (value * 1000).round())))
                        : null,
                  ),
                  const Text('Volume brano originale'),
                  Row(children: [
                    const Icon(Icons.multitrack_audio, size: 19),
                    Expanded(child: Slider(
                      value: _originalVolume,
                      min: 0,
                      max: 1,
                      onChanged: (value) {
                        setState(() => _originalVolume = value);
                        unawaited(_player.setVolume(value));
                      },
                    )),
                    SizedBox(width: 46,
                        child: Text('${(_originalVolume * 100).round()}%')),
                  ]),
                  const Text('Volume MIDI sintetizzato'),
                  Row(children: [
                    const Icon(Icons.piano, size: 19),
                    Expanded(child: Slider(
                      value: _midiVolume,
                      min: 0,
                      max: 1,
                      onChanged: (value) {
                        setState(() => _midiVolume = value);
                        unawaited(_midiPlayer.setVolume(value));
                        unawaited(_notePlayer.setVolume(value));
                      },
                    )),
                    SizedBox(width: 46,
                        child: Text('${(_midiVolume * 100).round()}%')),
                  ]),
                  if (_activeIndex >= 0 && _activeIndex < _notes.length)
                    Text('Nota attuale: ${_notes[_activeIndex].label}',
                        style: const TextStyle(
                            color: Color(0xFF62DFC3),
                            fontWeight: FontWeight.bold)),
                  const SizedBox(height: 9),
                  const Text(
                    'Sincronizzazione approssimata: due player indipendenti. '
                    'In questa versione il MIDI è monofonico.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9DAABA)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _section(
              icon: Icons.queue_music,
              title: 'Spartito completo · 4/4',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_score == null)
                    const Text('Analizza un WAV per vedere tutti i pentagrammi.')
                  else ...[
                    SegmentedButton<PaperTone>(
                      segments: const [
                        ButtonSegment(value: PaperTone.ivory,
                            label: Text('Bianco')),
                        ButtonSegment(value: PaperTone.sepia,
                            label: Text('Seppia')),
                      ],
                      selected: {_paperTone},
                      onSelectionChanged: (tone) =>
                        setState(() => _paperTone = tone.first),
                    ),
                    const SizedBox(height: 10),
                    StudioScore(
                      project: _score!,
                      positionSeconds: _cursor.inMicroseconds / 1000000.0,
                      tone: _paperTone,
                      activeNoteId: _selectedNoteId,
                      onTapNote: (note) => setState(() {
                        _selectedNoteId = note.id;
                        _selectedFamily = note.family;
                        _notes = _score!.forFamily(note.family).map((item) =>
                            DetectedNote(
                              midi: item.midi,
                              startSeconds: _score!.timeOf(item),
                              endSeconds: _score!.timeOf(item) +
                                item.length * 60 / (_score!.bpm * 4),
                              confidence: item.evidence,
                            ),
                        ).toList();
                      }),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Tutti i registri in simultanea. Barra verde marino in '
                    'riproduzione; battute rosse se NoteLab trova errori '
                    'di durata/sovrapposizione.',
                    style: TextStyle(fontSize: 12,
                        color: Color(0xFF9DAABA)),
                  ),
                  if (_notes.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      _selectedFamily == null
                          ? 'Tocca una nota per ascoltarla da sola:'
                          : 'Pentagramma: ${_parts.firstWhere(
                                (part) => part.family == _selectedFamily,
                              ).name}. Tocca una nota:',
                      style: const TextStyle(color: Color(0xFFAFBDCA)),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 54,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _notes.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 7),
                        itemBuilder: (context, index) {
                          final note = _notes[index];
                          return ActionChip(
                            avatar: Icon(
                              _activeIndex == index
                                  ? Icons.volume_up : Icons.play_arrow,
                              size: 19,
                            ),
                            label: Text('${index + 1} · ${note.label}'
                                '${_rhythm == null ? "" : " · ${_rhythm!.valueFor(note, next: index + 1 < _notes.length ? _notes[index + 1] : null).label}"}'),
                            onPressed: _busy || _recording
                                ? null : () => unawaited(_playOneNote(index)),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            _section(
              icon: Icons.edit_note,
              title: 'NoteLab · editor e revisione',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_score == null)
                    const Text('Trascrivi prima una traccia.')
                  else ...[
                    Text(
                      'Rianalizza a tempo impostato: '
                      '${_tempoSlider.round()} BPM '
                      '(tempo stimato originario '
                      '≈ ${_rhythm?.bpm ?? 120} BPM)',
                    ),
                    Slider(
                      value: _tempoSlider,
                      min: 50,
                      max: 220,
                      divisions: 170,
                      label: '${_tempoSlider.round()} BPM',
                      onChanged: _busy ? null :
                          (value) => setState(() => _tempoSlider = value),
                    ),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _retranscribeAtBpm,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Ritrascrivi al nuovo BPM'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _rebuildMidiFromScore,
                        icon: const Icon(Icons.piano),
                        label: const Text('Aggiorna MIDI dalle note'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _exportMusicXml,
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Esporta MusicXML'),
                      ),
                    ]),
                    const SizedBox(height: 13),
                    NoteLab(
                      score: _score!,
                      selectedFamily: _selectedFamily,
                      selectedNoteId: _selectedNoteId,
                      onSelect: (item) => setState(() {
                        _selectedNoteId = item.id;
                        _selectedFamily = item.family;
                      }),
                      onChanged: _onScoreEdit,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            _section(
              icon: Icons.filter_alt_outlined,
              title: 'Estrazione sperimentale WAV · offline',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filtri DSP per ascoltare porzioni dello spettro. '
                    'La fascia vocale è una STIMA, può contenere strumenti '
                    'e non isola realmente il cantante; serve un modello '
                    'di source separation per veri stem.',
                    style: TextStyle(fontSize: 12,
                      color: Color(0xFFAFBEC9)),
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<FocusStem>(
                    isExpanded: true,
                    value: _focusStem,
                    items: [
                      for (final stem in FocusStem.values)
                        DropdownMenuItem(value: stem, child: Text(stem.title)),
                    ],
                    onChanged: _busy ? null :
                        (value) => setState(() {
                          if (value != null) _focusStem = value;
                        }),
                  ),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.tonalIcon(
                      onPressed: _busy || _trackPath == null ? null : _playStem,
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Ascolta filtro'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || _trackPath == null ? null : _exportStem,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Salva WAV filtrato'),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _section(
              icon: Icons.psychology_alt_outlined,
              title: 'ChatGPT · facoltativo / online',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Il riconoscimento delle note funziona offline. '
                    'Solo su tua richiesta ChatGPT riceve i NOMI delle note '
                    '(mai la registrazione) e restituisce una spiegazione. '
                    'Richiede Internet e una chiave API OpenAI con eventuali costi.',
                    style: TextStyle(fontSize: 13,
                        color: Color(0xFFBDC8D1)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKey,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Chiave API OpenAI (solo questa sessione)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _notes.isEmpty || _busy || _recording
                        ? null : _askChatGpt,
                    icon: const Icon(Icons.smart_toy_outlined),
                    label: const Text('Chiedi a ChatGPT'),
                  ),
                  if (_assistantAnswer != null) ...[
                    const SizedBox(height: 13),
                    SelectableText(_assistantAnswer!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Open source · MIT · Nessun login richiesto per le funzioni offline.',
              style: TextStyle(fontSize: 12, color: Color(0xFF8B9BA9)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

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

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'audio/staff_painter.dart';
import 'audio/wav_engine.dart';
import 'audio/midi_engine.dart';
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
  final _apiKey = TextEditingController();
  Timer? _transportTimer;

  List<DetectedNote> _notes = const [];
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
    await _player.setFilePath(path);
    if (!mounted) return;
    setState(() {
      _trackPath = path;
      _trackName = name;
      _notes = const [];
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
          return;
        }
        if (!await _recorder.hasPermission()) {
          throw StateError('Permesso microfono negato.');
        }
        await _pauseTransport();
        await _player.stop();
        await _midiPlayer.stop();
        await _notePlayer.stop();
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
    final detected = await compute(WavTranscriber.transcribe, bytes);
    await _midiPlayer.stop();
    if (detected.isNotEmpty) {
      final rendered = await compute(MidiEngine.renderWav, detected);
      final dir = await getApplicationDocumentsDirectory();
      final midiPreview = File('${dir.path}/ampyscore_midi_preview.wav');
      await midiPreview.writeAsBytes(rendered, flush: true);
      await _midiPlayer.setFilePath(midiPreview.path);
      await _midiPlayer.setVolume(_midiVolume);
    }
    await _player.seek(Duration.zero);
    if (mounted) {
      setState(() {
        _notes = detected;
        _assistantAnswer = null;
        _midiReady = detected.isNotEmpty;
        _cursor = Duration.zero;
        _activeIndex = -1;
        _status = detected.isEmpty
            ? 'Non ho trovato note abbastanza chiare: prova una melodia singola.'
            : 'Rilevate ${detected.length} note (analisi locale, primi 40 s). '
              'Puoi ascoltare il MIDI e confrontarlo con il brano.';
      });
    }
  }

  Future<void> _analyse() => _execute(_analyseInternal);

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

  Future<void> _exportMidi() => _execute(() async {
        if (_notes.isEmpty) return;
        final bytes = MidiEngine.exportMidi(_notes);
        final output = await FilePicker.saveFile(
          dialogTitle: 'Esporta la trascrizione MIDI',
          fileName: 'AmpyScore_trascrizione.mid',
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
              child: Text('v0.2', style: TextStyle(color: Color(0xFF9DAABA))),
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
              'Registrazione, prova musicale e note monofoniche offline.',
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
              title: 'Anteprima pentagramma',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StaffPreview(
                    notes: _notes,
                    activeIndex: _activeIndex,
                    onNoteTap: (index) {
                      unawaited(_playOneNote(index));
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Riconoscimento sperimentale: una nota alla volta. '
                    'Durate approssimate, nessuna separazione strumenti.',
                    style: TextStyle(fontSize: 12,
                        color: Color(0xFF9DAABA)),
                  ),
                  if (_notes.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('Tocca una nota per ascoltarla da sola:',
                        style: TextStyle(color: Color(0xFFAFBDCA))),
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
                            label: Text('${index + 1} · ${note.label}'),
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

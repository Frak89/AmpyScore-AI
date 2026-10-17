import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'audio/staff_painter.dart';
import 'audio/wav_engine.dart';
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

class StudioPage extends StatefulWidget {
  const StudioPage({super.key});

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _apiKey = TextEditingController();
  StreamSubscription<PlayerState>? _playerEvents;

  List<DetectedNote> _notes = const [];
  String? _trackPath;
  String _trackName = 'Nessuna traccia';
  String _status = 'Pronto per una registrazione o un file WAV.';
  String? _assistantAnswer;
  bool _recording = false;
  bool _busy = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _playerEvents = _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() => _playing = state.playing &&
            state.processingState != ProcessingState.completed);
      }
    });
  }

  @override
  void dispose() {
    _playerEvents?.cancel();
    _apiKey.dispose();
    _recorder.dispose();
    _player.dispose();
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
    await _player.stop();
    await _player.setFilePath(path);
    if (!mounted) return;
    setState(() {
      _trackPath = path;
      _trackName = name;
      _notes = const [];
      _assistantAnswer = null;
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
        await _player.stop();
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
    if (mounted) {
      setState(() {
        _notes = detected;
        _assistantAnswer = null;
        _status = detected.isEmpty
            ? 'Non ho trovato note abbastanza chiare: prova una melodia singola.'
            : 'Rilevate ${detected.length} note (analisi locale, primi 40 s).';
      });
    }
  }

  Future<void> _analyse() => _execute(_analyseInternal);

  Future<void> _togglePlayback() async {
    try {
      if (_trackPath == null) return;
      if (_playing) {
        await _player.pause();
      } else {
        if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        unawaited(_player.play());
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'Riproduzione: $error');
    }
  }

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
              child: Text('v0.1', style: TextStyle(color: Color(0xFF9DAABA))),
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
                      onPressed: canPlay ? _togglePlayback : null,
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                      label: Text(_playing ? 'Pausa' : 'Riproduci'),
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
              icon: Icons.queue_music,
              title: 'Anteprima pentagramma',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StaffPreview(notes: _notes),
                  const SizedBox(height: 8),
                  const Text(
                    'Riconoscimento sperimentale: una nota alla volta. '
                    'Durate approssimate, nessuna separazione strumenti.',
                    style: TextStyle(fontSize: 12,
                        color: Color(0xFF9DAABA)),
                  ),
                  if (_notes.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      _notes.take(25).map((n) => n.label).join('  ·  '),
                      style: const TextStyle(fontSize: 15,
                          fontWeight: FontWeight.w600),
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

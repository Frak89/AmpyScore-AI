import 'package:ampy_score_ai/services/ai_stem_session.dart';
import 'package:ampy_score_ai/audio/multitrack_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture() => {
  'format': 'ampyscore-ai-session',
  'version': 1,
  'title': 'Quartet sample',
  'original': 'original/song.mp3',
  'instrumental': 'stems/instrumental.wav',
  'bpm': 170,
  'beatsPerBar': 5,
  'durationSeconds': 68.5,
  'tracks': [
    {
      'id': 'vocals',
      'label': 'Voce (Demucs + Basic Pitch)',
      'audio': 'stems/vocals.wav',
      'gmProgram': 53,
      'confidence': .55,
      'notes': [
        {'midi': 69, 'start': .2, 'end': .6, 'confidence': .85},
        {'midi': 71, 'start': .8, 'end': 1.1, 'confidence': .76},
      ],
    },
    {
      'id': 'bass',
      'label': 'Basso separato',
      'audio': 'stems/bass.wav',
      'gmProgram': 32,
      'confidence': .61,
      'notes': [
        {'midi': 45, 'start': 0, 'end': .6, 'confidence': .70},
      ],
    },
    {
      'id': 'drums',
      'label': 'Batteria separata',
      'audio': 'stems/drums.wav',
      'gmProgram': 0,
      'confidence': .25,
      'notes': [],
    },
    {
      'id': 'other',
      'label': 'Altri strumenti',
      'audio': 'stems/other.wav',
      'gmProgram': 0,
      'confidence': .44,
      'notes': [],
    },
  ],
};

void main() {
  test('AI project reconstructs authentic four source lanes and meter', () {
    final session = AiStemSession.fromManifest(fixture(), '/data/session');
    expect(session.bpm, 170);
    expect(session.beatsPerBar, 5);
    expect(session.parts.length, 4);
    expect(session.parts.first.family, InstrumentFamily.melody);
    expect(session.parts.first.name, 'Voce (Demucs + Basic Pitch)');
    expect(session.parts.first.notes.length, 2);
    expect(session.parts[1].programOverride, 32);
    expect(session.stems[InstrumentFamily.drums],
        '/data/session/stems/drums.wav');
    expect(session.instrumentalPath,
        '/data/session/stems/instrumental.wav');
  });

  test('Archive path validation prevents traversal and absolute paths', () {
    for (final unsafe in [
      '../private.txt', 'stems/../vocals.wav', '/tmp/file',
      'C:/data/file', 'stems\\evil.wav', './manifest.json',
      'stems/.hidden', '', 'stems//vocals.wav',
    ]) {
      expect(AiStemSession.safePath(unsafe), isFalse, reason: unsafe);
    }
    expect(AiStemSession.safePath('stems/vocals.wav'), isTrue);
  });

  test('Invalid manifest and repeated real instrument source rejected', () {
    final wrong = fixture()..['version'] = 99;
    expect(() => AiStemSession.fromManifest(wrong, '/temp'),
        throwsFormatException);

    final duplicated = fixture();
    final tracks = List<Map<String, dynamic>>.from(
        (duplicated['tracks'] as List).cast<Map<String, dynamic>>());
    tracks.add(Map<String, dynamic>.from(tracks.first));
    duplicated['tracks'] = tracks;
    expect(() => AiStemSession.fromManifest(duplicated, '/temp'),
        throwsFormatException);
  });

  test('Out-of-range pitches and note timestamps are dropped', () {
    final raw = fixture();
    final tracks = (raw['tracks'] as List).cast<Map<String, dynamic>>();
    final first = tracks.first;
    first['notes'] = [
      {'midi': 69, 'start': .2, 'end': .5, 'confidence': .8},
      {'midi': 170, 'start': .2, 'end': .4, 'confidence': .8},
      {'midi': 61, 'start': 70, 'end': 71, 'confidence': .8},
      {'midi': 61, 'start': 2, 'end': 1, 'confidence': .8},
    ];
    final session = AiStemSession.fromManifest(raw, '/temp');
    expect(session.parts.first.notes.length, 1);
    expect(session.parts.first.notes.first.midi, 69);
  });
}

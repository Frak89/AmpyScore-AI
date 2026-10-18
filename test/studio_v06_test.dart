import 'package:flutter_test/flutter_test.dart';
import 'package:ampy_score_ai/audio/metronome_synth.dart';
import 'package:ampy_score_ai/audio/multitrack_engine.dart';
import 'package:ampy_score_ai/audio/wav_engine.dart';
import 'package:ampy_score_ai/score/score_engine.dart';
import 'package:ampy_score_ai/score/note_lab.dart';
import 'package:ampy_score_ai/services/song_lookup.dart';

void main() {
  test('Metronome accent WAV aligns with 120 BPM beats', () {
    final data = MetronomeSynth.render(const MetronomeSettings(
      bpm: 120, subdivisions: 2, durationSeconds: 2.25,
    ));
    final decoded = WavAudio.decode(data);
    expect(decoded.samples.length, greaterThan(15000));
    expect(decoded.samples.take(2000).any((x) => x.abs() > .05), isTrue);
    // A click occurs on the 0.5s quarter beat and on the 0.25s eighth.
    final sampleAtQuarter = (0.5 * decoded.sampleRate).round();
    expect(
      decoded.samples.skip(sampleAtQuarter).take(80)
          .any((x) => x.abs() > .05),
      isTrue,
    );
  });

  test('NoteLab values 1/32 through 4/1 and rest cycle', () {
    expect(NoteLab.durations.keys.toList(),
        [1, 2, 4, 8, 16, 32, 64, 128]);
    final score = ScoreProject.fromTranscription([
      InstrumentPart(family: InstrumentFamily.melody, confidence: .7,
          notes: [const DetectedNote(midi: 60, startSeconds: 0,
              endSeconds: .5, confidence: .8)]),
    ], 120);
    final n = score.notes.single;
    n.length = NoteLab.durations.keys.first;
    expect(n.length, 1);
    n.length = NoteLab.durations.keys.last;
    expect(score.barCount, 4);
    expect(score.deleteOrRest(n.id), isTrue);
    expect(n.isRest, isTrue);
    expect(score.deleteOrRest(n.id), isTrue);
    expect(score.notes, isEmpty);
  });

  test('MusicXML groups short consecutive notes with beams', () {
    final notes = <DetectedNote>[
      for (var i = 0; i < 4; i++)
        DetectedNote(
          midi: 60 + i,
          startSeconds: i * .25,
          endSeconds: (i + 1) * .25,
          confidence: .8,
        ),
    ];
    final score = ScoreProject.fromTranscription([
      InstrumentPart(family: InstrumentFamily.melody,
          confidence: .7, notes: notes),
    ], 120);
    final xml = MusicXmlWriter.export(score);
    expect(xml, contains('<beam number="1">begin</beam>'));
    expect(xml, contains('<beam number="1">end</beam>'));
    expect(xml, isNot(contains('<tie type="start"/>')));
  });

  test('Online song query starts from file title, never audio', () {
    expect(SongLookup.filenameTitle('My Song.mp3'), 'My Song');
    expect(SongLookup.filenameTitle('recording.wav'), isNull);
  });
}

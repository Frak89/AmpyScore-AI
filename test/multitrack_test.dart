import 'package:ampy_score_ai/audio/multitrack_engine.dart';
import 'package:ampy_score_ai/audio/multitrack_midi.dart';
import 'package:ampy_score_ai/audio/rhythm_engine.dart';
import 'package:ampy_score_ai/audio/wav_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parts = [
    InstrumentPart(
      family: InstrumentFamily.bass,
      confidence: 0.5,
      notes: [
        const DetectedNote(midi: 48, startSeconds: 0, endSeconds: 1, confidence: 0.6),
      ],
    ),
    InstrumentPart(
      family: InstrumentFamily.harmony,
      confidence: 0.4,
      notes: [
        const DetectedNote(midi: 60, startSeconds: 0, endSeconds: .5, confidence: 0.4),
        const DetectedNote(midi: 62, startSeconds: .5, endSeconds: 1, confidence: 0.4),
        const DetectedNote(midi: 64, startSeconds: 1, endSeconds: 1.5, confidence: 0.4),
        const DetectedNote(midi: 65, startSeconds: 1.5, endSeconds: 2, confidence: 0.4),
      ],
    ),
  ];

  test('Real MIDI format 1 has multiple tracks and channels', () {
    final file = MultiTrackMidi.export(parts, bpm: 120);
    expect(String.fromCharCodes(file.sublist(0, 4)), 'MThd');
    expect(file.sublist(8, 12), [0, 1, 0, 3]); // Type 1; tempo + 2 voices
    expect(file.contains(0x91), isTrue); // Note on channel 2 (bass).
    expect(file.contains(0x92), isTrue); // Note on channel 3 (harmony).
  });

  test('Offline mixed preview decodes and can mute bass', () {
    final both = WavAudio.decode(MultiTrackMidi.renderMix(
      TrackMix(parts, {InstrumentFamily.bass: 1, InstrumentFamily.harmony: 1}),
    ));
    final withoutBass = WavAudio.decode(MultiTrackMidi.renderMix(
      TrackMix(parts, {InstrumentFamily.bass: 0, InstrumentFamily.harmony: 1}),
    ));
    expect(both.samples.length, withoutBass.samples.length);
    final at = 2800;
    expect(both.samples[at], isNot(equals(withoutBass.samples[at])));
  });

  test('Pitch-note durations are labelled in quarters eighths sixteenths halves', () {
    const rhythm = RhythmReport(bpm: 120, confidence: 1, values: {});
    DetectedNote n(double duration) => DetectedNote(
      midi: 60, startSeconds: 0, endSeconds: duration, confidence: 1);
    expect(rhythm.valueFor(n(1)).label, '1/2');
    expect(rhythm.valueFor(n(.5)).label, '1/4');
    expect(rhythm.valueFor(n(.25)).label, '1/8');
    expect(rhythm.valueFor(n(.125)).label, '1/16');
  });

  test('BPM estimator derives rough pulse from half-second note onsets', () {
    final rhythm = RhythmAnalyzer.estimate(parts);
    expect(rhythm.bpm, inInclusiveRange(55, 190));
    expect(rhythm.confidence, greaterThan(0));
  });

  test('Demo WAV has overlapping frequencies', () {
    final file = MultiInstrumentDemo.create();
    final audio = WavAudio.decode(file);
    expect(audio.samples.length, greaterThan(10000));
    final result = MultiTrackAnalyzer.analyze(file);
    expect(result.durationSeconds, greaterThan(6));
    expect(result.parts, isNotEmpty);
  });
}

import 'package:ampy_score_ai/audio/midi_engine.dart';
import 'package:ampy_score_ai/audio/wav_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final melody = [
    const DetectedNote(midi: 60, startSeconds: 0, endSeconds: 0.5, confidence: 0.9),
    const DetectedNote(midi: 64, startSeconds: 0.6, endSeconds: 1.0, confidence: 0.9),
  ];

  test('Generated MIDI uses standard header and one valid track', () {
    final midi = MidiEngine.exportMidi(melody);
    expect(String.fromCharCodes(midi.sublist(0, 4)), 'MThd');
    expect(midi.sublist(8, 14), [0, 0, 0, 1, 1, 0xE0]);
    expect(String.fromCharCodes(midi.sublist(14, 18)), 'MTrk');
    final trackSize = (midi[18] << 24) | (midi[19] << 16) |
        (midi[20] << 8) | midi[21];
    expect(trackSize, midi.length - 22);
    expect(midi.sublist(midi.length - 4), [0, 0xFF, 0x2F, 0]);
    expect(midi.contains(0x90), isTrue);
    expect(midi.contains(0x80), isTrue);
  });

  test('Synthesized MIDI preview is a decodable WAV with silence/gaps', () {
    final decoded = WavAudio.decode(MidiEngine.renderWav(melody));
    expect(decoded.sampleRate, greaterThan(7000));
    expect(decoded.samples.length, greaterThan(7000));
    expect(decoded.samples.every((value) => value.abs() <= 1), isTrue);
    expect(decoded.samples.take(100).any((value) => value != 0), isTrue);
  });

  test('Single note generates locally playable sound', () {
    expect(WavAudio.decode(MidiEngine.renderOneNote(69)).samples, isNotEmpty);
  });

  test('MIDI event delta survives pauses longer than 127 ticks', () {
    final midi = MidiEngine.exportMidi(melody);
    expect(midi.contains(0x83), isTrue); // 0.5 s = 480 ticks, VLQ 0x83 0x60
  });
}

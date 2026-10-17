import 'package:ampy_score_ai/audio/wav_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WAV demo is valid and transcribes at least the expected melody', () {
    final wav = DemoWav.create();
    final decoded = WavAudio.decode(wav);
    expect(decoded.sampleRate, greaterThan(7000));
    expect(decoded.samples, isNotEmpty);
    final notes = WavTranscriber.transcribe(wav);
    expect(notes, isNotEmpty);
    expect(notes.any((n) => n.midi == 60), isTrue);
    expect(notes.any((n) => n.midi == 67), isTrue);
  });

  test('Unsupported audio rejects cleanly', () {
    expect(
      () => WavAudio.decode(DemoWav.create().sublist(0, 16)),
      throwsFormatException,
    );
  });
}

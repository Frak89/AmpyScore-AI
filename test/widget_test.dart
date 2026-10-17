import 'package:ampy_score_ai/audio/wav_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Italian note names are generated correctly', () {
    final notes = WavTranscriber.transcribe(DemoWav.create());
    expect(notes.first.label, 'Do4');
    expect(notes.any((note) => note.label == 'Sol4'), isTrue);
  });
}

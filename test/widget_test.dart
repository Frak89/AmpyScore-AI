import 'package:ampy_score_ai/audio/wav_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Italian pitch labels after demo transcription', () {
    final notes = WavTranscriber.transcribe(DemoWav.create());
    expect(notes, isNotEmpty);
    expect(notes.first.label, 'Do4');
    expect(notes.any((note) => note.label == 'Sol4'), isTrue);
  });
}

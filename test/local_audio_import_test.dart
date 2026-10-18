import 'package:ampy_score_ai/services/local_audio_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Common compressed and lossless audio extensions accepted', () {
    for (final file in [
      'track.mp3', 'track.M4A', 'audio.aac', 'orchestra.flac',
      'concert.ogg', 'voice.opus', 'sample.wav', 'master.aiff',
      'sample.caf',
    ]) {
      expect(LocalAudioImport.isSupported(file), isTrue, reason: file);
    }
  });

  test('Non audio and remote URLs rejected', () {
    for (final file in ['track.exe', 'x.pdf', 'noextension', 'https://x']) {
      expect(LocalAudioImport.isSupported(file), isFalse, reason: file);
    }
  });

  test('Analysis size bounds remain finite for offline phones', () {
    expect(LocalAudioImport.maxDecodedBytes, lessThan(64 * 1024 * 1024));
  });
}

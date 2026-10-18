import 'package:flutter_test/flutter_test.dart';
import 'package:ampy_score_ai/audio/playback_tuning.dart';

void main() {
  test('Continuous audio speed clamps to quarter through quadruple', () {
    expect(PlaybackTuning.speed(0.1), 0.25);
    expect(PlaybackTuning.speed(0.25), 0.25);
    expect(PlaybackTuning.speed(.75), .75);
    expect(PlaybackTuning.speed(1), 1);
    expect(PlaybackTuning.speed(2.8), 2.8);
    expect(PlaybackTuning.speed(4), 4);
    expect(PlaybackTuning.speed(7), 4);
    expect(PlaybackTuning.speed(double.nan), 1);
  });

  test('Audio speed labels show fractional and reset values', () {
    expect(PlaybackTuning.speedLabel(.25), '0.25×');
    expect(PlaybackTuning.speedLabel(1), '1×');
    expect(PlaybackTuning.speedLabel(1.5), '1.5×');
    expect(PlaybackTuning.speedLabel(4), '4×');
  });

  test('SoundFont buffer and output sample rate stay in safe presets', () {
    expect(PlaybackTuning.bufferFrames,
        [128, 256, 512, 1024, 2048]);
    expect(PlaybackTuning.supportsBuffer(512), isTrue);
    expect(PlaybackTuning.supportsBuffer(384), isFalse);
    expect(PlaybackTuning.supportsSampleRate(44100), isTrue);
    expect(PlaybackTuning.supportsSampleRate(48000), isTrue);
    expect(PlaybackTuning.supportsSampleRate(16000), isFalse);
    expect(PlaybackTuning.nominalMilliseconds(512, 44100),
        closeTo(11.61, .05));
    expect(PlaybackTuning.nominalMilliseconds(2048, 48000),
        closeTo(42.67, .05));
  });
}

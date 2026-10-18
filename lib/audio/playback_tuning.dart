/// Shared transport configuration, tested independently of native audio.
class PlaybackTuning {
  static const double minSpeed = 0.25;
  static const double maxSpeed = 4.0;
  static const double normalSpeed = 1.0;

  static const List<int> bufferFrames = [128, 256, 512, 1024, 2048];
  static const List<int> sampleRates = [44100, 48000];
  static const int defaultBufferFrames = 512;
  static const int defaultSampleRate = 44100;

  static double speed(double proposed) =>
      proposed.isFinite ? proposed.clamp(minSpeed, maxSpeed).toDouble() : normalSpeed;

  static String speedLabel(double speed) {
    final fixed = speed.toStringAsFixed(2);
    return '${fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\\.$'), '')}×';
  }

  static bool supportsBuffer(int value) => bufferFrames.contains(value);
  static bool supportsSampleRate(int value) => sampleRates.contains(value);

  /// Purely theoretical frames / sample rate; device output mixer adds latency.
  static double nominalMilliseconds(int buffer, int rate) =>
      1000.0 * buffer / rate;
}

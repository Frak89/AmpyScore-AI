import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Random-access PCM-WAV window reader. Keeps long recordings on disk;
/// each FFT worker receives <= 19 seconds, never the entire song.
class WavWindowReader {
  WavWindowReader._(this.file, this.sampleRate, this.channels,
      this.dataStart, this.frameCount);

  final File file;
  final int sampleRate;
  final int channels;
  final int dataStart;
  final int frameCount;

  double get durationSeconds => frameCount / sampleRate;

  static Future<WavWindowReader> open(File file) async {
    final handle = await file.open();
    try {
      final size = await handle.length();
      if (size < 44) throw const FormatException('WAV incompleto.');
      final head = await handle.read(math.min(131072, size));
      if (head.length < 44 ||
          String.fromCharCodes(head.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(head.sublist(8, 12)) != 'WAVE') {
        throw const FormatException('Serve WAV PCM RIFF.');
      }
      final view = ByteData.sublistView(Uint8List.fromList(head));
      int? rate, channels, bitDepth, audioFormat, dataStart, dataSize;
      var offset = 12;
      while (offset + 8 <= head.length) {
        final tag = String.fromCharCodes(head.sublist(offset, offset + 4));
        final len = view.getUint32(offset + 4, Endian.little);
        final position = offset + 8;
        if (tag == 'fmt ' && len >= 16 && position + 16 <= head.length) {
          audioFormat = view.getUint16(position, Endian.little);
          channels = view.getUint16(position + 2, Endian.little);
          rate = view.getUint32(position + 4, Endian.little);
          bitDepth = view.getUint16(position + 14, Endian.little);
        }
        if (tag == 'data') {
          dataStart = position;
          dataSize = math.min(len, math.max(0, size - position));
          break;
        }
        offset = position + len + (len.isOdd ? 1 : 0);
      }
      if (rate == null || rate < 4000 || rate > 192000 ||
          (channels != 1 && channels != 2) ||
          audioFormat != 1 || bitDepth != 16 ||
          dataStart == null || dataSize == null) {
        throw const FormatException('Serve WAV PCM 16-bit mono/stereo.');
      }
      return WavWindowReader._(
        file, rate, channels!, dataStart, dataSize ~/ (channels * 2));
    } finally {
      await handle.close();
    }
  }

  /// 16-bit mono/stereo WAV byte window with timestamps supplied by caller.
  Future<Uint8List> window(double from, double duration) async {
    final frameStart = ((from * sampleRate).floor())
        .clamp(0, frameCount);
    final frames = math.min(frameCount - frameStart,
        (duration * sampleRate).ceil());
    final byteCount = frames * channels * 2;
    final handle = await file.open();
    late final Uint8List pcm;
    try {
      await handle.setPosition(dataStart + frameStart * channels * 2);
      pcm = Uint8List.fromList(await handle.read(byteCount));
    } finally {
      await handle.close();
    }
    if (pcm.isEmpty) return Uint8List(0);
    final wav = Uint8List(44 + pcm.length);
    final view = ByteData.sublistView(wav);
    void mark(int start, String word) {
      for (var i = 0; i < word.length; i++) {
        wav[start + i] = word.codeUnitAt(i);
      }
    }
    mark(0, 'RIFF'); mark(8, 'WAVE'); mark(12, 'fmt '); mark(36, 'data');
    view.setUint32(4, wav.length - 8, Endian.little);
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, channels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * channels * 2, Endian.little);
    view.setUint16(32, channels * 2, Endian.little);
    view.setUint16(34, 16, Endian.little);
    view.setUint32(40, pcm.length, Endian.little);
    wav.setRange(44, wav.length, pcm);
    return wav;
  }
}

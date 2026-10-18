import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'wav_window_reader.dart';
import 'stem_extractor.dart';

/// Chunked export of equalizer bands. Never materializes a full length WAV
/// in memory. This is FREQUENCY FOCUS, not isolation of instrument stems.
class BandFocusRenderer {
  static Future<void> export(
    WavWindowReader reader,
    File file,
    FocusStem stem, {
    void Function(double)? progress,
  }) async {
    final writer = await file.open(mode: FileMode.write);
    var bytesWritten = 0;
    var sampleRate = 0;
    try {
      await writer.writeFrom(Uint8List(44));
      const chunkSeconds = 3.0;
      for (var start = 0.0; start < reader.durationSeconds; start += chunkSeconds) {
        final dur = math.min(chunkSeconds, reader.durationSeconds - start);
        // Use a short look-behind/look-ahead for the IIR band filters,
        // then trim it so there is no artificial reset click every 3s.
        const padding = .2;
        final from = math.max(0.0, start - padding);
        final until = math.min(reader.durationSeconds,
            start + dur + padding);
        final data = await reader.window(from, until - from);
        if (data.isEmpty) break;
        final wave = await compute(
          StemExtractor.focus, StemRequest(data, stem));
        final view = ByteData.sublistView(wave);
        sampleRate = view.getUint32(24, Endian.little);
        final skip = ((start - from) * sampleRate).round();
        final length = (dur * sampleRate).round();
        final first = math.min(wave.length, 44 + skip * 2);
        final last = math.min(wave.length, first + length * 2);
        await writer.writeFrom(wave, first, last);
        bytesWritten += last - first;
        progress?.call(math.min(1.0, (start + dur) / reader.durationSeconds));
      }
      if (sampleRate == 0) throw const FormatException('WAV non disponibile');
      final header = Uint8List(44);
      final view = ByteData.sublistView(header);
      void tag(int start, String name) {
        for (var i = 0; i < name.length; i++) {
          header[start + i] = name.codeUnitAt(i);
        }
      }
      tag(0, 'RIFF'); tag(8, 'WAVE'); tag(12, 'fmt '); tag(36, 'data');
      view.setUint32(4, bytesWritten + 36, Endian.little);
      view.setUint32(16, 16, Endian.little);
      view.setUint16(20, 1, Endian.little);
      view.setUint16(22, 1, Endian.little);
      view.setUint32(24, sampleRate, Endian.little);
      view.setUint32(28, sampleRate * 2, Endian.little);
      view.setUint16(32, 2, Endian.little);
      view.setUint16(34, 16, Endian.little);
      view.setUint32(40, bytesWritten, Endian.little);
      await writer.setPosition(0);
      await writer.writeFrom(header);
      await writer.flush();
    } finally {
      await writer.close();
    }
  }
}

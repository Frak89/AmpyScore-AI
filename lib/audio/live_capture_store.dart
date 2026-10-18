import 'dart:io';
import 'dart:typed_data';

/// A durable PCM microphone capture that is readable while recording.
///
/// AudioRecord gives PCM16 LE with no WAV header; a valid RIFF header is
/// maintained on disk so the existing bounded WAV analyzer can process
/// completed windows while capture continues. Only a few bytes are held in
/// memory at once, and the original capture is retained for Studio analysis.
class LiveCaptureStore {
  LiveCaptureStore._(this.file, this.sampleRate, this._handle);

  final File file;
  final int sampleRate;
  final RandomAccessFile _handle;
  int _pcmLength = 0;
  bool _closed = false;
  int? _pendingByte;

  static Future<LiveCaptureStore> open(File file,
      {int sampleRate = 16000}) async {
    if (sampleRate < 8000 || sampleRate > 48000) {
      throw const FormatException('Campionamento non valido.');
    }
    final handle = await file.open(mode: FileMode.write);
    final store = LiveCaptureStore._(file, sampleRate, handle);
    await handle.writeFrom(Uint8List(44));
    return store;
  }

  double get durationSeconds => _pcmLength / (2.0 * sampleRate);
  int get frames => _pcmLength ~/ 2;
  bool get closed => _closed;

  Future<void> append(Uint8List incoming) async {
    if (_closed) throw StateError('Registrazione già terminata.');
    if (incoming.isEmpty) return;
    var bytes = incoming;
    if (_pendingByte case final pending?) {
      final merged = Uint8List(incoming.length + 1);
      merged[0] = pending;
      merged.setRange(1, merged.length, incoming);
      bytes = merged;
      _pendingByte = null;
    }
    if (bytes.length.isOdd) {
      _pendingByte = bytes.last;
      bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
    }
    if (bytes.isEmpty) return;
    // RIFF32 cannot exceed 4GB. Reject before corrupting stored audio.
    if (_pcmLength + bytes.length > 0xFFFFFF00) {
      throw const FormatException('Registrazione oltre il limite WAV.');
    }
    await _handle.writeFrom(bytes);
    _pcmLength += bytes.length;
  }

  Future<double> snapshot() async {
    if (_closed) return durationSeconds;
    await _writeHeader();
    await _handle.flush();
    return durationSeconds;
  }

  Future<File> finish() async {
    if (_closed) return file;
    await _writeHeader();
    await _handle.flush();
    await _handle.close();
    _closed = true;
    return file;
  }

  Future<void> _writeHeader() async {
    final bytes = Uint8List(44);
    final view = ByteData.sublistView(bytes);
    void mark(int index, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes[index + i] = value.codeUnitAt(i);
      }
    }
    mark(0, 'RIFF');
    view.setUint32(4, 36 + _pcmLength, Endian.little);
    mark(8, 'WAVE');
    mark(12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, 1, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * 2, Endian.little);
    view.setUint16(32, 2, Endian.little);
    view.setUint16(34, 16, Endian.little);
    mark(36, 'data');
    view.setUint32(40, _pcmLength, Endian.little);
    await _handle.setPosition(0);
    await _handle.writeFrom(bytes);
    await _handle.setPosition(44 + _pcmLength);
  }
}

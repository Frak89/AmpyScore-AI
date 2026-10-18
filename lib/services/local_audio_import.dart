import 'dart:io';
import 'package:audio_decoder/audio_decoder.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../audio/wav_engine.dart';
import '../audio/wav_window_reader.dart';

class LocalAudioFile {
  const LocalAudioFile({
    required this.playbackPath,
    required this.analysisWavPath,
    required this.displayName,
  });

  final String playbackPath;
  final String analysisWavPath;
  final String displayName;
}

/// File import is local-only: system codecs decode compressed audio,
/// no cloud conversion, web services or upload.
class LocalAudioImport {
  static const acceptedExtensions = <String>[
    'wav', 'mp3', 'm4a', 'aac', 'flac', 'ogg', 'opus',
    'aiff', 'aif', 'caf', 'wma', 'alac', 'webm', 'mp4',
  ];
  static const maxInputBytes = 512 * 1024 * 1024;
  static const maxDecodedBytes = 1024 * 1024 * 1024;

  static bool isSupported(String name) {
    final i = name.lastIndexOf('.');
    if (i <= 0) return false;
    return acceptedExtensions.contains(name.substring(i + 1).toLowerCase());
  }

  static Future<LocalAudioFile> import(PlatformFile selected) async {
    if (!isSupported(selected.name)) {
      throw const FormatException('Formato audio non riconosciuto.');
    }
    if ((selected.lengthSync() ?? await selected.length() ?? 0) > maxInputBytes) {
      throw const FormatException('File oltre 512 MB; limite di importazione.');
    }

    final dir = await getApplicationDocumentsDirectory();
    final prefix = 'brano_${DateTime.now().microsecondsSinceEpoch}';
    final suffix = selected.name.substring(selected.name.lastIndexOf('.')).toLowerCase();
    final copied = File('${dir.path}/$prefix$suffix');
    if (selected.path case final String sourcePath) {
      if (sourcePath.isNotEmpty && await File(sourcePath).exists()) {
        await File(sourcePath).copy(copied.path);
      } else {
        await copied.writeAsBytes(await selected.readAsBytes(), flush: true);
      }
    } else {
      await copied.writeAsBytes(await selected.readAsBytes(), flush: true);
    }
    if (await copied.length() > maxInputBytes) {
      await copied.delete();
      throw const FormatException('File troppo grande.');
    }

    final wav = File('${dir.path}/${prefix}_analysis.wav');
    try {
      // Keep native 16-bit RIFF WAV as-is if it is compatible. Conversion
      // handles 24/32-bit/float WAV as well as MP3/M4A/AAC/FLAC/etc.
      if (suffix == '.wav' && await copied.length() <= maxDecodedBytes) {
        try {
          WavAudio.decode(await copied.readAsBytes());
          return LocalAudioFile(
            playbackPath: copied.path,
            analysisWavPath: copied.path,
            displayName: selected.name,
          );
        } on FormatException {
          // Native transcoding below.
        }
      }
      await AudioDecoder.convertToWav(
        copied.path,
        wav.path,
        sampleRate: 16000,
        channels: 1,
        bitDepth: 16,
      );
      if (!await wav.exists() || await wav.length() < 44 ||
          await wav.length() > maxDecodedBytes) {
        throw const FormatException(
          'Audio decodificato troppo grande o non valido.',
        );
      }
      // Validate only the header in the random-access window reader;
      // decoding the full WAV into Dart memory would crash on long songs.
      await WavWindowReader.open(wav);
      return LocalAudioFile(
        playbackPath: copied.path,
        analysisWavPath: wav.path,
        displayName: selected.name,
      );
    } catch (_) {
      if (await wav.exists()) await wav.delete();
      // Preserve original import only when analysis succeeded.
      if (await copied.exists()) await copied.delete();
      rethrow;
    }
  }

  static Future<LocalAudioFile?> pickAndConvert() async {
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: acceptedExtensions,
    );
    if (selected == null) return null;
    return import(selected);
  }
}

import 'dart:math' as math;
import '../audio/multitrack_engine.dart';

class InstrumentGuess {
  const InstrumentGuess(this.program, this.name, this.reason);
  final int program;
  final String name;
  final String reason;
}

/// Audible GM program recommendation based on note duration/register.
/// THIS IS NOT timbre recognition or an ML instrument classifier.
class InstrumentHeuristics {
  static InstrumentGuess suggest(InstrumentPart part) {
    if (part.percussion) {
      return const InstrumentGuess(0, 'Percussioni GM',
          'Attacchi broadband (provvisori)');
    }
    final notes = part.notes;
    if (notes.isEmpty) {
      return const InstrumentGuess(0, 'Pianoforte', 'Nessuna nota');
    }
    final seconds = notes.fold<double>(0,
        (sum, n) => sum + (n.endSeconds - n.startSeconds));
    final average = seconds / notes.length;
    final meanPitch = notes.fold<double>(0,
        (sum, n) => sum + n.midi) / notes.length;
    switch (part.family) {
      case InstrumentFamily.bass:
        return average < .25
          ? const InstrumentGuess(33, 'Basso elettrico',
              'Articolazione breve nel registro basso')
          : const InstrumentGuess(32, 'Contrabbasso',
              'Articolazione sostenuta nel registro basso');
      case InstrumentFamily.harmony:
        return average > 1.0
          ? const InstrumentGuess(48, 'Archi',
              'Note armoniche sostenute (ipotesi)')
          : const InstrumentGuess(0, 'Pianoforte',
              'Accordi e note medie (ipotesi)');
      case InstrumentFamily.melody:
        if (meanPitch > 79 && average > .45) {
          return const InstrumentGuess(73, 'Flauto',
              'Registro molto acuto e note sostenute (ipotesi)');
        }
        if (average < .15 && meanPitch < 75) {
          return const InstrumentGuess(56, 'Tromba',
              'Attacchi brevi della linea melodica (ipotesi)');
        }
        return const InstrumentGuess(65, 'Sax contralto',
            'Suono melodico medio-acuto (ipotesi)');
      case InstrumentFamily.drums:
        return const InstrumentGuess(0, 'Percussioni GM', 'Transienti');
    }
  }

  static double level(InstrumentPart part) =>
      (0.25 + 0.65 * math.sqrt(part.signalLevel.clamp(0.0, 1.0)))
          .clamp(.25, .95);
}

import 'package:flutter/material.dart';
import '../audio/multitrack_engine.dart';
import 'score_engine.dart';

/// Edits score ticks directly; one sixteenth = one tick.
/// Every edit rechecks each 4/4 measure and the PDF-style preview.
class NoteLab extends StatelessWidget {
  const NoteLab({
    super.key,
    required this.score,
    required this.selectedFamily,
    required this.selectedNoteId,
    required this.onSelect,
    required this.onChanged,
  });

  final ScoreProject score;
  final InstrumentFamily? selectedFamily;
  final int? selectedNoteId;
  final ValueChanged<ScoreNote> onSelect;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final family = selectedFamily ??
        (score.parts.isEmpty ? null : score.parts.first.family);
    if (family == null) return const Text('Nessuna parte da modificare.');
    final events = score.forFamily(family);
    final current = events.where((n) => n.id == selectedNoteId).firstOrNull;
    final invalidMeasures = List.generate(score.barCount, (bar) => bar)
        .where((bar) => score.hasOverflow(family, bar)).toList();
    const lengths = <int, String>{
      1: '1/16', 2: '1/8', 3: '1/8 puntato',
      4: '1/4', 6: '1/4 puntato',
      8: '1/2', 12: '1/2 puntato',
      16: '1/1',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Modifica note e pause · griglia 1/16.',
          style: TextStyle(fontSize: 12, color: Color(0xFFAFBEC9)),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final n in events.take(200))
            ChoiceChip(
              label: Text('${n.label}'),
              selected: selectedNoteId == n.id,
              onSelected: (_) => onSelect(n),
            ),
        ]),
        const SizedBox(height: 8),
        if (invalidMeasures.isNotEmpty)
          Text(
            '⛔ Sovrapposizione / più di 4/4: battute '
            '${invalidMeasures.map((n) => n + 1).join(", ")}. '
            'Evidenziate in rosso sullo spartito.',
            style: const TextStyle(
                color: Color(0xFFEF7373), fontWeight: FontWeight.bold),
          )
        else
          const Text(
            '✓ Battute valide: durate e pause rispettano i 4/4.',
            style: TextStyle(color: Color(0xFF62DFC3)),
          ),
        if (current != null) ...[
          const Divider(),
          Text(
            'Nota ${current.label} · battuta '
            '${current.start ~/ ticksPerBar + 1}, '
            'semicroma ${current.start % ticksPerBar + 1}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(
              onPressed: () { current.midi = (current.midi - 1).clamp(28, 99);
                onChanged(); },
              icon: const Icon(Icons.remove), label: const Text('− 1 semitono')),
            OutlinedButton.icon(
              onPressed: () { current.midi = (current.midi + 1).clamp(28, 99);
                onChanged(); },
              icon: const Icon(Icons.add), label: const Text('+ 1 semitono')),
            OutlinedButton.icon(
              onPressed: () { current.start = (current.start - 1).clamp(0, 640);
                onChanged(); },
              icon: const Icon(Icons.chevron_left),
              label: const Text('Anticipa 1/16')),
            OutlinedButton.icon(
              onPressed: () { current.start = (current.start + 1).clamp(0, 640);
                onChanged(); },
              icon: const Icon(Icons.chevron_right),
              label: const Text('Ritarda 1/16')),
            DropdownButton<int>(
              value: lengths.containsKey(current.length) ? current.length : null,
              hint: Text('Durata: ${current.length}/16'),
              items: [
                for (final entry in lengths.entries)
                  DropdownMenuItem<int>(
                    value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) {
                if (value == null) return;
                current.length = value;
                onChanged();
              },
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () {
                // Creates a gap of 1/16 after this note in the same lane.
                for (final other in score.notes) {
                  if (other.family == family &&
                      other.start >= current.end && other.id != current.id) {
                    other.start += 1;
                  }
                }
                onChanged();
              },
              icon: const Icon(Icons.space_bar),
              label: const Text('Inserisci pausa 1/16'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                score.addNote(family, afterId: current.id);
                onChanged();
              },
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Aggiungi nota'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                score.removeNote(current.id);
                onChanged();
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Elimina nota'),
            ),
          ]),
        ] else
          FilledButton.tonalIcon(
            onPressed: () { score.addNote(family); onChanged(); },
            icon: const Icon(Icons.add),
            label: const Text('Aggiungi prima nota'),
          ),
        const SizedBox(height: 8),
        const Text(
          'Premi Aggiorna MIDI per ascoltare le modifiche.',
          style: TextStyle(fontSize: 12, color: Color(0xFFAFBEC9)),
        ),
      ],
    );
  }
}

extension on ScoreNote {
  String get label {
    const names = [
      'Do', 'Do♯', 'Re', 'Re♯', 'Mi', 'Fa', 'Fa♯',
      'Sol', 'Sol♯', 'La', 'La♯', 'Si',
    ];
    return '${names[midi % 12]}${midi ~/ 12 - 1}';
  }
}

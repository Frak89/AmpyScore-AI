import 'package:flutter/material.dart';
import '../audio/multitrack_engine.dart';
import 'score_engine.dart';

/// The staff above this toolbar is the primary editor: touch a note to edit it.
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

  static const durations = <int, String>{
    1: '1/32', 2: '1/16', 4: '1/8', 8: '1/4',
    16: '1/2', 32: '1/1', 64: '2/1', 128: '4/1',
  };

  @override
  Widget build(BuildContext context) {
    final family = selectedFamily ??
        (score.parts.isEmpty ? null : score.parts.first.family);
    if (family == null) return const SizedBox.shrink();
    final current = score.notes.where((n) => n.id == selectedNoteId).firstOrNull;
    final issues = List.generate(score.barCount, (bar) => bar)
        .where((bar) => score.hasOverflow(family, bar)).toList();
    final theme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (issues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Battute da correggere: ${issues.map((e) => e + 1).join(", ")}',
              style: const TextStyle(
                color: Color(0xFFEC7272), fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (current == null) ...[
          const Text('Tocca una nota sul pentagramma.'),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () {
              score.addNote(family);
              final newest = score.forFamily(family).last;
              onSelect(newest);
              onChanged();
            },
            icon: const Icon(Icons.add),
            label: const Text('Aggiungi nota'),
          ),
        ] else ...[
          Row(children: [
            Expanded(
              child: Text(
                current.isRest ? 'Pausa' : _label(current.midi),
                style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 20),
              ),
            ),
            Text(
              'Batt. ${current.start ~/ ticksPerBar + 1}',
              style: TextStyle(color: theme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Aggiungi',
              onPressed: () {
                score.addNote(family, afterId: current.id);
                onChanged();
              },
              icon: const Icon(Icons.add),
            ),
            IconButton.filledTonal(
              tooltip: current.isRest ? 'Rimuovi pausa e chiudi lo spazio' :
                  'Trasforma nota in pausa',
              onPressed: () {
                score.deleteOrRest(current.id);
                onChanged();
              },
              icon: Icon(current.isRest ?
                  Icons.delete_forever_outlined : Icons.delete_outline),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            IconButton.outlined(
              tooltip: '− 1 semitono',
              onPressed: current.isRest ? null : () {
                current.midi = (current.midi - 1).clamp(28, 99);
                onChanged();
              },
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            const Expanded(
              child: Center(child: Text('Altezza',
                  style: TextStyle(fontWeight: FontWeight.w600))),
            ),
            IconButton.outlined(
              tooltip: '+ 1 semitono',
              onPressed: current.isRest ? null : () {
                current.midi = (current.midi + 1).clamp(28, 99);
                onChanged();
              },
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            IconButton.outlined(
              tooltip: 'Durata precedente',
              onPressed: () {
                final options = durations.keys.toList();
                final currentIndex = _nearest(options, current.length);
                current.length = options[(currentIndex - 1)
                    .clamp(0, options.length - 1)];
                onChanged();
              },
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Center(
                child: Column(children: [
                  const Text('Durata',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text(durations[current.length] ??
                      '${current.length}/32',
                      style: const TextStyle(fontSize: 18)),
                ]),
              ),
            ),
            IconButton.outlined(
              tooltip: 'Durata successiva',
              onPressed: () {
                final options = durations.keys.toList();
                final currentIndex = _nearest(options, current.length);
                current.length = options[(currentIndex + 1)
                    .clamp(0, options.length - 1)];
                onChanged();
              },
              icon: const Icon(Icons.add),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilterChip(
              selected: current.isRest,
              showCheckmark: true,
              avatar: const Icon(Icons.horizontal_rule),
              label: const Text('Pausa'),
              onSelected: (value) {
                current.isRest = value;
                onChanged();
              },
            ),
            OutlinedButton.icon(
              onPressed: () {
                current.start = (current.start - 1).clamp(0, 9999);
                onChanged();
              },
              icon: const Icon(Icons.chevron_left),
              label: const Text('− 1/32'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                current.start = (current.start + 1).clamp(0, 9999);
                onChanged();
              },
              icon: const Icon(Icons.chevron_right),
              label: const Text('+ 1/32'),
            ),
          ]),
        ],
      ],
    );
  }

  static int _nearest(List<int> values, int value) {
    var index = 0;
    var distance = 99999;
    for (var i = 0; i < values.length; i++) {
      final d = (values[i] - value).abs();
      if (d < distance) {
        distance = d;
        index = i;
      }
    }
    return index;
  }

  static String _label(int midi) {
    const names = ['Do', 'Do♯', 'Re', 'Re♯', 'Mi', 'Fa',
      'Fa♯', 'Sol', 'Sol♯', 'La', 'La♯', 'Si'];
    return '${names[midi % 12]}${midi ~/ 12 - 1}';
  }
}

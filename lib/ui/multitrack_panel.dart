import 'package:flutter/material.dart';

import '../audio/multitrack_engine.dart';
import '../audio/rhythm_engine.dart';

/// Experimental frequency lanes. Instrument names are explicitly estimates.
class MultiTrackPanel extends StatelessWidget {
  const MultiTrackPanel({
    super.key,
    required this.parts,
    required this.rhythm,
    required this.selected,
    required this.gains,
    required this.solo,
    required this.enabled,
    required this.onSelect,
    required this.onSolo,
    required this.onListenBand,
    required this.onGain,
    required this.onGainDone,
  });

  final List<InstrumentPart> parts;
  final RhythmReport? rhythm;
  final InstrumentFamily? selected;
  final Map<InstrumentFamily, double> gains;
  final InstrumentFamily? solo;
  final bool enabled;
  final ValueChanged<InstrumentFamily> onSelect;
  final ValueChanged<InstrumentFamily> onSolo;
  final ValueChanged<InstrumentFamily> onListenBand;
  final void Function(InstrumentFamily, double) onGain;
  final VoidCallback onGainDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Riconoscimento per registro · stima sperimentale.',
          style: TextStyle(color: Color(0xFFB7C7D0), fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (parts.isEmpty)
          const Text('Carica una demo multistrumento e premi Analizza WAV.')
        else
          ...parts.map((part) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: ChoiceChip(
                        selected: selected == part.family,
                        label: Text('${part.name} · ${part.notes.length} note'),
                        onSelected: enabled
                            ? (_) => onSelect(part.family) : null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Ascolta frequenze del registro (non isolamento IA)',
                      onPressed: enabled
                          ? () => onListenBand(part.family) : null,
                      icon: const Icon(Icons.headphones),
                    ),
                    const SizedBox(width: 5),
                    OutlinedButton(
                      onPressed: enabled
                          ? () => onSolo(part.family) : null,
                      child: Text(
                        solo == part.family ? 'Ripristina' : 'Solo MIDI',
                      ),
                    ),
                  ]),
                  Row(children: [
                    Expanded(child: Slider(
                      value: (gains[part.family] ?? .9).clamp(0.0, 1.0),
                      onChanged: enabled
                          ? (value) => onGain(part.family, value) : null,
                      onChangeEnd: enabled ? (_) => onGainDone() : null,
                    )),
                    SizedBox(
                      width: 45,
                      child: Text(
                        '${((gains[part.family] ?? .9) * 100).round()}%',
                      ),
                    ),
                  ]),
                ],
              )),
        const Divider(),
        Text(
          rhythm == null
              ? 'Tempo: da analizzare'
              : 'Tempo stimato ≈ ${rhythm!.bpm} BPM'
                  ' · confidenza indicativa ${(rhythm!.confidence * 100).round()}%',
          style: const TextStyle(
              color: Color(0xFF62DFC3), fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 7),
        Text(
          'Durate rilevate: ${rhythm == null || rhythm!.values.isEmpty ? "—" :
              rhythm!.values.map((value) => value.label).join(", ")}',
        ),
        const SizedBox(height: 7),
        const Text(
          '1/16 semicroma · 1/8 croma · 1/4 semiminima · 1/2 minima. '
          'Valori approssimati in base agli attacchi rilevati. '
          'Il metro 4/4 nei MIDI esportati è un default, non una misura.',
          style: TextStyle(color: Color(0xFFB7C7D0), fontSize: 12),
        ),
      ],
    );
  }
}

# AmpyScore AI v0.3 — MIDI multitraccia e tempo stimato

Applicazione Flutter open source Android / iOS.

## v0.3: come provarla

1. Apri **Demo multistrumento** (generata sul dispositivo: basso sintetico, registro medio, registro acuto e transienti ritmici).
2. Lascia acceso **Analisi multitraccia** e premi **Analizza WAV**.
3. Leggi **Tempo stimato ≈ N BPM** e le durate ipotizzate **1/16 (semicroma), 1/8 (croma), 1/4 (semiminima), 1/2 (minima)**; appaiono solo i valori che risultano dagli eventi rilevati. La precisione non è garantita.
4. Tocca un gruppo/registro per visualizzare lo spartito di quella parte e ascoltare le singole note.
5. Regola il volume di ogni gruppo (oppure usa **Solo**); il mix MIDI locale viene rigenerato al rilascio del cursore. Il brano originale ha un volume indipendente.
6. Scegli **Solo brano**, **Solo MIDI** o **Ascolta insieme**. **Esporta .mid** produce un file MIDI tipo 1 con tracce e canali distinti.
7. Per tornare alla trascrizione monofonica YIN, spegni **Analisi multitraccia** e premi nuovamente Analizza WAV.

**Limitazioni sostanziali:** l'algoritmo in questa versione è una **euristica DSP locale per frequenze**: identifica gruppi di registri, **non riconosce il timbro o il vero strumento musicale**. Non separa audio stem e può attribuire armoniche di una sorgente a strumenti fittizi; non è un modello di IA. La precisione è molto migliore sulla demo sintetica che su registrazioni polifoniche reali. Il rilevamento del tempo è orientativo (anche possibile mezzo/doppio tempo) e il 4/4 inserito nel file MIDI è un **default**, non un riconoscimento della metrica. Il mix MIDI ha timbri sintetici approssimati; rigenerare il mix interrompe brevemente la riproduzione. Gli audio WAV importati sono limitati a PCM 16-bit, max 32 MB e analisi max 40 secondi.

## Privacy

Trascrizione, sintesi, BPM e MIDI restano offline. **ChatGPT** è la funzione online opzionale già presente in v0.1: invia solo sequenze testuali di note quando richiesta esplicitamente, richiede una chiave OpenAI e può avere costi API.

## Build

- Installare Flutter SDK.
- `flutter create --platforms=android,ios --project-name=ampy_score_ai --org=dev.ampyscore .`
- `python3 tool/configure_platforms.py` (Windows: `py -3 tool/configure_platforms.py`).
- `flutter pub get`
- `flutter test`
- `flutter build apk --debug`

GitHub Actions genera l'artefatto **ampyscore-debug-apk** per Android. La build iOS richiede macOS/Xcode. Il repository è distribuito con licenza MIT.

## Prossime tappe

Per riconoscere veri strumenti con affidabilità serve integrare **source separation e trascrizione con modelli IA offline**, ottimizzati per Android e iOS. L'attuale classificazione per registri è il prototipo da confrontare con la demo e non va confusa con questo obiettivo.

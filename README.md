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


## Versione 0.4 — Studio Score e NoteLab (funzioni sperimentali)

Questa versione rende la partitura **più compatta** e presenta **tutti i pentagrammi contemporaneamente** allineati in battute di **4/4**. La barra di lettura **verde marino** segue il tempo della canzone; battute con note sovrapposte o durate complessive superiori a 4/4 vengono marcate **in rosso**. La pagina dello spartito può essere impostata su **bianco ad alto contrasto** oppure **seppia chiaro** con inchiostro scuro. La visualizzazione imita una pagina cartacea, **non è un renderer PDF completo**.

Lo score engine:
- ricostruisce lunghezze su griglia di semicrome; include 1/2, 1/4, 1/8, 1/16, valori puntati, pause, stanghette 4/4 e note legate a cavallo di due battute;
- espone il comando **Esporta MusicXML**, compatibile in linea di principio con software di notazione per successive correzioni;
- offre **NoteLab** per modificare altezza, posizione, durata, aggiungere/cancellare note o inserire una pausa 1/16. Le modifiche aggiornano lo spartito; **Aggiorna MIDI dalle note** rigenera l'audio per confrontarlo con l'originale;
- consente di cambiare BPM e **Ritrascrivi al nuovo BPM** (l'analisi dello spettro riparte e la quantizzazione viene ricostruita; le precedenti modifiche manuali non vengono mantenute);
- per ciascun rigo visualizza un **indice di affidabilità % stimato** da punteggi interni e diagnostica temporale. **Non è una misurazione dell'accuratezza della trascrizione**, perché non esiste uno spartito di riferimento da confrontare; le etichette di strumento restano ipotesi per registro.

**Estrazione audio locale:** dal pannello **Estrazione sperimentale WAV** puoi ascoltare ed esportare filtri separati per basse, medie, alte frequenze, transienti e una **banda candidata vocale**. I filtri non eliminano le altre sorgenti nella stessa banda: **non sono una separazione affidabile degli strumenti e non estraggono una vera voce pulita**. È una funzione sperimentale verificabile mediante ascolto.

### Piano tecnico documentato

- Per vera separazione **voce / basso / batteria / altri**: studiare Demucs (MIT) e alternative più leggere convertibili in ONNX/TFLite, con test di RAM, velocità e licenza dei pesi.
- Per trascrizione polifonica di **una sorgente separata**: Basic Pitch (Apache-2.0), ottimizzazione e conversione a motore on-device, dopo verifica su segnali vocali/musicali.
- Per incisione musicale professionale: **Verovio (LGPL)** e **OpenSheetMusicDisplay (licenza del progetto da verificare per la distribuzione)** possono ricevere il MusicXML ora generato. Richiedono integrazione del renderer sul dispositivo prima di dichiarare conforme la notazione finale.
- Convalida indispensabile su audio reale con MusicXML originale: accuratezza per pitch/onset/offset, F1 del riconoscimento strumenti, WER? (non adatto), e SDR/SI-SDR degli stem. Solo così la percentuale può chiamarsi *accuratezza*.

Riferimenti:
- https://github.com/vvigot/demucs
- https://github.com/spotify/basic-pitch
- https://github.com/rism-digital/verovio
- https://github.com/opensheetmusicdisplay/opensheetmusicdisplay
- https://pub.dev/packages/onnxruntime_v2

**Avvertenze:** non sono ancora incorporati pesi IA pretrained o soundfont con licenza verificata. Le note estratte restano approssimate, specialmente su brani con strumenti sovrapposti. La qualità del display, la stampa PDF, la metrica reale diversa da 4/4 e l'accuratezza con riferimento richiedono sviluppo ulteriore. Nessun server è necessario per le nuove funzioni locali.

# AmpyScore Studio 0.7 — intera canzone, GM SoundFont, partitura sincronizzata

Applicazione Flutter gratuita e open source (MIT), elaborazione audio musicale locale. **Il motore di trascrizione non è ancora un modello AI di source separation**: i registri basso/armonia/melodia/percussioni sono stime da frequenze, perciò le note non saranno fedeli a un brano jazz polifonico complesso come *Take Five*. Non confondere qualità del sintetizzatore MIDI (timbrica) con accuratezza delle note estratte.

## Problemi corretti

- **Analisi di durata completa:** eliminata la troncatura a 40 secondi per tutti gli audio. `WavWindowReader` legge soltanto finestre PCM da 16 secondi, con sovrapposizione, mediante operazioni su file. L'analisi prosegue automaticamente fino alla fine, mostrando progresso percentuale. Un brano importato viene riprodotto dal **file originale MP3/AAC/stereo**: la conversione PCM mono è solo per il riconoscimento note. Nei telefoni con codec non supportato resta un fallback WAV, qualitativamente peggiore e identificabile tramite errore/avviso.
- **MIDI per tutta la durata:** eliminati limiti arbitrari di 110/128/200 eventi nelle tracce. Il renderer PCM di fallback e il metronomo scrivono audio completo a blocchi sul disco, senza un enorme buffer RAM.
- **MIDI GM realmente campionato (Android):** `flutter_midi_pro 4.0.4` utilizza **FluidSynth**, 44,1 kHz e 128 voci, con **GeneralUser GS 2.0.3** e strumenti GM modificabili in **Tracce** (sax, chitarre, pianoforte, contrabbasso, archi, flauto, ecc.). La demo precedente con 3–4 onde sintetiche resta soltanto fallback se FluidSynth non funziona. **iOS conserva il fallback per i file MIDI**: l'interfaccia plugin non fornisce ancora MIDI-file playback su iOS.
- **Spartito completo, interfaccia veloce:** i pentagrammi ora sono virtualizzati a 8 battute per volta, la **barra verde marino** prosegue e scorre lungo i pentagrammi mentre l'audio originale avanza. Frecce per passare manualmente alle battute successive.
- **Take Five:** riconoscimento **suggerito dal solo nome file** (Take Five / Take 5) come **5/4**, modificabile manualmente in **Opzioni → Tempo in chiave** (3/4, 4/4, 5/4, 6/4). Non è ancora vera inferenza automatica della metrica. MIDI, pentagramma e MusicXML rispettano la metrica selezionata.
- **Confronto serio:** pulsante **Confronta online** per cercare volontariamente in **IMSLP, MuseScore, 8notes, Flat, ScoreExchange, OpenScore**, aprendo siti esterni (nessuno scraping o download occulto). **Confronta MusicXML** permette importare uno spartito .xml/.musicxml acquisito legalmente dall'utente e calcolare un **F1 reale pitch/onset** (match temporale ±1/16). Questo valore misura solo le note/attacchi corrispondenti con la trascrizione di riferimento, NON la qualità percettiva del brano né il riconoscimento strumenti.

## Limiti e sicurezza

- L'analisi automatica usa un algoritmo DSP sperimentale: jazz con contrabbasso, pianoforte e sax sovrapposti contiene armoniche che creano **note errate**, anche se il GM suona più realistico. Una ricostruzione *veramente accurata* richiede separation e polyphonic pitch transcription **on-device**, ancora da integrare e testare.
- Non esegue download automatici dei contenuti degli spartiti o di musica protetta da copyright. L'eventuale ricerca online è volontaria; altre funzioni (analisi, GM, esportazione, NoteLab) sono offline.
- Lo SoundFont, una volta incorporato nell'APK, funziona senza rete. **Solo la pipeline CI** scarica il SoundFont originale dall'autore con commit Git pinned durante la build.
- Gli import sono limitati a **512 MB file originale / 1 GB PCM** per motivi di archiviazione; il numero di note e la durata non sono troncati a 40 secondi. File molto lunghi possono richiedere tempo e spazio su disco; la percentuale indica avanzamento reale dell'analisi.
- La riproduzione GM con player MIDI Android sincronizzato con audio originale da player multipli non è sample-accurate; test con cuffie Bluetooth possono mostrare offset.
- Il **MIDI esportato contiene gli eventi riconosciuti, non l'audio originale**. Non applica automagicamente mastering o strumenti perfettamente riconosciuti.

## Build

```bash
flutter create --platforms=android,ios --project-name=ampy_score_ai --org=dev.ampyscore .
python3 tool/configure_platforms.py
python3 tool/fetch_soundfont.py
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
```

La build `android-apk.yml` esegue tutti i passaggi e pubblica l'APK. Per installare aggiornamenti su un APK esistente è necessaria la **stessa firma stabile**; i debug APK delle Actions possono richiedere una installazione separata con backup dei dati.

Licenze componenti: `flutter_midi_pro` MIT (inclusi i termini di librerie native FluidSynth/LGPL), `GeneralUser GS` [licenza specifica 2.0](https://github.com/mrbumpy409/GeneralUser-GS/blob/main/documentation/LICENSE.txt), riportata nel bundle come `assets/soundfonts/GeneralUser-GS-LICENSE.txt`. Per pubblicazione definitiva verificare obblighi di notice LGPL delle librerie native distribuite.

Riferimenti:
- GeneralUser GM soundbank: https://github.com/mrbumpy409/GeneralUser-GS
- flutter_midi_pro: https://pub.dev/packages/flutter_midi_pro
- MusicXML: https://www.w3.org/2021/06/musicxml40/
- IMSLP: https://imslp.org/
- OpenScore: https://openscore.cc/
- 8notes: https://www.8notes.com/
- MuseScore: https://musescore.com/
- Flat: https://flat.io/
- ScoreExchange: https://www.scoreexchange.com/

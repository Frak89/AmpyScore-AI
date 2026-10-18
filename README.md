# AmpyScore AI 1.1 — ascolta musica, riconosci le parti, leggi gli spartiti

## Partiture e audio di ogni strumento

[Guida completa al percorso AI e all'isolamento delle sorgenti](docs/AI_STUDIO.md). Lo Studio importa i progetti Demucs/Basic Pitch per voce, basso, batteria e altri, con note polifoniche; produce partitura completa o singola linea, MIDI e PDF per ciascuna parte. **Tracce → Mixer audio originale** sceglie e combina una o più sorgenti reali direttamente da WAV stereo, producendo PCM 24 bit senza MIDI, con protezione globale anti-clipping.

**Limite:** l'analisi neurale è oggi preparata su computer e poi importata come ZIP; il microfono Live e l'analisi rapida del telefono usano DSP euristico e NON isolano realmente ogni strumento.


**Scopo originario:** il microfono ascolta una canzone; l'app riconosce le parti musicali e le trascrive in **pentagrammi simultanei separati**, per poi lasciare ascoltare, correggere ed esportare ogni parte. La voce cantata è una parte del progetto, non una semplice funzionalità karaoke. La modalità Studio completa la trascrizione e permette le correzioni con NoteLab.

## Flusso principale, adesso funzionante

1. **Ascolta** è la prima schermata. Premi **Ascolta dal microfono**: l'app registra PCM16 localmente, salva un WAV completo su disco e ogni pochi secondi aggiorna una **partitura multirigo provvisoria** (basso, armonia, melodia, transienti/percussioni).
2. **Termina e completa lo spartito**: la registrazione viene finalizzata e sottoposta all'analisi completa, con riconoscimento di eventi/tempi approssimativi, notazione per parte e navigazione tra le battute.
3. **Apri una canzone** offre la stessa trascrizione automatica Studio a partire da file audio supportati dal dispositivo (MP3, M4A, FLAC, WAV e altri). Non serve un secondo pulsante per generare lo spartito.
4. **Spartito** mette al centro la partitura multitraccia, la riproduzione e la barra di avanzamento. **NoteLab** modifica le note. **Tracce** consente ascolto e mixer per famiglia stimata, controlli GM, filtri e modalità senza voce sperimentale. **Opzioni** contiene buffer, demo e configurazioni.

La registrazione Live usa `record.startStream(pcm16bits)`, un **writer WAV persistente con snapshot**, decodifica in isolate e un merge temporale senza creare note doppie ai bordi delle finestre. Salva l'intera esecuzione, non soltanto gli ultimi secondi. Non carica la registrazione completa in memoria e non invia l'audio a un server.

### Stato effettivo dei riconoscimenti

**Già funzionante:** analisi spettrale locale di 4 registri, note con inizio/durata stimati, primi pentagrammi Live, rianalisi completa Studio, controlli di tempo e notazione, modifiche/esportazioni già disponibili in v1.0.

**Non ancora ottenuto:** vera separazione IA affidabile dei singoli strumenti/voce, identificazione del timbro come sax/piano/chitarra, accordi polifonici completi, tonalità robusta e notazione perfetta di pause/battute da qualsiasi canzone. Le percentuali interne sono **confidenze euristiche**, non un tasso d'accuratezza verificato. Una registrazione mono da microfono contiene una miscela, non quattro tracce audio realmente separate.

Per integrare separazione autentica senza trasformare il telefono in un server, vedi `docs/ROADMAP_CORE.md`: modelli on-device con inferenza verificata e una suite di confronto note/stem. La modalità Live nasce volutamente con analisi DSP leggera, mentre la futura Studio neurale eseguirà l'elaborazione più pesante.

---

Applicazione Flutter gratuita e open source (MIT), elaborazione audio musicale locale. **Il motore di trascrizione non è ancora un modello AI di source separation**: i registri basso/armonia/melodia/percussioni sono stime da frequenze, perciò le note non saranno fedeli a un brano jazz polifonico complesso come *Take Five*. Non confondere qualità del sintetizzatore MIDI (timbrica) con accuratezza delle note estratte.


## Novità v1.0 — PDF, strumenti GM completi, esportazione tracce

- **Esporta PDF:** spartito multipagina A4 orizzontale in grafica vettoriale con tutti i righi, battute, note/pause, metro e BPM; bianco o seppia come impostato in Opzioni. Usa il menu nativo di condivisione/stampa; le funzioni avanzate di impaginazione musicale (corretta grafica di legature, gruppi di note, alterazioni armoniche) rimangono **preferibilmente gestite attraverso l'export MusicXML** e software di notazione.
- **Tutti i timbri MIDI GM1:** menu con 128 programmi, 0–127 (pianoforti, organi, chitarre, bassi, archi, fiati, pad e FX); percussioni sul canale MIDI 10 con 47 strumenti a note 35–81, selezione "automatico" oppure sostituzione esplicita con un suono percussivo. La scelta non aumenta la precisione del rilevamento.
- **Spessore cromatico +1 semitono:** funzione **facoltativa e disattivata per impostazione predefinita**. Aggiunge una seconda voce MIDI a un semitono sopra, a circa il 16% di velocity. Può introdurre dissonanze e non migliora la risoluzione/campionamento del suono. Non modifica percussioni.
- **Buffer sperimentale 4096:** scelta addizionale SoundFont, con maggiore latenza teorica. Non migliora la registrazione originale.
- **Esportazione WAV completa:** "Base senza voce" tramite attenuazione del centro stereo, "Solo voce stimata" tramite filtro sul centro stereo di banda media, più singoli registri basso, armonia, melodia e percussioni via filtri di frequenza. L'app produce ogni brano in streaming su disco e lo invia al menu condivisione Android/iOS, senza copiare WAV multi-centinaia MB in memoria. **Queste sono estrazioni sperimentali, non stem separati da reti neurali.** 
- **MIDI singola parte** dal menu Tracce: esporta uno Standard MIDI File di quella voce.


## Novità v0.9 — pratica musicale

- **Velocità audio continua 0,25×–4×** nello Studio, regolabile mentre il brano sta suonando. Pulsante **1×** per il ripristino immediato. La selezione si applica all'audio originale (o base stereo filtrata), al MIDI, al metronomo e al filtro ascoltato. Gli attacchi, la barra sul pentagramma e le durate restano riferiti alla timeline originale: cambiano la velocità di avanzamento, non i dati dello spartito.
- **Pitch MIDI invariato:** Android FluidSynth 4.0.4 supporta `setMidiTempo(factor)` senza trasporre le note; `just_audio.setSpeed` usa i controlli nativi del riproduttore audio, ma qualità di time-stretch/pitch a velocità estreme dipende dal dispositivo.
- **Opzioni → Audio sperimentale:** buffer nativo SoundFont MIDI da **128/256/512/1024/2048 frame**, campionamento selezionabile **44,1/48 kHz**, ripristino **512 / 44,1 kHz**. La configurazione viene salvata in locale con `shared_preferences`; cambiando buffer o sample-rate il sintetizzatore si riavvia e la riproduzione riprende dal punto corrente.
- Buffer maggiore può ridurre interruzioni o scricchiolii aumentando la latenza. **Non migliora la qualità dei campioni originali**, non converte il file originale, né corregge errori delle note riconosciute. I nuovi parametri sono solo del **SoundFont Android**; nessun controllo sul buffer MP3 di sistema viene dichiarato. Il tempo teorico mostrato nell'app è numero di frame / frequenza di campionamento e **non** misura la latenza audio finale.
- Preset salvati su Android/iOS; campionamento e buffer GM modificabili nell'interfaccia solo su Android perché il playback dei MIDI-file SoundFont del plugin è attualmente Android-only.
- L'uso di `setSpeed` per brano/metronomo e `setMidiTempo` per MIDI consente un confronto sincronizzato approssimativamente. Se il Bluetooth aggiunge latenza o l'audio viene time-stretched pesantemente, l'allineamento al campione non è garantito.

## v0.8 — ascolto migliore, riduzione vocale e prestazioni

- **Tracce → Base senza voce:** filtro offline da stereo con attenuazione del centro (intensità regolabile) e recupero parziale dei bassi. Elaborazione a blocchi per tutta la canzone, il brano originale rimane invariato. Se i due canali sono quasi uguali, il filtro rifiuta la conversione invece di produrre una base inutile. Il risultato è compatibile anche con un'uscita mono; la riduzione vocale non può garantire una voce pulita, né separare sax, piano e basso sovrapposti. L'app distingue chiaramente questo **metodo spaziale** dalla futura separazione neurale.
- **Tracce → Cuffie per registro:** riproduci la fascia di frequenza corrispondente a un registro stimato (basso, armonia, melodia, transienti) oppure usa **Solo MIDI** per ascoltare soltanto gli eventi MIDI ricostruiti. Questi NON sono stem autentici: note e armoniche di strumenti diversi possono sovrapporsi.
- **Strumenti suggeriti automaticamente:** toni GM scelti usando caratteristiche elementari della trascrizione (articolazione e registro), sempre presentati come ipotesi, e sostituibili manualmente.
- **Auto bilancia MIDI:** stima iniziale del volume relativo di ciascun registro attraverso energia spettrale; il comando reimposta i quattro volumi, con possibilità di perfezionarli a mano. Non è un algoritmo di loudness professionale su tracce separate.
- **Qualità del suono MIDI:** FluidSynth mantiene il SoundFont GeneralUser GS campionato; il buffer audio Android passa a 512 frame (anziché 64) per ridurre i glitch e l'uso di CPU. Riverbero molto leggero, chorus disattivato.
- **Analisi più rapida:** 2 isolate concorrenti per blocchi di 16 s, cache dei fattori FFT, ricerca dei picchi senza ordinamenti ad ogni frame e normalizzazione automatica. L'analisi non deve più saturare il thread che disegna lo spartito. I filtri frequenziali usano blocchi con overlap anti-click e caching su disco.
- **Rendering più efficiente:** aggiornamento della partitura limitato alle modifiche effettive, animazione nota disattivata quando non selezionata, `RepaintBoundary` dedicato al rigo.

**GPU:** la grafica Flutter può usare il renderer accelerato del dispositivo, ma **non è attiva inferenza GPU per separazione audio**, perché l'app non include ancora un modello neurale utilizzabile. ONNX Runtime NNAPI Android/Core ML iOS funzionano soltanto con modelli supportati e conversioni/verifiche specifiche: accendere un interruttore senza tale motore non migliora né garantisce qualità. Il lavoro v0.8 accelera invece la trascrizione CPU in modo reale. <https://onnxruntime.ai/docs/tutorials/mobile/>

Per la funzione `Base senza voce` l'audio stereo con voce centrale può migliorare, ma se anche batteria, basso, pianoforte o sax sono al centro, questi strumenti saranno attenuati. Per file mono serve una vera AI source separation da implementare.

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

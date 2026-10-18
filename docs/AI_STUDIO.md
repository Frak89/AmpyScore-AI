# AmpyScore AI — dall'audio ai veri spartiti per strumento

## L'idea originale

Importare o registrare una canzone, riconoscere quali strumenti suonano,
isolare le rispettive sorgenti musicali e generare automaticamente:
**uno spartito per ogni parte, una partitura completa, MIDI, MusicXML e PDF**.
Lo spartito deve restare sincronizzato con l'ascolto e modificabile in NoteLab.

Lo Studio rimane l'interfaccia principale: tutti gli altri strumenti
(mixer, velocità, metronomo, temi, effetti) devono servire questa funzione.

## Due motori con funzioni dichiaratamente diverse

| | Analisi rapida sul telefono | Progetto AI multistrumento |
|---|---|---|
| Sorgenti isolate reali | **No**, suddivisione per frequenze | **Sì**, Demucs HTDemucs |
| Riconoscimento intonazioni | DSP euristico | **Basic Pitch** separatamente su voce, basso, altri |
| Percussioni | transienti frequenziali | sorgente batteria separata e **attacchi stimati**, non drum transcription AI |
| Ascolto da solo | filtro frequenziale + MIDI | audio originale di ogni singola sorgente |
| Spartito multitraccia | approssimato | note per sorgente neurale (da verificare) |
| Dov'è eseguita l'AI | non disponibile | **computer dell'utente** in questa versione |
| Privacy | totalmente offline | elaborazione locale offline dopo download dei modelli |

**Stato tecnico:** l'esecuzione diretta dei modelli neurali Demucs e Basic Pitch
sul Pixel non è ancora implementata. Il progetto è un passo concreto verso
l'architettura richiesta, ma non è ancora il riconoscimento IA automatico
in un solo tap sul telefono. Il termine "strumento" significa qui
**voce, basso, batteria, altri strumenti**: la sorgente 'altri' può contenere
pianoforte, chitarra, archi, sax ecc. Non inventiamo una separazione aggiuntiva.

## Preparare il progetto AI sul proprio computer

Requisiti consigliati: Windows/Linux/macOS, Python **3.10 o 3.11**,
spazio su disco per modelli e WAV intermedi; su NVIDIA la GPU CUDA accelera
Demucs, mentre il passo Basic Pitch può richiedere dipendenze diverse.

### Windows — trascinamento, senza comandi

Nella cartella del progetto trovi **`tool/AmpyScore-AI-Converti-Brano.bat`**.
Trascina il brano MP3/FLAC/WAV sul file BAT: la prima volta configura
Python 3.10 e scarica i modelli AI, poi genera automaticamente lo ZIP
nella cartella del brano. Le esecuzioni successive riutilizzano l’ambiente.

### Windows — PowerShell

```powershell
py -3.10 -m venv .ampy-ai
.\.ampy-ai\Scripts\python -m pip install --upgrade pip
.\.ampy-ai\Scripts\python -m pip install demucs basic-pitch librosa soundfile numpy
.\.ampy-ai\Scripts\python tool\create_ai_session.py "C:\Music\canzone.mp3" --bpm 120 --meter 4 --device cpu
```

Per GPU NVIDIA configurata con PyTorch CUDA, sostituisci `--device cpu`
con `--device cuda`. Verifica compatibilità PyTorch/CUDA prima di farlo:
un GPU Intel/AMD o solo la grafica integrata non implicano CUDA.

Per un brano in cinque quarti, usa `--meter 5` e il BPM appropriato.
Il tempo reale non è ancora ricavato in modo affidabile dalla rete neurale:
puoi correggerlo dall'app NoteLab senza dover riscaricare alcun brano.

Il risultato è **`canzone_AmpyScore_AI.zip`**, contenente:
- `original/`: audio originale nel formato di importazione
- `stems/vocals.wav`, `bass.wav`, `drums.wav`, `other.wav`
- `stems/instrumental.wav`: somma bass + drums + other (vera base senza voce)
- `manifest.json`: eventi note, BPM, metro, nomi sorgenti e programma MIDI

### Android / iOS — AmpyScore Studio

Copia il file ZIP sul telefono, apri **Studio → Apri progetto AI multistrumento**.
L'app carica automaticamente note, quattro sorgenti, tempo, partitura completa
e strumenti MIDI. Tocca una sorgente per ascoltare **l'audio effettivamente
separato** oppure aprine il pentagramma in NoteLab.

Nello **Studio** trovi la partitura completa e le singole parti;
puoi selezionare la vista di un solo pentagramma ed esportarne
indipendentemente il **PDF**. Il motore mantiene anche note simultanee
(accordi) e voci sovrapposte; nel MusicXML sono rappresentate con
`<chord/>` e voci separate con `<backup>`.

In **Tracce**, usa l'ascolto cuffie per la sorgente reale, **Solo MIDI**
per ascoltare le note ricostruite, e **Esporta audio WAV** per voce,
base o singolo strumento. Il PDF e il MusicXML includono i pentagrammi
delle parti importate.

Gli eventi vocali/basso/altri vengono prodotti da Basic Pitch: una parte
delle note può essere errata, specialmente con riverbero, assoli sovrapposti,
musica jazz complessa o armoniche. Le durate/ritmi sono quantizzate dal
motore dello spartito e restano modificabili manualmente.

## Perché questi modelli

- [Demucs HTDemucs](https://github.com/adefossez/demucs): 4 sorgenti
  vocals/bass/drums/other; nella versione 6 sorgenti piano/chitarra sono
  sperimentali e possono avere importanti artefatti.
- [Spotify Basic Pitch](https://github.com/spotify/basic-pitch): modello
  polifonico generalista, lavora meglio su una sorgente alla volta.
- [ONNX Runtime Mobile](https://onnxruntime.ai/docs/tutorials/mobile/):
  per una futura inferenza locale NNAPI Android / CoreML iOS. Non è
  ancora integrato e la conversione modello è una milestone distinta.

Dopo l'installazione dei modelli su PC **non viene caricato audio su server**
dal programma AmpyScore; i file ZIP restano dell'utente. La connessione alla rete
può essere usata inizialmente da pip/PyTorch per scaricare codice/modelli.
Conserva i diritti necessari sugli audio che elabori e distribuisci.

## Cosa manca per la versione veramente autonoma

Porting e ottimizzazione NNAPI/CoreML di un modello di separazione e di
trascrizione per sorgente, identificazione timbrica (sax/piano/chitarra,
non per frequenza), riconoscimento affidabile di metri/tempi e notazione
professionale delle percussioni. Tali capacità non vengono dichiarate
già presenti sull'APK.

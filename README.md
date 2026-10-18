# AmpyScore Studio 0.5

Studio musicale gratuito, open source (MIT) e offline per Android e iOS. La UI principale contiene **Studio**, **NoteLab** e **Tracce**.

## Importazione audio

Premi **Apri brano** e seleziona un file audio (WAV, MP3, M4A, AAC, FLAC, OGG, OPUS, AIFF, CAF; altri formati decodificabili dal sistema). L'app conserva il file originale per l'ascolto e lo converte localmente in PCM WAV 16-bit mono 16 kHz per l'analisi, usando le API native del telefono. Il plugin `audio_decoder` è MIT e non utilizza server o FFmpeg esterno.

L'importazione **avvia direttamente la trascrizione e lo spartito**, senza ulteriori pulsanti. Anche la demo e la registrazione dal microfono si analizzano automaticamente. Nel menu in alto si può scegliere tra analisi multitraccia euristica e melodia singola.

**Limiti:** 96 MB per il file importato, 48 MB per il WAV decodificato, primi 40 secondi analizzati. La compatibilità con alcuni codec varia fra Android e iOS e con le capacità del dispositivo. Audio DRM protetto non è supportato.

## Interfaccia

- **Studio:** carta musicale bianca o seppia, spartito con barra scorrevole, comandi Audio / MIDI / Insieme, due volumi, esportazione MIDI e MusicXML.
- **NoteLab:** modifica note e pause, tempo BPM, controllo battute 4/4 e rigenerazione MIDI.
- **Tracce:** selezione registri, solo/mixer, filtri WAV locali. ChatGPT opzionale online resta nascosto in un pannello secondario.

## Stato del motore

La trascrizione multitraccia usa **analisi spettrale per registri**, non un modello IA per riconoscere con certezza singoli strumenti; il filtro di frequenze non estrae una voce pulita. I valori percentuali di affidabilità sono **stime interne**, non accuratezze misurate rispetto a una partitura di riferimento. L'editor suddivide su griglia 4/4; la metrica reale e le alterazioni non sono ancora riconosciute con precisione professionale.

Le funzioni locali sono interamente offline. **ChatGPT** è facoltativo: invia soltanto note testuali all'API OpenAI su richiesta esplicita, con Internet e chiave API separata.

## Build

Requisiti: Flutter SDK 3.47+ (Dart 3.10+) e Android SDK; per iOS, macOS + Xcode.

```bash
flutter create --platforms=android,ios --project-name=ampy_score_ai --org=dev.ampyscore .
python3 tool/configure_platforms.py
flutter pub get
flutter test
flutter build apk --debug
```

GitHub Actions **Android debug APK** esegue analisi, test e build e pubblica l'artefatto `ampyscore-debug-apk`. È una build di test, non una release firmata.

## Motori upstream

- `audio_decoder` (MIT) usa MediaExtractor/MediaCodec su Android e AVFoundation su iOS: https://pub.dev/packages/audio_decoder
- `file_picker` (MIT) importa file locali: https://pub.dev/packages/file_picker
- Prossima milestone: test reale su brani polifonici, modelli on-device di separazione e trascrizione; non dichiarare accuratezza misurata prima di avere dataset e ground truth.

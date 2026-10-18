# AmpyScore Studio 0.6

Studio musicale open source (MIT). Le funzioni di trascrizione locale rimangono **sperimentali**: i registri non equivalgono al riconoscimento affidabile degli strumenti, e le percentuali interne non sono misure d'accuratezza con spartiti di riferimento.

## Novità v0.6

- **Studio:** spartito multirigo e riproduzione audio/MIDI. Tocca una nota per ripartire da quel punto. Ruota il dispositivo in orizzontale mentre la riproduzione è attiva per la partitura a schermo intero; puoi entrarci anche dai comandi dello spartito.
- **Zoom:** pressione prolungata sul foglio per attivare pinch-to-zoom; da lì compaiono zoom −/+, fullscreen, chiusura.
- **NoteLab:** lo **stesso spartito** dello Studio e la nota selezionata lampeggia fra colore originale e verde scuro. Con −/+ scegli durate progressive da **1/32** a **4/1**; puoi cambiare semitono, collocazione, selezionare pausa. La prima eliminazione converte la nota in pausa; la seconda rimuove quella pausa e sposta indietro le note successive. Eventuali silenzi residui vengono notati come pause automatiche, perché le battute 4/4 devono rimanere valide.
- **Notazione:** gruppi di crome/semicrome contigue hanno aste collegate (beams), secondo la battuta. Le legature di valore compaiono soltanto quando una singola nota viene divisa, ad esempio attraversando una stanghetta, non automaticamente sulle note lunghe intere.
- **Metronomo:** sintetizzato offline, segue la posizione della traccia; 40–240 BPM, 4/4 accentato, divisioni 1/4, 1/8, 1/16, 1/32 e volume indipendente, in **Opzioni**. Poiché il player è indipendente, il sincronismo non è garantito a livello di singolo campione.
- **Opzioni:** esempi audio demo sono stati spostati dalle azioni principali. Testi della UI ridotti.
- **Confronta online:** dopo analisi, ricerca volontaria su MusicBrainz per **titolo/metadata del file**, con collegamento alla ricerca esterna dello spartito. Nessuna impronta acustica, upload del file o confronto automatico MusicXML con una partitura online; il riconoscimento preciso per audio è ancora da sviluppare.
- **App update:** pulsante nell'app per controllare su GitHub **Releases** se esiste una nuova versione stabile e aprirla nel browser. Non effettua download/installazione silenziosa.

## Aggiornamenti Android: firma stabile indispensabile

Il file debug generato da GitHub Actions è destinato ai test, **non è un canale di aggiornamento in-place sicuro**: una chiave di debug generata su runner differente può rendere incompatibile l'upgrade sopra l'app installata.

La workflow `.github/workflows/android-signed-release.yml` produce una release Android **firmata sempre con la stessa chiave** quando viene inviato un tag `v0.6.0` o successivo, **soltanto dopo** aver configurato in GitHub Settings → Secrets and variables → Actions quattro secret:
- `AMPY_RELEASE_KEYSTORE_BASE64`: contenuto base64 del file .jks, senza il percorso.
- `AMPY_RELEASE_STORE_PASSWORD`
- `AMPY_RELEASE_KEY_ALIAS`
- `AMPY_RELEASE_KEY_PASSWORD`

Conserva il keystore originale al sicuro e **non** inserire password, token o chiavi nel repository o nella chat. Prima di pubblicare, verificare che la firma resti la stessa in ogni release, così Android potrà installare le versioni successive senza perdere i dati. La workflow esegue test e pubblica un APK su una release GitHub con lo stesso tag; su iOS la distribuzione richiede firma e provisioning Apple separati.

## Importazione

Brani MP3, M4A, AAC, WAV, FLAC, OGG e altri codec compatibili con il dispositivo vengono convertiti offline in PCM per analisi, avviata automaticamente dopo la selezione. Fino a **40 secondi** analizzati per brano, formato di importazione massimo 96 MB e decoder dipendente dal dispositivo. Per la trascrizione accurata polifonica e la separazione effettiva degli strumenti servono modelli IA locali addestrati (non ancora presenti).

## Build sviluppatori

```bash
flutter create --platforms=android,ios --project-name=ampy_score_ai --org=dev.ampyscore .
python3 tool/configure_platforms.py
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug
```

Per iOS usare macOS + Xcode e provisioning appropriato. La build Android di debug è prodotta da `.github/workflows/android-apk.yml`. Le funzioni di analisi locale restano offline; online solo le funzioni **richieste esplicitamente** (OpenAI API per note testuali, ricerca metadata, controllo update). La disponibilità di una release su GitHub non rende l'installazione automatica.

### Documentazione tecnica consultata

- GitHub REST latest release: https://docs.github.com/en/rest/releases/releases
- MusicXML 4.0 ties: https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/tied/
- MusicXML 4.0 beams: https://www.w3.org/2021/06/musicxml40/musicxml-reference/elements/beam/
- Flutter url_launcher: https://pub.dev/packages/url_launcher

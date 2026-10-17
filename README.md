# AmpyScore AI

App open source per Android e iOS: ascolta dal microfono, importa file WAV e prova a trascrivere una **melodia monofonica** in note musicali. Include un esempio musicale WAV generato localmente.

**Stato: prototipo v0.1 / non ancora testato su dispositivi reali.** Non riconosce ancora singoli strumenti nei mix, accordi o partiture orchestrali. La trascrizione v0.1 usa analisi del segnale YIN, **non un modello di deep learning**.

## Privacy e ChatGPT

- Microfono, importazione, riproduzione, WAV demo e analisi note funzionano **offline**.
- Il pulsante facoltativo **ChatGPT (online)**, su consenso esplicito, invia **solo l'elenco delle note rilevate** alle API OpenAI per suggerimenti musicali. Non invia registrazioni audio.
- ChatGPT non può funzionare interamente sul dispositivo; l'API richiede Internet e una **chiave API OpenAI con fatturazione separata**. La chiave viene mantenuta soltanto in memoria per la sessione e non viene inserita nel codice sorgente.
- Non premere ChatGPT se vuoi restare al 100% offline. Per un rilascio pubblico sarebbe necessario sostituire l'inserimento diretto della chiave con un flusso sicuro.

## Prova rapida (Android, Windows/macOS/Linux)

Prerequisiti: Flutter SDK sul PATH, Android SDK (per build Android); macOS + Xcode per build iOS.

1. Clona il repository.
2. Genera i progetti nativi: `flutter create --platforms=android,ios --project-name=ampy_score_ai --org=dev.ampyscore .`
3. Applica le autorizzazioni: `python3 tool/configure_platforms.py` (Windows: `py -3 tool/configure_platforms.py`).
4. Installa pacchetti: `flutter pub get`.
5. Avvia: `flutter run` oppure `flutter build apk --debug`.

Su GitHub apri **Actions → Android debug APK**, avvia il workflow su questa branch o usa l'esecuzione automatica: scarica l'artefatto `ampyscore-debug-apk`, che contiene `app-debug.apk`. **Non è una release firmata per la distribuzione.**

## Prova del microfono e della demo

1. Tocca **Demo musicale** e poi **Riproduci** per ascoltare 8 note sintetizzate sul dispositivo.
2. Premi **Analizza WAV**: la trascrizione dovrebbe contenere Do4, Re4, Mi4 e Sol4.
3. Tocca **Registra**, suona o canta una nota alla volta, poi **Stop e analizza**.
4. In alternativa importa un file WAV PCM 16-bit mono/stereo (MP3/FLAC non sono ancora supportati per la trascrizione).

Il riconoscimento è limitato alla melodia monofonica (circa E2–C6), all'audio WAV PCM 16-bit e ai primi 40 secondi di ogni traccia. Rumore, vibrato, riverbero e più strumenti contemporanei peggiorano i risultati.

## Architettura

- `lib/audio/wav_engine.dart`: decoder WAV, generatore demo, trascrittore monofonico YIN.
- `lib/audio/staff_painter.dart`: pentagramma di anteprima.
- `lib/services/chatgpt_service.dart`: richiesta API **facoltativa** e solo testuale.
- `lib/main.dart`: interfaccia Flutter, microfono, file locale, player e trascrizione.
- `test/wav_engine_test.dart`: test automatico della demo.

## Roadmap

v0.2: modello IA on-device per trascrizione; v0.3: separazione sorgenti/strumenti e MusicXML; v1.0: ottimizzazione Android/iOS. Gli esiti dei modelli, le licenze e il consumo di memoria andranno verificati prima di includerli.

Licenza: MIT. Nessun server, account o analytics necessario per le funzioni locali.

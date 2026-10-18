@echo off
setlocal
set "ROOT=%~dp0.."
cd /d "%ROOT%"
if "%~1"=="" (
    echo.
    echo AmpyScore AI - separazione e spartiti per strumento
    echo Trascina un file MP3, FLAC o WAV su questo file .bat.
    echo.
    pause
    exit /b 2
)
set "BRANO=%~f1"
set "VENV=%ROOT%\.ampy-ai"
if not exist "%VENV%\Scripts\python.exe" (
    echo Installazione ambiente Python 3.10 e modelli AI...
    py -3.10 -m venv "%VENV%"
    if errorlevel 1 goto err
    "%VENV%\Scripts\python.exe" -m pip install --upgrade pip
    if errorlevel 1 goto err
    "%VENV%\Scripts\python.exe" -m pip install demucs basic-pitch librosa soundfile numpy
    if errorlevel 1 goto err
)
echo.
echo Separazione reale della voce, basso, batteria e altri...
echo La prima esecuzione scarica i modelli AI: richiede spazio su disco.
"%VENV%\Scripts\python.exe" "%ROOT%\tool\create_ai_session.py" "%BRANO%" --device cpu
if errorlevel 1 goto err
echo.
echo Completato. Trovi il progetto ZIP accanto al file audio.
echo Copialo sul telefono e aprilo in AmpyScore Studio.
pause
exit /b 0
:err
echo.
echo Si e' verificato un errore. Il file originale non viene modificato.
echo Verifica Python 3.10, spazio e connessione per il primo download.
pause
exit /b 1

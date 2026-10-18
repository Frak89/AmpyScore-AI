#!/usr/bin/env python3
"""AmpyScore AI: source-separated polyphonic audio -> editable score package.

Desktop-assisted, genuinely neural pipeline:
  Demucs HTDemucs separates vocals/drums/bass/other.
  Spotify Basic Pitch transcribes vocals/bass/other independently.
  Drums receive LOW-CONFIDENCE onset/class labels (not a drum transcription AI).
  Generates one .zip that AmpyScore Android/iOS can import offline.

The inference is LOCAL ON THE USER'S COMPUTER, with no audio upload by
AmpyScore. Audio rights and model licenses remain with their owners.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def analyze_pitched(wav: Path, low: int, high: int) -> list[dict]:
    from basic_pitch.inference import predict
    _, _, events = predict(
        str(wav),
        minimum_frequency=440.0 * 2 ** ((low - 69) / 12),
        maximum_frequency=440.0 * 2 ** ((high - 69) / 12),
        onset_threshold=0.58,
        frame_threshold=0.33,
    )
    result = []
    for start, end, pitch, amplitude, _ in events:
        if end <= start or pitch < low or pitch > high:
            continue
        result.append({
            "midi": int(pitch),
            "start": round(float(start), 4),
            "end": round(float(end), 4),
            # Raw model amplitude; not measured transcription accuracy.
            "confidence": round(max(0.05, min(1.0, float(amplitude))), 3),
        })
    return result


def percussion_onsets(path: Path) -> list[dict]:
    """Crude percussive hits to make an editable drum staff.
    No false claim of identifying the actual drum hit used by the player.
    """
    import librosa
    import numpy as np
    y, rate = librosa.load(str(path), sr=22050, mono=True)
    hop = 512
    onsets = librosa.onset.onset_detect(
        y=y, sr=rate, hop_length=hop, backtrack=False, units="samples")
    notes = []
    min_gap = 0.075
    last_time = -1.0
    for onset in onsets:
        t = float(onset) / rate
        if t - last_time < min_gap:
            continue
        last_time = t
        segment = y[int(onset):int(onset) + 2048]
        if len(segment) < 500:
            continue
        energy = float(np.sqrt(np.mean(segment * segment)))
        if energy < 0.012:
            continue
        spectrum = np.abs(np.fft.rfft(segment, n=2048))
        freqs = np.fft.rfftfreq(2048, 1 / rate)
        low = spectrum[freqs < 150].sum()
        high = spectrum[freqs > 3500].sum()
        mid = spectrum.sum() - low - high
        # Heuristic GM note: low=kick, mid=snare, high=closed hat.
        key = 36 if low > mid * .65 else (42 if high > mid * .8 else 38)
        notes.append({
            "midi": key, "start": round(t, 4),
            "end": round(t + .08, 4),
            "confidence": 0.25,
        })
    return notes


def build_session(audio: Path, output: Path, bpm: int, meter: int,
                  device: str, skip_drums: bool) -> None:
    if not audio.is_file():
        raise FileNotFoundError(audio)
    if audio.stat().st_size > 512 * 1024 * 1024:
        raise ValueError("File originale oltre 512 MB.")
    if not 40 <= bpm <= 240 or not 2 <= meter <= 12:
        raise ValueError("BPM 40–240, numeratore 2–12.")
    with tempfile.TemporaryDirectory(prefix="ampyscore_ai_") as tmp:
        workspace = Path(tmp)
        command = [
            sys.executable, "-m", "demucs", "--name", "htdemucs",
            "--out", str(workspace / "separated"),
            "--int24",
            "--device", device, str(audio),
        ]
        print("1/3 Separazione reale strumenti (Demucs):", flush=True)
        subprocess.run(command, check=True)
        separated = workspace / "separated" / "htdemucs" / audio.stem
        if not separated.is_dir():
            raise RuntimeError("Demucs non ha generato le quattro sorgenti.")
        session = workspace / "package"
        (session / "stems").mkdir(parents=True)
        (session / "original").mkdir(parents=True)
        original_name = "original" + audio.suffix.lower()
        shutil.copy2(audio, session / "original" / original_name)
        tracks = []
        config = [
            ("vocals", "Voce (Demucs + Basic Pitch)", 53, 42, 90, .55),
            ("bass", "Basso (Demucs + Basic Pitch)", 32, 28, 66, .60),
            ("drums", "Batteria (Demucs, attacchi stimati)", 0, 35, 81, .25),
            ("other", "Altri strumenti (Demucs + Basic Pitch)", 0, 45, 92, .43),
        ]
        print("2/3 Trascrizione indipendente delle sorgenti:", flush=True)
        duration = 0.0
        import soundfile as sf
        for family, title, gm, low, high, confidence in config:
            source = separated / f"{family}.wav"
            if not source.is_file():
                raise RuntimeError(f"Manca {family}.wav nel risultato Demucs.")
            source_name = f"stems/{family}.wav"
            shutil.copy2(source, session / source_name)
            meta = sf.info(str(source))
            duration = max(duration, float(meta.duration))
            if family == "drums":
                notes = [] if skip_drums else percussion_onsets(source)
            else:
                notes = analyze_pitched(source, low, high)
            print(f"   {family}: {len(notes)} eventi", flush=True)
            tracks.append({
                "id": family, "label": title, "audio": source_name,
                "gmProgram": gm, "confidence": confidence, "notes": notes,
            })
        # Correct accompaniment is the SUM of genuine separated sources,
        # rather than a centre-removal/phase cancellation heuristic.
        instrumental = session / "stems" / "instrumental.wav"
        import soundfile as sf
        import numpy as np
        inputs = [sf.SoundFile(str(session / "stems" / f"{name}.wav"))
                  for name in ("bass", "drums", "other")]
        try:
            rate = inputs[0].samplerate
            channels = inputs[0].channels
            if any(f.samplerate != rate or f.channels != channels
                   for f in inputs):
                raise ValueError("Stem Demucs con campionamenti diversi.")
            with sf.SoundFile(str(instrumental), mode="w",
                              samplerate=rate, channels=channels,
                              subtype="PCM_24") as output_audio:
                while True:
                    blocks = [f.read(8192, dtype="float32", always_2d=True)
                              for f in inputs]
                    length = max((len(block) for block in blocks), default=0)
                    if length == 0:
                        break
                    merged = np.zeros((length, channels), dtype=np.float32)
                    for block in blocks:
                        merged[:len(block)] += block
                    output_audio.write(np.clip(merged, -1.0, 1.0))
        finally:
            for f in inputs:
                f.close()
        manifest = {
            "format": "ampyscore-ai-session", "version": 1,
            "title": audio.stem,
            "original": f"original/{original_name}",
            "instrumental": "stems/instrumental.wav",
            "bpm": bpm, "beatsPerBar": meter,
            "durationSeconds": round(duration, 4),
            "separationModel": "htdemucs",
            "transcriptionModel": "spotify-basic-pitch",
            "notes": "Confidence = heuristic/model score, not evaluation F1.",
            "tracks": tracks,
        }
        (session / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8")
        output.parent.mkdir(parents=True, exist_ok=True)
        if output.exists():
            raise FileExistsError(output)
        print("3/3 Creazione progetto AmpyScore:", flush=True)
        with zipfile.ZipFile(output, "w", allowZip64=True) as zf:
            for file in sorted(session.rglob("*")):
                if file.is_file():
                    relative = file.relative_to(session).as_posix()
                    # WAVs and compressed input should not consume extra RAM
                    # or CPU to attempt futile recompression.
                    zf.write(file, relative, compress_type=zipfile.ZIP_STORED)
        print(f"Progetto pronto: {output.resolve()}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Genera un progetto multistrumento AmpyScore con vera IA.")
    parser.add_argument("audio", type=Path,
                        help="Brano audio originale, es. take-five.mp3")
    parser.add_argument("--output", type=Path,
                        help="Nome file .zip per importazione nell'app")
    parser.add_argument("--bpm", type=int, default=120,
                        help="BPM della partitura (correggibili in NoteLab)")
    parser.add_argument("--meter", type=int, default=4,
                        help="Numeratore del tempo, ad es. 5 per 5/4")
    parser.add_argument("--device", choices=["cpu", "cuda", "mps"],
                        default="cpu", help="Acceleratore Demucs, se disponibile")
    parser.add_argument("--skip-drums", action="store_true",
                        help="Non generare attacchi percussivi approssimati")
    args = parser.parse_args()
    target = args.output or args.audio.with_name(
        args.audio.stem + "_AmpyScore_AI.zip")
    try:
        build_session(args.audio, target, args.bpm, args.meter,
                      args.device, args.skip_drums)
    except Exception as ex:
        print(f"ERRORE: {ex}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

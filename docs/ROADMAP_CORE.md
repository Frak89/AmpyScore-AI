# AmpyScore AI — original product contract and technical milestones

## Primary experience (acceptance criteria)

A musician places a phone near a performing ensemble, taps **Ascolta**, and sees provisional independent music staves appearing while recording. Stopping the recording automatically runs a complete offline Studio pass, yielding one editable note/rest lane per recognizable voice/instrument, synchronized with the original song. Every part can then be auditioned, isolated, corrected in NoteLab, and exported as MIDI, MusicXML or PDF.

**Do not move these essential actions behind advanced settings.** Start screen: one prominent microphone action, secondary file import, a running time, detected part summary and the multistaff sheet.

## Technology and verification

### Live engine (implemented v1.1)
- Android/iOS `record` PCM16 16k mono stream, on-disk WAV ringless writer.
- Snapshot every ~2.3s; bounded FFT analysis in background isolate; append notes in timestamp order with overlap deduplication, never upload audio.
- Staves update while capture continues; on stop the full WAV is analyzed in Studio and exported normally.
- Melodic/bass/harmonic/percussive lanes represent frequency **registers and transients** and MUST NOT be named as confirmed real instruments.
- Live tempo locked after enough evidence to prevent notes jumping every update.

### Studio source separation (next required core engine)
- Research: HT-Demucs ONNX on Android/iOS has model files on the order of hundreds of megabytes, and inference memory/performance concerns. Mobile NNAPI/Core ML support and licensing are conditional. Before bundling, benchmark Pixel-class arm64 phones for <= 30s chunks with overlap and no internet; measure RAM, battery and clipping.
- True separate stems: vocals, bass, drums, remaining instruments, potentially guitar/piano with suitable evaluated model; original stereo channel preservation; solo/mute individual waveform playback.
- Each stem must be transcribed by an evaluated multiple-pitch model rather than only harmonic-bin detection. Basic Pitch is a possible starting point for monophonic/limited-polyphonic stems; consider MT3 or comparable instrument-aware AMT on suitably supported inference runtime.
- Map every stem to pitch/onset/offset, rest duration, attack strength, instrument GM program with classification confidence. Allow correcting meter/key/tempo without destroying manually edited work.
- Voice lane uses the isolated sung melody for notes. Speech/vocals with no pitched melody are not represented as fabricated notes.
- MIDI note accuracy and instrument identity confidence must be **measured** against ground-truth performances. Distinguish estimated/verified confidence percentages.

### Benchmarks/quality gates
- Unit: valid WAV while PCM capture is active; 2+ overlapping segments produce one continuous note; simultaneous bass+melody have independent staves; no >40s truncation.
- Integration: microphone and file both produce a project with >=2 independently editable tracks from prepared musical recordings.
- Music corpus: acoustic solo instrument, a duo, a quartet, 5/4 *Take Five*-style jazz (with permissible original test audio), live room noise, overlapping note sustains. Compare pitch/onset F1, false positives, instrument labeling precision and stem bleed.
- End-to-end: recording, stopping, full score review, NoteLab correction, per-stem playback and exports. Confirm all controls at Android portrait/landscape.
- Device: UI smooth at 60/120Hz while audio capture and bounded DSP run; sustained memory and CPU metrics on real Pixel 7 Pro. Audio fidelity of original recording vs synthesized GM playback measured separately.

## References
- Flutter/record microphone streaming: https://pub.dev/packages/record
- Original Demucs / neural source separation: https://github.com/facebookresearch/demucs
- Demucs ONNX mobile: https://github.com/StemSplit/demucs-onnx
- Spotify Basic Pitch: https://github.com/spotify/basic-pitch
- MusicXML: https://www.w3.org/2021/06/musicxml40/

This document is a concrete implementation plan. Neural source separation and trained multi-instrument transcription **are not present in v1.1**, and must not be represented as installed/functional until implementation and device QA.

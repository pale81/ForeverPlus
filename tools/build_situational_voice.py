#!/usr/bin/env python3
"""Build and Whisper-verify German and English male-dwarf situational voice clips.

Reads tools/situational_voice.json and renders mono 24 kHz MP3 clips into
Media/SituationalVoice/<locale>/DwarfMale/<KEY>.mp3 using Qwen3-TTS via mlx-audio.
Each rendered clip is checked for duration (0.6-5.5 s), valid peak amplitude, and
transcription accuracy via local Whisper ASR; failing clips are automatically
re-rendered with a fresh seed.

Reference recordings and model caches remain outside the addon. Requires ffmpeg.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tools" / "situational_voice.json"
MIN_DURATION = 0.6
MAX_DURATION = 5.5

NUMBER_WORDS = {
    "de": {"10": "zehn"},
    "en": {"10": "ten"},
}


def normalize(text, lang):
    text = text.lower().replace("ß", "ss")
    for digit, word in NUMBER_WORDS.get(lang, {}).items():
        text = re.sub(rf"\b{digit}\b", word, text)
    # Normalize common English contractions so "I'll" matches "I will", "couldn't" matches "could not"
    if lang == "en":
        text = text.replace("i'll", "i will").replace("couldn't", "could not").replace("don't", "do not")
    return re.findall(r"[a-zäöü0-9]+", text)


def levenshtein(left, right):
    row = list(range(len(right) + 1))
    for i, a in enumerate(left, 1):
        new = [i]
        for j, b in enumerate(right, 1):
            new.append(min(new[-1] + 1, row[j] + 1, row[j - 1] + (a != b)))
        row = new
    return row[-1]


def word_error_rate(expected_text, heard_text, lang):
    left = normalize(expected_text, lang)
    right = normalize(heard_text, lang)
    return levenshtein(left, right) / max(1, len(left))


def char_error_rate_nospace(expected_text, heard_text, lang):
    left = "".join(normalize(expected_text, lang))
    right = "".join(normalize(heard_text, lang))
    return levenshtein(left, right) / max(1, len(left))


def build_reference_wav(file_ids, build, locale, folder):
    """Download original client voice files from wago.tools and concat at 24 kHz."""
    oggs = []
    for file_id in file_ids:
        path = folder / f"{locale}-{file_id}.ogg"
        url = f"https://wago.tools/api/casc/{file_id}?download&version={build}&locale={locale}"
        request = urllib.request.Request(url, headers={"User-Agent": "ForeverPlus-situational-voice/1.0"})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
        if not data.startswith(b"OggS"):
            raise ValueError(f"{locale} FileDataID {file_id} did not return an Ogg recording")
        path.write_bytes(data)
        oggs.append(path)
        time.sleep(0.15)
    ref_wav = folder / f"reference-{locale}.wav"
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
    for ogg in oggs:
        cmd += ["-i", str(ogg)]
    inputs = "".join(f"[{i}:a]" for i in range(len(oggs)))
    cmd += ["-filter_complex", f"{inputs}concat=n={len(oggs)}:v=0:a=1,aresample=24000", str(ref_wav)]
    subprocess.run(cmd, check=True)
    return ref_wav


def encode_mp3(source_wav, target_mp3, voice_filter):
    filters = (
        "silenceremove=start_periods=1:start_duration=0.015:start_threshold=-45dB,"
        "areverse,silenceremove=start_periods=1:start_duration=0.015:start_threshold=-45dB,"
        f"areverse,highpass=f=60,{voice_filter},loudnorm=I=-20:TP=-2:LRA=7,"
        "afade=t=in:d=0.005,apad=pad_dur=0.08"
    )
    subprocess.run([
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(source_wav),
        "-af", filters, "-ac", "1", "-ar", "24000", "-c:a", "libmp3lame",
        "-q:a", "3", str(target_mp3),
    ], check=True)


def verify_clip(asr_model, mp3_path, expected_text, whisper_lang, max_wer):
    import numpy as np
    from mlx_audio.audio_io import read

    audio, rate = read(str(mp3_path))
    audio = np.asarray(audio)
    duration = len(audio) / rate
    peak = float(abs(audio).max()) if len(audio) else 0.0
    if not np.isfinite(audio).all() or peak > 1.0 or not (MIN_DURATION <= duration <= MAX_DURATION):
        return False, duration, peak, 1.0, ""
    heard = asr_model.generate(
        str(mp3_path), language=whisper_lang, temperature=0, return_timestamps=False
    ).text.strip()
    wer = word_error_rate(expected_text, heard, whisper_lang)
    cer = char_error_rate_nospace(expected_text, heard, whisper_lang)
    ok = wer <= max_wer or cer <= 0.08
    return ok, duration, peak, wer, heard


def collect_entries(locale_spec, only):
    entries = []
    for category, variants in locale_spec["categories"].items():
        for variant in variants:
            key = variant["key"]
            if not only or key in only or category in only:
                entries.append((category, key, variant["text"]))
    return entries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--locales", nargs="+", choices=["deDE", "enUS"], default=["deDE", "enUS"])
    parser.add_argument("--model", type=Path, help="Local path to Qwen3-TTS model snapshot")
    parser.add_argument("--asr-model", type=Path, help="Local path to Whisper model snapshot")
    parser.add_argument("--reference-de", type=Path, help="Optional pre-built 24 kHz deDE reference WAV")
    parser.add_argument("--reference-en", type=Path, help="Optional pre-built 24 kHz enUS reference WAV")
    parser.add_argument("--only", nargs="+", help="Render/verify only specific keys or categories")
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--max-retries", type=int, default=8)
    parser.add_argument("--max-wer", type=float, default=0.25)
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    voice_filter = manifest.get("voice_filter", "anull")
    temperature = manifest.get("temperature", 0.65)
    base_seed = manifest.get("seed", 2026)

    if not args.verify_only and not args.model:
        parser.error("--model is required unless --verify-only is set")
    if not args.asr_model:
        parser.error("--asr-model is required for quality verification")

    import mlx.core as mx
    import numpy as np
    from mlx_audio.audio_io import write
    from mlx_audio.stt import load as load_stt
    from mlx_audio.tts.utils import load_model as load_tts

    tts_model = None if args.verify_only else load_tts(str(args.model))
    asr_model = load_stt(str(args.asr_model))

    failures = []
    with tempfile.TemporaryDirectory(prefix="foreverplus-situational-") as tmp_str:
        tmp_dir = Path(tmp_str)
        ref_overrides = {"deDE": args.reference_de, "enUS": args.reference_en}

        for loc_idx, locale in enumerate(args.locales):
            spec = manifest["locales"][locale]
            destination = ROOT / "Media" / "SituationalVoice" / locale / "DwarfMale"
            destination.mkdir(parents=True, exist_ok=True)
            entries = collect_entries(spec, set(args.only) if args.only else None)
            if not entries:
                continue

            ref_wav = None
            if not args.verify_only:
                ref_wav = ref_overrides.get(locale)
                if not ref_wav:
                    print(f"[{locale}] Downloading reference IDs {manifest['reference_file_ids']}...", flush=True)
                    ref_wav = build_reference_wav(manifest["reference_file_ids"], manifest["build"], locale, tmp_dir)

            source_wav = tmp_dir / f"{locale}-speech.wav"
            encoded_mp3 = tmp_dir / f"{locale}-speech.mp3"

            for idx, (category, key, text) in enumerate(entries, 1):
                target = destination / f"{key}.mp3"

                if args.verify_only or (target.exists() and not args.overwrite):
                    if not target.exists():
                        failures.append(f"{locale}/{key}: missing")
                        continue
                    ok, dur, peak, wer, heard = verify_clip(
                        asr_model, target, text, spec["whisper_language"], args.max_wer
                    )
                    status = "OK" if ok else "FAIL"
                    print(
                        f"[{locale}] {idx}/{len(entries)} {key} [{status}] "
                        f"dur={dur:.2f}s peak={peak:.3f} WER={wer:.2f} | {heard!r}",
                        flush=True,
                    )
                    if ok or args.verify_only:
                        if not ok:
                            failures.append(f"{locale}/{key}: dur={dur:.2f}s WER={wer:.2f} heard={heard!r}")
                        continue

                passed = False
                for attempt in range(args.max_retries):
                    seed = base_seed + loc_idx * 10000 + idx * 100 + attempt * 17
                    mx.random.seed(seed)
                    results = list(tts_model.generate(
                        text=text,
                        ref_audio=str(ref_wav),
                        ref_text=spec["reference_text"],
                        lang_code=spec["lang_code"],
                        max_tokens=160,
                        temperature=temperature,
                        repetition_penalty=1.05,
                        verbose=False,
                    ))
                    audio = np.concatenate([np.asarray(item.audio) for item in results])
                    sample_rate = results[0].sample_rate if results else tts_model.sample_rate
                    if not np.isfinite(audio).all() or len(audio) / sample_rate < 0.3 or len(audio) / sample_rate > 9.0:
                        print(f"[{locale}] {key} attempt {attempt + 1}: invalid raw audio, retrying...", flush=True)
                        mx.clear_cache()
                        continue

                    write(str(source_wav), audio, sample_rate)
                    encode_mp3(source_wav, encoded_mp3, voice_filter)
                    ok, dur, peak, wer, heard = verify_clip(
                        asr_model, encoded_mp3, text, spec["whisper_language"], args.max_wer
                    )
                    status = "OK" if ok else "RETRY"
                    print(
                        f"[{locale}] {idx}/{len(entries)} {key} (try {attempt + 1}, seed={seed}) [{status}] "
                        f"dur={dur:.2f}s peak={peak:.3f} WER={wer:.2f} | {heard!r}",
                        flush=True,
                    )
                    mx.clear_cache()
                    if ok:
                        encoded_mp3.replace(target)
                        passed = True
                        break

                if not passed:
                    failures.append(f"{locale}/{key}: failed after {args.max_retries} attempts")

    if failures:
        print("\nFAILURES:", flush=True)
        for item in failures:
            print("  -", item, flush=True)
        raise SystemExit(1)
    print("\nALL CLIPS PASSED VERIFICATION", flush=True)


if __name__ == "__main__":
    main()

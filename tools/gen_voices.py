"""Speaks every story line with Kokoro and writes assets/voice/CC_S_L.ogg.

Run it with a Python that has kokoro_onnx and soundfile, for example:
    ~/Projects/Open-Montage/myenv/bin/python tools/gen_voices.py [target ...]

A target is a chapter ("3"), a shot ("3_2") or a single line ("3_2_1"); with no
targets every line is spoken. Use the narrowest targets after a small edit.

Lines are read straight from scripts/story_data.gd, so re-run this after editing
the story. File names are chapter_shot_line, all counted from zero.
"""
import pathlib
import re
import subprocess
import sys
import tempfile

import soundfile
from kokoro_onnx import Kokoro

ROOT = pathlib.Path(__file__).resolve().parent.parent
STORY = ROOT / "scripts" / "story_data.gd"
OUT = ROOT / "assets" / "voice"
CACHE = pathlib.Path.home() / ".cache" / "openmontage" / "kokoro"

COMMON = "loudnorm=I=-16:TP=-1.5:LRA=7"
CAST = {
    "VARGA": {"voice": "bf_isabella", "lang": "en-gb", "speed": 1.0,
              "filter": "highpass=f=170,lowpass=f=6500"},
    "REEVE": {"voice": "am_michael", "lang": "en-us", "speed": 0.96,
              "filter": "highpass=f=210,lowpass=f=5200"},
    # Slowed and pitched down, with a short echo and a machine flutter.
    "OVERSEER": {"voice": "bm_george", "lang": "en-gb", "speed": 0.9,
                 "filter": "asetrate=24000*0.86,aresample=24000,atempo=1.08,aecho=0.8:0.55:22:0.45,tremolo=f=70:d=0.22,highpass=f=90"},
    "HARBOR RING": {"voice": "bf_emma", "lang": "en-gb", "speed": 1.0,
                    "filter": "highpass=f=320,lowpass=f=3300,acompressor=threshold=0.12:ratio=5"},
}

## Things a speech engine would read wrongly from the on-screen text.
SPOKEN = [
    (r"WREN-9", "Wren Nine"),
    (r"\bShaft 1\b", "Shaft One"),
    (r"\bShaft 3\b", "Shaft Three"),
    (r"\bSector 9\b", "Sector Nine"),
    (r"DIRECTIVE ONE", "Directive one"),
    (r"ASSET PRESERVED", "Asset preserved"),
]
LINE = re.compile(r'\["(' + "|".join(CAST) + r')", "((?:[^"\\]|\\.)*)"\]')


def story_lines():
    chapter, shot, line = -1, -1, 0
    for raw in STORY.read_text().splitlines():
        if '"title":' in raw:
            chapter, shot = chapter + 1, -1
        if '"stage":' in raw:
            shot, line = shot + 1, 0
        for match in LINE.finditer(raw):
            yield chapter, shot, line, match[1], match[2].replace('\\"', '"')
            line += 1


def spoken(text):
    for pattern, replacement in SPOKEN:
        text = re.sub(pattern, replacement, text)
    return text


def picked(targets, chapter, shot, line):
    if not targets:
        return True
    here = (chapter, shot, line)
    return any(here[:len(t)] == t for t in targets)


def main():
    targets = [tuple(int(part) for part in a.split("_")) for a in sys.argv[1:]]
    OUT.mkdir(parents=True, exist_ok=True)
    kokoro = Kokoro(str(CACHE / "models" / "kokoro-v1.0.onnx"), str(CACHE / "voices" / "voices-v1.0.bin"))
    total = 0.0
    count = 0
    with tempfile.TemporaryDirectory() as tmp:
        for chapter, shot, line, speaker, text in story_lines():
            if not picked(targets, chapter, shot, line):
                continue
            cast = CAST[speaker]
            samples, rate = kokoro.create(spoken(text), voice=cast["voice"], speed=cast["speed"], lang=cast["lang"])
            raw = pathlib.Path(tmp) / "line.wav"
            soundfile.write(raw, samples, rate)
            target = OUT / f"{chapter:02d}_{shot}_{line}.ogg"
            subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(raw),
                            "-af", f"{cast['filter']},{COMMON}", "-ar", "44100", "-ac", "1",
                            "-c:a", "libvorbis", "-q:a", "4", str(target)], check=True)
            seconds = len(samples) / rate
            total += seconds
            count += 1
            print(f"[voice] {target.name} {speaker:12s} {seconds:5.1f}s  {text[:60]}", flush=True)
    print(f"[voice] {count} lines, {total:.0f}s of speech")


main()

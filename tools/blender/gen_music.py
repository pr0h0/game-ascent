"""Composes the soundtrack from note patterns and synthesised instruments.

Each mine song is three perfectly aligned stems the same length: "calm" always plays,
"combat" is faded in by the game when robots attack, and "intense" joins on top when
the fight gets heavy (several robots at once, a big one, or the shield running low). Everything wraps at the
loop point, including reverb and delay tails, so the tracks loop without a seam.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from synth import (RATE, ROOT, bandpass, decay, env_ar, highpass, lowpass, midi_hz, pan_stereo, resonant_sweep, sat, saw, sine, square, write_ogg)

OUT = os.path.join(ROOT, "assets", "music")
os.makedirs(OUT, exist_ok=True)

SCALES = {
    "minor": [0, 2, 3, 5, 7, 8, 10],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "harmonic": [0, 2, 3, 5, 7, 8, 11],
    "phrygian_dominant": [0, 1, 4, 5, 7, 8, 10],
}


class Bus:
    """Stereo buffer in which writes wrap around at the loop point."""

    def __init__(self, n):
        self.buf = np.zeros((n, 2))

    def add(self, sound, pos, gain=1.0, pan=0.0):
        s = pan_stereo(sound, pan) if sound.ndim == 1 else sound
        n = len(self.buf)
        pos %= n
        if len(s) >= n:
            s = s[:n]
        first = min(len(s), n - pos)
        self.buf[pos:pos + first] += s[:first] * gain
        if first < len(s):
            self.buf[: len(s) - first] += s[first:] * gain


def reverb(bus, seconds, damp, wet, rng):
    n = len(bus.buf)
    m = min(int(seconds * RATE), n)
    ir_time = np.arange(m) / RATE
    out = np.zeros_like(bus.buf)
    for ch in range(2):
        tail = rng.normal(0, 1, m) * np.exp(-ir_time * 6.9 / seconds)
        tail = lowpass(tail, damp, 1)
        tail /= np.sqrt(np.sum(tail ** 2)) + 1e-9
        ir = np.zeros(n)
        ir[:m] = tail
        out[:, ch] = np.fft.irfft(np.fft.rfft(bus.buf[:, ch]) * np.fft.rfft(ir), n)
    return bus.buf + out * wet


def echo(buf, seconds, feedback, wet, repeats=5):
    delay = int(seconds * RATE)
    out = buf.copy()
    gain = wet
    for i in range(1, repeats + 1):
        # Bounces across channels on every repeat.
        moved = np.roll(buf, delay * i, axis=0)
        out += (moved[:, ::-1] if i % 2 else moved) * gain
        gain *= feedback
    return out


def duck(buf, positions, depth, release):
    """Sidechain: dips the buffer on each kick so the drums punch through."""
    n = len(buf)
    width = int(release * 5 * RATE)
    shape = 1.0 - depth * np.exp(-np.arange(width) / (release * RATE))
    gain = np.ones(n)
    for p in positions:
        idx = (p + np.arange(width)) % n
        gain[idx] = np.minimum(gain[idx], shape)
    return buf * gain[:, None]


# --- Instruments --------------------------------------------------------------
_cache = {}


def cached(key, make):
    if key not in _cache:
        _cache[key] = make()
    return _cache[key]


def i_pad(notes, seconds, bright, seed):
    def make():
        n = int(seconds * RATE)
        out = np.zeros((n, 2))
        r = np.random.default_rng(seed)
        for note in notes:
            f = float(midi_hz(note))
            for ch in range(2):
                for detune in (-0.08, -0.03, 0.04, 0.09):
                    out[:, ch] += saw(f * 2.0 ** (detune / 12.0 * (1 if ch else -1)), n, float(r.random()))
        slow = lowpass(out[:, 0], bright * 0.5), lowpass(out[:, 1], bright * 0.5)
        fast = lowpass(out[:, 0], bright * 1.6), lowpass(out[:, 1], bright * 1.6)
        morph = 0.5 - 0.5 * np.cos(np.linspace(0, 2 * np.pi, n))
        out = np.stack((slow[0] * (1 - morph) + fast[0] * morph, slow[1] * (1 - morph) + fast[1] * morph), axis=1)
        return out * env_ar(n, seconds * 0.22, seconds * 0.4, 1.4)[:, None] * (0.32 / max(1, len(notes)) ** 0.5)
    return cached(("pad", tuple(notes), seconds, bright), make)


def i_bass(note, seconds, cut, drive):
    def make():
        n = int(seconds * RATE)
        f = float(midi_hz(note))
        body = lowpass(saw(f, n) + saw(f * 1.006, n, 0.3), cut)
        return sat((body * 0.8 + sine(f, n)) * env_ar(n, 0.005, 0.05), drive) * 0.6
    return cached(("bass", note, seconds, cut, drive), make)


def i_reese(note, seconds, cut):
    def make():
        n = int(seconds * RATE)
        f = float(midi_hz(note))
        body = saw(f, n) + saw(f * 1.012, n, 0.2) + saw(f * 0.989, n, 0.6)
        return sat(lowpass(body, cut) * 1.4 + sine(f, n) * 0.6, 1.5) * env_ar(n, 0.006, 0.04) * 0.5
    return cached(("reese", note, seconds, cut), make)


def i_pluck(note, seconds, brightness):
    def make():
        n = int(seconds * RATE)
        f = float(midi_hz(note))
        mod = sine(f * 2.0, n) * brightness * decay(n, 16.0)
        return np.sin(2 * np.pi * np.arange(n) * f / RATE + mod) * decay(n, 7.0) * env_ar(n, 0.002, 0.02) * 0.34
    return cached(("pluck", note, seconds, brightness), make)


def i_bell(note, seconds):
    def make():
        n = int(seconds * RATE)
        f = float(midi_hz(note))
        partials = ((1.0, 1.0, 2.2), (2.76, 0.5, 4.0), (5.4, 0.25, 7.0), (8.9, 0.12, 12.0))
        return sum(sine(f * ratio, n) * a * decay(n, rate) for ratio, a, rate in partials) * env_ar(n, 0.002, 0.2) * 0.26
    return cached(("bell", note, seconds), make)


def i_lead(note, seconds, bright):
    def make():
        n = int(seconds * RATE)
        f = float(midi_hz(note))
        vib = f * (1.0 + 0.004 * np.sin(2 * np.pi * 5.2 * np.arange(n) / RATE) * np.minimum(np.arange(n) / (RATE * 0.35), 1.0))
        tone = lowpass(saw(vib, n) * 0.6 + square(vib * 1.003, n, 0.3) * 0.5, bright)
        return sat(tone * 1.6) * env_ar(n, 0.012, min(seconds * 0.5, 0.12)) * 0.26
    return cached(("lead", note, seconds, bright), make)


def i_stab(notes, seconds, bright):
    def make():
        n = int(seconds * RATE)
        out = np.zeros(n)
        for note in notes:
            f = float(midi_hz(note))
            out += saw(f, n) + saw(f * 1.007, n, 0.4)
        out = lowpass(out, bright)
        return sat(out * 0.9, 1.4) * decay(n, 9.0) * env_ar(n, 0.003, 0.03) * 0.3
    return cached(("stab", tuple(notes), seconds, bright), make)


def i_kick(weight=1.0):
    def make():
        n = int(0.42 * RATE)
        f = 42.0 + 165.0 * np.exp(-np.arange(n) / RATE * 40.0)
        click = highpass(np.random.default_rng(5).normal(0, 1, n), 2500) * decay(n, 240.0) * 0.14
        return sat(sine(f, n) * decay(n, 8.5) * 1.4 + click, 1.4) * 0.92
    return cached(("kick", weight), make) * weight


def i_snare():
    def make():
        n = int(0.32 * RATE)
        r = np.random.default_rng(7)
        return sat(bandpass(r.normal(0, 0.8, n), 900, 9000) * decay(n, 15.0) + sine(198, n) * decay(n, 24.0) * 0.7, 1.2) * 0.8
    return cached("snare", make)


def i_hat(open_hat=False):
    def make():
        n = int((0.32 if open_hat else 0.07) * RATE)
        r = np.random.default_rng(9)
        return highpass(r.normal(0, 0.8, n), 7000) * decay(n, 10.0 if open_hat else 70.0) * 0.46
    return cached(("hat", open_hat), make)


def i_metal(pitch):
    def make():
        n = int(0.7 * RATE)
        f = float(midi_hz(pitch))
        r = sum(sine(f * ratio, n) * a * decay(n, 7.0 * (1 + ratio * 0.35)) for ratio, a in ((1.0, 1.0), (1.47, 0.8), (2.09, 0.7), (3.14, 0.5), (4.2, 0.3)))
        return r * 0.24
    return cached(("metal", pitch), make)


def i_tom(note):
    def make():
        n = int(0.34 * RATE)
        f = float(midi_hz(note)) * (1.0 + 0.8 * np.exp(-np.arange(n) / RATE * 30.0))
        return sine(f, n) * decay(n, 11.0) * 0.72
    return cached(("tom", note), make)


# --- Composition --------------------------------------------------------------
class Song:
    def __init__(self, name, bpm, root, scale, prog, seed, **style):
        self.name = name
        self.bpm = bpm
        self.root = root
        self.scale = SCALES[scale]
        self.prog = prog
        self.rng = np.random.default_rng(seed)
        self.seed = seed
        self.bars = style.get("bars", 32)
        self.style = style
        self.step = 60.0 / bpm / 4.0
        self.n = int(round(self.bars * 16 * self.step * RATE))

    def pos(self, bar, step):
        return int(round((bar * 16 + step) * self.step * RATE))

    def note(self, degree, octave=0):
        q, r = divmod(degree, 7)
        return self.root + 12 * (q + octave) + self.scale[r]

    def chord_at(self, bar):
        return self.prog[bar % len(self.prog)]

    def chord(self, degree, count=4, octave=0):
        return [self.note(degree + 2 * i, octave) for i in range(count)]

    def section(self, bar):
        return (bar // 8) % 4

    def melody(self):
        """One four-bar phrase, varied each time: returns (step, length, degree)."""
        r = self.rng
        phrases = []
        for variant in range(3):
            notes = []
            step = 0
            degree = int(r.integers(0, 5))
            while step < 64:
                length = int(r.choice([2, 3, 4, 6, 8], p=[0.22, 0.2, 0.3, 0.14, 0.14]))
                if r.random() > 0.2:
                    notes.append((step, min(length, 64 - step), degree))
                step += length
                degree = int(np.clip(degree + r.choice([-2, -1, 1, 2, 3], p=[0.2, 0.3, 0.3, 0.14, 0.06]), -2, 9))
            phrases.append(notes)
        return phrases


def pattern_hits(pattern):
    return [i for i, ch in enumerate(pattern) if ch != "."]


def render_calm(song):
    st = song.style
    pads = Bus(song.n)
    plucks = Bus(song.n)
    low = Bus(song.n)
    perc = Bus(song.n)
    bar_len = 16 * song.step
    phrases = song.melody()
    for bar in range(song.bars):
        section = song.section(bar)
        deg = song.chord_at(bar)
        if bar % st.get("pad_bars", 2) == 0:
            count = st.get("pad_bars", 2)
            pads.add(i_pad(song.chord(deg, 4, st.get("pad_oct", 1)), bar_len * count * 1.25, st.get("pad_bright", 1100) * (1.0 + 0.3 * (section == 3)), song.seed), song.pos(bar, 0))
        for i in pattern_hits(st.get("calm_bass", "x.......x.......")):
            low.add(i_bass(song.note(deg, st.get("bass_oct", 0)), song.step * 3.0, 300, 1.0), song.pos(bar, i), 0.7)
        arp = st.get("arp", [0, 2, 1, 3])
        rate = st.get("arp_rate", 2)
        if section >= st.get("arp_from", 1):
            for i in range(0, 16, rate):
                tones = song.chord(deg, 4, st.get("arp_oct", 2))
                note = tones[arp[(i // rate) % len(arp)] % len(tones)]
                sound = i_bell(note, 2.2) if st.get("arp_kind") == "bell" else i_pluck(note, 1.3, st.get("arp_fm", 2.4))
                plucks.add(sound, song.pos(bar, i), 0.55 if i % 8 else 0.8, 0.5 * np.sin(i * 0.7 + bar))
        if st.get("calm_metal"):
            for i in pattern_hits(st["calm_metal"]):
                perc.add(i_metal(st.get("metal_note", 74)), song.pos(bar, i), 0.45 if section > 1 else 0.28, float(song.rng.uniform(-0.6, 0.6)))
        if section >= 1 and st.get("calm_hat"):
            for i in pattern_hits(st["calm_hat"]):
                perc.add(i_hat(), song.pos(bar, i), 0.3)
        if st.get("calm_kick") and section >= 2:
            for i in pattern_hits(st["calm_kick"]):
                perc.add(i_kick(), song.pos(bar, i), 0.42)
        if section == 2 and bar % 4 == 0:
            for step, length, degree in phrases[(bar // 4) % 3]:
                b = bar + step // 16
                plucks.add(i_bell(song.note(degree, 3), max(1.5, length * song.step * 3.0)), song.pos(b, step % 16), 0.7, 0.2)
    rng = np.random.default_rng(song.seed + 1)
    mix = reverb(pads, 3.4, 1900, 0.5, rng)
    mix = mix + reverb(Bus_from(echo(plucks.buf, song.step * 3, 0.42, 0.5)), 2.6, 3400, 0.6, rng)
    mix = mix + low.buf + reverb(perc, 1.7, 3000, 0.35, rng)
    return mix


def Bus_from(buffer):
    b = Bus(len(buffer))
    b.buf = buffer
    return b


def render_combat(song):
    st = song.style
    drums = Bus(song.n)
    bass = Bus(song.n)
    stabs = Bus(song.n)
    lead = Bus(song.n)
    kicks = []
    phrases = song.melody()
    song.combat_phrases = phrases
    for bar in range(song.bars):
        section = song.section(bar)
        deg = song.chord_at(bar)
        fill = bar % 8 == 7
        for i in pattern_hits(st["kick"]):
            drums.add(i_kick(), song.pos(bar, i))
            kicks.append(song.pos(bar, i))
        for i in pattern_hits(st["snare"]):
            drums.add(i_snare(), song.pos(bar, i), 0.8, -0.05)
        for i, ch in enumerate(st["hat"]):
            if ch != ".":
                drums.add(i_hat(ch == "o"), song.pos(bar, i), 0.7 if i % 4 == 0 else 0.42, 0.2)
        if fill:
            for i, off in zip((10, 11, 12, 13, 14, 15), (0, 0, -3, -3, -7, -7)):
                drums.add(i_tom(st.get("tom", 50) + off), song.pos(bar, i), 0.75, (i - 12) * 0.12)
        if st.get("metal"):
            for i in pattern_hits(st["metal"]):
                drums.add(i_metal(st.get("metal_note", 74)), song.pos(bar, i), 0.5, 0.45 if i % 2 else -0.45)
        for i, ch in enumerate(st["bass"]):
            if ch != ".":
                note = song.note(deg, st.get("bass_oct", 0) + (1 if ch == "o" else 0))
                length = song.step * st.get("bass_len", 1.8)
                if st.get("reese"):
                    bass.add(i_reese(note, length, st.get("bass_cut", 900)), song.pos(bar, i), 0.85)
                else:
                    bass.add(i_bass(note, length, st.get("bass_cut", 1100), 1.7), song.pos(bar, i))
        if section != 0 or st.get("stab_from_start"):
            for i in pattern_hits(st["stab"]):
                stabs.add(i_stab(song.chord(deg, 3, st.get("stab_oct", 1)), song.step * 3.5, st.get("stab_bright", 2200)), song.pos(bar, i), 0.65, float(song.rng.uniform(-0.3, 0.3)))
        if section >= 2 and bar % 4 == 0:
            for step, length, degree in phrases[(bar // 4) % 3]:
                b = bar + step // 16
                lead.add(i_lead(song.note(degree, st.get("lead_oct", 2)), length * song.step, st.get("lead_bright", 2600)), song.pos(b, step % 16), 1.1)
    rng = np.random.default_rng(song.seed + 2)
    music = reverb(stabs, 1.6, 3600, 0.42, rng) * 1.35 + bass.buf * 0.7
    music = music + reverb(Bus_from(echo(lead.buf, song.step * 3, 0.32, 0.34)), 2.2, 3500, 0.42, rng)
    music = duck(music, kicks, 0.58, 0.085)
    return music + reverb(drums, 0.7, 5000, 0.16, rng), kicks


def i_riser(seconds, seed):
    """Filtered noise that climbs into the downbeat of the next section."""
    def make():
        n = int(seconds * RATE)
        r = np.random.default_rng(seed)
        ramp = np.linspace(0.0, 1.0, n)
        swept = resonant_sweep(r.normal(0, 0.6, n), 300.0 + 5200.0 * ramp ** 2, 0.5)
        return swept * ramp ** 1.6 * 0.5
    return cached(("riser", seconds), make)


def render_intense(song):
    """The top layer for a heavy fight: driving sixteenths, a pumping octave bass, the
    melody an octave up in every section, and a riser into each new eight bars. It
    reuses the combat stem's phrases so the two leads move together."""
    st = song.style
    drums = Bus(song.n)
    bass = Bus(song.n)
    lead = Bus(song.n)
    fx = Bus(song.n)
    kicks = []
    phrases = getattr(song, "combat_phrases", None) or song.melody()
    bar_len = 16 * song.step
    for bar in range(song.bars):
        deg = song.chord_at(bar)
        for i in range(16):
            drums.add(i_hat(i % 4 == 2), song.pos(bar, i), 0.5 if i % 2 else 0.26, 0.35 if i % 2 else -0.35)
        for i in (3, 7, 11, 14):
            drums.add(i_kick(), song.pos(bar, i), 0.55)
            kicks.append(song.pos(bar, i))
        if bar % 4 == 3:
            for i in range(8, 16):
                drums.add(i_snare(), song.pos(bar, i), 0.25 + 0.06 * (i - 8), 0.1)
        for i in range(0, 16, 2):
            note = song.note(deg, st.get("bass_oct", 0) + (1 if i % 4 else 0))
            bass.add(i_reese(note, song.step * 1.6, st.get("bass_cut", 1000) * 1.3), song.pos(bar, i), 0.55)
        if bar % 4 == 0:
            for step, length, degree in phrases[(bar // 4) % 3]:
                b = bar + step // 16
                lead.add(i_lead(song.note(degree, st.get("lead_oct", 2) + 1), length * song.step, st.get("lead_bright", 2600) * 1.2), song.pos(b, step % 16), 0.6, 0.25)
        if bar % 8 == 7:
            fx.add(i_riser(bar_len, song.seed), song.pos(bar, 0), 1.0)
    rng = np.random.default_rng(song.seed + 3)
    music = bass.buf * 0.6 + reverb(Bus_from(echo(lead.buf, song.step * 3, 0.3, 0.3)), 2.0, 3800, 0.4, rng)
    music = duck(music + reverb(fx, 1.2, 6000, 0.3, rng), kicks, 0.45, 0.07)
    return music + reverb(drums, 0.6, 6000, 0.14, rng)


# Pass track names after "--" to render only those.
ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def wanted(name):
    return not ONLY or name in ONLY


def master(buf, target_rms):
    buf = buf - np.mean(buf, axis=0)
    rms = np.sqrt(np.mean(buf ** 2))
    buf = buf * (target_rms / max(rms, 1e-8))
    return np.tanh(buf * 1.05) * 0.97


def export_stems(song, combat):
    """Calm and combat share one gain so the crossfade keeps their balance."""
    if not wanted(song.name):
        return
    calm = render_calm(song)
    if combat:
        fight, _ = render_combat(song)
        joined = calm * 0.75 + fight
        rms = np.sqrt(np.mean(joined ** 2))
        gain = 0.17 / max(rms, 1e-8)
        write_ogg(os.path.join(OUT, song.name + "_calm.ogg"), np.tanh(calm * 0.75 * gain * 1.05) * 0.97)
        write_ogg(os.path.join(OUT, song.name + "_combat.ogg"), np.tanh(fight * gain * 1.05) * 0.97)
        heavy = render_intense(song)
        write_ogg(os.path.join(OUT, song.name + "_intense.ogg"), np.tanh(heavy * gain * 1.05) * 0.97)
        print("[music] %s %.1fs calm+combat+intense" % (song.name, song.n / RATE))
    else:
        write_ogg(os.path.join(OUT, song.name + ".ogg"), master(calm, 0.13))
        print("[music] %s %.1fs" % (song.name, song.n / RATE))
    _cache.clear()


def export_action(song):
    """One stem containing both calm harmony and the full kit, for set pieces."""
    if not wanted(song.name):
        return
    calm = render_calm(song)
    fight, _ = render_combat(song)
    write_ogg(os.path.join(OUT, song.name + ".ogg"), master(calm * 0.55 + fight, 0.2))
    print("[music] %s %.1fs" % (song.name, song.n / RATE))
    _cache.clear()


def sting(name, seconds, notes_list, step, seed, rms):
    if not wanted(name):
        return
    n = int(seconds * RATE)
    bus = Bus(n * 2)
    for i, notes in enumerate(notes_list):
        length = seconds - i * step
        bus.add(i_pad(notes, length, 2200, seed), int(i * step * RATE), 1.6)
        for j, note in enumerate(notes):
            bus.add(i_bell(note + 12, 3.0), int((i * step + j * 0.03) * RATE), 0.8, -0.3 + j * 0.2)
    mixed = reverb(bus, 3.0, 2800, 0.7, np.random.default_rng(seed))[:n]
    fade = np.ones(n)
    fade[-int(0.7 * RATE):] = np.linspace(1, 0, int(0.7 * RATE))
    write_ogg(os.path.join(OUT, name + ".ogg"), master(mixed * fade[:, None], rms))
    print("[music]", name)


# --- Boss themes ----------------------------------------------------------------
# Each boss with its own fight gets one looping track rendered by its own function.
SCALES["locrian"] = [0, 1, 3, 5, 6, 8, 10]


def i_anvil(pitch, seconds=0.9):
    """A hammer on an anvil: a hard transient and a bright, inharmonic ring."""
    def make():
        n = int(seconds * RATE)
        f = float(midi_hz(pitch))
        ring = sum(sine(f * ratio, n) * a * decay(n, rate) for ratio, a, rate in
                   ((1.0, 1.0, 5.0), (2.32, 0.7, 7.0), (3.87, 0.5, 9.0), (5.11, 0.35, 13.0), (7.43, 0.2, 18.0)))
        hit = highpass(np.random.default_rng(pitch).normal(0, 1, n), 1800) * decay(n, 90.0)
        return sat(ring * 0.5 + hit * 0.6, 1.3) * 0.3
    return cached(("anvil", pitch, seconds), make)


def i_thud(weight=1.0):
    """A drop hammer: a sub thump with a gritty iron body on top."""
    def make():
        n = int(0.6 * RATE)
        f = 34.0 + 90.0 * np.exp(-np.arange(n) / RATE * 22.0)
        body = sine(f, n) * decay(n, 6.0)
        grit = bandpass(np.random.default_rng(13).normal(0, 1, n), 120, 1400) * decay(n, 18.0)
        return sat(body * 1.2 + grit * 0.9, 2.2) * 0.7
    return cached("thud", make) * weight


def i_steam(seconds, seed):
    """A vent of steam: bright noise that swells and hisses away."""
    def make():
        n = int(seconds * RATE)
        noise = bandpass(np.random.default_rng(seed).normal(0, 1, n), 2500, 11000)
        return noise * env_ar(n, seconds * 0.15, seconds * 0.8, 2.0) * 0.2
    return cached(("steam", seconds, seed), make)


def i_chain(seconds, seed):
    """Chain links rattling through a pulley: a burst of tiny metal ticks."""
    def make():
        n = int(seconds * RATE)
        r = np.random.default_rng(seed)
        tick = int(0.025 * RATE)
        shape = highpass(r.normal(0, 1, tick * 4), 3000)[:tick] * decay(tick, 160.0)
        out = np.zeros(n)
        for p in np.sort(r.integers(0, n - tick, int(seconds * 28))):
            out[p:p + tick] += shape * r.uniform(0.3, 1.0)
        return out * env_ar(n, 0.01, seconds * 0.6) * 0.3
    return cached(("chain", seconds, seed), make)


def i_grind(note, seconds, cut):
    """The furnace drone: detuned saws through heavy drive, dark and rough."""
    def make():
        n = int(seconds * RATE)
        f = float(midi_hz(note))
        body = saw(f, n) + saw(f * 1.009, n, 0.3) + saw(f * 0.5, n, 0.7) * 0.3
        rough = sat(lowpass(body, cut) * 2.4, 2.0)
        return rough * env_ar(n, seconds * 0.1, seconds * 0.2) * 0.32
    return cached(("grind", note, seconds, cut), make)


def render_crucible(song):
    """The Crucible: a syncopated drop-hammer stomp, two anvils trading blows, a
    chugging overdriven bass and a grinding furnace drone, with chains and steam
    venting between phrases."""
    drums = Bus(song.n)
    metal = Bus(song.n)
    low = Bus(song.n)
    harm = Bus(song.n)
    lead = Bus(song.n)
    kicks = []
    bar_len = 16 * song.step
    phrases = song.melody()
    for bar in range(song.bars):
        section = song.section(bar)
        deg = song.chord_at(bar)
        for i in pattern_hits("x..x..x...x.x..."):
            drums.add(i_thud(1.0 if i in (0, 10) else 0.75), song.pos(bar, i))
            kicks.append(song.pos(bar, i))
        for i in (4, 12):
            drums.add(i_snare(), song.pos(bar, i), 0.7)
            drums.add(i_metal(57), song.pos(bar, i), 0.5, 0.1)
        if bar % 8 == 7:
            for i in (13, 14, 15):
                drums.add(i_thud(0.8), song.pos(bar, i))
        for i, ch in enumerate("..a...b...a.b..b" if section % 2 else "..a.......a...b."):
            if ch != ".":
                metal.add(i_anvil(79 if ch == "a" else 74), song.pos(bar, i), 0.6, -0.5 if ch == "a" else 0.5)
        if section >= 1:
            for i in range(1, 16, 2):
                drums.add(i_hat(i == 7), song.pos(bar, i), 0.28, 0.3)
        if bar % 4 == 1:
            metal.add(i_chain(bar_len * 0.5, 41 + bar % 3), song.pos(bar, 8), 0.8, 0.6 if bar % 8 == 1 else -0.6)
        if bar % 8 == 7:
            metal.add(i_steam(bar_len * 0.9, 31), song.pos(bar, 2), 1.0, 0.0)
        if bar % 2 == 0:
            harm.add(i_grind(song.note(deg, 0), bar_len * 2.05, 220 + 120 * section), song.pos(bar, 0), 0.8)
        for i in pattern_hits("x.xxx.xx.xxx.x.x"):
            low.add(i_bass(song.note(deg, 0), song.step * 0.9, 900, 3.0), song.pos(bar, i), 0.8)
        if section >= 1:
            for i in pattern_hits("x.....x........."):
                root = song.note(deg, 1)
                harm.add(i_stab([root, root + 7, root + 12], song.step * 4, 1400), song.pos(bar, i), 0.7)
        if section >= 2 and bar % 4 == 0:
            for step, length, degree in phrases[(bar // 4) % 3]:
                b = bar + step // 16
                lead.add(i_lead(song.note(degree, 1), length * song.step, 1800), song.pos(b, step % 16), 1.0)
    rng = np.random.default_rng(song.seed + 5)
    music = harm.buf * 0.9 + low.buf * 0.75 + reverb(lead, 1.8, 2400, 0.35, rng) * 1.1
    music = duck(music, kicks, 0.5, 0.09)
    return music + reverb(metal, 2.4, 4200, 0.45, rng) * 1.7 + reverb(drums, 0.9, 3500, 0.2, rng)


def i_blip(note, seconds=0.25):
    """A cold digital tick."""
    def make():
        n = int(seconds * RATE)
        f = float(midi_hz(note))
        return (sine(f, n) + 0.3 * sine(f * 3.01, n)) * decay(n, 22.0) * env_ar(n, 0.001, 0.02) * 0.24
    return cached(("blip", note, seconds), make)


def i_pulse(note, seconds, cut):
    """A narrow pulse bass: hollow and synthetic."""
    def make():
        n = int(seconds * RATE)
        f = float(midi_hz(note))
        tone = lowpass(square(f, n, 0.18) + sine(f, n) * 0.7, cut)
        return tone * env_ar(n, 0.003, seconds * 0.5) * 0.4
    return cached(("pulse", note, seconds, cut), make)


def i_glide(start, end, seconds):
    """A thin, theremin-like sine that slides from one note into the next."""
    def make():
        n = int(seconds * RATE)
        t = np.arange(n) / RATE
        s = np.clip(t / max(seconds * 0.35, 1e-3), 0.0, 1.0)
        notes = start + (end - start) * s * s * (3.0 - 2.0 * s)
        f = midi_hz(notes) * (1.0 + 0.006 * np.sin(2 * np.pi * 4.3 * t))
        return (sine(f, n) + 0.12 * sine(f * 2.0, n)) * env_ar(n, 0.2, seconds * 0.45) * 0.2
    return cached(("glide", start, end, seconds), make)


def render_zero(song):
    """Zero: a sixteenth pulse bass whose filter breathes over two bars, a sub kick
    that pumps everything under it, glass bells in threes against the four, data
    ticks, and a sliding sine voice that never quite lands on the beat."""
    drums = Bus(song.n)
    pulse = Bus(song.n)
    pads = Bus(song.n)
    bells = Bus(song.n)
    voice = Bus(song.n)
    fx = Bus(song.n)
    kicks = []
    bar_len = 16 * song.step
    phrases = song.melody()
    r = np.random.default_rng(song.seed + 7)
    for bar in range(song.bars):
        section = song.section(bar)
        deg = song.chord_at(bar)
        if section == 0:
            beats = (0, 3, 8, 11)
        else:
            beats = (0, 4, 8, 12)
        for i in beats:
            drums.add(i_kick(), song.pos(bar, i), 0.8 if section else 0.55)
            kicks.append(song.pos(bar, i))
        if section >= 1:
            for i in (4, 12):
                drums.add(i_snare(), song.pos(bar, i), 0.35, 0.0)
            for i in range(2, 16, 4):
                drums.add(i_hat(True), song.pos(bar, i), 0.22, -0.3)
        for i in range(16):
            if r.random() < 0.3:
                drums.add(i_blip(int(r.choice([93, 96, 100, 103]))), song.pos(bar, i), 0.5, float(r.uniform(-0.8, 0.8)))
        for i in range(16):
            sweep = 0.5 - 0.5 * np.cos(np.pi * ((bar % 2) * 16 + i) / 16.0)
            cut = int(round(250 + 1650 * sweep, -2))
            octave = 1 if i % 4 == 2 else 0
            pulse.add(i_pulse(song.note(deg, octave), song.step * 0.95, cut), song.pos(bar, i), 1.0 if i % 4 == 0 else 0.7)
        if bar % 4 == 0:
            tones = song.chord(deg, 3, 1)
            pads.add(i_pad(tones + [tones[0] + 1], bar_len * 4.6, 650, song.seed), song.pos(bar, 0), 0.9)
        tones = song.chord(deg, 4, 3)
        for k, i in enumerate(range(0, 16, 3)):
            bells.add(i_bell(tones[(k + bar) % 4], 2.0), song.pos(bar, i), 0.45 if section else 0.3, 0.6 * np.sin(bar * 1.3 + k))
        if section >= 2 and bar % 4 == 0:
            last = None
            for step, length, degree in phrases[(bar // 4) % 3]:
                note = song.note(degree, 2)
                b = bar + step // 16
                voice.add(i_glide(note if last is None else last, note, max(length, 4) * song.step * 1.4), song.pos(b, step % 16), 1.0, 0.15)
                last = note
        if section == 3:
            for i in range(0, 16, 8):
                pulse.add(i_reese(song.note(deg, -1), song.step * 7.5, 400), song.pos(bar, i), 0.5)
        if bar % 8 == 7:
            fx.add(i_riser(bar_len, song.seed), song.pos(bar, 0), 0.8)
    rng = np.random.default_rng(song.seed + 9)
    music = pulse.buf * 0.8 + reverb(pads, 4.0, 1600, 0.6, rng) * 0.9
    music = music + reverb(Bus_from(echo(bells.buf, song.step * 3, 0.5, 0.55)), 3.2, 5000, 0.6, rng)
    music = music + reverb(Bus_from(echo(voice.buf, song.step * 6, 0.4, 0.4)), 3.5, 3000, 0.55, rng) * 1.2
    music = duck(music + reverb(fx, 1.5, 6000, 0.3, rng), kicks, 0.62, 0.11)
    return music + reverb(drums, 1.2, 6000, 0.22, rng)


def export_boss(song, render, rms=0.2):
    """A boss with its own theme: one looping track from its render function."""
    if not wanted(song.name):
        return
    write_ogg(os.path.join(OUT, song.name + ".ogg"), master(render(song), rms))
    print("[music] %s %.1fs" % (song.name, song.n / RATE))
    _cache.clear()


# --- The soundtrack ------------------------------------------------------------
export_stems(Song("shift", 100, 38, "minor", [0, 0, 5, 5, 3, 3, 6, 4], 11,
    pad_oct=1, pad_bright=1000, arp=[0, 2, 1, 3, 2, 1], arp_rate=2, arp_oct=2,
    calm_bass="x.....x.........", calm_hat="....x.......x...",
    kick="x.....x...x.....", snare="....x.......x...", hat="x.x.x.x.x.x.x.xo",
    bass="x.xx..x.x.xx..xo", bass_oct=0, bass_cut=950,
    stab="x.....x.....x...", stab_oct=1, tom=50), True)

export_stems(Song("smelter", 112, 40, "phrygian", [0, 0, 1, 0, 6, 0, 1, 5], 23,
    pad_oct=0, pad_bright=700, arp=[0, 3, 1, 3], arp_rate=4, arp_oct=2, arp_fm=4.0, arp_from=2,
    calm_bass="x.x.....x.x.....", calm_metal="......x.......x.", metal_note=69, calm_kick="x...............",
    kick="x..x..x...x..x..", snare="....x.......x..x", hat="x.xxx.xxx.xxx.xo", metal="..x.....x.....x.",
    bass="xxx.xxx.xxx.x.xo", bass_oct=0, bass_cut=1300, bass_len=1.3,
    stab="x..x....x..x....", stab_oct=0, stab_bright=1500, tom=45), True)

export_stems(Song("glass", 86, 37, "dorian", [0, 2, 5, 3, 0, 6, 5, 4], 37,
    pad_oct=1, pad_bright=1500, arp=[0, 1, 2, 3, 2, 1], arp_rate=2, arp_oct=3, arp_kind="bell",
    calm_bass="x...............", calm_hat="..x...x...x...x.",
    kick="x.......x.x.....", snare="....x.......x...", hat="xxoxxxoxxxoxxxox",
    bass="x.....x...x.....", bass_oct=0, reese=True, bass_len=5.5, bass_cut=650,
    stab=".....x.....x....", stab_oct=2, stab_bright=3200, lead_oct=3, tom=52), True)

export_stems(Song("core", 126, 41, "harmonic", [0, 0, 5, 5, 3, 3, 4, 4], 41,
    pad_oct=0, pad_bright=850, arp=[0, 2, 3, 2, 1, 2, 3, 1], arp_rate=2, arp_oct=2, arp_fm=3.2, arp_from=0,
    calm_bass="x.x...x.x.x...x.", calm_metal="....x.......x...", metal_note=62, calm_kick="x.......x.......",
    kick="x...x...x...x.x.", snare="....x.......x...", hat="x.xxx.xxx.xxx.xo", metal="..x...x...x...x.",
    bass="x.xox.xox.xox.xo", bass_oct=-1, bass_cut=1500, bass_len=1.5,
    stab="x.x...x...x.x...", stab_oct=1, stab_bright=2000, tom=47), True)

export_stems(Song("menu", 70, 45, "minor", [0, 5, 2, 6], 53, bars=24,
    pad_bars=2, pad_oct=0, pad_bright=900, arp=[0, 2, 3, 1], arp_rate=4, arp_oct=2, arp_kind="bell", arp_from=1,
    calm_bass="x..............."), False)

export_action(Song("boss", 150, 43, "phrygian_dominant", [0, 1, 0, 6, 0, 1, 5, 4], 61, bars=32,
    pad_oct=0, pad_bright=1000, arp=[0, 3, 1, 3], arp_rate=2, arp_oct=2, arp_fm=4.5, arp_from=0,
    calm_bass="x...............",
    kick="x..x..x..x..x.x.", snare="....x.......x.xx", hat="xoxoxoxoxoxoxoxo", metal="x...x...x...x...", metal_note=66,
    bass="x.xx.xx.x.xx.xxo", bass_oct=-1, bass_cut=1700, bass_len=1.25,
    stab="x..x..x.......x.", stab_oct=1, stab_bright=2500, stab_from_start=True, lead_oct=2, lead_bright=3400, tom=43))

export_boss(Song("boss_crucible", 132, 38, "phrygian", [0, 0, 1, 0, 0, 0, 6, 1], 97, bars=32), render_crucible, 0.23)

export_boss(Song("boss_zero", 118, 42, "locrian", [0, 0, 1, 1, 5, 5, 3, 6], 101, bars=32), render_zero)

export_action(Song("escape", 174, 34, "minor", [0, 0, 6, 6, 5, 5, 4, 4], 67, bars=48,
    pad_bars=4, pad_oct=1, pad_bright=1300, arp=[0, 1, 2, 3], arp_rate=1, arp_oct=2, arp_fm=3.0, arp_from=0,
    calm_bass="x...............",
    kick="x.x.......x.....", snare="....x.......x...", hat="xxoxxxoxxxoxxxoo", metal="x.......x.......", metal_note=80,
    bass="xxoxxxoxxxoxxxoo", bass_oct=0, bass_cut=1800, bass_len=1.1,
    stab="x.......x.......", stab_oct=1, stab_from_start=True, lead_oct=3, lead_bright=4200, tom=48))

export_stems(Song("story", 62, 40, "minor", [0, 5, 3, 6], 83, bars=20,
    pad_bars=2, pad_oct=0, pad_bright=800, arp=[0, 3, 2, 1], arp_rate=4, arp_oct=2, arp_kind="bell", arp_from=1,
    calm_bass="x..............."), False)

export_stems(Song("ascent", 76, 45, "dorian", [0, 3, 5, 4, 0, 3, 6, 4], 89, bars=24,
    pad_bars=2, pad_oct=1, pad_bright=1700, arp=[0, 2, 1, 3, 2, 1], arp_rate=2, arp_oct=2, arp_fm=1.8, arp_from=0,
    calm_bass="x.......x......."), False)

sting("sting_win", 9.0, [[50, 57, 62, 66], [52, 59, 64, 68], [57, 64, 69, 73]], 2.4, 71, 0.15)
sting("sting_lose", 7.0, [[45, 48, 52], [41, 44, 48], [40, 43, 46]], 1.9, 73, 0.11)
print("[music] done")

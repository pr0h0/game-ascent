"""Small numpy synthesiser shared by the sound-effect and music generators."""
import os
import subprocess
import wave

import numpy as np

RATE = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def secs(duration):
    return np.arange(int(duration * RATE)) / RATE


def midi_hz(note):
    return 440.0 * 2.0 ** ((np.asarray(note, dtype=float) - 69.0) / 12.0)


def phase_of(freq, n):
    """Phase in cycles for a constant or per-sample frequency."""
    if np.ndim(freq) == 0:
        return np.arange(n) * float(freq) / RATE
    return np.cumsum(freq) / RATE


def sine(freq, n, offset=0.0):
    return np.sin(2 * np.pi * (phase_of(freq, n) + offset))


def saw(freq, n, offset=0.0):
    """Band-limited sawtooth using a polyBLEP correction at each wrap."""
    p = (phase_of(freq, n) + offset) % 1.0
    dt = np.full(n, float(freq) / RATE) if np.ndim(freq) == 0 else np.asarray(freq) / RATE
    out = 2.0 * p - 1.0
    low = p < dt
    high = p > 1.0 - dt
    x = p[low] / dt[low]
    out[low] -= x + x - x * x - 1.0
    x = (p[high] - 1.0) / dt[high]
    out[high] -= x * x + x + x + 1.0
    return out


def square(freq, n, width=0.5, offset=0.0):
    return saw(freq, n, offset) - saw(freq, n, offset + width)


def lowpass(x, cutoff, order=2):
    """Zero-phase Butterworth-shaped low-pass, for a fixed cutoff."""
    if len(x) < 4:
        return x
    freqs = np.fft.rfftfreq(len(x), 1.0 / RATE)
    response = 1.0 / np.sqrt(1.0 + (freqs / max(cutoff, 1.0)) ** (2 * order))
    return np.fft.irfft(np.fft.rfft(x) * response, len(x))


def highpass(x, cutoff, order=2):
    if len(x) < 4:
        return x
    freqs = np.fft.rfftfreq(len(x), 1.0 / RATE)
    response = 1.0 / np.sqrt(1.0 + (max(cutoff, 1.0) / np.maximum(freqs, 1e-3)) ** (2 * order))
    return np.fft.irfft(np.fft.rfft(x) * response, len(x))


def bandpass(x, low, high):
    return highpass(lowpass(x, high), low)


def resonant_sweep(x, cutoff, resonance=0.25):
    """State-variable low-pass whose cutoff follows an array. Sample-by-sample."""
    cut = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    coef = 2.0 * np.sin(np.pi * np.clip(cut, 10.0, RATE / 6.2) / RATE)
    out = np.zeros(len(x))
    lo = band = 0.0
    for i, v in enumerate(x):
        lo += coef[i] * band
        band += coef[i] * (v - lo - resonance * band)
        out[i] = lo
    return out


def env_ar(n, attack, release, curve=1.0):
    """Attack in seconds, then a release curve across the remaining samples."""
    a = min(n, max(1, int(attack * RATE)))
    rel = int(release * RATE)
    out = np.ones(n)
    out[:a] = np.linspace(0.0, 1.0, a)
    rel = min(rel, n - a)
    if rel > 0:
        out[n - rel:] = np.linspace(1.0, 0.0, rel) ** curve
    return out


def decay(n, rate):
    return np.exp(-np.arange(n) / RATE * rate)


def sat(x, drive=1.0):
    return np.tanh(x * drive)


def pan_stereo(x, pan):
    angle = (pan + 1.0) * np.pi / 4.0
    return np.stack((x * np.cos(angle), x * np.sin(angle)), axis=1)


def write_wav(path, x, peak=None):
    x = np.asarray(x, dtype=float)
    if peak is not None:
        x = x / max(np.max(np.abs(x)), 1e-6) * peak
    x = np.clip(x, -1.0, 1.0)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    channels = 1 if x.ndim == 1 else x.shape[1]
    with wave.open(path, "wb") as f:
        f.setnchannels(channels)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((x * 32767).astype(np.int16).tobytes())


def write_ogg(path, stereo, quality=4):
    """Encodes through ffmpeg; the temporary WAV is removed afterwards."""
    temp = path + ".tmp.wav"
    try:
        write_wav(temp, stereo)
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", temp, "-c:a", "libvorbis", "-qscale:a", str(quality), path],
            check=True,
        )
    finally:
        if os.path.exists(temp):
            os.remove(temp)

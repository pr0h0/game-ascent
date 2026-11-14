"""Synthesises every sound effect and looping bed as 16-bit mono WAV (numpy only)."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from synth import (RATE, ROOT, bandpass, decay, env_ar, highpass, lowpass, midi_hz, phase_of, resonant_sweep, sat, saw, secs, sine, square, write_wav)

OUT = os.path.join(ROOT, "assets", "audio")
rng = np.random.default_rng(99)


def noise(n):
    return rng.normal(0, 0.5, n)


def save(name, x, peak=0.9):
    write_wav(os.path.join(OUT, name + ".wav"), x, peak)
    print("[audio]", name)


def glide(a, b, n, curve=1.0):
    return a + (b - a) * np.linspace(0.0, 1.0, n) ** curve


def seamless(x, fade=0.25):
    """Crossfades the tail into the head so the sample loops without a click."""
    n = int(fade * RATE)
    r = np.linspace(0, 1, n)
    head = x[:n] * r + x[-n:] * (1 - r)
    return np.concatenate((head, x[n:-n]))


def at(buffer, start, sound, gain=1.0):
    """Mixes a sound into a buffer at a time in seconds, clipping any overflow."""
    i = int(start * RATE)
    end = min(len(buffer), i + len(sound))
    if end > i:
        buffer[i:end] += sound[: end - i] * gain


def blast(seconds, brightness, body_hz, tail):
    """Layered explosion: crack, low-passed roar, and a falling sub thump."""
    n = int(seconds * RATE)
    crack = highpass(noise(n), 1500) * decay(n, 55.0)
    roar = resonant_sweep(noise(n), brightness * np.exp(-secs(seconds) * 3.2 / max(seconds, 0.6)) + 70.0, 0.5) * decay(n, tail)
    sub = sine(glide(body_hz * 2.2, body_hz * 0.55, n, 0.45), n) * decay(n, tail * 1.1)
    grit = sat(lowpass(noise(n), 500) * 8.0) * decay(n, tail * 2.2)
    return sat(crack * 1.1 + roar * 3.5 + sub * 1.1 + grit * 0.5, 1.2)


def chirp(notes, step, ring, partial=0.35):
    """Rising confirmation tones, each ringing into the next."""
    n = int((len(notes) * step + 1.0 / ring * 4.0) * RATE)
    out = np.zeros(n)
    for i, note in enumerate(notes):
        m = n - int(i * step * RATE)
        f = float(midi_hz(note))
        tone = (sine(f, m) + partial * sine(f * 2.0, m) + partial * 0.3 * sine(f * 3.01, m)) * decay(m, ring) * np.minimum(np.arange(m) / 80.0, 1.0)
        at(out, i * step, tone)
    return out


def metal_ping(n, base, rate):
    partials = ((1.0, 1.0), (2.76, 0.6), (5.4, 0.4), (8.93, 0.25))
    return sum(sine(base * r, n) * a * decay(n, rate * (1.0 + r * 0.4)) for r, a in partials)


# --- Player weapons -----------------------------------------------------------
def laser(top, bottom, length, body):
    n = int(length * RATE)
    sweep = glide(top, bottom, n, 0.45)
    tone = sine(sweep, n) + body * square(sweep * 0.5, n) * 0.5 + highpass(noise(n), 3500) * 0.14 * decay(n, 60.0)
    return tone * decay(n, 6.0 / length) * np.minimum(np.arange(n) / 30.0, 1.0)


save("laser_1", laser(1700, 330, 0.2, 0.5), 0.55)
save("laser_2", laser(1450, 240, 0.22, 0.75), 0.58)
save("laser_3", laser(1150, 170, 0.25, 1.05), 0.62)
save("laser_4", laser(2100, 120, 0.28, 1.35) + laser(1050, 90, 0.28, 0.7) * 0.6, 0.66)

n = int(0.36 * RATE)
save("cutter", (bandpass(noise(n) * 4.0 + saw(glide(240, 90, n), n), 300, 5200) + sine(glide(95, 55, n), n) * 0.7) * env_ar(n, 0.008, 0.28), 0.8)

n = int(0.42 * RATE)
crackle = (rng.random(n) > 0.82) * 1.0
crackle = lowpass(crackle, 7000) * 3.0
save("arc", sat((highpass(noise(n), 2200) * 0.7 + crackle) * (0.55 + 0.45 * square(float(rng.uniform(55, 75)), n)) + sine(120, n) * 0.4) * decay(n, 9.0), 0.72)

n = int(1.5 * RATE)
charge = glide(90, 1500, n, 1.8)
save("rail_charge", (sine(charge, n) + 0.5 * square(charge * 0.5, n) * 0.3 + highpass(noise(n), 4000) * 0.12) * env_ar(n, 0.04, 0.03) * np.linspace(0.45, 1.0, n), 0.5)
n = int(0.95 * RATE)
crack = highpass(noise(n), 900) * decay(n, 28.0) * 2.0
save("rail_fire", sat(crack + sine(glide(2600, 60, n, 0.22), n) * decay(n, 8.0) + sine(glide(120, 38, n), n) * decay(n, 6.0) * 1.2, 1.4), 0.92)

n = int(0.17 * RATE)
save("prism", (sine(glide(2400, 1500, n), n) + sine(glide(3650, 2300, n), n) * 0.6 + sine(glide(5900, 3600, n), n) * 0.3) * decay(n, 24.0), 0.5)
n = int(0.2 * RATE)
save("prism_bounce", (sine(3100, n) + sine(4670, n) * 0.6 + sine(7300, n) * 0.25) * decay(n, 38.0), 0.32)

n = int(1.3 * RATE)
save("singularity_fire", sat(sine(glide(620, 28, n, 0.32), n) * decay(n, 2.6) * 1.8 + lowpass(noise(n), 360) * decay(n, 3.4) * 4.0 + saw(glide(90, 24, n), n) * 0.35 * decay(n, 3.0)), 0.95)
t = secs(3.0)
n = len(t)
save("singularity_loop", seamless((sine(42 + 7 * np.sin(2 * np.pi * t), n) + 0.5 * sine(84, n) + lowpass(noise(n), 280) * 3.4) * (0.75 + 0.25 * np.sin(2 * np.pi * 2.0 * t)), 0.2), 0.85)
n = int(1.8 * RATE)
save("singularity_burst", sat(blast(1.8, 700, 34, 2.2) + sine(glide(70, 700, n, 3.0), n) * decay(n, 9.0) * 0.7), 1.0)

# --- Missiles and mines -------------------------------------------------------
n = int(0.75 * RATE)
save("missile", sat(lowpass(noise(n), 2600) * 3.2 * np.minimum(np.arange(n) / 500.0, 1.0) * decay(n, 3.2) + sine(glide(170, 430, n, 0.7), n) * 0.55 * decay(n, 3.6)), 0.88)
n = int(0.62 * RATE)
save("missile_cluster", sat(lowpass(noise(n), 1500) * 3.0 * decay(n, 4.2) + square(glide(110, 240, n), n) * 0.35 * decay(n, 4.8)), 0.88)
n = int(0.5 * RATE)
sw = np.zeros(int(0.85 * RATE))
for i in range(8):
    tiny = lowpass(noise(int(0.16 * RATE)), 3800) * decay(int(0.16 * RATE), 22.0) * 1.6 + sine(glide(420 + i * 45, 950, int(0.16 * RATE)), int(0.16 * RATE)) * decay(int(0.16 * RATE), 26.0) * 0.5
    at(sw, i * 0.075, tiny, 0.72 + 0.04 * i)
save("missile_swarm", sw, 0.85)
n = int(1.25 * RATE)
save("missile_bunker", sat(lowpass(noise(n), 700) * 5.0 * np.minimum(np.arange(n) / 2500.0, 1.0) * decay(n, 1.9) + saw(glide(52, 110, n), n) * 0.5 * decay(n, 2.2), 1.3), 0.95)
n = int(1.6 * RATE)
save("emp", sat(sine(glide(1900, 55, n, 0.3), n) * decay(n, 4.0) * 1.1 + highpass(noise(n), 1600) * 0.9 * decay(n, 12.0) * (0.5 + 0.5 * square(38.0, n)) + sine(glide(90, 40, n), n) * decay(n, 3.0)), 0.92)
n = int(0.35 * RATE)
save("mine_drop", (metal_ping(n, 410, 15.0) + lowpass(noise(n), 900) * decay(n, 34.0) * 1.2), 0.7)
n = int(0.13 * RATE)
save("mine_beep", (square(1320, n) * 0.4 + sine(1320, n)) * decay(n, 18.0), 0.5)
n = int(0.28 * RATE)
save("mine_arm", np.concatenate((sine(880, int(0.1 * RATE)) * 0.7, sine(1320, n - int(0.1 * RATE)) * decay(n - int(0.1 * RATE), 18.0))), 0.55)
n = int(0.9 * RATE)
save("pulse_mine", sat(square(glide(220, 40, n, 0.4), n) * decay(n, 5.0) * 0.8 + highpass(noise(n), 3000) * 0.8 * decay(n, 12.0) * (0.5 + 0.5 * square(24.0, n))), 0.9)

n = int(0.6 * RATE)
save("flare", (highpass(noise(n), 2400) * 0.8 + sine(glide(600, 1400, n, 0.5), n) * 0.3 * decay(n, 7.0)) * env_ar(n, 0.012, 0.45), 0.52)

# --- Explosions ----------------------------------------------------------------
save("explode_tiny", blast(0.55, 4200, 110, 8.0), 0.85)
save("explode_small", blast(1.05, 3200, 70, 4.5), 0.95)
save("explode_medium", blast(1.8, 2500, 52, 2.7), 1.0)
save("explode_big", blast(3.4, 1900, 42, 1.3), 1.0)
tail = blast(5.5, 1500, 33, 0.85)
for start in (0.3, 0.75, 1.3, 2.1):
    at(tail, start, blast(1.5, 2500, 60, 3.0), 0.7)
save("explode_boss", tail, 1.0)

# --- Robots --------------------------------------------------------------------
n = int(0.28 * RATE)
save("enemy_shot", (square(glide(760, 170, n, 0.5), n) * 0.65 + sine(glide(1200, 300, n, 0.5), n) * 0.35 + noise(n) * 0.1) * decay(n, 12.0), 0.5)
n = int(0.42 * RATE)
save("enemy_shot_heavy", sat((saw(glide(420, 62, n, 0.45), n) + sine(glide(210, 40, n, 0.5), n) * 0.8 + lowpass(noise(n), 2000) * 0.8) * decay(n, 8.0), 1.2), 0.62)
n = int(0.2 * RATE)
save("enemy_shot_fast", (square(glide(1400, 480, n, 0.5), n) * 0.5 + sine(glide(1900, 900, n), n) * 0.5) * decay(n, 20.0), 0.42)


machine_rng = np.random.default_rng(7)


def machine_noise(n):
    """Own generator, so changing these sounds leaves every other sample as it was."""
    return machine_rng.normal(0, 0.5, n)


def machine_alert(rpm, dur, whine, weight):
    """A robot waking up: a clunk, a motor revving with its firing pulses, a servo
    whine on top and a hiss of hydraulics. Pitch and weight follow the robot's size."""
    n = int(dur * RATE)
    rev = glide(rpm * 0.55, rpm, n, 0.4) * (1.0 + 0.05 * sine(5.0, n))
    pulse = 0.55 + 0.45 * square(rev / 6.0, n, 0.35)
    motor = lowpass(saw(rev, n) + saw(rev * 2.01, n) * 0.45 + square(rev * 0.5, n) * 0.5, rpm * 6.0) * pulse
    servo = sine(glide(whine * 0.6, whine, n, 0.5), n) * (0.6 + 0.4 * sine(13.0, n)) * 0.22
    hiss = bandpass(machine_noise(n), 1800, 7000) * decay(n, 9.0) * 0.22
    clunk = (lowpass(machine_noise(n), 400) * 1.6 * decay(n, 40.0) + metal_ping(n, 140 / weight, 18.0) * 0.5)
    body = motor * env_ar(n, 0.05, dur * 0.45) + servo * env_ar(n, 0.1, dur * 0.3) + hiss
    return sat((body + clunk * weight) * 1.2)


save("robot_alert_small", machine_alert(95, 0.5, 2400, 0.6), 0.55)
save("robot_alert_mid", machine_alert(62, 0.65, 1500, 1.0), 0.6)
save("robot_alert_big", machine_alert(34, 0.9, 820, 1.6), 0.72)
n = int(0.5 * RATE)
save("robot_saw", seamless(bandpass(saw(195, n) + saw(392, n) * 0.5 + noise(n) * 0.35, 220, 4200) * (0.65 + 0.35 * square(38.0, n)), 0.03), 0.65)
n = int(0.22 * RATE)
save("melee_hit", sat(highpass(noise(n), 700) * 1.4 * decay(n, 34.0) + metal_ping(n, 620, 22.0) * 0.8 + sine(glide(190, 70, n), n) * decay(n, 24.0), 1.5), 0.92)
n = int(0.9 * RATE)
save("cinder_arm", (square(glide(320, 1900, n, 2.0), n) * 0.5 + sine(glide(640, 3800, n, 2.0), n) * 0.5) * (0.5 + 0.5 * square(glide(9, 34, n), n)), 0.45)
n = int(0.55 * RATE)
save("blink", (sine(glide(200, 2800, n, 3.0), n) + sine(glide(2800, 180, n, 0.35), n)) * env_ar(n, 0.01, 0.2) + highpass(noise(n), 4800) * 0.12, 0.55)
n = int(0.7 * RATE)
save("cloak", (sine(glide(1700, 240, n, 0.5), n) * (0.55 + 0.45 * sine(31.0, n)) + highpass(noise(n), 5000) * 0.24) * env_ar(n, 0.02, 0.5), 0.5)
save("uncloak", (sine(glide(240, 1700, n, 1.8), n) * (0.55 + 0.45 * sine(31.0, n)) + highpass(noise(n), 5000) * 0.24) * env_ar(n, 0.3, 0.1), 0.5)
n = int(0.5 * RATE)
save("heal", (sine(880, n) * (0.5 + 0.5 * sine(9.0, n)) + sine(1320, n) * 0.4) * env_ar(n, 0.05, 0.3), 0.34)
n = int(0.75 * RATE)
save("hive_spawn", sat(lowpass(noise(n), 1100) * 2.5 * (0.5 + 0.5 * square(14.0, n)) * env_ar(n, 0.04, 0.3) + sine(glide(70, 180, n), n) * 0.6 * env_ar(n, 0.02, 0.5)), 0.72)

n = int(2.1 * RATE)
roar = bandpass(saw(glide(68, 44, n, 0.6), n) + saw(glide(102.5, 66, n, 0.6), n) + noise(n) * 0.5, 45, 1500)
save("boss_roar", sat(roar * (0.7 + 0.3 * square(23.0, n)) * env_ar(n, 0.12, 0.9) * 2.4), 1.0)
n = int(1.6 * RATE)
save("boss_phase", sat(metal_ping(n, 160, 2.6) * 1.2 + sine(glide(52, 30, n), n) * decay(n, 2.2) * 1.6 + lowpass(noise(n), 900) * decay(n, 6.0) * 2.0), 1.0)
n = int(0.6 * RATE)
save("reactor_hit", sat(metal_ping(n, 270, 8.0) + sine(70, n) * decay(n, 7.0) * 1.1), 0.75)

# --- Impacts --------------------------------------------------------------------
n = int(0.12 * RATE)
save("hit", (noise(n) * 0.7 + sine(2300, n) * 0.5 + sine(3170, n) * 0.35) * decay(n, 42.0), 0.42)
n = int(0.1 * RATE)
save("hit_wall", (bandpass(noise(n), 500, 4000) * 1.5 + sine(glide(420, 170, n), n) * 0.5) * decay(n, 58.0), 0.42)
n = int(0.1 * RATE)
save("hit_confirm", (sine(1760, n) + sine(2637, n) * 0.5) * decay(n, 40.0), 0.3)
save("kill_confirm", chirp([84, 91], 0.055, 22.0), 0.34)
n = int(0.42 * RATE)
save("player_hurt", sat(lowpass(noise(n), 1100) * 3.0 * decay(n, 13.0) + metal_ping(n, 210, 11.0) * 0.8 + sine(glide(210, 80, n), n) * decay(n, 12.0)), 0.8)
n = int(0.5 * RATE)
save("shield_absorb", (sine(glide(620, 1300, n, 0.7), n) * decay(n, 10.0) + highpass(noise(n), 4000) * 0.24 * decay(n, 16.0)) * (0.65 + 0.35 * sine(75.0, n)), 0.4)
n = int(0.32 * RATE)
save("wall_bump", sat(lowpass(noise(n), 700) * 3.0 * decay(n, 18.0) + sine(glide(120, 52, n), n) * decay(n, 15.0) * 1.2 + metal_ping(n, 165, 16.0) * 0.45), 0.8)
n = int(0.7 * RATE)
save("wall_scrape", seamless(bandpass(noise(n) * 2.0 + square(73, n) * 0.25, 650, 5200) * (0.7 + 0.3 * sine(19.0, n)), 0.05), 0.5)
n = int(0.5 * RATE)
save("shield_low", (square(760, n) * 0.25 + sine(760, n)) * ((secs(0.5) * 8 % 1.0) < 0.5) * env_ar(n, 0.004, 0.02), 0.36)
n = int(1.2 * RATE)
save("player_die", sat(blast(1.2, 3200, 58, 3.4) + sine(glide(1500, 80, n, 0.25), n) * decay(n, 3.6) * 0.8), 1.0)
n = int(1.1 * RATE)
save("respawn", (sine(glide(170, 980, n, 0.55), n) + sine(glide(255, 1470, n, 0.55), n) * 0.5 + highpass(noise(n), 5000) * 0.1) * env_ar(n, 0.04, 0.5), 0.55)
n = int(0.9 * RATE)
save("afterburner", (lowpass(noise(n), 1700) * 3.2 + sine(glide(70, 150, n), n) * 0.9) * env_ar(n, 0.02, 0.6), 0.78)
n = int(2.0 * RATE)
save("afterburner_loop", seamless(lowpass(noise(n), 1500) * 2.8 + sine(92, n) * 0.5, 0.1), 0.7)
click_a = int(0.05 * RATE)
click_b = int(0.08 * RATE)
save("weapon_select", np.concatenate((square(1120, click_a) * decay(click_a, 60.0), np.zeros(int(0.03 * RATE)), sine(1680, click_b) * decay(click_b, 38.0))), 0.34)
n = int(0.3 * RATE)
save("weapon_empty", square(180, n) * decay(n, 14.0) * 0.8 + noise(n) * 0.1 * decay(n, 40.0), 0.34)

# --- Pickups and progress -------------------------------------------------------
save("pickup", chirp([72, 79, 84], 0.075, 11.0), 0.55)
save("pickup_energy", chirp([67, 74, 79, 86], 0.045, 15.0, 0.2), 0.5)
save("pickup_shield", chirp([60, 67, 72, 76], 0.06, 12.0, 0.5), 0.56)
save("pickup_ammo", np.concatenate((metal_ping(int(0.1 * RATE), 900, 26.0), metal_ping(int(0.22 * RATE), 1250, 18.0))), 0.56)
save("pickup_upgrade", chirp([60, 67, 72, 79, 84, 91], 0.085, 5.5, 0.55), 0.72)
power_tone = chirp([62, 69, 74, 81, 86], 0.06, 3.0, 0.75)
save("pickup_power", power_tone * (0.8 + 0.2 * sine(14.0, len(power_tone))), 0.7)
save("power_ending", chirp([84, 79, 84, 79], 0.14, 14.0), 0.4)
save("key", chirp([55, 62, 67, 74, 79], 0.13, 4.2, 0.45), 0.72)
save("secret", chirp([64, 71, 76, 79, 83, 88], 0.11, 4.0, 0.3) + chirp([52, 59, 64, 67, 71, 76], 0.11, 4.0, 0.3), 0.7)
save("astronaut", chirp([69, 74, 78, 81], 0.1, 6.0, 0.25), 0.55)

n = int(1.4 * RATE)
door = lowpass(square(58, n) * 0.5 + noise(n) * 0.5, 800) * env_ar(n, 0.08, 0.18)
at(door, 0.0, metal_ping(int(0.3 * RATE), 300, 14.0), 0.8)
at(door, 1.15, lowpass(noise(int(0.24 * RATE)), 500) * decay(int(0.24 * RATE), 20.0), 2.6)
save("door", door, 0.65)
n = int(1.1 * RATE)
save("door_secret", lowpass(noise(n) * 2.0 + square(36, n) * 0.6, 420) * env_ar(n, 0.15, 0.3) + metal_ping(n, 130, 5.0) * 0.45, 0.72)
n = int(0.32 * RATE)
save("denied", np.concatenate((square(160, int(0.12 * RATE)), np.zeros(int(0.05 * RATE)), square(120, n - int(0.17 * RATE)))) * env_ar(n, 0.002, 0.04), 0.42)

# --- Mine atmosphere: scattered at random around the player -----------------------
n = int(1.7 * RATE)
save("mine_creak", bandpass(square(glide(44, 67, n), n) * (rng.random(n) > 0.7), 180, 1400) * env_ar(n, 0.3, 0.9), 0.52)
n = int(0.5 * RATE)
save("mine_drip", sine(glide(1300, 2100, n, 0.3), n) * decay(n, 30.0), 0.4)
n = int(3.2 * RATE)
save("mine_rumble", lowpass(noise(n), 140) * 4.5 * env_ar(n, 0.7, 1.9), 0.7)
n = int(1.3 * RATE)
save("mine_clank", metal_ping(n, 196, 3.6) + metal_ping(n, 311, 5.0) * 0.5, 0.6)
n = int(3.6 * RATE)
save("mine_steam", highpass(noise(n), 1300) * env_ar(n, 0.5, 2.0) * (0.8 + 0.2 * sine(3.0, n)), 0.42)

# --- Interface ---------------------------------------------------------------------
n = int(0.05 * RATE)
save("ui_hover", sine(1560, n) * decay(n, 80.0), 0.2)
n = int(0.1 * RATE)
save("ui_click", (sine(1040, n) + sine(1560, n) * 0.5) * decay(n, 42.0), 0.42)
n = int(0.14 * RATE)
save("ui_back", sine(glide(780, 440, n), n) * decay(n, 24.0), 0.36)
save("ui_start", chirp([50, 57, 62, 69, 74], 0.09, 3.2, 0.5), 0.6)
n = int(0.4 * RATE)
save("map_open", (sine(glide(280, 1060, n, 0.6), n) + highpass(noise(n), 4000) * 0.15) * env_ar(n, 0.01, 0.24), 0.42)
save("map_close", (sine(glide(1060, 280, n, 0.6), n) + highpass(noise(n), 4000) * 0.15) * env_ar(n, 0.01, 0.24), 0.42)

# --- Loops ---------------------------------------------------------------------------
t = secs(1.2)
# The sweep's phase is integrated (phase_of), so the pitch really goes 520 -> 880 -> 520 Hz.
save("alarm", seamless(np.sign(np.sin(2 * np.pi * phase_of(np.interp(t, [0, 0.6, 1.2], [520, 880, 520]), len(t)))) * 0.5 * (0.7 + 0.3 * np.sin(2 * np.pi * 5 * t)), 0.02), 0.5)
n = int(1.0 * RATE)
save("countdown_tick", (sine(1240, n) * 0.8 + metal_ping(n, 1860, 26.0) * 0.5) * decay(n, 13.0), 0.5)
t = secs(5.25)
n = len(t)
hum = sum(sine(f, n) * a for f, a in ((47, 1.0), (94.3, 0.45), (141, 0.25), (283, 0.08)))
hiss = lowpass(noise(n), 2100) * 1.1
whine = sine(1880, n) * 0.022 + sine(2820, n) * 0.012
save("engine", seamless(hum * (0.8 + 0.2 * np.sin(2 * np.pi * 4 * t)) + hiss + whine), 0.8)


def bed(seconds, tones, air_cut, air_gain, name, peak):
    t_ = secs(seconds)
    m = len(t_)
    drone = sum(sine(f, m, ph) * a for f, a, ph in tones)
    air = lowpass(noise(m), air_cut) * air_gain * (0.7 + 0.3 * np.sin(2 * np.pi * t_ / seconds))
    save(name, seamless(drone * (0.72 + 0.28 * np.sin(2 * np.pi * t_ / (seconds / 2.0))) + air, 1.2), peak)


bed(14.25, ((36, 1.0, 0), (54.3, 0.55, 0.16), (73, 0.3, 0.32), (110.4, 0.15, 0.48)), 340, 5.0, "ambience", 0.6)
bed(16.0, ((30, 1.0, 0), (45.2, 0.7, 0.1), (61, 0.25, 0.7), (92.5, 0.16, 0.4)), 200, 6.5, "ambience_deep", 0.62)
bed(13.0, ((48, 0.6, 0), (72.1, 0.4, 0.3), (1460, 0.018, 0.2), (2191, 0.012, 0.6)), 620, 3.6, "ambience_glass", 0.5)
t = secs(4.0)
n = len(t)
save("reactor_hum", seamless(sum(sine(f, n) * a for f, a in ((60, 1), (120, 0.7), (181, 0.3), (1200, 0.04))) * (0.75 + 0.25 * np.sin(2 * np.pi * 2.5 * t)), 0.2), 0.8)
t = secs(6.25)
n = len(t)
rumble = lowpass(noise(n), 260) * 10.0 + lowpass(noise(n), 1500) * 2.2
save("fire_roar", seamless(rumble * (0.8 + 0.2 * np.sin(2 * np.pi * 3 * t)), 0.4), 0.95)
# --- Radio for the story scenes ------------------------------------------------------
n = int(0.28 * RATE)
save("comm_open", (bandpass(noise(n) * 2.0, 900, 4200) * env_ar(n, 0.01, 0.08) + sine(1560, n) * 0.35 * decay(n, 18.0)), 0.42)
n = int(0.22 * RATE)
save("comm_close", (bandpass(noise(n) * 2.0, 900, 4200) * env_ar(n, 0.005, 0.12) + sine(glide(1100, 700, n), n) * 0.3 * decay(n, 14.0)), 0.38)
n = int(0.035 * RATE)
save("comm_blip", bandpass(square(830, n) + noise(n) * 0.5, 700, 3600) * decay(n, 80.0), 0.3)
# --- Robot engines and guns: one voice per class ----------------------------------------
# Everything below draws from its own generator, so adding sounds here never changes
# the samples above.
voice_rng = np.random.default_rng(31)


def vnoise(n):
    return voice_rng.normal(0, 0.5, n)


def loop_tone(freq, seconds):
    """A frequency nudged to a whole number of cycles in the loop, so it wraps cleanly."""
    return max(1.0, round(freq * seconds)) / seconds


def engine_loop(seconds, layers):
    n = int(seconds * RATE)
    out = sum(layer(n) for layer in layers)
    return seamless(out, 0.12)


L = 2.0  # loop length for the engines; every modulation rate below fits it exactly.
t = secs(L + 0.12)
n_loop = len(t)

# Small fast robots: an insect buzz, a two-stroke motor with a whine on top.
buzz_f = loop_tone(176, L)
save("hum_buzz", engine_loop(L + 0.12, [
    lambda n: lowpass(saw(buzz_f, n) + saw(buzz_f * 1.502, n) * 0.4, 2600) * (0.6 + 0.4 * sine(loop_tone(31, L), n)) * 0.8,
    lambda n: sine(loop_tone(1240, L), n) * 0.08 * (0.7 + 0.3 * sine(loop_tone(3, L), n)),
    lambda n: bandpass(vnoise(n), 1500, 6000) * 0.25,
]), 0.6)

# Melee robots: a chopping rotor, air beaten into pulses, and a grinding gearbox.
chop = loop_tone(17, L)
save("hum_rotor", engine_loop(L + 0.12, [
    lambda n: bandpass(vnoise(n) * 3.0, 200, 2400) * (0.35 + 0.65 * np.clip(sine(chop, n), 0, 1) ** 3),
    lambda n: lowpass(saw(loop_tone(68, L), n), 500) * 0.45,
    lambda n: square(loop_tone(137, L), n, 0.2) * 0.06 * (0.5 + 0.5 * sine(loop_tone(5, L), n)),
]), 0.62)

# Gunships: a turbine whine over a soft jet rush.
save("hum_turbine", engine_loop(L + 0.12, [
    lambda n: (sine(loop_tone(820, L), n) + sine(loop_tone(1230, L), n) * 0.5 + sine(loop_tone(2465, L), n) * 0.15) * 0.16 * (0.8 + 0.2 * sine(loop_tone(1.5, L), n)),
    lambda n: lowpass(vnoise(n), 900) * 1.6,
    lambda n: sine(loop_tone(55, L), n) * 0.35,
]), 0.55)

# Arc robots: mains hum and the crackle of a coil that never quite discharges.
crackle_v = lowpass((voice_rng.random(n_loop) > 0.985) * 1.0, 6000) * 3.0
save("hum_arc", engine_loop(L + 0.12, [
    lambda n: (square(loop_tone(100, L), n, 0.3) * 0.3 + sine(loop_tone(200, L), n) * 0.4) * (0.75 + 0.25 * sine(loop_tone(7, L), n)),
    lambda n: highpass(crackle_v[:n] + vnoise(n) * 0.08, 1800),
]), 0.55)

# Heavy robots: a slow diesel throb, each firing stroke a dull knock.
fire_rate = loop_tone(7, L)
strokes = np.zeros(n_loop)
for i in range(int(fire_rate * (L + 0.12)) + 1):
    knock = lowpass(vnoise(int(0.09 * RATE)), 700) * decay(int(0.09 * RATE), 40.0)
    at(strokes, i / fire_rate, knock, 1.6 if i % 2 else 1.0)
save("hum_heavy", engine_loop(L + 0.12, [
    lambda n: sat(lowpass(saw(loop_tone(41, L), n) + saw(loop_tone(41.5, L), n, 0.3), 260) * (0.55 + 0.45 * np.clip(sine(fire_rate, n), 0, 1)) * 1.6),
    lambda n: strokes[:n],
    lambda n: sine(loop_tone(510, L), n) * 0.03,
]), 0.75)

# Gravity robots: a deep beating sub and a faint glassy shimmer.
save("hum_grav", engine_loop(L + 0.12, [
    lambda n: (sine(loop_tone(38, L), n) + sine(loop_tone(39.5, L), n)) * 0.6,
    lambda n: (sine(loop_tone(1720, L), n) * 0.04 + sine(loop_tone(2581, L), n) * 0.025) * (0.5 + 0.5 * sine(loop_tone(0.5, L), n)),
    lambda n: lowpass(vnoise(n), 180) * 2.0,
]), 0.72)

# Bosses: a building-sized machine idling.
save("hum_boss", engine_loop(L + 0.12, [
    lambda n: sat(lowpass(saw(loop_tone(29, L), n) + saw(loop_tone(43.5, L), n) * 0.6, 220) * (0.7 + 0.3 * sine(loop_tone(4, L), n)) * 1.8),
    lambda n: bandpass(vnoise(n), 300, 1600) * 0.4 * (0.6 + 0.4 * sine(loop_tone(0.5, L), n)),
    lambda n: sine(loop_tone(331, L), n) * 0.05,
]), 0.85)


def zap(top, bottom, length, body=0.5, grit=0.1, curve=0.5):
    n = int(length * RATE)
    sweep = glide(top, bottom, n, curve)
    tone = square(sweep, n, 0.3) * body + sine(sweep * 1.5, n) * (1 - body)
    return (tone + bandpass(vnoise(n), 1500, 7000) * grit * decay(n, 40.0)) * decay(n, 5.0 / length) * np.minimum(np.arange(n) / 40.0, 1.0)


# Tick: a tiny chirping zap.
save("shot_tick", zap(2300, 900, 0.12, 0.6, 0.15), 0.42)
# Hornet: a thin needle, quick and high.
n = int(0.16 * RATE)
save("shot_hornet", (sine(glide(3800, 1600, n, 0.4), n) + sine(glide(5200, 2600, n, 0.4), n) * 0.3 + highpass(vnoise(n), 5000) * 0.2) * decay(n, 26.0), 0.38)
# Lancer: a long lance with a resonant tail.
n = int(0.38 * RATE)
lance = resonant_sweep(saw(glide(520, 210, n, 0.6), n), glide(4200, 600, n, 0.5), 0.75)
save("shot_lancer", (lance * 1.4 + sine(glide(1040, 420, n, 0.6), n) * 0.4) * decay(n, 9.0) * np.minimum(np.arange(n) / 30.0, 1.0), 0.55)
# Bulwark: a chunky autocannon round.
n = int(0.32 * RATE)
save("shot_bulwark", sat(lowpass(vnoise(n), 1600) * 2.5 * decay(n, 22.0) + saw(glide(240, 70, n, 0.4), n) * decay(n, 13.0) + sine(glide(120, 45, n), n) * decay(n, 10.0) * 1.2, 1.4), 0.66)
# Siege: a mortar thump with a ringing barrel.
n = int(0.7 * RATE)
save("shot_siege", sat(lowpass(vnoise(n), 900) * 3.0 * decay(n, 14.0) + sine(glide(95, 34, n, 0.4), n) * decay(n, 5.5) * 1.6 + metal_ping(n, 230, 9.0) * 0.35, 1.3), 0.75)
# Warden and sower: a wobbling plasma glob.
n = int(0.34 * RATE)
wob = glide(380, 180, n, 0.6) * (1.0 + 0.25 * sine(glide(30, 12, n), n))
save("shot_plasma", (sine(wob, n) + sine(wob * 2.0, n) * 0.35 + lowpass(vnoise(n), 1200) * 0.4) * env_ar(n, 0.01, 0.26), 0.55)
# Phase and shade: a zap smeared through a comb filter, as if out of tune with the room.
n = int(0.3 * RATE)
raw = zap(1800, 300, 0.3, 0.5, 0.2, 0.4)
d = int(0.0021 * RATE)
save("shot_phase", (raw + np.concatenate((np.zeros(d), raw[:-d])) * 0.8 + sine(glide(600, 1400, n, 0.5), n) * 0.12 * decay(n, 10.0)), 0.5)
# Revenant: a heavy crack with a metallic snap.
n = int(0.45 * RATE)
save("shot_revenant", sat(highpass(vnoise(n), 1200) * 1.6 * decay(n, 30.0) + saw(glide(700, 90, n, 0.35), n) * 0.8 * decay(n, 9.0) + metal_ping(n, 880, 16.0) * 0.4, 1.3), 0.6)
# Hive: a buzzing spit, like something thrown rather than fired.
n = int(0.26 * RATE)
save("shot_hive", sat(bandpass(saw(glide(260, 140, n), n) + vnoise(n) * 0.8, 300, 3200) * (0.55 + 0.45 * square(48.0, n)) * decay(n, 11.0) * 1.6), 0.55)
# Bosses: a deep cannon with a long rumble behind it.
n = int(0.9 * RATE)
save("shot_boss", sat(lowpass(vnoise(n), 700) * 3.5 * decay(n, 7.0) + saw(glide(160, 38, n, 0.4), n) * 0.9 * decay(n, 6.0) + sine(glide(70, 28, n), n) * decay(n, 4.0) * 1.5, 1.4), 0.85)

# Low shield, critical: a heavy double heartbeat under the warning beep.
n = int(0.62 * RATE)
beat = np.zeros(n)
for start, gain in ((0.0, 1.0), (0.2, 0.7)):
    m = int(0.2 * RATE)
    at(beat, start, sine(glide(72, 44, m, 0.5), m) * decay(m, 16.0) + lowpass(vnoise(m), 180) * decay(m, 30.0), gain)
save("shield_critical", sat(beat * 1.4), 0.7)

print("[audio] done")

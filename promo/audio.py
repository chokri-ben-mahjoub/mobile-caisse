"""Builds the voice-over timeline and a synthetic upbeat soundtrack -> promo/audio.wav + timeline.json"""
import json, wave, os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SR = 44100
GAPS = [0.5, 0.5, 0.2, 0.25, 0.55, 0.2, 0.2, 0.5, 0.55, 0.2]


def load(path):
    w = wave.open(path)
    sr, n, ch = w.getframerate(), w.getnframes(), w.getnchannels()
    d = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768
    if ch == 2:
        d = d.mean(axis=1)
    x = np.arange(int(len(d) * SR / sr)) * sr / SR
    return np.interp(x, np.arange(len(d)), d).astype(np.float32)


cues = [load(os.path.join(HERE, f"c{i}.wav")) for i in range(10)]
starts, ends, t = [], [], 0.0
for g, c in zip(GAPS, cues):
    t += g
    starts.append(t)
    t += len(c) / SR
    ends.append(t)
TOTAL = ends[-1] + 1.8
N = int(TOTAL * SR)

# ---- voice track
voice = np.zeros(N, np.float32)
for s, c in zip(starts, cues):
    c = c / max(1e-6, np.abs(c).max()) * 0.95
    i = int(s * SR)
    voice[i:i + len(c)] += c[: N - i]

# ---- music
rng = np.random.default_rng(7)
BPM = 122
beat = 60 / BPM
tt = np.arange(N) / SR


def midi(m):
    return 440 * 2 ** ((m - 69) / 12)


def place(buf, s, sig, gain=1.0):
    i = int(s * SR)
    if i >= len(buf):
        return
    sig = sig[: len(buf) - i]
    buf[i:i + len(sig)] += sig * gain


def kick():
    t = np.arange(int(0.28 * SR)) / SR
    f = 48 + 110 * np.exp(-t * 32)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) * np.exp(-t * 11)).astype(np.float32)


def clap():
    t = np.arange(int(0.22 * SR)) / SR
    n = np.diff(rng.standard_normal(len(t) + 1)).astype(np.float32)
    env = np.exp(-t * 24) + 0.5 * np.exp(-((t - 0.012) ** 2) * 9000)
    return n * env * 0.35


def hat(open_=False):
    t = np.arange(int((0.22 if open_ else 0.05) * SR)) / SR
    n = np.diff(rng.standard_normal(len(t) + 1)).astype(np.float32)
    return n * np.exp(-t * (18 if open_ else 90)) * 0.22


def pluck(f, dur=0.22):
    t = np.arange(int(dur * SR)) / SR
    s = (2 * ((t * f) % 1) - 1) * 0.5 + np.sin(2 * np.pi * f * t) * 0.5
    s += 0.25 * np.sign(np.sin(2 * np.pi * f * t))
    return (s * np.exp(-t * 13)).astype(np.float32)


def bass(f, dur):
    t = np.arange(int(dur * SR)) / SR
    s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(4 * np.pi * f * t) + 0.12 * np.sign(np.sin(2 * np.pi * f * t))
    env = np.minimum(1, t * 120) * np.exp(-t * 4.0)
    return (s * env).astype(np.float32)


def pad(freqs, dur):
    t = np.arange(int(dur * SR)) / SR
    s = np.zeros_like(t)
    for f in freqs:
        for d in (-0.6, 0.0, 0.7):
            s += np.sin(2 * np.pi * (f + d) * t + rng.uniform(0, 6))
    env = np.minimum(1, t * 3) * np.minimum(1, (dur - t) * 3)
    return (s * env / (len(freqs) * 3)).astype(np.float32)


# Am - F - C - G
prog = [([57, 60, 64], 45), ([53, 57, 60], 41), ([48, 52, 55], 36), ([55, 59, 62], 43)]
bar = 4 * beat
S2 = starts[1] - 0.15  # drums enter with the demo
S5 = starts[8] - 0.2   # final scene
END_BEAT = TOTAL - 1.6

mus_pad = np.zeros(N, np.float32)
mus_arp = np.zeros(N, np.float32)
mus_bass = np.zeros(N, np.float32)
mus_drum = np.zeros(N, np.float32)
mus_fx = np.zeros(N, np.float32)

nbar = int(TOTAL / bar) + 1
for b in range(nbar):
    notes, root = prog[b % 4]
    t0 = b * bar
    place(mus_pad, t0, pad([midi(n) for n in notes], bar + 0.05), 0.5)
    for k in range(16):
        ts = t0 + k * beat / 4
        n = notes[[0, 1, 2, 1][k % 4] if k % 8 < 4 else [2, 1, 0, 1][k % 4]] + 12
        if k % 8 == 7:
            n += 12
        place(mus_arp, ts, pluck(midi(n)), 0.34)
    if t0 >= S2 - 0.01 or True:
        for k in range(8):
            if t0 + k * beat / 2 >= S2 - 0.01 and k % 2 == 1 or (t0 + k * beat / 2 >= S2 and k % 4 == 0):
                place(mus_bass, t0 + k * beat / 2, bass(midi(root), beat / 2 * 0.95), 0.55)

k_s = kick()
c_s = clap()
nb = int(TOTAL / beat) + 1
for i in range(nb):
    ts = i * beat
    if ts < S2 - 0.01 or ts > END_BEAT:
        continue
    place(mus_drum, ts, k_s, 0.95)
    if i % 2 == 1:
        place(mus_drum, ts, c_s, 0.8)
    place(mus_drum, ts + beat / 2, hat(), 0.8)
    if i % 4 == 3:
        place(mus_drum, ts + beat / 2, hat(True), 0.7)

# riser before the demo + impact on the last scene
rl = 1.1
t = np.arange(int(rl * SR)) / SR
nz = np.diff(rng.standard_normal(len(t) + 1)).astype(np.float32)
mus_fx[int((S2 - rl) * SR):int((S2 - rl) * SR) + len(t)] += nz * (t / rl) ** 2.2 * 0.55
t = np.arange(int(1.6 * SR)) / SR
boom = np.sin(2 * np.pi * (38 + 90 * np.exp(-t * 6)) * t) * np.exp(-t * 2.4)
place(mus_fx, S5, boom.astype(np.float32), 1.0)
nz2 = np.diff(rng.standard_normal(len(t) + 1)).astype(np.float32)
place(mus_fx, S5, nz2 * np.exp(-t * 5) * 0.5)
place(mus_drum, S2 - 0.0, k_s, 0.0)

# final chord stab (Am) at the end
final = pad([midi(57), midi(64), midi(69), midi(72)], 1.8)
place(mus_pad, END_BEAT, final, 1.4)

# sidechain pumping from the kick
sc = np.ones(N, np.float32)
for i in range(nb):
    ts = i * beat
    if S2 - 0.01 <= ts <= END_BEAT:
        a = int(ts * SR)
        m = min(int(0.28 * SR), N - a)
        if m > 0:
            sc[a:a + m] *= 1 - 0.55 * np.exp(-np.arange(m) / SR * 11)
music = (mus_pad * 0.6 + mus_arp * 0.9 + mus_bass * 0.9) * sc + mus_drum * 0.9 + mus_fx
# intro: arp/pad only gets a gentle fade-in
music *= np.minimum(1, tt / 0.8)
music *= np.minimum(1, np.maximum(0, (TOTAL - tt) / 1.0))
music = np.tanh(music * 1.1)

# ---- duck music under the voice
k = int(0.12 * SR)
env = np.convolve(np.abs(voice), np.ones(k) / k, mode="same")
duck = 1 - 0.58 * np.clip(env * 12, 0, 1)
duck = np.convolve(duck, np.ones(int(0.08 * SR)) / int(0.08 * SR), mode="same")
music *= duck

# stereo: music with a little width, voice centred
d = int(0.011 * SR)
mus_r = np.concatenate([np.zeros(d, np.float32), music[:-d]])
L = music * 0.5 + voice * 1.0
R = mus_r * 0.5 + voice * 1.0
st = np.stack([L, R], axis=1)
st = np.tanh(st * 0.9)
st = st / np.abs(st).max() * 0.92
pcm = (st * 32767).astype(np.int16)
with wave.open(os.path.join(HERE, "audio.wav"), "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())

json.dump({"starts": starts, "ends": ends, "total": TOTAL, "S2": S2, "S5": S5},
          open(os.path.join(HERE, "timeline.json"), "w"), indent=1)
print("total", round(TOTAL, 2), [round(s, 2) for s in starts])

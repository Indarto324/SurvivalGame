"""Original deterministic surf-like noise. No sampled/external recordings."""
import math
import random
import struct
import wave
from pathlib import Path

rng = random.Random(9009)
rate, seconds = 16000, 8
values, filtered = [], 0.0
for index in range(rate * seconds):
    filtered = 0.86 * filtered + 0.14 * rng.uniform(-1, 1)
    envelope = 0.35 + 0.65 * (0.5 - 0.5 * math.cos(math.tau * index / (rate * 4)))
    values.append(filtered * envelope)
# Join the ends with a short equal-power crossfade, avoiding loop clicks.
fade = rate // 2
for index in range(fade):
    mix = index / fade
    values[-fade + index] = values[-fade + index] * (1 - mix) + values[index] * mix
values = values[fade:]
peak = max(abs(value) for value in values)
out = Path(__file__).resolve().parents[1] / 'audio/music/coastal_surf.wav'
with wave.open(str(out), 'wb') as stream:
    stream.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
    stream.writeframes(b''.join(struct.pack('<h', round(value / peak * 16000)) for value in values))

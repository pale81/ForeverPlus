"""Offline audio checks; run with the renderer's NumPy/SciPy/Praat environment."""

import importlib.util
from pathlib import Path
import unittest
import os

import numpy as np


spec = importlib.util.spec_from_file_location(
    "emote_builder", Path(__file__).resolve().parents[1] / "tools/build_emote_voice.py"
)
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class ProsodyTests(unittest.TestCase):
    rate = 24000
    settings = {"pitch_spread": 1.15, "max_shift_semitones": 0.75}

    def peak(self, audio, start, end):
        part = audio[int(start * self.rate):int(end * self.rate)]
        spectrum = abs(np.fft.rfft(part * np.hanning(len(part)), n=65536))
        return np.fft.rfftfreq(65536, 1 / self.rate)[np.argmax(spectrum)]

    def test_disabled_and_unvoiced_audio_stay_unchanged(self):
        noise = np.random.default_rng(17).normal(0, 0.03, self.rate).astype(np.float32)
        np.testing.assert_array_equal(builder.shape_prosody(noise, self.rate, None, os.environ.get("PRAAT", "praat")), noise)
        np.testing.assert_array_equal(builder.shape_prosody(noise, self.rate, self.settings, os.environ.get("PRAAT", "praat")), noise)

    def test_melody_expands_without_a_global_pitch_or_duration_change(self):
        time = np.arange(self.rate * 2) / self.rate
        frequency = np.where(time < 0.6, 140, np.where(time < 1.3, 180, 225))
        audio = (0.15 * np.sin(2 * np.pi * np.cumsum(frequency) / self.rate)).astype(np.float32)
        result = builder.shape_prosody(audio, self.rate, self.settings, os.environ.get("PRAAT", "praat"))
        self.assertEqual(len(result), len(audio))
        self.assertTrue(np.isfinite(result).all())
        peaks = np.array([self.peak(result, a, b) for a, b in [(0.2, 0.45), (0.85, 1.1), (1.55, 1.8)]])
        shifts = 12 * np.log2(peaks / [140, 180, 225])
        self.assertLess(shifts[0], -0.3)
        self.assertGreater(shifts[2], 0.3)
        self.assertLess(abs(shifts[1]), 0.15)
        self.assertLessEqual(abs(shifts).max(), 0.8)

    def test_invalid_controls_are_rejected(self):
        audio = np.zeros(self.rate, dtype=np.float32)
        for spread, limit in [(float("nan"), 0.75), (1.5, 0.75), (1.15, -1)]:
            with self.subTest(spread=spread, limit=limit), self.assertRaises(ValueError):
                builder.shape_prosody(audio, self.rate, {"pitch_spread": spread, "max_shift_semitones": limit}, os.environ.get("PRAAT", "praat"))

    def test_resynthesis_cannot_clip_the_intermediate_pcm(self):
        time = np.arange(self.rate) / self.rate
        audio = (2 * np.sin(2 * np.pi * 180 * time)).astype(np.float32)
        result = builder.shape_prosody(audio, self.rate, self.settings, os.environ.get("PRAAT", "praat"))
        self.assertLessEqual(abs(result).max(), 0.981)
        self.assertGreater(abs(result).max(), 0.95)
        self.assertLess(np.mean(abs(result) > 0.97), 0.2)


if __name__ == "__main__":
    unittest.main()

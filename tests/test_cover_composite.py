import sys
import unittest
from unittest.mock import MagicMock

# Bare `python3 -m unittest` does not install project deps.
sys.modules.setdefault("PIL", MagicMock())
sys.modules.setdefault("PIL.Image", MagicMock())
sys.modules.setdefault("PIL.ImageDraw", MagicMock())
sys.modules.setdefault("PIL.ImageFont", MagicMock())
sys.modules.setdefault("PIL.ImageFilter", MagicMock())

import gen_cover_composite


class CoverTextPaletteTests(unittest.TestCase):
    def test_light_and_dark_palettes_differ(self):
        light_text, _light_shadow, light_band = gen_cover_composite.cover_text_palette("light")
        dark_text, _dark_shadow, dark_band = gen_cover_composite.cover_text_palette("dark")
        self.assertNotEqual(
            (light_text, light_band),
            (dark_text, dark_band),
            "light and dark must differ in text_color and/or band_color",
        )

    def test_auto_maps_brightness_onto_dark_and_light_palettes(self):
        dark = gen_cover_composite.cover_text_palette("dark")
        light = gen_cover_composite.cover_text_palette("light")
        threshold = gen_cover_composite.COVER_AUTO_DARK_BELOW
        self.assertEqual(gen_cover_composite.cover_text_palette("auto", brightness=0), dark)
        self.assertEqual(
            gen_cover_composite.cover_text_palette("auto", brightness=threshold - 1),
            dark,
        )
        self.assertEqual(
            gen_cover_composite.cover_text_palette("auto", brightness=threshold),
            light,
        )
        self.assertEqual(gen_cover_composite.cover_text_palette("auto", brightness=255), light)


if __name__ == "__main__":
    unittest.main()

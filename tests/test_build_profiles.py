"""Tests for scripts/build-profiles.py. Run: python3 -m unittest tests/test_build_profiles.py"""

import importlib.util
import pathlib
import tempfile
import textwrap
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "build-profiles.py"
spec = importlib.util.spec_from_file_location("build_profiles", SCRIPT)
build_profiles = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_profiles)


def translate(source: str):
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as file:
        file.write(textwrap.dedent(source))
    return build_profiles.translate(pathlib.Path(file.name))


class TranslateTests(unittest.TestCase):
    def test_plain_calls_become_profile_fields(self):
        profile, partial = translate('''
            """Game fix for Example"""
            from protonfixes import util

            def main() -> None:
                """Docstring is skipped."""
                util.protontricks('vcrun2019')
                util.protontricks('win7')
                util.protontricks('sound=alsa')
                util.winedll_override('dinput8', util.OverrideOrder.NATIVE_BUILTIN)
                util.append_argument('-dx11 -BattlEye')
                util.regedit_add('HKCU\\\\Software\\\\Example', 'Lang', 'REG_DWORD', '1')
                util.disable_esync()
        ''')
        self.assertFalse(partial)
        self.assertEqual(profile["name"], "Example")
        self.assertEqual(profile["winetricks"], ["vcrun2019"])
        self.assertEqual(profile["windowsVersion"], "win7")
        self.assertEqual(profile["dllOverrides"], {"dinput8": "native,builtin"})
        self.assertEqual(profile["arguments"], ["-dx11"])
        self.assertEqual(profile["registry"], [{"key": "HKCU\\Software\\Example", "name": "Lang",
                                                "type": "REG_DWORD", "value": "1"}])

    def test_conditional_code_is_left_out_and_marked(self):
        profile, partial = translate('''
            from protonfixes import util

            def main() -> None:
                util.protontricks('d3dcompiler_47')
                if util.get_resolution():
                    util.protontricks('dotnet48')
                util.replace_command('Launcher.exe', 'Game.exe')
        ''')
        self.assertTrue(partial)
        self.assertTrue(profile["partial"])
        self.assertEqual(profile["winetricks"], ["d3dcompiler_47"])

    def test_linux_controller_keys_are_dropped(self):
        profile, _ = translate('''
            from protonfixes import util

            def main() -> None:
                util.regedit_add('HKLM\\\\System\\\\CurrentControlSet\\\\Services\\\\winebus', 'DisableHidraw', 'REG_DWORD', '1')
        ''')
        self.assertNotIn("registry", profile)


if __name__ == "__main__":
    unittest.main()

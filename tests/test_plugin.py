"""Runtime, permissions and archive checks; Python 3.11+ and liblua5.4."""
import ctypes
import ctypes.util
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest
import zipfile

ROOT = Path(__file__).resolve().parent.parent


class Lua:
    def run(self, code):
        library = ctypes.util.find_library("lua5.4")
        if not library:
            raise RuntimeError("Install liblua5.4 to run runtime tests")
        lib = ctypes.CDLL(library)
        for name, args, result in [
            ("luaL_newstate", [], ctypes.c_void_p),
            ("luaL_openlibs", [ctypes.c_void_p], None),
            ("luaL_loadstring", [ctypes.c_void_p, ctypes.c_char_p], ctypes.c_int),
            ("lua_pcallk", [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p], ctypes.c_int),
            ("lua_tolstring", [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p], ctypes.c_char_p),
            ("lua_close", [ctypes.c_void_p], None),
        ]:
            fn = getattr(lib, name)
            fn.argtypes, fn.restype = args, result
        state = lib.luaL_newstate()
        try:
            lib.luaL_openlibs(state)
            status = lib.luaL_loadstring(state, code.encode())
            if not status:
                status = lib.lua_pcallk(state, 0, 0, 0, 0, None)
            if status:
                raise AssertionError(lib.lua_tolstring(state, -1, None).decode())
        finally:
            lib.lua_close(state)


class PluginTests(unittest.TestCase):
    def test_colour_aliases_and_generated_listing(self):
        Lua().run('ROOT = ' + repr(str(ROOT)) + '; dofile(ROOT .. "/tests/parser_test.lua")')

    def test_runtime(self):
        Lua().run('ROOT = ' + repr(str(ROOT)) + '; dofile(ROOT .. "/tests/runtime_test.lua")')

    def test_invalid_storage_is_not_overwritten(self):
        Lua().run('ROOT = ' + repr(str(ROOT)) + '''
            require = function(name) return dofile(ROOT .. "/src/" .. name .. ".lua") end
            local wrote = false
            storage = { get = function() return {version = 99} end,
                set = function() wrote = true end }
            local ok = pcall(require("aliases").init)
            assert(not ok and not wrote)
        ''')

    def test_permissions_and_module_paths(self):
        manifest = tomllib.loads((ROOT / "plugin.toml").read_text())
        self.assertEqual(manifest["name"], "Being's Discworld Alias Helper")
        self.assertTrue(manifest["permissions"]["sends"])
        self.assertFalse(manifest["permissions"]["network"])
        self.assertEqual(manifest["mallard_api_version"], "1.0")
        self.assertEqual(manifest["minimum_app_version"], "0.28.0")
        # Mallard resolves require relative to src/, rather than the entry file.
        self.assertTrue((ROOT / "src/aliases.lua").is_file())
        self.assertTrue((ROOT / "src/parser.lua").is_file())

    def test_reproducible_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            archives = [Path(directory) / name for name in ("one.mallardx", "two.mallardx")]
            for archive in archives:
                subprocess.run([sys.executable, str(ROOT / "scripts/build.py"), str(archive)],
                               check=True, capture_output=True)
            self.assertEqual(archives[0].read_bytes(), archives[1].read_bytes())
            with zipfile.ZipFile(archives[0]) as archive:
                manifest = tomllib.loads(archive.read("plugin.toml").decode())
                self.assertIn(manifest["entry"], archive.namelist())
                for panel in manifest["panels"].values():
                    self.assertIn(panel["entry"], archive.namelist())
                for name in archive.namelist():
                    self.assertTrue(name in ("plugin.toml", "LICENSE", "README.md")
                                    or name.startswith(("src/", "ui/", "assets/")))
                    self.assertNotIn("..", Path(name).parts)
                    self.assertEqual(archive.read(name), (ROOT / name).read_bytes())


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Slang importer regression tests; no GPU/compiler needed for ABI tests."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import re

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("slang", ROOT / "extras/tools/import-slang-shaders.py")
slang = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(slang)


class SlangImport(unittest.TestCase):
    def test_generated_presets_include_d3d11_hlsl_abi(self):
        root = ROOT / "share/retroarch-shaders/crt"
        presets = list((root / "slang").glob("*.glslp"))
        self.assertEqual(len(presets), 85)
        hlsl_files = set()
        for preset in presets:
            values = {}
            for line in preset.read_text().splitlines():
                match = re.match(r'^([^#=]+?)\s*=\s*"(.*)"$', line)
                if match:
                    values[match[1].strip()] = match[2]
            passes = int(values["shaders"])
            for index in range(passes):
                with self.subTest(preset=preset.name, shader=index):
                    for stage in ("vertex", "fragment"):
                        key = f"hlsl_{stage}{index}"
                        self.assertIn(key, values)
                        path = root / values[key]
                        self.assertTrue(path.is_file(), path)
                        hlsl_files.add(path)
                    self.assertIn(f"hlsl_buffer0_size{index}", values)
                    self.assertIn(f"hlsl_buffer1_size{index}", values)
                    self.assertIn(f"hlsl_textures{index}", values)
                    for binding in values[f"hlsl_textures{index}"].split(";"):
                        if binding:
                            self.assertLessEqual(int(binding.rsplit(":", 1)[1]), 15)

        self.assertGreaterEqual(len(hlsl_files), 300)
        for path in hlsl_files:
            source = path.read_text()
            with self.subTest(hlsl=path.name):
                self.assertNotIn("#version", source)
                self.assertNotIn("GL_ARB_", source)
                if "cbuffer Push" in source:
                    self.assertRegex(source, r"cbuffer\s+Push\s*:\s*register\(b1\)")

    def test_generated_legacy_programs_do_not_require_420pack(self):
        programs = list((ROOT / "share/retroarch-shaders/crt/slang/programs").glob("*.glsl"))
        self.assertTrue(programs)
        for path in programs:
            source = path.read_text()
            version = int(re.search(r"#version (\d+)", source)[1])
            if version < 420:
                with self.subTest(program=path.name):
                    self.assertNotIn("GL_ARB_shading_language_420pack", source)
                    self.assertNotRegex(source, r"layout\s*\([^)]*\bbinding\b")

    def test_stage_isolation(self):
        stages = slang.stages("#version 450\nshared\n#pragma stage vertex\nvertex\n#pragma stage fragment\nfragment")
        self.assertIn("shared", stages["vertex"])
        self.assertNotIn("fragment", stages["vertex"])
        self.assertNotIn("vertex", stages["fragment"])

    def test_pass_indices_and_aliases(self):
        self.assertEqual(slang.texture_name("PassOutput0", {}, [], 1, set()), "Pass1Texture")
        self.assertEqual(slang.texture_name("BLOOM", {"BLOOM": 1}, [], 2, set()), "Pass2Texture")
        with self.assertRaises(slang.Unsupported):
            slang.texture_name("PassOutput1", {}, [], 1, set())

    def test_feedback_fail_closed(self):
        targets = set()
        self.assertEqual(slang.texture_name("BLOOMFeedback", {"BLOOM": 1}, [], 0, targets), "FeedbackTexture")
        self.assertEqual(targets, {1})
        with self.assertRaises(slang.Unsupported):
            slang.texture_name("PassFeedback0", {}, [], 1, targets)

    def test_history_not_silently_substituted(self):
        with self.assertRaises(slang.Unsupported):
            slang.texture_name("OriginalHistory1", {}, [], 1, set())
        self.assertEqual(slang.texture_name("OriginalHistory0", {}, [], 1, set()), "OrigTexture")

    def test_size_semantics(self):
        self.assertEqual(slang.size_texture("PassOutputSize3"), "PassOutput3")
        self.assertEqual(slang.size_texture("SourceSize"), "Source")

    def test_reflected_uniforms_and_inverse_dimensions(self):
        reflection = {"ubos": [{"type": "u"}], "types": {"u": {"name": "UBO", "members": [
            {"name": "SourceSize", "type": "vec4"},
            {"name": "PassOutputSize0", "type": "vec4"},
            {"name": "FinalViewportSize", "type": "vec4"},
            {"name": "FrameCount", "type": "uint"},
            {"name": "SHARPNESS", "type": "float"}]}}}
        source = "uniform UBO global;\nvoid main() { vec4 x = global.SourceSize + global.PassOutputSize0 + global.FinalViewportSize; uint frame = global.FrameCount; float sharp = global.SHARPNESS; }"
        result = slang.adapt(source, reflection, {"SHARPNESS"}, {}, [], 1, set())
        self.assertIn("vec4(TextureSize, 1.0 / TextureSize)", result)
        self.assertIn("vec4(Pass1TextureSize, 1.0 / Pass1TextureSize)", result)
        self.assertIn("uniform vec2 RAViewportSize;", result)
        self.assertIn("uint(FrameCount)", result)
        self.assertIn("uniform float SHARPNESS;", result)
        self.assertNotIn("global.", result)

    def test_extensions_precede_inserted_uniforms(self):
        reflection = {"ubos": [{"type": "u"}], "types": {"u": {"name": "UBO", "members": [{"name": "MVP", "type": "mat4"}]}}}
        source = "#version 120\n#extension GL_ARB_shader_texture_lod : require\n\nuniform UBO global;\nvoid main(){ gl_Position = global.MVP * vec4(1.0); }"
        result = slang.adapt(source, reflection, set(), {}, [], 0, set())
        self.assertLess(result.index("#extension"), result.index("uniform mat4"))

    def test_unknown_uniform_is_rejected(self):
        reflection = {"push_constants": [{"type": "u"}], "types": {"u": {"name": "Push", "members": [{"name": "CurrentSubFrame", "type": "uint"}]}}}
        with self.assertRaises(slang.Unsupported):
            slang.adapt("uniform Push pc; void main(){ uint x = pc.CurrentSubFrame; }", reflection, set(), {}, [], 0, set())

    def test_reference_resource_origins_and_cycles(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "base").mkdir()
            (root / "base/base.slangp").write_text('shaders = 1\nshader0 = "shader.slang"\nGAIN = 1\n')
            (root / "preset.slangp").write_text('#reference "base/base.slangp"\nGAIN = 2\n')
            values = slang.preset_values(root, root / "preset.slangp", set())
            self.assertEqual(values["shader0"][1], (root / "base").resolve())
            self.assertEqual(values["GAIN"][0], "2")
            (root / "cycle.slangp").write_text('#reference "cycle.slangp"\n')
            with self.assertRaises(slang.Unsupported):
                slang.preset_values(root, root / "cycle.slangp", set())

    def test_optional_include_and_path_boundary(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "shader.slang").write_text('#pragma include_optional "missing.h"\nbody')
            self.assertEqual(slang.expand(root, root / "shader.slang", set()), "\nbody")
            with self.assertRaises(slang.Unsupported):
                slang.within(root, root / "../outside.h")


if __name__ == "__main__":
    unittest.main()

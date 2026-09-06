#!/usr/bin/env python3
"""Compile the supported CRT Slang catalogue for PowerVLC's GPU backends.

Build-time only: glslang -> SPIR-V -> SPIRV-Cross GLSL/HLSL. No dependency on
RetroArch's GPL parser. Unsupported semantics fail closed. The shader
algorithms are compiled, never replaced with look-alike effects. OpenGL
compiles the generated GLSL on first use; Direct3D 11 compiles the generated
HLSL with the D3D compiler already used by VLC's video output.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path


class Unsupported(ValueError):
    pass


def run(*args):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    if result.returncode:
        raise Unsupported(result.stdout.strip())
    return result.stdout


def read(path):
    return path.read_text(encoding="utf-8-sig")


def within(root, path):
    path = path.resolve()
    if not path.is_relative_to(root.resolve()):
        raise Unsupported("resource escapes upstream tree")
    return path


def expand(root, path, dependencies, stack=()):
    path = within(root, path)
    if path in stack or len(stack) >= 64:
        raise Unsupported("recursive shader include")
    dependencies.add(path)
    text = read(path)
    text = re.sub(r'^\s*#pragma\s+include_optional\s+"([^"]+)"[^\n]*$',
                  lambda m: expand(root, path.parent / m[1], dependencies,
                                   stack + (path,))
                  if within(root, path.parent / m[1]).is_file() else "",
                  text, flags=re.M)
    return re.sub(r'^\s*#include\s+"([^"]+)"[^\n]*$',
                  lambda m: expand(root, path.parent / m[1], dependencies,
                                   stack + (path,)), text, flags=re.M)


def preset_values(root, path, dependencies, stack=()):
    path = within(root, path)
    if path in stack or len(stack) >= 32:
        raise Unsupported("recursive preset reference")
    dependencies.add(path)
    values = {}
    text = read(path)
    for reference in re.findall(r'^\s*#reference\s+"([^"]+)"', text, re.M):
        values.update(preset_values(root, path.parent / reference,
                                    dependencies, stack + (path,)))
    for line in text.splitlines():
        match = re.match(r'\s*(\w+)\s*=\s*(?:"([^"]*)"|([^#]*))', line)
        if match:
            value = match[2] if match[2] is not None else match[3].strip()
            values[match[1]] = (value, path.parent)
    return values


def stages(text):
    result = {"vertex": [], "fragment": []}
    stage = None
    for line in text.splitlines():
        match = re.match(r'\s*#pragma\s+stage\s+(\w+)', line)
        if match:
            stage = match[1]
            if stage not in result:
                raise Unsupported("only vertex/fragment stages are supported")
        else:
            for name in result:
                if stage is None or stage == name:
                    result[name].append(line)
    if stage is None:
        raise Unsupported("missing Slang stage declarations")
    return {k: "\n".join(v) + "\n" for k, v in result.items()}


def texture_name(name, aliases, luts, index, feedback):
    if name == "Source":
        return "Texture"
    if name in ("Original", "OriginalHistory0"):
        return "OrigTexture"
    match = re.fullmatch(r'PassOutput(\d+)', name)
    if match:
        number = int(match[1])
        if number >= index:
            raise Unsupported("non-causal PassOutput")
        return f"Pass{number + 1}Texture"
    match = re.fullmatch(r'PassFeedback(\d+)', name)
    if match:
        number = int(match[1])
        feedback.add(number)
        if len(feedback) > 1:
            raise Unsupported("multiple feedback targets")
        return "FeedbackTexture"
    if name in aliases:
        return texture_name(f"PassOutput{aliases[name]}", {}, luts,
                            index, feedback)
    if name.endswith("Feedback") and name[:-8] in aliases:
        return texture_name(f"PassFeedback{aliases[name[:-8]]}", {}, luts,
                            index, feedback)
    if name in luts:
        return name
    match = re.fullmatch(r'User(\d+)', name)
    if match and int(match[1]) < len(luts):
        return luts[int(match[1])]
    # The Slang adapter does not expose frame history yet. Reject it rather
    # than silently substitute another texture or change raster semantics.
    raise Unsupported(f"unsupported texture semantic: {name}")


def size_texture(name):
    match = re.fullmatch(r'(OriginalHistory|PassOutput|PassFeedback|User)Size(\d+)', name)
    return match[1] + match[2] if match else name[:-4]


def adapt(glsl, reflection, parameters, aliases, luts, index, feedback):
    """Map reflected Slang interface members to the renderer's GLSL ABI."""
    uniforms = {}

    def uniform(kind, name):
        if name in uniforms and uniforms[name] != kind:
            raise Unsupported(f"conflicting uniform: {name}")
        uniforms[name] = kind
        return name

    def semantic(kind, name):
        if name == "MVP" and kind == "mat4":
            return uniform("mat4", "MVPMatrix")
        if name in ("FrameCount", "FrameDirection") and kind in ("uint", "int"):
            value = uniform("int", name)
            return f"uint({value})" if kind == "uint" else value
        if name in parameters and kind == "float":
            return uniform("float", name)
        if kind == "vec4" and (name.endswith("Size") or re.search(r'Size\d+$', name)):
            if name == "OutputSize":
                target = "OutputSize"
            elif name == "FinalViewportSize":
                target = "RAViewportSize"
            else:
                target = texture_name(size_texture(name), aliases, luts,
                                      index, feedback) + "Size"
            uniform("vec2", target)
            return f"vec4({target}, 1.0 / {target})"
        raise Unsupported(f"unsupported uniform semantic: {kind} {name}")

    for resource in reflection.get("ubos", []) + reflection.get("push_constants", []):
        struct = reflection["types"][resource["type"]]
        declaration = re.search(r'\buniform\s+' + re.escape(struct["name"]) +
                                r'\s+(\w+)\s*;', glsl)
        if not declaration:
            raise Unsupported("cannot identify emitted uniform block")
        instance = declaration[1]
        glsl = glsl[:declaration.start()] + glsl[declaration.end():]
        for member in struct["members"]:
            pattern = r'\b' + re.escape(instance) + r'\.' + re.escape(member["name"]) + r'\b'
            if not re.search(pattern, glsl):
                continue
            if "array" in member:
                raise Unsupported("uniform arrays")
            replacement = semantic(member["type"], member["name"])
            glsl = re.sub(pattern, lambda _: "(" + replacement + ")", glsl)
        if re.search(r'\b' + re.escape(instance) + r'\b', glsl):
            raise Unsupported("whole-block uniform use")

    # Rename all sampler identifiers simultaneously (aliases can overlap).
    replacements = {}
    for resource in reflection.get("textures", []):
        if resource["type"] != "sampler2D" or "array" in resource:
            raise Unsupported("only non-array sampler2D resources are supported")
        replacements[resource["name"]] = texture_name(resource["name"], aliases,
                                                    luts, index, feedback)
    glsl = re.sub(r'\b\w+\b', lambda m: replacements.get(m[0], m[0]), glsl)
    if any(reflection.get(k) for k in ("ssbos", "images", "separate_images", "separate_samplers", "subpass_inputs")):
        raise Unsupported("unsupported shader resource")
    glsl = re.sub(r'^#version[^\n]*\n', '', glsl, flags=re.M)
    # Apple requires extension directives before any declarations, including
    # the ABI uniforms inserted here. Keep SPIRV-Cross's preamble first.
    preamble = re.match(r'\A(?:[ \t]*(?:#[^\n]*|//[^\n]*)?\n)*', glsl).end()
    declarations = "\n".join(f"uniform {kind} {name};" for name, kind in sorted(uniforms.items())) + "\n"
    return glsl[:preamble] + declarations + glsl[preamble:]


def hlsl_metadata(reflection, parameters, aliases, luts, index, feedback):
    """Describe SPIRV-Cross's stable HLSL resource ABI for the D3D11 runner."""
    buffers = {0: {"size": 0, "members": {}},
               1: {"size": 0, "members": {}}}
    resources = ((reflection.get("ubos", []), 0),
                 (reflection.get("push_constants", []), 1))
    for blocks, slot in resources:
        for resource in blocks:
            struct = reflection["types"][resource["type"]]
            buffers[slot]["size"] = max(buffers[slot]["size"],
                                         resource.get("block_size", 0))
            for member in struct["members"]:
                if "array" in member:
                    raise Unsupported("uniform arrays")
                name, kind = member["name"], member["type"]
                # Keep exactly the same fail-closed semantic policy as the
                # GLSL ABI adapter. The D3D runner fills these reflected byte
                # offsets directly instead of relying on compiler reflection.
                semantic(kind, name, parameters, aliases, luts, index,
                         feedback)
                current = buffers[slot]["members"].get(name)
                value = (member["offset"], kind)
                sizes = {"float": 4, "int": 4, "uint": 4,
                         "vec4": 16, "mat4": 64}
                buffers[slot]["size"] = max(
                    buffers[slot]["size"], member["offset"] + sizes[kind])
                if current is not None and current != value:
                    raise Unsupported("conflicting uniform layout: " + name)
                buffers[slot]["members"][name] = value

    for slot in (0, 1):
        buffers[slot]["size"] = (buffers[slot]["size"] + 15) & ~15

    textures = {}
    for resource in reflection.get("textures", []):
        if resource["type"] != "sampler2D" or "array" in resource:
            raise Unsupported("only non-array sampler2D resources are supported")
        canonical = texture_name(resource["name"], aliases, luts, index,
                                 feedback)
        binding = resource.get("binding")
        if binding is None or not 0 <= binding < 16:
            raise Unsupported("D3D11 sampler binding outside 0..15")
        if canonical in textures and textures[canonical] != binding:
            raise Unsupported("conflicting texture binding: " + canonical)
        textures[canonical] = binding
    return buffers, textures


def semantic(kind, name, parameters, aliases, luts, index, feedback):
    """Validate one reflected uniform and return its D3D runtime semantic."""
    if name == "MVP" and kind == "mat4":
        return name
    if name in ("FrameCount", "FrameDirection") and kind in ("uint", "int"):
        return name
    if name in parameters and kind == "float":
        return name
    if kind == "vec4" and (name.endswith("Size") or
                           re.search(r'Size\d+$', name)):
        if name in ("OutputSize", "FinalViewportSize"):
            return name
        texture_name(size_texture(name), aliases, luts, index, feedback)
        return name
    raise Unsupported(f"unsupported uniform semantic: {kind} {name}")


def merge_hlsl_metadata(target, source):
    for slot in (0, 1):
        target["buffers"][slot]["size"] = max(
            target["buffers"][slot]["size"], source[0][slot]["size"])
        for name, value in source[0][slot]["members"].items():
            previous = target["buffers"][slot]["members"].get(name)
            if previous is not None and previous != value:
                raise Unsupported("stage uniform layout mismatch: " + name)
            target["buffers"][slot]["members"][name] = value
    for name, binding in source[1].items():
        previous = target["textures"].get(name)
        if previous is not None and previous != binding:
            raise Unsupported("stage texture binding mismatch: " + name)
        target["textures"][name] = binding


def encode_hlsl_members(members):
    return ";".join(f"{name}:{offset}:{kind}" for name, (offset, kind) in
                    sorted(members.items()))


def encode_hlsl_textures(textures):
    return ";".join(f"{name}:{binding}" for name, binding in
                    sorted(textures.items()))


def compile_shader(text, aliases, luts, index, feedback, version=120):
    parameter_lines = re.findall(r'^\s*(#pragma parameter\s+(\w+)\s+[^\n]+)', text, re.M)
    parameters = {name for _, name in parameter_lines}
    parameter_defaults = {
        name: float(value) for name, value in re.findall(
            r'^\s*#pragma parameter\s+(\w+)\s+"[^"]*"\s+([^\s]+)',
            text, re.M)
    }
    if len(parameters) > 64:
        raise Unsupported("more than 64 shader parameters")
    compiled = {}
    hlsl = {}
    hlsl_meta = {"buffers": {0: {"size": 0, "members": {}},
                              1: {"size": 0, "members": {}}},
                 "textures": {}, "parameters": parameter_defaults}
    with tempfile.TemporaryDirectory(prefix="powervlc-slang-") as tmp:
        tmp = Path(tmp)
        for stage, source in stages(text).items():
            short = "vert" if stage == "vertex" else "frag"
            source_path, binary = tmp / ("shader." + short), tmp / (short + ".spv")
            source_path.write_text(source)
            run("glslangValidator", "-V", "-Os", "-S", short, "-o", str(binary), str(source_path))
            reflection = json.loads(run("spirv-cross", str(binary), "--reflect"))
            hlsl_source = run("spirv-cross", str(binary), "--hlsl",
                              "--shader-model", "50")
            # Vulkan push constants do not carry a D3D register. Reserve b1;
            # the regular RetroArch UBO remains at b0 in SPIRV-Cross output.
            hlsl_source = re.sub(r'\bcbuffer\s+Push\s*(?=\{)',
                                 'cbuffer Push : register(b1)\n', hlsl_source)
            hlsl[stage] = hlsl_source
            merge_hlsl_metadata(
                hlsl_meta,
                hlsl_metadata(reflection, parameters, aliases, luts, index,
                              feedback))
            command = ["spirv-cross", str(binary), "--version", str(version), "--no-es",
                       # The runtime assigns sampler units with glUniform1i.
                       # Binding qualifiers need GL 4.2/420pack even when the
                       # shader itself only requires GLSL 130 (e.g. Parallels).
                       "--no-420pack-extension",
                       "--glsl-emit-ubo-as-plain-uniforms"]
            for direction in ("inputs", "outputs"):
                for resource in reflection.get(direction, []):
                    location = resource.get("location")
                    if location is None:
                        raise Unsupported("shader interface missing location")
                    if stage == "vertex" and direction == "inputs":
                        if location not in (0, 1):
                            raise Unsupported("unsupported vertex input")
                        name = "VertexCoord" if location == 0 else "TexCoord"
                    elif stage == "fragment" and direction == "outputs":
                        if location != 0 or resource["type"] != "vec4":
                            raise Unsupported("unsupported fragment output")
                        continue
                    else:
                        name = f"RA_VARYING_{location}"
                    command += ["--rename-interface-variable", "in" if direction == "inputs" else "out", str(location), name]
            glsl = adapt(run(*command), reflection, parameters, aliases, luts, index, feedback)
            if version == 120 and "GL_EXT_gpu_shader4" in glsl:
                raise Unsupported("integer operations require GLSL 130")
            # Verify the adapted ABI as well as the upstream compiler output.
            checked = tmp / ("checked." + short)
            checked.write_text(f"#version {version}\n" + glsl)
            run("glslangValidator", str(checked))
            compiled[stage] = glsl
        run("glslangValidator", "-l", str(tmp / "checked.vert"), str(tmp / "checked.frag"))
    glsl = (f"#version {version}\n" +
            "\n".join(dict.fromkeys(line for line, _ in parameter_lines)) +
            "\n#ifdef VERTEX\n" + compiled["vertex"] +
            "\n#endif\n#ifdef FRAGMENT\n" + compiled["fragment"] +
            "\n#endif\n")
    return glsl, hlsl, hlsl_meta


def import_preset(root, path, output, dependencies):
    data = preset_values(root, path, dependencies)
    values = {k: v[0] for k, v in data.items()}
    count = int(values.get("shaders", "0"))
    if not 1 <= count <= 15:
        raise Unsupported("pass count outside 1..15")
    for key, value in values.items():
        if (key.startswith(("frame_count_mod", "shader_subframes")) or
                key.startswith("format") or key == "imports"):
            raise Unsupported(f"unsupported preset setting: {key}")
    # Slang feedback is declared by reflected PassFeedbackN samplers. The
    # old GLSL feedback_pass key is sometimes left in upstream presets.
    values.pop("feedback_pass", None)
    aliases = {values[f"alias{i}"]: i for i in range(count) if values.get(f"alias{i}")}
    sources = []
    all_parameters = set()
    for i in range(count):
        key = f"shader{i}"
        source_path = within(root, data[key][1] / values[key])
        text = expand(root, source_path, dependencies)
        sources.append((source_path, text))
        all_parameters.update(re.findall(r'^\s*#pragma parameter\s+(\w+)', text, re.M))
        implicit_alias = re.search(r'^\s*#pragma name\s+(\w+)', text, re.M)
        if implicit_alias and not values.get(f"alias{i}"):
            aliases[implicit_alias[1]] = i
            values[f"alias{i}"] = implicit_alias[1]
        formats = set(re.findall(r'^\s*#pragma format\s+(\w+)', text, re.M))
        if len(formats) > 1:
            raise Unsupported("conditional framebuffer formats")
        if formats:
            format_name = next(iter(formats))
            if format_name not in ("R8G8B8A8_UNORM", "R8G8B8A8_SRGB", "R16G16B16A16_SFLOAT"):
                raise Unsupported(f"unsupported framebuffer format: {format_name}")
            values[f"srgb_framebuffer{i}"] = str(format_name == "R8G8B8A8_SRGB").lower()
            values[f"float_framebuffer{i}"] = str(format_name == "R16G16B16A16_SFLOAT").lower()
            # A format directive on the final shader still requires a target
            # with that format before the stock presentation pass.
            if i == count - 1 and not any(k in values for k in (f"scale_type{i}", f"scale_type_x{i}", f"scale_type_y{i}")):
                values[f"scale_type{i}"] = "viewport"
                values[f"scale{i}"] = "1"
    if len(all_parameters) > 64:
        raise Unsupported("more than 64 global preset parameters")
    luts = list(filter(None, values.get("textures", "").split(";")))
    if len(luts) > 12:
        raise Unsupported("too many lookup textures")
    feedback = set()
    products = {}
    required_version = 120
    for i in range(count):
        key = f"shader{i}"
        source_path, text = sources[i]
        for version in (120, 130, 330, 430):
            candidate_feedback = set(feedback)
            try:
                compiled, hlsl, hlsl_meta = compile_shader(
                    text, aliases, luts, i, candidate_feedback, version)
                feedback = candidate_feedback
                required_version = max(required_version, version)
                break
            except Unsupported:
                if version == 430:
                    raise
        digest = hashlib.sha256(compiled.encode()).hexdigest()
        target = f"slang/programs/{digest}.glsl"
        products[target] = (f"// Generated from {source_path.relative_to(root)}. See slang/upstream for licence/source.\n" + compiled).encode()
        values[key] = target
        for stage in ("vertex", "fragment"):
            hlsl_source = (f"// Generated from {source_path.relative_to(root)}. "
                           "See slang/upstream for licence/source.\n" +
                           hlsl[stage])
            hlsl_digest = hashlib.sha256(hlsl_source.encode()).hexdigest()
            hlsl_target = f"slang/hlsl/{hlsl_digest}.hlsl"
            products[hlsl_target] = hlsl_source.encode()
            values[f"hlsl_{stage}{i}"] = hlsl_target
        for slot in (0, 1):
            values[f"hlsl_buffer{slot}_size{i}"] = str(
                hlsl_meta["buffers"][slot]["size"])
            values[f"hlsl_buffer{slot}_members{i}"] = encode_hlsl_members(
                hlsl_meta["buffers"][slot]["members"])
        values[f"hlsl_textures{i}"] = encode_hlsl_textures(
            hlsl_meta["textures"])
        values[f"hlsl_parameters{i}"] = ";".join(
            f"{name}:{value:.9g}" for name, value in
            sorted(hlsl_meta["parameters"].items()))
    if feedback:
        number = next(iter(feedback))
        if number >= count:
            raise Unsupported("feedback references a nonexistent pass")
        if number == count - 1 and not any(k in values for k in (f"scale_type{number}", f"scale_type_x{number}", f"scale_type_y{number}")):
            values[f"scale_type{number}"] = "viewport"
            values[f"scale{number}"] = "1"
        values["feedback_pass"] = str(number)
    for name in luts:
        resource = within(root, data[name][1] / values[name])
        dependencies.add(resource)
        content = resource.read_bytes()
        target = f"slang/assets/{hashlib.sha256(content).hexdigest()}{resource.suffix}"
        products[target] = content
        values[name] = target
    for target, content in products.items():
        destination = output / target
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)
    destination = output / "slang" / (path.stem + ".glslp")
    destination.write_text("# Generated from Slang; do not edit.\n" + "\n".join(f'{k} = "{v}"' for k, v in values.items()) + "\n")
    return required_version


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("upstream", type=Path)
    parser.add_argument("output", type=Path, help="destination retroarch-shaders/crt directory")
    parser.add_argument("--preset", action="append", help="top-level CRT name, repeatable")
    parser.add_argument("--revision", help="upstream commit for an exported source snapshot")
    args = parser.parse_args()
    root = args.upstream.resolve()
    revision = (args.revision or
                run("git", "-C", str(root), "rev-parse", "HEAD").strip())
    if not re.fullmatch(r"[0-9a-fA-F]{40}", revision):
        parser.error("upstream revision must be a 40-character commit hash")
    output = args.output.resolve()
    if (output / "slang").exists():
        parser.error("destination slang directory must not exist; generate into a fresh staging directory")
    (output / "slang").mkdir(parents=True)
    report = {"upstream": "https://github.com/libretro/slang-shaders", "revision": revision,
              "glslang": run("glslangValidator", "--version"), "accepted": [], "rejected": {}, "minimum_glsl": {}}
    dependencies = {root / "README.md"}
    paths = [root / "crt" / (name + ".slangp") for name in args.preset] if args.preset else sorted((root / "crt").glob("*.slangp"))
    for path in paths:
        local_dependencies = set()
        try:
            version = import_preset(root, path, output, local_dependencies)
            report["accepted"].append(path.stem)
            report["minimum_glsl"][path.stem] = version
            dependencies.update(local_dependencies)
            print("OK", path.stem, flush=True)
        except (Unsupported, OSError, KeyError, ValueError) as error:
            report["rejected"][path.stem] = re.sub(r'[^\s]*powervlc-slang-[^/\s]+/', '<compiler-temp>/', str(error)).replace(str(root), '<upstream>')
            print("SKIP", path.stem, str(error).splitlines()[-1][:160], flush=True)
    dependencies.update(p for p in root.rglob("*") if p.is_file() and
                        p.name.lower().startswith(("license", "copying")) and
                        ".git" not in p.parts)
    for path in sorted(dependencies):
        target = output / "slang/upstream" / path.relative_to(root)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
    (output / "slang/import-report.json").write_text(json.dumps(report, indent=2) + "\n")
    (output / "slang/catalog.txt").write_text("\n".join(report["accepted"]) + "\n")
    lightweight = {"crt-1tap", "crt-cgwg-fast", "crt-geom-mini", "crt-hyllian-fast", "crt-lottes-fast", "crt-mattias", "crt-pi", "zfast-crt"}
    (output / "slang/catalog.h").write_text(
        "/* Generated by extras/tools/import-slang-shaders.py. */\n" +
        "".join('    { "slang/%s", %s, %d },\n' %
                (name, "true" if name in lightweight else "false", report["minimum_glsl"][name])
                for name in report["accepted"]))
    print(f'{len(report["accepted"])} accepted; {len(report["rejected"])} rejected')


if __name__ == "__main__":
    main()

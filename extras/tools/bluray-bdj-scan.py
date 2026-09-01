#!/usr/bin/env python3
"""Fast BD-J compatibility scan for Blu-ray ISO images.

Only UDF metadata and BDMV/JAR/*.jar are read; video streams are never opened.
The runtime probe is executed with the same java.base patching model as
libbluray, which is important for the Java 17+ socket implementation check.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import zipfile


REQUIRED_JAVA = (8, 11, 17, 25)
DEFAULT_ROOT = Path(".")
SCRIPT_DIR = Path(__file__).resolve().parent / "bluray-bdj-scan"
REPO_ROOT = Path(__file__).resolve().parents[2]
CONTRIB = REPO_ROOT / "contrib/aarch64-apple-darwin24"
BDJ_JAR = CONTRIB / "share/java/libbluray-j2se-1.5.0.jar"
AWT_JAR = CONTRIB / "share/java/libbluray-awt-j2se-1.5.0.jar"


def run(command: list[str], timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=timeout)


def java_major(java: Path) -> int | None:
    result = run([str(java), "-version"], 15)
    text = result.stderr + result.stdout
    match = re.search(r'version "(?:1\.)?(\d+)', text)
    return int(match.group(1)) if match else None


def discover_javas(explicit: list[str]) -> dict[int, Path]:
    candidates: list[Path] = []
    candidates.extend(Path(item).expanduser() for item in explicit)
    sdkman = Path.home() / ".sdkman/candidates/java"
    if sdkman.is_dir():
        candidates.extend(path for path in sdkman.iterdir() if path.name != "current")
    candidates.extend(Path("/Library/Java/JavaVirtualMachines").glob("*/Contents/Home"))

    found: dict[int, Path] = {}
    for home in candidates:
        java = home / "bin/java"
        if not java.is_file():
            continue
        try:
            major = java_major(java)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if major in REQUIRED_JAVA and major not in found:
            found[major] = home.resolve()
    return found


def compile_helpers(build: Path, java8: Path) -> tuple[Path, Path]:
    extractor = build / "bluray-bdj-extract"
    source = SCRIPT_DIR / "bluray_bdj_extract.c"
    command = [
        "cc", "-std=c11", "-Wall", "-Wextra", "-O2",
        f"-I{CONTRIB / 'include'}", str(source),
        str(CONTRIB / "lib/libbluray.a"), f"-L{CONTRIB / 'lib'}",
        "-lfontconfig", "-lfreetype", "-lz", "-lxml2", "-lm",
        "-framework", "CoreFoundation", "-framework", "DiskArbitration",
        "-o", str(extractor),
    ]
    result = run(command)
    if result.returncode:
        raise RuntimeError("échec de compilation de l'extracteur:\n" + result.stderr)

    probe = build / "probe"
    probe.mkdir()
    result = run([
        str(java8 / "bin/javac"), "-source", "8", "-target", "8",
        "-cp", str(BDJ_JAR), "-d", str(probe),
        str(SCRIPT_DIR / "BDJJavaCompatProbe.java"),
    ])
    if result.returncode:
        raise RuntimeError("échec de compilation du probe Java:\n" + result.stderr)
    return extractor, probe


def probe_command(home: Path, major: int, probe: Path,
                  jar_directory: Path | None) -> list[str]:
    java = str(home / "bin/java")
    mode = ["scan", str(jar_directory)] if jar_directory else ["shim"]
    if jar_directory:
        classpath = os.pathsep.join((str(probe), str(BDJ_JAR), str(AWT_JAR)))
        return [java, "-cp", classpath,
                "org.videolan.BDJJavaCompatProbe"] + mode
    if major == 8:
        return [java, f"-Xbootclasspath/p:{probe}",
                "org.videolan.BDJJavaCompatProbe"] + mode

    base_patch = str(probe)
    command = [java, f"--patch-module=java.base={base_patch}"]
    return command + ["-m", "java.base/org.videolan.BDJJavaCompatProbe"] + mode


def run_probe(home: Path, major: int, probe: Path,
              jar_directory: Path | None) -> dict[str, object]:
    try:
        result = run(probe_command(home, major, probe, jar_directory), 90)
    except subprocess.TimeoutExpired:
        return {"java": major, "ok": False, "error": "timeout"}
    output = result.stdout.strip().splitlines()
    failures = [line for line in output if line.startswith("CLASS\tFAIL\t")]
    summary = next((line for line in reversed(output)
                    if line.startswith("SCAN\t")), None)
    shim_ok = any(line.startswith("SHIM\tOK\t") for line in output)
    scan_ok = summary is not None and summary.startswith("SCAN\tOK\t")
    return {
        "java": major,
        "ok": result.returncode == 0 and (scan_ok if jar_directory else shim_ok),
        "shim_ok": shim_ok,
        "summary": summary,
        "failures": failures[:25],
        "failure_count": len(failures),
        "error": result.stderr.strip()[-2000:] if result.returncode else "",
    }


def inspect_class_versions(directory: Path) -> dict[str, object]:
    counts: dict[int, int] = {}
    classes = 0
    bad_archives: list[str] = []
    internal_api: set[str] = set()
    signatures = ((b"sun/", "sun.*"), (b"jdk/internal/", "jdk.internal.*"),
                  (b"setSecurityManager", "System.setSecurityManager"))
    for jar in sorted(directory.glob("*.jar")):
        try:
            with zipfile.ZipFile(jar) as archive:
                for info in archive.infolist():
                    if not info.filename.endswith(".class"):
                        continue
                    data = archive.read(info)
                    if len(data) < 8 or data[:4] != b"\xca\xfe\xba\xbe":
                        continue
                    major = struct.unpack(">H", data[6:8])[0]
                    counts[major] = counts.get(major, 0) + 1
                    classes += 1
                    for needle, label in signatures:
                        if needle in data:
                            internal_api.add(label)
        except (OSError, zipfile.BadZipFile) as error:
            bad_archives.append(f"{jar.name}: {error}")
    newest = max(counts, default=0)
    return {
        "classes": classes,
        "class_majors": counts,
        "java8_bytecode_ok": newest <= 52,
        "bad_archives": bad_archives,
        "risky_api_references": sorted(internal_api),
    }


def scan_iso(iso: Path, workspace: Path, extractor: Path, probe: Path,
             javas: dict[int, Path], deep: bool) -> dict[str, object]:
    digest = hashlib.sha1(str(iso).encode("utf-8")).hexdigest()[:12]
    output = workspace / digest
    output.mkdir()
    extracted = run([str(extractor), str(iso), str(output)], 120)
    result: dict[str, object] = {"iso": str(iso), "ok": False}
    if extracted.returncode == 3 and "NO_BDJ" in extracted.stdout:
        result.update({"ok": True, "skipped": True, "reason": "aucun code BD-J"})
        return result
    if extracted.returncode:
        result["extract_error"] = extracted.stderr.strip()[-2000:]
        return result
    jars = sorted(output.glob("*.jar"))
    result["jars"] = len(jars)
    static = inspect_class_versions(output)
    result["static"] = static
    runtime = []
    if deep:
        for major in REQUIRED_JAVA:
            runtime.append(run_probe(javas[major], major, probe, output))
    result["runtime"] = runtime
    if runtime:
        failure_sets = {tuple(item.get("failures", [])) for item in runtime}
        result["java_version_specific"] = len(failure_sets) > 1
    result["ok"] = bool(jars) and static["java8_bytecode_ok"] and not static["bad_archives"] \
        and all(item["ok"] for item in runtime)
    return result


def iso_paths(target: Path) -> list[Path]:
    if target.is_file() and not target.name.startswith("._"):
        return [target]
    return sorted(path for path in target.rglob("*")
                  if path.is_file() and path.suffix.lower() == ".iso"
                  and not path.name.startswith("._"))


def print_result(result: dict[str, object]) -> None:
    marker = "OK" if result["ok"] else "ECHEC"
    print(f"[{marker}] {result['iso']}")
    if result.get("skipped"):
        print(f"  ignorée: {result['reason']}")
        return
    if "extract_error" in result:
        print(f"  extraction: {result['extract_error']}")
        return
    static = result["static"]
    print(f"  {result['jars']} JAR, {static['classes']} classes, "
          f"bytecode Java 8: {'OK' if static['java8_bytecode_ok'] else 'NON'}")
    if static["bad_archives"]:
        print("  archives invalides: " + "; ".join(static["bad_archives"]))
    if static["risky_api_references"]:
        print("  références à surveiller: " +
              ", ".join(static["risky_api_references"]))
    for runtime in result["runtime"]:
        state = "OK" if runtime["ok"] else "ECHEC"
        detail = runtime.get("summary") or runtime.get("error") or ""
        print(f"  Java {runtime['java']}: {state} {detail}")
        for failure in runtime.get("failures", [])[:5]:
            print("    " + failure.replace("\t", " | "))
    if result["runtime"] and not result["ok"]:
        if result.get("java_version_specific"):
            print("  incompatibilité dépendante de la version de Java")
        else:
            print("  défaut identique sur les quatre versions de Java")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", nargs="?", type=Path, default=DEFAULT_ROOT,
                        help="ISO ou dossier à parcourir")
    parser.add_argument("--java-home", action="append", default=[],
                        help="JAVA_HOME supplémentaire (répétable)")
    parser.add_argument("--quick", action="store_true",
                        help="analyse statique des disques; probe JVM global seulement")
    parser.add_argument("--runtime-only", action="store_true",
                        help="teste uniquement les shims libbluray sur les quatre JVM")
    parser.add_argument("--jobs", type=int, default=4,
                        help="ISO analysées en parallèle (défaut: 4)")
    parser.add_argument("--json", type=Path,
                        help="écrit aussi le rapport JSON ici")
    args = parser.parse_args()

    missing_inputs = [path for path in (BDJ_JAR, AWT_JAR,
                      SCRIPT_DIR / "bluray_bdj_extract.c",
                      SCRIPT_DIR / "BDJJavaCompatProbe.java") if not path.is_file()]
    if missing_inputs:
        parser.error("build libbluray incomplet: " + ", ".join(map(str, missing_inputs)))

    javas = discover_javas(args.java_home)
    missing = [str(version) for version in REQUIRED_JAVA if version not in javas]
    if missing:
        parser.error("JVM LTS introuvable(s): " + ", ".join(missing))
    print("JVM: " + ", ".join(f"Java {v}={javas[v]}" for v in REQUIRED_JAVA))

    with tempfile.TemporaryDirectory(prefix="powervlc-bdj-scan-") as temporary:
        workspace = Path(temporary)
        extractor, probe = compile_helpers(workspace, javas[8])
        shim_results = [run_probe(javas[v], v, probe, None) for v in REQUIRED_JAVA]
        for item in shim_results:
            print(f"Shim Java {item['java']}: {'OK' if item['ok'] else 'ECHEC'} "
                  f"{item.get('error', '')}")
        if not all(item["ok"] for item in shim_results):
            return 1
        if args.runtime_only:
            return 0

        images = iso_paths(args.target.expanduser())
        if not images:
            parser.error(f"aucune ISO trouvée dans {args.target}")
        print(f"{len(images)} ISO à analyser ({args.jobs} en parallèle)")
        results: list[dict[str, object]] = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            futures = [pool.submit(scan_iso, image, workspace, extractor, probe,
                                   javas, not args.quick) for image in images]
            for future in concurrent.futures.as_completed(futures):
                result = future.result()
                results.append(result)
                print_result(result)
        results.sort(key=lambda item: str(item["iso"]))
        report = {"jvms": {str(v): str(javas[v]) for v in REQUIRED_JAVA},
                  "shim": shim_results, "discs": results}
        if args.json:
            args.json.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n",
                                 encoding="utf-8")
        failed = sum(not result["ok"] for result in results)
        print(f"Bilan: {len(results) - failed} OK, {failed} en échec")
        return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

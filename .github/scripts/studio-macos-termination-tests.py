#!/usr/bin/env python3
"""Exercise the real macOS termination adapter without a GUI or system logout."""

import pathlib
import subprocess
import sys
import tempfile


def main():
    root = pathlib.Path(__file__).resolve().parents[2]
    app = pathlib.Path(sys.argv[1]).resolve()
    frameworks = app / "Contents/Frameworks"
    runner = root / "code/anywork/macos/Runner"
    common = root / "code/anywork/runner_common"
    assert (frameworks / "FlutterMacOS.framework").is_dir(), "Build the native app first"
    # Flutter strips framework headers from the distributable app. Compile with
    # the matching SDK headers, then load the framework shipped in the app.
    configuration = runner.parent / "Flutter/ephemeral/Flutter-Generated.xcconfig"
    flutter_root = next(
        line.split("=", 1)[1] for line in configuration.read_text().splitlines()
        if line.startswith("FLUTTER_ROOT=")
    )
    sdk_frameworks = pathlib.Path(flutter_root) / (
        "bin/cache/artifacts/engine/darwin-x64-release/"
        "FlutterMacOS.xcframework/macos-arm64_x86_64"
    )
    with tempfile.TemporaryDirectory(prefix="anywork-appkit-termination-") as directory:
        scratch = pathlib.Path(directory)
        # Remove only the executable entry-point attribute so the fixture owns
        # main(); all production delegate methods are compiled unchanged.
        delegate = (runner / "AppDelegate.swift").read_text()
        assert delegate.count("\n@main\n") == 1
        source = scratch / "AppDelegate.swift"
        source.write_text(delegate.replace("\n@main\n", "\n"))
        objects = []
        for file in [
            runner / "AnyworkHost.mm",
            common / "studio_host_lifecycle.cc",
            common / "studio_instance.cc",
            runner.parent / "RunnerTests/termination_test.mm",
        ]:
            output = scratch / (file.stem + ".o")
            subprocess.run([
                "xcrun", "clang++", "-c", "-std=c++17", "-fobjc-arc",
                "-I", str(runner), "-I", str(common), "-F", str(sdk_frameworks),
                str(file), "-o", str(output),
            ], check=True)
            objects.append(str(output))
        executable = scratch / "termination-test"
        subprocess.run([
            "xcrun", "swiftc", "-parse-as-library", "-module-name", "Runner",
            "-module-cache-path", str(scratch / "modules"),
            "-import-objc-header", str(runner / "Runner-Bridging-Header.h"),
            "-F", str(sdk_frameworks), "-framework", "FlutterMacOS",
            "-framework", "Cocoa", "-framework", "UniformTypeIdentifiers", "-lc++",
            "-Xlinker", "-rpath", "-Xlinker", str(frameworks),
            str(source), *objects, "-o", str(executable),
        ], check=True)
        for mode in ["clean", "degraded", "repeated", "window"]:
            diagnostics = scratch / mode
            diagnostics.mkdir()
            result = subprocess.run(
                [str(executable), mode, str(diagnostics)], capture_output=True,
                text=True, timeout=10,
            )
            expected = 1 if mode == "degraded" else 0
            assert result.returncode == expected, (mode, result.returncode, result.stderr)
            assert result.stdout.count("cleanup-requested") == 1, (mode, result.stdout)
            assert ("appkit-reply-after-cleanup" in result.stdout) == (mode != "window"), (
                mode, result.stdout,
            )
            log = (diagnostics / "anywork-exit-diagnostics.log").read_text()
            assert "event=finish" in log, (mode, log)
            assert ("code=degradedExit" if expected else "code=cleanExit") in log, (mode, log)
            print(f"AppKit termination {mode}: passed", flush=True)


if __name__ == "__main__":
    main()

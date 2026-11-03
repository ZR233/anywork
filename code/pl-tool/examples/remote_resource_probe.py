#!/usr/bin/env python3
"""Run the canonical public-client acceptance; no parallel implementation of the wire protocol."""
import argparse
from pathlib import Path
import subprocess

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("helper", type=Path)
    args = parser.parse_args()
    _ = args.helper.resolve()
    root = Path(__file__).resolve().parents[3]
    result = subprocess.run([
        "cargo", "test", "--locked", "-p", "pl-tool", "--test", "remote_resource",
        "--", "--nocapture",
    ], cwd=root, check=False)
    raise SystemExit(result.returncode)

if __name__ == "__main__":
    main()

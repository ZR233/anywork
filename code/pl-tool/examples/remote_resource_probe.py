#!/usr/bin/env python3
"""Run the canonical public-client acceptance; no parallel implementation of the wire protocol."""
import argparse
from pathlib import Path
import subprocess

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("helper", type=Path)
    parser.add_argument("--operations", type=int, default=10000)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    result = subprocess.run([
        "cargo", "run", "--locked", "-p", "pl-tool", "--example", "remote_resource_validation",
        "--", str(args.helper.resolve()), str(args.operations),
    ], cwd=root, check=False)
    raise SystemExit(result.returncode)

if __name__ == "__main__":
    main()

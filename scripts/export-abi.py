#!/usr/bin/env python3
"""Regenerate the delivered ABIs from the pinned Foundry build; no network or test cheatcodes."""
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
for name in ("Band", "PriceBandHook"):
    output = subprocess.check_output(
        ["forge", "inspect", f"src/{name}.sol:{name}", "abi", "--json"], cwd=ROOT, text=True
    )
    abi = json.loads(output)
    path = ROOT / "docs" / "abi" / f"{name}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(abi, indent=2) + "\n")
    print(path.relative_to(ROOT))

#!/usr/bin/env python3
"""Run forge build first. Site ABI is a delivered ordinary file, not a runtime dependency on out/."""
import json
import pathlib
names = ['SeasonPot', 'DeedVault', 'SwarmopolyGame']
abi = {name: json.loads(pathlib.Path(f'out/{name}.sol/{name}.json').read_text())['abi'] for name in names}
pathlib.Path('site/abi.json').write_text(json.dumps(abi, separators=(',', ':')) + '\n')

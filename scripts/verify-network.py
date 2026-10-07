#!/usr/bin/env python3
"""Read-only dependency verification. Never reads wallet keys or broadcasts."""
import datetime
import json
import pathlib
import subprocess

RPC = 'https://rpc.mainnet.chain.robinhood.com'
HOOK = '0x19bec7c2e1b2aadaf67b259744751a9960d66000'
CURRENCY = '0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127'

def cast(*args):
    return subprocess.check_output(['cast', *args, '--rpc-url', RPC, '--rpc-timeout', '20'], text=True).strip()

def main():
    chain = int(cast('chain-id'))
    assert chain == 4663, 'Wrong chain'
    block = cast('block-number')
    manager = cast('call', HOOK, 'poolManager()(address)', '--block', block)
    assert len(manager) == 42 and int(manager, 16), 'Invalid PoolManager response'
    evidence = {'checkedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'rpc': RPC,
                'chainId': chain, 'block': int(block), 'hook': HOOK, 'poolManager': manager, 'currency': CURRENCY}
    for name, address in [('hook', HOOK), ('poolManager', manager), ('currency', CURRENCY)]:
        code = cast('code', address, '--block', block)
        assert code != '0x', f'{name} has no code'
        evidence[name + 'RuntimeBytes'] = (len(code) - 2) // 2
    evidence['currencySymbol'] = cast('call', CURRENCY, 'symbol()(string)', '--block', block)
    evidence['currencyDecimals'] = int(cast('call', CURRENCY, 'decimals()(uint8)', '--block', block))
    assert evidence['currencyDecimals'] == 18, 'Game economics require 18-decimal IMD'
    pathlib.Path('docs/network-verification.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence, indent=2))

if __name__ == '__main__':
    main()

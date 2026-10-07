# Deployment and operator handoff

## Verified external configuration

Target Robinhood Chain **4663**, ETH for gas, RPC `https://rpc.mainnet.chain.robinhood.com`, explorer `https://robin.etherscan.io`.

| Parameter | Value |
|---|---|
| Currency | `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127` |
| Currency metadata read | IMD, 18 decimals |
| Discovery hook | `0x19bec7c2e1b2aadaf67b259744751a9960d66000` |
| `hook.poolManager()` result | `0x8366a39CC670B4001A1121B8F6A443A643e40951` |
| Evidence block | 82,405,974 |

The evidence was collected on 2026-10-07. All three external addresses had code at the recorded block. `docs/network-verification.json` stores the responses and code lengths. Re-run `python3 scripts/verify-network.py` before release; compare the result with the manifest and site configuration. The discovery hook is not automatically assigned to listed pools; each tile supplies its exact initialized PoolKey.

## Contracts in manifest order

1. `SeasonPot($owner, currency)`
2. `DeedVault($owner, currency, verifiedPoolManager)`
3. `SwarmopolyGame($owner, currency, $contract:DeedVault, $contract:SeasonPot)`

Use `launch.json`. `$owner` comes from the actual launch owner, never the factory caller. Constructors are nonpayable and fully establish immutable dependencies. No wallet key, transaction broadcaster, compiler binary, `.env`, or network-dependent test is included. The explicit owner can be a multisig; owner loss cannot be repaired in these immutable contracts.

This game's brief explicitly requires post-deployment one-shot `bindGame` calls. A deployment platform that generically prohibits every post-deployment call must support this application-specific owner handoff; deploying the constructors alone does not start a usable season.

The contracts must be deployed by the authorized deployment service, and then the operator must:

1. Independently review the code and actual currency/pool/hook implementations before real funds are admitted. Verify source/runtime against these settings.
2. Record confirmed addresses and the earliest deployment block. Check currency, owner and dependency getters, plus the manager returned by the supplied hook.
3. Call `SeasonPot.bindGame(game)` and `DeedVault.bindGame(game)` from the configured owner. The site owner panel supports these calls. Each is irreversible and permitted only once; game startup checks both bindings.
4. Review each candidate ERC20 for normal transfers (no fees, rebases or misleading return values), its administrator powers and blacklist/pause behavior. Review the exact pool's initialization, liquidity, fee mode and hook. Only then list a vacant tile via the game. Listings can be corrected only while deed assets, shares and all sponsor liabilities are zero; this includes unused old-season funding and unclaimed lander awards. There is no delisting. Verify the PoolKey before accepting any funding.
5. Optionally set capped parameters while no season is active. Suggested initial season: buy-in `10000000000000000000`, duration `2592000`, bond `1000000000000000000`, max buy `100000000000000000000` (10 IMD / 30 days / 1 IMD / 100 IMD). These are suggestions, not signed configuration. The stronger timeout charge is the maximum possible landing exposure, up to the player's balance, even if the bond is smaller.
6. Start the season. Anyone can fund the pot with `game.fundPot(amount)`. Buy-ins also fund it. Do not directly transfer currency to the pot: unsolicited transfers are deliberately outside internal accounting.
7. Monitor timeouts and let anyone call `expireRoll(player)`; the operator should run a public keeper. Finalization needs a caller after the end. No keeper rewards are charged. A sequencer outage lasting beyond the reveal window can cause penalties.

## Website and publishing

The site is ordinary HTML/CSS/ES modules with ethers v6.13.5 vendored locally. No npm installation or network build is necessary. ABI JSON is delivered; regenerate after contract edits with `forge build` then `python3 scripts/export-abi.py`.

Apply only a **confirmed** deployment handoff:

```sh
node scripts/configure-site.mjs GAME_ADDRESS VAULT_ADDRESS POT_ADDRESS DEPLOYMENT_BLOCK
python3 -m http.server 8080 --directory site
```

The configuration command performs read-only chain, code, dependency and owner checks before writing `site/config.json`. It does not send transactions. The application also validates chain/code/dependencies at runtime and requests exact token approvals. Approvals and every game transaction require the connected wallet's signature. Use HTTPS in production (or localhost), including IPFS gateways with EIP-1193 wallets. Retain the relative directory layout including `vendor/`, `abi.json`, `rules.html`, and `config.json`. Publish the complete `site/` directory to the approved **swarmopoly** label. Review and version the resulting CID with the deployment addresses; no GitHub push, IPFS publish, or onchain deployment was performed in this worker.

Roll secrets are stored in localStorage under chain/game/account before commitment and can be exported. They are sensitive until the reveal. Keep the tab open; automatic reveal still requires wallet confirmation. The browser will not repeatedly prompt after rejection; use Resume reveal. Losing storage requires importing the original secret; it cannot be reconstructed from the commitment. The interface exposes expiry resolution if the deadline is missed. Operators must explain this to players and protect the site's origin from script injection.

The site queries Joined and DeedBought logs in 2,000-block chunks and rereads current contract state, with a 12-block overlap. For large histories, run a compatible indexed RPC; initial sync can be slow. The deployment block must be the earliest of the three contracts, not a recent convenient block. Pagination/indexer enhancements are an operational scaling item, not a custody dependency.

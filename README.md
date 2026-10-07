# Swarmopoly v2

The live IMD board game on **Robinhood Chain, chain ID 4663**, now styled as the Swarmopoly arcade table. Source is in `site/`; the complete static export is in `dist/`. All runtime assets, including ethers, Space Grotesk, ABIs and rules, are local. The website works at an IPFS gateway subpath without rewrites or a CDN.

This continuation changes no Solidity, dependencies, Foundry configuration or contract deployment. The existing IMD token remains `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127`.

| Contract | Live address |
| --- | --- |
| SwarmopolyGame | `0xa5ae5282aa914a4ce689f1609462e2a5eaa2490d` |
| DeedVault | `0x5a3dc16c23447f70c414145118ee2e9984260482` |
| SeasonPot | `0xd77f768d634328bdfa826051457c974f4028a6dc` |

Deployment block: **82454371**. `site/config.json` pins the launch. Reads verify chain ID, deployed code, currency, PoolManager, owners and contract dependencies before enabling transactions. Publicnode is the first RPC; the supplied mainnet RPC handles historical logs when Publicnode refuses archive requests. Board/player/deed history is indexed in bounded batches, with a visible progress state. At validation time the live contracts had no season, no listed tiles and an empty pot; those are inviting launch states, not fabricated gameplay.

## Build and preview

Requires Node.js 22+ for build/check scripts. No package install is needed to build or serve this native-module site.

```sh
node site/build.mjs
python3 -m http.server 8080 --directory .
```

Open `http://localhost:8080/dist/`. Serving over HTTP is required; opening `index.html` directly as a file will block its module/JSON requests. `node site/build.mjs` replaces only `dist/` using a runtime asset allowlist. After editing `site/`, always rebuild and include the resulting export in the submission. The export contains 12 files and is approximately 655 KB uncompressed.

## Install validation tools and check

The original `site/package.json` is preserved. Additional checking tools and their exact lockfile live in `site/tooling/`. Install them outside the repository so caches and dependencies cannot enter the submission:

```sh
mkdir -p /tmp/swarmopoly-tools
cp site/tooling/package.json site/tooling/package-lock.json /tmp/swarmopoly-tools/
npm ci --prefix /tmp/swarmopoly-tools --cache /tmp/swarmopoly-npm-cache
PLAYWRIGHT_BROWSERS_PATH=/tmp/swarmopoly-browsers /tmp/swarmopoly-tools/node_modules/.bin/playwright install chromium
node site/build.mjs
/tmp/swarmopoly-tools/node_modules/.bin/tsc --project site/tsconfig.json
node --test test/site.test.mjs
CHECK_PACKAGE=/tmp/swarmopoly-tools/package.json PLAYWRIGHT_BROWSERS_PATH=/tmp/swarmopoly-browsers node test/site-browser.mjs
```

The typecheck uses TypeScript `checkJs` over the complete application and pure presentation helpers. A small declaration file marks the ABI-dynamic vendored ethers boundary; it does not typecheck third-party minified code. Browser tests start their own local server under `/preview/`, use the production export, and exercise real ethers encoding with a local JSON-RPC/wallet fixture. They never send a live transaction.

Actual results and scoped Better Interface review are in [docs/SITE-VALIDATION.md](docs/SITE-VALIDATION.md). Production build and typecheck passed; all eight source/export tests and six browser scenarios passed. Automated accessibility checks found no violations in the inspected desktop, mobile, populated purchase and Rules states. Live reads and historical fallback were also checked. Real wallet-extension signing, mainnet writes, physical devices, native screen readers and IPFS pin propagation were not tested.

## Publish

Publish the **contents of `dist/`** as the site named **`swarmopoly`**. The contributor publisher must serve this export; it does not need to rebuild. Relative module, font, CSS and JSON URLs work at `/ipfs/<CID>/`; navigation uses hashes and Rules has its own exported page.

For a separately operated IPFS node:

```sh
ipfs add --cid-version=1 --recursive dist
```

Pin the returned directory CID, verify its `index.html`, then point the hosting service’s `swarmopoly` name at that CID. This workspace has no IPFS CLI or publication credentials, so no CID or public URL is claimed here. The complete export is ready for the assignment’s publishing service.

## Using the game

Explore without a wallet. Connect an injected Ethereum-compatible wallet; use **Add Robinhood Chain** if needed. Join an active season, then deposit a play balance. Joining, deed purchases and pot contributions spend IMD from the wallet separately. The UI approves exact amounts. Keep ETH in the wallet for gas.

Rolling is commit then reveal: keep the tab open and confirm both wallet requests. The secret is saved before the commit signature; download it from **Save recovery secret** while pending. Returning to the same origin and wallet can resume a roll. If a new IPFS CID changes the browser origin, restore the exported secret in recovery controls. A missed deadline forfeits the reserved balance; the UI retains recovery and expired-roll resolution. EVM block time, not RPC block height, gates reveals.

My Swarm includes deposit/withdraw, lock countdowns, claimable rent and redemption. The big Claim rent action submits one transaction per deed and stops if a request fails or is declined. “None” on the lock card still has the contract’s 24-hour minimum; House locks 30 days and Hotel 90 days. Leaderboard & pot includes funding, prize claims and season finalization. Owner controls appear only for the immutable owner and explain permanent one-shot binding, listing, parameters, pauses and season creation. No owner action was performed by this job.

## Project documents and licenses

- [Implemented design system](DESIGN.md)
- [Website validation and limitations](docs/SITE-VALIDATION.md)
- [Game rules](docs/RULES.md) and exported [player rules](site/rules.html)
- [Original deployment handoff](docs/DEPLOYMENT.md), [contract security review](docs/REVIEW.md), [contract test coverage](docs/TESTING.md)

The older contract documents describe the original build job; the live addresses and website status above supersede their pre-deployment website notes. Contract tests remain available via `forge test` with the existing pinned configuration; they were not rerun for this frontend-only change.

Original vendoring remains OpenZeppelin Contracts v5.0.2, forge-std v1.9.7 and ethers v6.13.5, with their included licenses. Space Grotesk is copied from the Swarmopoly v1 project and includes its OFL. The six original player shapes and corner icons are implemented as local inline SVG geometry. Better Interface/Impeccable guidance attribution and license texts are preserved in [docs/INTERFACE-LICENSE.txt](docs/INTERFACE-LICENSE.txt). No submodule, registry archive, generated dependency directory or cache is part of this deliverable.

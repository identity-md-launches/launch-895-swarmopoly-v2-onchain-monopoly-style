# Website validation — 7 October 2026

This report covers the final `site/` source and the corresponding `dist/` static export. It is worker-run evidence, not independent certification. The existing contracts, ABI JSON, ethers bundle, Foundry configuration and dependencies were preserved. No live transaction was sent.

## Commands and actual results

| Check | Actual result |
| --- | --- |
| `node site/build.mjs` | Pass. 12 runtime files; 655,297 bytes. Local CSS, font, ethers, JSON, module and Rules URLs. |
| `/tmp/swarmopoly-tools/node_modules/.bin/tsc --project site/tsconfig.json` | Pass. TypeScript 5.7.3 checks both application JS modules; vendored ABI-dynamic calls use the documented declaration boundary. |
| `node --test test/site.test.mjs` | 8 passed, 0 failed. Configuration, all three canonical ABI hashes, 40-square ring, movement/relocation, six stable player identities, clocks/dice, action ABI availability, identical source/export assets. |
| `CHECK_PACKAGE=/tmp/swarmopoly-tools/package.json PLAYWRIGHT_BROWSERS_PATH=/tmp/swarmopoly-browsers node test/site-browser.mjs` | 6 scenarios passed, 0 failed. Real production export, served at `/preview/`; real ethers serializes calls against an isolated JSON-RPC and injected-wallet fixture. |
| `node scripts/verify-site.mjs` | Pass. Read-only live checks of chain ID, code at five dependencies, immutable dependency/owner relationships, exact deployment block, season, pot, bindings, listed tiles and historical fallback. Raw output: `docs/site-evidence/site-live-verification.json`. |
| `git diff --check` | Pass. |

The existing `site/package.json` is unchanged. The new optional tool manifest and exact npm lock are in `site/tooling/`. Dependencies, browser binaries and npm cache were installed only under `/tmp`. The original standalone browser MCP tool failed to start because its expected chrome-for-testing binary was absent. Rendered verification instead used locally installed Playwright 1.51.1 / Chromium 134.0.6998.35, plus axe-core 4.10.2. Screenshots were opened and inspected; they are not inferred from source.

## Interaction coverage

The browser suite checks these scenarios:

1. Launch/no-wallet: forty squares, tile selection and equivalent selector, Board/My Swarm/Leaderboard navigation, owner hidden, Add Robinhood Chain explanation, disabled wallet actions, loaded local font, responsive ordering, skip link and visible keyboard focus, reduced-motion CSS, Rules navigation, axe audits.
2. Wallet/account: exact-amount approval, season join, deposit and withdrawal with proper arguments, zero-amount rejection before submission, `fundPot(7.5 IMD)`, explorer links and account-change clearing.
3. Roll/deeds: secret saved before commit, labeled waiting state, EVM clock gate independent of high RPC block number, successful reveal and secret removal, dice values, final square, quote invalidation when slippage changes, 30-day purchase and minimum output, lock countdown, disabled locked redemption, rent claim and unlocked redemption.
4. Owner: hidden before connection, visible only for fixture owner, both one-shot bind targets and post-bind disabling, property listing, parameters, pause and season start with the real ABI.
5. Network: wallet switches away, writes disable, designed wrong-network state appears, switching back restores the same game.
6. Chance/jail: revealed Chance relocation to GO, flipping-card class and outcome, jail bars, bail action and clearing the stale jail outcome after release.

A separate normal-motion browser pass observed the computed dice tumble duration at **0.9 seconds**, a **+salary · 1 IMD** chip, the **0.8 IMD → holders** rent effect and a correctly quoted purchase card. This pass used fixture values, not claims about live gameplay. The production page has no demo mode or fixture injection code. Both fixture and source review confirm sequential claim transactions and recovery handlers; actual browser-extension prompts are not part of the fixture.

## Live chain findings

At 16:46 UTC, the verified contracts reported season **0**, available pot **0**, **0** listed tiles, and unbound SeasonPot/DeedVault. The deployment block read back as exactly **82454371**, with hash in the raw evidence. No owner initialization was performed.

The first RPC, `https://robinhood-rpc.publicnode.com`, refused historical logs with “Archive requests require a personal token.” The application now falls back for history to `https://rpc.mainnet.chain.robinhood.com`, which returned the requested deployment range successfully. No token, credential or alternate address was introduced. Indexing runs eight 5,000-block chunks per update and marks history as incomplete until the cursor reaches the head. Current balances/season/pot remain separately usable during indexing. Long histories can take several update cycles; RPC availability is external to the static export.

All three delivered ABI hashes match the pinned deployment values byte for byte after canonical key ordering and Keccak hashing. Onchain transaction success under current liquidity, token behavior, gas availability and wallet policies is not established by these read-only checks.

## Better Interface review

The pinned workflow, six core domains and documentation method were read and applied during implementation. The v1 `DESIGN.md` was fetched as the visual reference. This consolidated review records the root causes once; it does not treat a source check as a rendered observation.

| Domain | Coverage and evidence | Findings and correction |
| --- | --- | --- |
| Accessibility | Native links/buttons, input labels, lock fieldset, live status, skip link, focus styles, reduced motion. Simulated keyboard navigation and axe in desktop/mobile launch, populated purchase and Rules states. | A nested complementary landmark was flagged at `site/index.html:21`; the control group now uses an ordinary container. Axe recheck returned zero violations. The offscreen skip-link treatment was also clipped when unfocused to avoid appearing in a scrolled full-page capture. |
| Layout | `/preview/` export measured at 320, 390, 759, 760, 1000 and 1440 CSS pixels. Root text enlarged to 200%. No horizontal page overflow in checked states. At widths below 760, turn controls are above the width-scaled board. | Board density makes full miniature text unsuitable for decisions; `site/index.html:64` retains a full-size square selector and readable inspector. Controls and mobile layout are in `site/style.css:12`. |
| Writing | Reviewed transaction, empty, wallet, no-season, owner and purchase text against actual handlers and contract rules. | `site/index.html:42` explicitly explains that “None” still means a 24h minimum. One-shot binding and pot contributions explain their consequences. `site/app.js:198` exposes a recoverable connection failure; historical RPC errors use plain language. |
| Typography | Confirmed local Space Grotesk loaded via `document.fonts.check`; inspected screenshots for wrapping; numeric roles use monospace/tabular figures. Fields are 16px; prose and long addresses wrap. | Removed the Arial/olive styling. Full wallet values remain available; compact board labels have larger equivalents. No italic face is claimed. |
| Colors | Browser-computed solid foreground/background pairs measured below; axe contrast checks on empty and populated states. One active decision is green. | Contrast stayed above 4.5:1 for measured text pairs. Vacant dimming applies to stripes/background, not text opacity. No whole-panel opacity that weakens labels. |
| UI | Designed offline/no-wallet/wrong-network/no-season states; selected, disabled, pending, success and error states; six shapes, stacked pieces, dice, landing/Chance/jail, toast dismissals. | `site/app.js:81` gates action priority by eligibility and quote freshness. `site/app.js:168` reports approvals and sends with explorer links. Stale jail bars/outcome clear on bail; focused deed rows update values and button eligibility without replacing focus (`site/app.js:316`). |

### Measured color pairs

These are computed solid backgrounds from an actual populated browser render. Scanline compositing was not measured at every pixel.

| Foreground / background | Role | Ratio |
| --- | --- | --- |
| `#18210d` / `#b6f85d` | Buy deed label | 13.13:1 |
| `#a4a2b0` / `#19191f` | Panel description | 6.98:1 |
| `#f0f0f2` / `#16161e` | Center wordmark | 15.80:1 |
| `#f0f0f2` / `#19191f` | Pot text | 15.37:1 |
| `#a4a2b0` / `#16161e` | Center supporting text | 7.17:1 |
| `#a4a2b0` / `#212128` | Corner supporting text | 6.38:1 |
| `#a4a2b0` / `#1c1b25` | Selected lock caption | 6.79:1 |

### Functional findings fixed

- `site/config.json:10`: deployment fields were null. They now use the pinned live addresses and deployment block.
- `site/app.js:206`: single-endpoint historical scans failed against Publicnode’s archive policy. Added the supplied fallback, bounded scans, replay/deduplication and visible incomplete-index state.
- `site/app.js:81`: roll/join/purchase eligibility previously missed inactive seasons, cooldowns and quote expiry in ordinary UI state. Controls now reflect those conditions; quotes are invalidated on edits and expiry.
- `site/app.js:154`: account/network events previously reloaded the whole document. The application now preserves the viewed board, disables wrong-chain writes and clears private wallet state on account change.
- `site/app.js:349`: roll secrets remain persisted before requesting a signature. Confirmed reveals remove the secret before optional animation/read work can fail. Recovery still checks nonce and commitment, and the contract EVM clock gates reveal.
- `site/app.js:415`: the prior website lacked a pot contribution flow. It now calls the game’s `fundPot` after exact approval.
- `site/app.js:418`: multi-deed claims are serialized and the queue prevents duplicate starts; focused individual deed controls update after a claim.
- `site/app.js:378`: receipt-derived movement drives square hops and Chance/jail relocation; dice no longer use Unicode clip-art glyphs or a blank waiting spinner.

## Submission size and integrity

The complete tracked-plus-submitted file set was measured at approximately **2.72 MB uncompressed**; a compressed snapshot is approximately **0.87 MB**, below the **8,388,608-byte** limit even without compression. This includes source, the new optional tooling manifest/lockfile, production export, retained vendored dependencies and browser evidence. The export is exactly **655,297 bytes**. No `node_modules`, npm cache, browser binary, dependency archive or submodule is present. The ignore file was unchanged; all temporary tooling and scratch files stayed under `/tmp`. A protected-path diff confirmed no changes to Solidity, Foundry files, existing manifests/lockfiles, dependencies, the original ABI or ethers runtime/license.

## Evidence and limitations

`docs/site-evidence/swarmopoly-desktop.png` and `docs/site-evidence/swarmopoly-mobile.png` capture the actual live launch state, with no wallet and no fabricated properties, pot or players. The populated state was inspected separately using explicitly local fixture data. All runtime assets resolved at the static subpath; no page errors were observed in the checked states.

Not verified: native screen-reader announcements; physical touch devices; Safari/Firefox; native browser zoom (200% root text enlargement was checked); RTL/localization; actual forced-colors hardware; animation replay in a browser DevTools panel at 10% speed; every alpha-overlay contrast pixel; mainnet signing, liquidity and token swaps; IPFS pin propagation or an ENS/name update. Sponsorship, prize claiming/finalization, imported-secret rejection and timeout resolution retain real ABI handlers and source review, but were not all executed in the browser fixture. No season existed on the live chain to test them there. Long-running chain reorganizations and large player populations were not load-tested.

The workspace has no IPFS publisher capability or CLI. The delivered `dist/` is ready for the contributor publisher under the requested name `swarmopoly`; no public URL/CID is invented. `.git/` is outside the allowed write scope, so this worker did not stage or create a commit. Source, lockfile, documentation and export are present for the submission service.

Guidance attribution: Jakub Krehel’s Better Interface (MIT), pinned commit `267330e1adfc66a718fb65fa6918c1f06d0a689e`; documentation method adapted from Paul Bakaus’s Impeccable (Apache-2.0), pinned commit `9d715cc4f5564a990ca8345abfdd5df6dc9b41c8`. Full included license texts: `docs/INTERFACE-LICENSE.txt`.

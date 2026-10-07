# Checks

Run from repository root with Foundry and the pinned Solidity 0.8.26 compiler installed:

```sh
forge build
forge test
forge fmt --check
node --test test/site.test.mjs
node --check site/app.js
node --check scripts/configure-site.mjs
python3 scripts/export-abi.py
```

No tests require network, fork state, secrets, environment variables, extra packages, FFI, or filesystem access. Vendored forge-std supports both delivered tests and the supplied deployment floor. The supplied floor's external environment setup is independent of these application tests.

`test/Swarmopoly.t.sol` uses a strict mock PoolManager that validates the single unlock, negative exact-input delta, positive output, sync before settlement, correct debt payment and complete take. The contract's no-settlement quote reverts mock swap state, then returns the decoded quote. Tests cover access/bind/list restrictions, all three custody balances, failed/no-return ERC20s, reentry, both swap directions through address ordering, minOut/partial input/settlement failures, transfers and donation-independent shares, daily moves, rent, locks, sponsors, bankruptcy, season boundaries, prizes and pause exits. Mock token minting exists only in test code.

Fuzz tests cover rent accounting across purchase sizes and differential reveal-vs-timeout balance results (256 samples each). Stateful `AccountingInvariants` uses two funded players and five action families: deposit/withdraw; roll/buy/expire/jail; claim/redeem; sponsor/claim; finalize/new-season/old-sponsor-withdraw. Four invariant predicates run together for 128 sequences of depth 64 (8,192 calls): currency/pot/vault custody, rent conservation, deed shares/weights, and positive-score, unique sorted leaders. A pre-seeded deed ensures rent-holder accounting is exercised from the beginning. State advances through actual game calls; helper cheatcodes only provide clocks, block hashes and caller identities.

The runtime test follows the supplied floor's PUSH-aware opcode scanning and enforces EIP-170's 24,576-byte limit on the three applications. Compiled runtimes are approximately 1.8 KB / 9.7 KB / 13.6 KB for pot/vault/game; exact values are available in build artifacts.

The website's browser library is local, ABI is exported from compiler output, and JS syntax checks do not need npm packages. `test/site.test.mjs` checks initial rendering and the unconfigured deployment state using a small dependency-free DOM/RPC harness. This is a smoke test, not a claim of full browser/wallet integration testing. A real-wallet rehearsal against a confirmed deployment, with the target RPC and supported wallet, remains a release responsibility.

Final local run (2026-10-07): `forge build`, `forge test`, `forge fmt --check`, both JavaScript syntax checks, and two site smoke tests passed. Foundry reported 40 passing tests: 39 unit/fuzz/regression tests plus the grouped four-predicate invariant suite, with 8,192 invariant calls and zero reverts. See `check-results.json` for exact runtime sizes. These are author-run checks, not independent verification.

## Revision regression coverage

`test/RevisionRegression.t.sol` adds eleven tests for the reviewed cases. They cover join-only prize exclusion, empty-rank carryover with a real positive scorer, zero-score rent claims, fee/tier correction on an empty listing, refusal to change funded listings, correction after redemption without losing old rent, new-deed rent baselines, sponsor liabilities across seasons, replacement of an exhausted dust sponsor without losing lander claims, funded-sponsor exclusivity, and cooldown preservation through the next season and its exact expiry. Three tests retain observable examples of the disputed economic reports: sole dust-holder rent, timeout forfeiture/bankruptcy, and per-player parking versus balance-limited rent.

Before changing contracts, `forge test --match-path 'test/scratch/*.t.sol' -vv` failed the supplied zero-score proof (600 IMD awarded), empty-listing correction, exhausted-sponsor replacement, and cooldown preservation. The three economic observation tests passed, confirming the reported traces. After the fixes, the same copied proof and reproduction tests all passed. The proof copy was byte-for-byte identical to the supplied input; scratch copies were moved outside the repository before the final delivered-suite and formatting checks. All lasting regression tests are under `test/RevisionRegression.t.sol`, not scratch.

The contract ABI and constructors are unchanged; the delivered website ABI was compared directly with the new compiler artifacts. Updated website copy explains positive-score prizes, correctable empty listings, sponsor replacement after exhaustion, and persistent cooldowns. All seven reviewer responses are in `.imd-responses.json`.

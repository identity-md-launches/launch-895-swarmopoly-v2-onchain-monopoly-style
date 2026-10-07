# Swarmopoly v2

An immutable three-contract daily board game for Robinhood Chain (4663), using the existing 18-decimal IMD token. Includes a self-contained static website, offline Foundry dependencies, unit/fuzz/stateful tests, and a deployment manifest. No token or pool is created.

```sh
forge build
forge test
forge fmt --check
python3 -m http.server 8080 --directory site
```

Solidity is pinned to **0.8.26**, Cancun, optimizer 200, via IR, without metadata CBOR or bytecode hash. The verifier supplies the compiler. No network, environment variables, filesystem cheatcodes, or FFI are used by tests. All Solidity imports and the browser's ethers library are ordinary vendored files. `out/` and `cache/` are disposable.

- [Rules and assumptions](docs/RULES.md)
- [Deployment parameters and operator handoff](docs/DEPLOYMENT.md)
- [Security review and limitations](docs/REVIEW.md)
- [Read-only chain evidence](docs/network-verification.json)
- [Test coverage](docs/TESTING.md)

The application has **not been deployed or published** by this assignment. The PoolManager was queried from the supplied hook, and code/chain/currency metadata were checked. `launch.json` is ready for the deployment service. `site/config.json` deliberately has no invented application addresses; the site displays its launch state until a verified deployment handoff is applied.

The Swarmopoly v1 job's screenshot/source was not included in the inputs. The delivered visual treatment is a dark olive dashboard with a classic sage 40-square board, colored property bands, daily dice, and IMD account panels. Exact visual matching to job `55ae5ec7` remains subject to that reference becoming available.

Third-party vendoring: OpenZeppelin Contracts v5.0.2 (used files only), forge-std v1.9.7 (`src`), ethers v6.13.5 (browser ESM bundle). Their licenses are included alongside the code. The v4 interface is an ABI-compatible minimal subset; the PoolManager itself is external and is never redeployed here.

The independent additions are `Adversarial.t.sol`, `StatefulAccounting.t.sol`, and
`helpers/AccountingHandler.sol`. They build on the accepted fixtures and offline
PoolManager mock without changing application code or configuration.

Run `forge build` and `forge test`. No RPC, environment writes, FFI, downloads, or
additional dependencies are required. Fuzz counts (1,000 per new fuzz property)
and stateful settings (256 runs, depth 96, fail on revert) are in Solidity comments.

The leaderboard revision excludes zero-score joiners. Prize fixtures earn real
scores through rolls, and the leaderboard invariant checks exactly the best
positive-score players, allowing empty trailing ranks. A deterministic test
exercises empty, partial, full and overflowing rankings plus a new first-place
scorer. Revision regressions also cover same-day parking across season rollover
and an unresolved old-season roll blocking rejoining until its penalty is paid.

The stateful handler uses twelve players, two tiles sharing a token, all three
lock choices, pending commitments, deposits/withdrawals, buys, rent claims,
redemptions, sponsorship topups and claims, donations, pause changes, funding,
season rollover and old prize claims. It only impersonates users or the owner;
it does not write production storage or call custody methods as the bound game.
A deterministic reachability test ensures rolls, purchases, expiry, redemption
and rollover actually execute.

Properties reconcile:

- All player balances and committed exposure against game custody.
- All outstanding prizes across every season against pot reservations.
- Every live deed's shares and weight against its tile's aggregates.
- Purchased assets minus redemptions against internal tile assets.
- Sponsorship receipts minus payments against remaining sponsor funds plus
  outstanding landing awards, including old seasons.
- Credited and claimed rent, including all outstanding deed claims, against
  actual currency backing and rent paid by players.
- Donations as separate surplus; they must not become shares or liabilities.
- The leaderboard against all twelve players, including omitted players and ties.

The expiry handler compares identical commitments revealed versus withheld from
an EVM snapshot. It compares play balances, scores, pending rent, and sponsorship
claims, then retains the expired branch for further random interactions.
Unexpected handler reverts fail the invariant campaign.

Unit and fuzz additions exercise custody authorization (including the owner),
binding/dependency failures, every classic board slot, malformed pool keys,
wrong-holder operations, failed transfers and swaps with atomic rollback,
no token balance reads by vault operations, domain-separated commitments,
missing entropy and deadline boundaries, exact rent bankruptcy thresholds,
lock maturities, weighted rent, all ten prize weights and rounding, and claims
through pauses and season transitions. The reentrancy test funds the callback
caller first so insufficient balance cannot produce a false positive.

Limits: the local swap mock models signed deltas, unlock, sync/settle, take and
rollback; it does not establish live PoolManager provenance, liquidity, hook
behavior or L2 blockhash behavior. A live Robinhood Chain integration rehearsal
is still owed. No live address was guessed or substituted. The campaign assumes
standard non-rebasing tokens, as required by the implementation's internal
accounting model; it makes no solvency claim for transfer-tax or dishonest tokens.

# Swarmopoly design system

## Overview

Swarmopoly is a daily onchain board game for the IMD community on Robinhood Chain (4663). This implementation follows [Swarmopoly v1’s DESIGN.md](https://github.com/identity-md-launches/launch-891-title-swarmopoly-v1/blob/main/DESIGN.md): near-black chrome, a deep-purple arcade board, geometric player pieces, quiet scanlines and one filled green decision at a time. The pot and neighborhood activity occupy the board’s stage; the next action lives in the adjacent turn panel.

Source of truth: `site/style.css` for tokens and responsive components, `site/index.html` for landmarks and forms, `site/ui.js` for original vector icons and board geometry, and `site/app.js` for state and interactions. The stack remains native HTML/CSS/JavaScript modules with the original local ethers runtime. `dist/` is the complete static export.

## Colors

All canonical values are sRGB hex. One dark theme is implemented.

| Token | Value | Purpose |
| --- | --- | --- |
| `--bg` | `#101014` | Page chrome |
| `--surface` | `#19191f` | Turn, balance, deed and pot panels |
| `--raised` | `#212128` | Neutral buttons and corners |
| `--board` | `#1c1b25` | Property squares and selected lock card |
| `--center` | `#16161e` | Stage, fields and vacant squares |
| `--text` | `#f0f0f2` | Primary copy |
| `--muted` | `#a4a2b0` | Descriptions, labels, metadata |
| `--line` | `#35333f` | Dividers and structural outlines |
| `--accent` | `#b6f85d` | Current decision, own-piece ring, brand |
| `--accent-hover` | `#c7ff7f` | Primary hover |
| `--on-accent` | `#18210d` | Primary label |
| `--purple` | `#bca0ff` | Special squares, locks, outcomes |
| `--focus` | `#d5ff9d` | Keyboard outline |
| `--danger` | `#f38686` | Error copy and toast edge |

Tier 1–8 stripes, in `site/ui.js`: `#b6a2e2`, `#85d8ec`, `#e987c3`, `#f6b37b`, `#f38686`, `#e9d47c`, `#a6d493`, `#969ef3`. Vacant stripes are muted with 55% opacity; text stays fully opaque. Tier numbers and selected details communicate categories without color. Address-derived pieces reuse these hues with six different shapes.

Measured browser-computed solid pairs: primary label 13.13:1; panel description 6.98:1; stage wordmark 15.80:1; stage description 7.17:1; selected lock caption 6.79:1. The faint scanline overlay was not measured pixel by pixel. The browser accessibility audit reported no contrast violations in the inspected launch and populated states. See `docs/SITE-VALIDATION.md` for coverage.

## Typography

Space Grotesk, a local variable normal font at weights 400–700, is copied from v1’s `public/fonts/space-grotesk-latin.woff2`. Its OFL travels in both `site/fonts/` and `dist/fonts/`. `font-display: swap` and `font-synthesis: none` are set. Fallback is `system-ui, sans-serif`; the old Arial rule is removed. The browser confirmed the font loaded.

`--mono` is `SFMono-Regular, Consolas, Liberation Mono, monospace`. Balances, pot values, countdowns, dice metadata and rents use it with tabular numerals. Body base is 16px/1.5; UI prose is 14px, fine copy 12px/1.6, eyebrows 10px with positive tracking. Inputs remain 16px. Page headings use `clamp(1.4rem, 2.1vw, 1.9rem)`; section introductions use 2rem; turn titles use 1.625rem. The center wordmark scales with its container. Long IDs can wrap; full wallet addresses remain in accessible tile titles and player labels.

The scaled board intentionally has miniature labels. At containers below 460px, full property names and holder captions give way to symbols and rent. Every square is a native named button, and the full-size “Explore a square” selector exposes the same details. Financial decisions always use the full-size inspector; miniature captions are supplementary.

## Layout

Shared chrome has a 1500px maximum width and 36px inline padding, reducing to 24px at 1050px and 16px below 760px. Common spaces are 4, 8, 12, 16, 20, 24 and 32px. Panels use 24px padding, reducing to 20px. Standard buttons and inputs are at least 44px high; the primary is 48px.

Desktop `.game-layout` has a flexible board and a 320px control rail with 24px gap. The rail becomes 285px at 1050px and 350px above 1500px. The board width is the smaller of available column width and `100svh - 215px`, preserving a square. It fills the available desktop height; the inspector can extend the document vertically. The 11×11 ring has 1.2fr corner tracks and nine 1fr tracks, with a stage spanning rows/columns 2–10. GO is bottom-right; `boardPosition()` maps all 40 spaces.

Below 760px, the turn panel comes first, the board scales to available width, and the inspector follows it. Controls precede the board in DOM order too. The large square selector remains available. The center uses container breakpoints at 610px and 460px to simplify the stage. Compact leader/activity previews link to the complete leaderboard; below 370px these previews are hidden to keep the pot visible. My Swarm, leaderboard and owner forms collapse to one column; deeds use two columns until 370px.

Hash routes (`#board`, `#swarm`, `#leaders`, `#owner`) need no server rewrites. Rules remain a separate exported `rules.html`. Observed widths: 320, 390, 759, 760, 1000 and 1440px, plus 200% root text enlargement. No horizontal page overflow in those checks. Native zoom, RTL and physical-device layout remain unverified.

## Elevation & Depth

Panels use a subtle 1px `#ffffff0a` shadow ring. The board has a `#4c4759` structural border and `0 12px 45px #0005` shadow. The stage uses a faint, static four-pixel scanline pattern that ignores pointer events. Tokens use a small shadow and fan out when stacked. The own-piece accent ring is separate from identity color. Persistent transaction notices sit above the page with explorer links and explicit dismiss controls; no modal component is used.

## Shapes

`--radius: 12px` defines panels and the board. Fields and die faces use 7px, buttons and lock choices 8px, the pot inset 10px, tile internals 2px. Original inline SVGs share a 32×32 viewBox, rounded caps/joins and `currentColor`. The six address-derived silhouettes are Imp, Seat, Kite, Orb, Crown and Bolt. GO, Jail, Free Parking and Go to Jail each have an original geometric icon, independent of the player silhouettes.

## Components

| Pattern | Source | Behavior |
| --- | --- | --- |
| `.primary`, neutral and `.text-button` | `style.css`, `updateControls()` | One green next decision; purchase takes priority once eligible and quoted. Hover, focus, disabled and busy states. |
| Turn panel and `nextAction()` | `index.html`, `app.js` | Wallet, wrong network, join, funding, cooldown, jail, pending reveal, bankruptcy and season states. Disabled actions have adjacent explanations. |
| `drawBoard()`, `renderTiles()` | `app.js`, `ui.js` | Named native square buttons, token monograms, tier rent, current holder count, vacant shimmer. Selector is an equivalent full-size control. |
| `identity()`, `renderPieces()` | `ui.js`, `app.js` | Stable address-based shape/color, short wallet label, stacked fan, own-piece ring. |
| `die()`, `playRoll()` | `ui.js`, `app.js` | Six-face CSS cubes tumble for 900ms; waiting state stays labeled “Rolling…”. Revealed values drive 180ms square hops and final Chance/jail relocation. Salary and rent chips use actual receipt/state data. |
| Inspector and lock cards | `index.html`, `getQuote()` | Native radio group: None (24h minimum, 1×), House (30 days, 1.5×), Hotel (90 days, 2×). Amount/slippage invalidate quotes; 60-second expiry. Landing slide, Chance flip, jail bars. |
| `.deed-row`, `renderDeeds()` | `app.js` | Real claimable rent, lock clock, individual claims, sequential Claim rent action, unlocked redemption. Polling preserves focus inside deeds. |
| `toast()`, `transact()` | `app.js` | Approval and transaction confirmation, explorer links, persistent dismissible errors, polite status announcements. |
| Owner panel | `index.html`, `app.js` | Only visible to owner. Plain explanations, current binding state, one-shot bind controls, listings, parameters, pauses and season start. |

Focus uses a two-pixel `--focus` outline with four-pixel offset (inset on tiles). A skip link reaches the next action. Motion is opt-in under `prefers-reduced-motion: no-preference`; reduced motion instantly resolves the movement sequence. A persistent “Pause effects” control stops ambient shimmer and all effects. Waiting text still describes a pending roll. Forced-colors styles supply native borders; physical forced-color behavior is unverified.

## Do’s and don’ts

- Start another page with `.page.content-page`, `.section-intro` and `.panel`; keep all assets relative and local.
- Keep one filled green action per decision. Tier and player colors carry identity, not action priority.
- Keep amounts in bigint until display; display animation interpolates only confirmed pot changes and never invents yield.
- Insert chain metadata with `textContent`. The inline SVG helpers accept only the original icon map.
- Preserve the full-size square selector, lock explanations, visible focus and motion preference guards.
- Do not infer holder counts or activity before indexing completes, equate Nitro’s RPC height with EVM `block.number`, or discard a roll secret before confirmation.

Design review applies the pinned Better Interface guidance (Jakub Krehel, MIT) and its adapted Impeccable documentation method (Paul Bakaus, Apache-2.0). Attribution and license texts are in `docs/INTERFACE-LICENSE.txt`.

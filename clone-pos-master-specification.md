# CLONE-POS — MASTER BUILD SPECIFICATION
*Exhaustive reference document. Every decision below was explicitly confirmed. Items marked DEFERRED are intentional, not omissions — do not build against an assumption for them.*

---

## 1. PRODUCT OVERVIEW

Clone-POS is a mobile-only inventory management and point-of-sale coordination system. No web app exists anywhere in the product — customer-facing, staff-facing, or administrative — under any circumstance. No AI features. The system is built for deterministic, idiot-proof, offline-resilient operation across multi-store retail and manufacturer field-sales use cases, targeting Europe and the US.

### Device roles
- **Master** — one per store. Tablet, landscape orientation only, never portrait. Fixed-geometry control-panel interface (spec in Section 5).
- **Satellite** — the full batch of staff terminals per store. Tablets, auto-layout adapting to landscape or portrait. (Internal name only — never referred to as "Clone device," to avoid collision with the "Clone-POS" product name.)
- **Clone-POS client** — the customer-facing shopping app. Phones only, not tablets.
- **Android TV / POS touch panel variants** — DEFERRED. Real future targets, explicitly not designed yet. Revisit only after tablet (Master + Satellite) and phone (Clone-POS client) builds are complete.

---

## 2. CORE ARCHITECTURE

### 2.1 Source-of-truth model
Event-sourced transaction ledger. No device ever overwrites a stock number directly. Every device — Master, Satellite, or Clone-POS client — logs a transaction/reservation event with a timestamp and originating device ID. The Master calculates real inventory state by applying events in timestamp order. This prevents silent data corruption; conflicts are surfaced (flagged), never hidden.

### 2.2 Sync model
- **Satellite ↔ Master**: hybrid — real-time when connected, queued locally when offline.
- **Satellite offline sale**: allowed, queued, reconciled automatically on reconnect.
- **Master unreachable**: Satellites and Clone-POS clients keep operating on cached data; full reconciliation happens once Master returns. The store never stops functioning because Master is offline — this is a hard requirement, not a nice-to-have.

### 2.3 Product/unit granularity
**Unique QR code per physical unit** — not per SKU. Every individual physical item gets its own label. Data model requires a distinct `Unit` entity nested under `Product` (SKU-level), with status: `in_stock` / `reserved` / `sold` / `missing`.

### 2.4 Overbooking prevention (the core algorithm)
On scan, a **soft reservation** is created against the specific `Unit`, not a SKU-level count. **20-minute timeout.** The timer is tracked **locally on the customer's own device**, never by Master — this is essential because Master may be offline for the entire reservation window, and a Master-side timer would never even start in that case. On reconciliation, if two reservations exist for the same unit, the **earliest timestamp wins**; the losing reservation's holder sees "this item just became unavailable, remove it" **before** payment is ever attempted — a customer is never charged for something that doesn't exist.

**Scan UX**: scanning does not silently add to cart. A confirmation pop-up shows reservation status first ("reserved for you, 20 min" / "already taken"), customer confirms before it lands in cart.

### 2.5 Stock intake
Staff App connects directly to a Bluetooth/USB label printer; a unique QR is generated and printed on the spot as new stock arrives. Supported printer brands (multiple from day one, behind an internal `PrinterService` abstraction so brands can be added/removed without touching other code): Zebra, Brother, TSC, Honeywell, Bixolon (candidate shortlist — final brand selection DEFERRED).

### 2.6 Returns
Staff manually searches by product/SKU, selects the correct unit from a short list of currently-sold units for that product, and toggles it back to `in_stock`. No re-scan required, and no free-text unit ID entry (avoids typo/data-integrity risk).

### 2.7 Multi-store / cloud
Confirmed multi-store. Each store's Master is fully local-first and independent — zero internet dependency for daily operation. Masters forward their ledgers to a cloud aggregation layer when internet is available, purely for cross-store visibility.

**DEFERRED — HQ / cross-store cloud access model.** This is the only part of the system that would touch the public internet and cross store boundaries, carrying real security weight (attack surface, data leakage risk, potential to destabilize store Masters if poorly isolated). May be dropped entirely if security review can't guarantee isolation. No feature should assume this exists until explicitly confirmed. Candidate approaches under consideration: dedicated HQ mobile app, an "HQ mode" inside the Staff App, or a narrowly scoped web exception (last resort, conflicts with the no-web rule).

### 2.8 Onboarding (Clone-POS client)
First name, last name, email, mobile number + SMS OTP verification on first use only. Customer **stays logged in** thereafter — no repeat OTP on return visits.

---

## 3. DATA MODEL

- **`Product`** — SKU-level: name, price, category.
- **`Unit`** — physical item: unique QR ID, belongs to a `Product`, status (`in_stock`/`reserved`/`sold`/`missing`), store ID.
- **`Transaction`** — event log entry: unit ID, type (`reservation`/`sale`/`return`), timestamp, originating device ID.
- **`Device`** — Master/Satellite/Clone-POS client instance, pairing info, store ID, role.
- **`Customer`** — name, email, mobile, verified flag (Clone-POS client only).
- **`Store`** — identity, its Master device reference.

---

## 4. DESIGN LANGUAGE

### 4.1 Aesthetic direction
Not modern flat minimalism. Target: **mid-1970s plastic consumer electronics** — warm, tactile, refined — in the vein of Braun (Dieter Rams) and Bang & Olufsen. Chunky rounded "key" style buttons (Braun ET66 calculator reference), recessed-panel/display-window feel, toggle-switch-style controls, grille/dot texture as decorative accent, restrained but warm palette. Quirky and engaging, not sterile or clinical.

### 4.2 Palette (working values, subject to refinement)
| Token | Hex (approx.) | Use |
|---|---|---|
| Cream (background) | `#F2E8D5` | Base canvas background |
| Cream card | `#FFFBF2` | Card/panel surfaces |
| Mustard | `#E8B84B` | Primary metric/data card fill |
| Rust/terracotta | `#C1551C` | Accent — role pills, numeric readouts, active states |
| Walnut brown | `#4A3728` | Primary text |
| Orange (buttons) | placeholder, exact hex TBD from the FAB component in the working Figma file — currently used as a "design handshake" marker, likely to be refined |

### 4.3 Typography
**Master font: Google Sans Flex** (confirmed loaded in the user's Figma environment; not available in this build environment's font list — verify availability in the actual Flutter build target before shipping). **Fallback: Roboto Flex** — the legitimate open-source variable-font sibling, same design lineage, safe substitute if Google Sans Flex isn't licensable/available at build time.

### 4.4 Texture note
The dotted background texture currently on the Master/FAB layout is a placeholder and is expected to change later in the design process — do not treat its current appearance as final.

---

## 5. MASTER DISPLAY TEMPLATE (fixed geometry — applies to every Master screen, no exceptions)

### 5.1 Canvas
**1280×800dp, landscape, edge-to-edge.** Confirmed to run in **Android kiosk/dedicated-device mode** — no system status bar or navigation bar, so true edge-to-edge is correct and does not need to reserve OS chrome space. This 1280×800 figure is not arbitrary: it is the density-independent-pixel equivalent that Android produces for the entire current flagship tablet market (Samsung Galaxy Tab S11 Ultra, Google Pixel Tablet, OnePlus Pad 3, etc.), which — despite wildly different physical screen sizes (10.4" to 14.6") — all converge on the same 16:10 aspect ratio. A layout built at 1280×800 scales cleanly across that entire hardware range.

### 5.2 The four regions (fixed position and size — NEVER change, for any reason, anywhere in the app)
| Region | Size | Position | Utility |
|---|---|---|---|
| Master display | 980×740 | x=18, y=43 | Main content — "does the bulk of the hauling." Full inventory grids, expanded category content, etc. |
| Secondary display | 240×400 | x≈1019, y=219 | Scrollable index/navigation — titles, categories, sub-categories. List-detail pattern: Secondary drives what Master shows. |
| Counter display (left) | 105×100 | x=1019, y=48 | Active carts count |
| Counter display (right) | 105×100 | x=1154, y=48 | Connected satellites count |

Both counters share a single "ACTIVE" label positioned beneath them.

**Hard rule confirmed explicitly by the client:** the size and position of every region above is locked for the entire build and the app's operation, without exception, regardless of what content or process is playing out. Only the *content rendered inside* a region ever changes.

### 5.3 Buttons (bottom of right column, y≈682, 56×56 each)
1. **Dash** — dashboard/home
2. **Settings**
3. **Back** — navigation back
4. **Toggle** (smaller, 56×21, sits just above the other three) — expands the Secondary display's current content into the Master display. Triggering it does not resize or reposition anything; it only swaps what Master renders. This toggle mechanism applies uniformly: tapping any Secondary index item moves that item's full content to the Master display's top edge, displaying its entire grid/stack — same fixed-geometry rule.

### 5.4 Master home menu — the stacked-card pattern
The Master display's home view is a **stacked-card / tabbed-drawer menu**: each category is a full-width card, all bottom-anchored to the same edge, offset so only a labeled strip of each peeks above the one in front of it — a rolodex/tab-index feel. Tapping any strip brings that category to the top edge, expanding it to show its full grid/stack of content, using the same fixed Master/Secondary geometry.

Confirmed categories, front-to-back order:

| Category | Definition |
|---|---|
| Active Carts | Live view of carts currently in progress, store-wide |
| Clones | Satellite device management and pairing |
| Inventory | Core stock management |
| Logistics | Inbound and outbound stock shipment tracking — status/progress on incoming deliveries and scheduled outgoing drops, both directions |
| Analytics | Sales & inventory analytics (label corrected from earlier "Analytica" typo) |
| Accounts | Billing and taxation documents only. (Outlook mail integration was considered and explicitly **dropped** — not in scope.) |
| Sales Kit | For manufacturer use cases: a rep can carry the Master tablet to a client meeting. Pulls thumbnails from a YouTube channel; video plays out on the Master display, playlist navigation lives on the Secondary display. Requires a YouTube Data API key and an active internet connection for this feature specifically — does not affect offline-first guarantees elsewhere in the app. |
| Data | Highly secure repository: all inventory, client list, leads. **Access gate (PIN/biometric) confirmed required, but explicitly DEFERRED to the final stage of the build.** Intentionally left exposed under standard Master login for now — a deliberate sequencing decision, not an oversight. Do not ship this to production without the gate. |

---

## 6. SATELLITE & CLONE-POS CLIENT TEMPLATES

- **Satellite (tablet, landscape or portrait)**: same visual language (palette, button style, texture treatment once finalized) as Master, but not the identical fixed 4-region layout — tablets running Satellite need their own auto-layout treatment appropriate to staff terminal tasks (scan/sell, lookups, reports).
- **Clone-POS client (phone only)**: single full-screen view at a time rather than simultaneous regions — phone screens don't have room for Master's 4-region layout without everything becoming illegibly small. Same visual language; list (category/index) pushes to full-screen detail (content), mirroring the same underlying navigation logic as Master/Secondary without the split-screen geometry. Onboarding flow: name/email/mobile + OTP → skippable demo → QR scanner + prominent live cart button.

---

## 7. FOLDER STRUCTURE

```
clone-pos/
├── docs/                        # architecture.md, data-model.md, sync-protocol.md, design-system.md
├── packages/
│   └── core/                    # shared: models, database, sync engine, printer abstraction, repositories
├── apps/
│   ├── staff_app/                # Master + Satellite (role chosen at pairing)
│   └── shopping_app/             # Clone-POS client (customer-facing)
└── design/                       # Bauhaus/Braun/Art Deco/B&O design tokens and references
```

---

## 8. DEFERRED ITEMS — DO NOT BUILD AGAINST AN ASSUMPTION FOR ANY OF THESE

1. **HQ / cross-store cloud access model** — under security review; may be dropped entirely.
2. **Specific label printer brand(s)** — shortlist identified, final pick pending.
3. **Data category access gate** — required, deferred to final build stage.
4. **Android TV and POS touch panel variants** — deferred until tablet + phone builds are complete.
5. **Exact orange button hex / final texture treatment** — current values are placeholders for "design handshake" purposes only.

---

## 9. WHAT EXISTS SO FAR

- A working Figma file with the Master template at correct 1280×800dp geometry, the 4-region layout, the stacked-card home menu example, and the toggle/expand interaction concept.
- This specification document.
- An accompanying Flutter/Dart code prototype (see delivered code archive) implementing the core data models, the reservation/ledger engine, and an initial Master dashboard screen matching this spec — not yet compiled or device-tested; requires a local Flutter environment to build and deploy.

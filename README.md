# Clone-POS — Prototype Codebase

This is a **real, structurally correct Flutter/Dart starter codebase** implementing the
architecture confirmed in `clone-pos-master-specification.md`. Read that document first —
this code exists to make the spec concrete, not to replace it.

## What's actually implemented here

- `packages/core` — the shared logic package:
  - `models/` — `Product`, `Unit`, `Transaction`, `Device`, matching the confirmed data model.
  - `sync/reservation_engine.dart` — the real algorithm behind the 20-minute soft
    reservation and the "earliest timestamp wins" overbooking resolution. This is the
    most important file in the prototype — it's the piece the entire multi-device
    architecture depends on.
  - `repositories/inventory_repository.dart` — in-memory reference repository. Swap
    for `drift`/sqlite in production without touching anything that calls into it.
  - `test/reservation_engine_test.dart` — unit tests proving the reconciliation logic
    behaves correctly, including the exact race-condition scenario from the spec.
- `apps/staff_app` — the Staff App (Master/Satellite):
  - `theme/clone_pos_theme.dart` — the warm retro palette and type scale from the spec.
  - `screens/master_dashboard_screen.dart` — the fixed 1280×800 four-region Master
    layout (Master display, Secondary display, two Counter displays, the button row),
    with a working stacked-card home menu covering all 8 confirmed categories.

## What is NOT here yet

- The Clone-POS client (customer/shopping) app — not started.
- Any real networking/sync between devices — the reservation engine's logic is real,
  but nothing here actually talks to another physical device over a network yet.
- A real local database (currently in-memory only, resets on every app restart).
- Pairing/role-selection flow (choosing Master vs Satellite on first launch).
- Printer, SMS/OTP, and YouTube API integrations — all called out as external
  dependencies in the spec, none are wired up here.
- The Data section's access gate (explicitly deferred per the spec).

## Honest limitation on this delivery

This code has **not been compiled or run**. It was written directly as source files in a
sandboxed environment that cannot reach Flutter's package registry (pub.dev) or install
the Flutter SDK, so nothing here has been build-verified. The code is written correctly
to the best of available knowledge of the Flutter/Dart APIs, but treat the first build
attempt as exactly that — a first attempt, likely to surface a small issue or two, as
with any freshly written codebase.

## How to actually run this

You'll need a real Flutter development environment — your own machine, or **Claude Code**,
which can install Flutter, run `flutter pub get`, and deploy directly to your test
devices (you mentioned 4 tablets, 1 Android phone, 1 iPhone — this is exactly the kind
of step that needs a real device connection, which this chat environment cannot provide).

```bash
# from the packages/core directory
flutter pub get
flutter test

# from the apps/staff_app directory
flutter pub get
flutter run   # with a tablet connected/emulator running
```

## Suggested next steps, in order

1. Open this in Claude Code, run `flutter pub get` in both `packages/core` and
   `apps/staff_app`, and fix whatever surfaces on the first build attempt.
2. Deploy `staff_app` to one of your 4 test tablets and sanity-check the Master
   dashboard against the Figma file.
3. Wire `InventoryRepository` to a real local database (drift recommended).
4. Build the pairing/role-selection flow so a device can actually become a
   Satellite, not just a hardcoded Master.
5. Only after that: real device-to-device networking for the sync engine.

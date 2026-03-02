# Contract → Implementation Lag

Tracks places where `specs/CONTRACT.md` is internally correct but the Rust codebase has not yet caught up.
Each entry states: the contract intent, what the code currently does, and the gap.

> **Status key:** `OPEN` = not started · `PARTIAL` = partially wired · `DONE` = fully implemented

---

## LAG-001 — `OrderSizeInput` is a flat struct, not a union

**Status:** OPEN

**Contract (lines 90–92):**
```
OrderSizeInput = mutually exclusive union: CoinQty | UsdQty | Contracts
NormalizedOrderSize = canonical_size_kind + all derived fields
```
The contract requires the strategy-supplied input to be an enum so the type system enforces mutual exclusivity and makes `MixedCanonicalSizeFields` (AT-1097) statically impossible to miss.

**Current code (`crates/soldier_core/src/execution/order_size.rs`):**
```rust
pub struct OrderSizeInput {
    pub instrument_kind: InstrumentKind,  // determines what canonical_qty means
    pub canonical_qty: f64,               // single scalar — no semantic tag at call site
    pub index_price: f64,
    pub contract_multiplier: Option<f64>,
}
```
`canonical_qty` is a bare `f64` whose semantics (coin vs USD) are implied by `instrument_kind`. There is no way for the type system to reject a caller that builds the struct with the wrong semantic. The `MixedCanonicalSizeFields` rejection cannot be enforced at the boundary.

Also: `build_order_size` is now called from non-test assembly code (`intent_assembly::assemble_sizing`), so it is no longer unit-test-only. However, TODOs in `order_size.rs` and `open_runtime.rs` still indicate the assembly path is not yet the explicit primary order-submission entrypoint.

**What needs to change:**
1. Replace `OrderSizeInput` struct with the contract's enum form:
   ```rust
   pub enum OrderSizeInput {
       CoinQty { qty_coin: Decimal },
       UsdQty  { qty_usd: Decimal },
       Contracts { contracts: i64 },
   }
   ```
2. Add `NormalizedOrderSize` with `canonical_size_kind` field.
3. Wire `build_order_size` into the live dispatch pipeline (remove the TODO).
4. Reject `MixedCanonicalSizeFields` at the strategy intake boundary, not deep in dispatch.

**Contract refs:** §1.0 lines 90–92, 740–741; AT-1097, AT-277

---

## LAG-002 — Sizing branches on `InstrumentKind`, not `AmountSemantics`

**Status:** OPEN

**Contract (lines 84–89):**
```
AmountSemantics: one of coin | usd — authoritative sizing discriminator
instrument_kind: legacy compatibility alias only
Sizing/quantization MUST branch on amount_semantics, not instrument_kind alone.
Normalize venue metadata to InstrumentMeta{instrument_family, amount_semantics}
before sizing logic executes.
```

**Current code:**
`build_order_size` (and its current assembly/dispatch callsites) match on `InstrumentKind`:
```rust
match input.instrument_kind {
    InstrumentKind::Option | InstrumentKind::LinearFuture => { /* coin */ }
    InstrumentKind::Perpetual | InstrumentKind::InverseFuture => { /* usd */ }
}
```
`InstrumentFamily` and `AmountSemantics` types do not exist in the codebase. The contract's `InstrumentMeta { instrument_family, amount_semantics, ... }` struct is specified but unimplemented.

**What needs to change:**
1. Introduce `AmountSemantics` enum (`Coin | Usd`) and `InstrumentFamily` enum (`Option | Future | Perpetual`).
2. Introduce `InstrumentMeta { instrument_family, amount_semantics, tick_size, amount_step, min_amount, contract_size_usd }`.
3. Replace `instrument_kind` branching in `build_order_size` with `amount_semantics` branching.
4. Demote `InstrumentKind` to an observability/compatibility field only.
5. Update all tests that construct `OrderSizeInput` or `InstrumentMeta` with the new types.

**Contract refs:** §1.0 lines 84–89, 707–708, 924–931; AT-277

---

## LAG-003 — TLSM terminal-state contradiction (RESOLVED in contract)

**Status:** DONE (contract only — no code action needed)

**History:** A concern was raised that §2.1 and §1.2.1 used different TLSM terminal sets (`Failed` vs `Rejected`). Verified against the current contract: both sections consistently use `{Filled, Canceled, Failed}`. `Rejected(reason)` is a pre-dispatch outcome from guards and is never a TLSM state. No implementation gap exists for this item.

**Contract refs:** §2.1 line 1878; §1.2.1 line 1128

---

## LAG-004 — Intent hash serialization format deviates from contract

**Status:** OPEN

**Contract (§1.1.1, line 1066):**
```
canonical_intent_bytes = UTF8("v1|" + instrument_id_lc + "|" + side_lc + "|"
                               + qty_steps_dec + "|" + price_ticks_dec + "|"
                               + group_id_nodash_lc + "|" + leg_idx_dec)
qty_steps_dec, price_ticks_dec, leg_idx_dec: base-10 ASCII integers,
no leading "+", no separators, no whitespace.
```

**Current code (`crates/soldier_core/src/idempotency/hash.rs`):**
```rust
buf.extend_from_slice(&input.qty_steps.to_le_bytes()); // little-endian binary
buf.push(0xFF);                                         // 0xFF separator, not "|"
buf.extend_from_slice(&input.price_ticks.to_le_bytes()); // little-endian binary
// group_id is passed raw (with dashes); no "v1|" prefix
```

Deviations from contract:
1. No `"v1|"` version prefix.
2. Separator is a `0xFF` byte, not the `|` pipe character.
3. `qty_steps` and `price_ticks` are little-endian binary, not base-10 ASCII decimal.
4. `group_id` is not stripped of dashes (`nodash`).

The current encoding is internally consistent (same code hashes everywhere), but any external tool, audit replay, or future codepath following the contract spec literally will produce different hash values and disagree on idempotency.

**What needs to change:**
Replace the binary encoding with the contract's canonical format:
```rust
let bytes = format!(
    "v1|{}|{}|{}|{}|{}|{}",
    input.instrument.to_lowercase(),
    input.side.to_lowercase(),
    input.qty_steps,
    input.price_ticks,
    input.group_id.replace('-', "").to_lowercase(),
    input.leg_idx,
);
xxh64(bytes.as_bytes(), 0)
```
Update all snapshot tests and golden vectors that depend on the current hash values.

**Contract refs:** §1.1.1 lines 1064–1068; AT-218, AT-343

---

## LAG-005 — `RejectReasonCode` missing three contract-required variants

**Status:** OPEN

**Contract (lines 2893, 2921, 2922):**
- `MixedCanonicalSizeFields` — reject when strategy supplies both `qty_coin` and `qty_usd` as canonical input (AT-1097)
- `InvalidLabelSchema` — reject when outbound label does not conform to `s4:` shape (AT-216)
- `UnknownLabelVersion` — reject when label version prefix is unrecognised (contract line 1018)

**Current code (`crates/soldier_core/src/execution/reject_reason.rs`):**
The generated enum currently has 30 variants. None of the three above are present. The contract-completeness test (`test_registry_contains_contract_minimum_set` in `crates/soldier_core/tests/test_reject_reason.rs`) does not include them in its minimum required set, so the gap can remain invisible to CI when manifest + generated code drift together.

`ContractsAmountMismatch` and `LabelTooLong` exist but serve different conditions and must not be conflated.

**What needs to change:**
1. Add three variants to `RejectReasonCode`:
   ```rust
   MixedCanonicalSizeFields,
   InvalidLabelSchema,
   UnknownLabelVersion,
   ```
2. Add them to `REGISTRY` and `as_str()`.
3. Add them to the `minimum` set in `test_registry_contains_contract_minimum_set`.
4. Add them to `test_registry_contains_all_enum_variants`.
5. Update `specs/status/status_reason_registries_manifest.json` (the manifest equality test will catch drift).
6. Wire `InvalidLabelSchema` and `UnknownLabelVersion` into the label validation gate's reject path.
7. Wire `MixedCanonicalSizeFields` into the strategy intake boundary (see LAG-001).

**Contract refs:** §2.2.6 lines 2879–2938; §1.1.2 line 971–972, 1018; AT-1097, AT-216

---

## LAG-006 — `derive_sid8` uses hex encoding instead of base32

**Status:** OPEN

**Contract (§1.1.2, line 963):**
```
sid8 = first 8 lowercase chars of RFC4648 base32 (no padding)
       over xxhash64(strategy_id_utf8_bytes) encoded as 8-byte big-endian
```
The encoding chain is: `strategy_id → xxhash64 → 8-byte big-endian → RFC4648 base32 (no padding) → first 8 chars`.

**Current code (`crates/soldier_core/src/execution/label.rs` line 109–111):**
```rust
pub fn derive_sid8(strat_id: &str) -> String {
    let hash = xxhash_rust::xxh64::xxh64(strat_id.as_bytes(), 0);
    format!("{hash:016x}")[..8].to_string()  // hex, not base32
}
```
The code hashes then formats as 16-char lowercase hex and takes the first 8 chars. The contract requires base32 encoding of the 8-byte big-endian representation. These produce different bytes for the same strategy ID.

The prop tests also generate `sid8` as 8 hex chars, not 8 base32 chars, so the test alphabet is wrong.

**What needs to change:**
```rust
pub fn derive_sid8(strat_id: &str) -> String {
    let hash = xxhash_rust::xxh64::xxh64(strat_id.as_bytes(), 0);
    let be_bytes = hash.to_be_bytes();
    let encoded =
        base32::encode(base32::Alphabet::RFC4648 { padding: false }, &be_bytes).to_lowercase();
    encoded[..8].to_string()
}
```
Update all golden vectors, snapshot tests, and the prop test `sid8_strategy` to use the base32 alphabet (`[a-z2-7]`) instead of hex.

**Contract refs:** §1.1.2 line 963; AT-216

---

## LAG-007 — `label_match` primary filter omits `sid8`; contract requires full-identity primary set

**Status:** OPEN

**Contract (§1.1.2, lines 984–989):**
```
Primary candidate set = all local intents where:
  - sid8 matches,
  - gid12 matches,
  - leg_idx matches,
  - ih16 matches (full short identity).
```
All four fields are required for the primary candidate set. The intention is that `ih16` is not a tie-breaker — it is part of the initial filter.

**Current code (`crates/soldier_core/src/recovery/label_match.rs`):**
- `MatchQuery` struct has no `sid8` field at all.
- Primary filter (line 114): `gid12 == query.gid12 && leg_idx == query.leg_idx` — two fields only.
- `ih16` is applied as tie-breaker B after the primary filter (line 125–136).
- `sid8` is never checked at any step.

In practice the risk is low because UUIDs make `gid12` collisions negligible across strategies. But the contract requires `sid8` to prevent cross-strategy phantom matches, and the implementation silently omits it. The algorithm also deviates structurally: the contract's "primary candidate set" means all four fields checked together, not a tiered waterfall.

**What needs to change:**
1. Add `sid8: &'a str` to `MatchQuery`.
2. Change primary filter to require all four: `gid12 && leg_idx && ih16 && sid8`.
3. If primary set is empty and a non-conforming (non-`s4:`) label is encountered, fail closed per AT-041.
4. Remove the tiered tie-breaker waterfall; replace with fail-closed on ambiguity after the four-field filter.
5. Update `IntentRecord` to carry `sid8`.
6. Update all tests that construct `MatchQuery` without `sid8`.

**Contract refs:** §1.1.2 lines 984–991; AT-217, AT-041

---

## Traceability map — likely touchpoints per lag

Use this section to scope changes quickly and avoid missing required test updates.

1. `LAG-001` and `LAG-002` (order-size domain model + amount semantics):
   - Implementation: `crates/soldier_core/src/execution/order_size.rs`, `crates/soldier_core/src/execution/intent_assembly.rs`, `crates/soldier_core/src/execution/open_runtime.rs`
   - Tests: `crates/soldier_core/src/execution/order_size_tests.rs`, `crates/soldier_core/src/execution/intent_assembly_tests.rs`, `crates/soldier_core/src/execution/dispatch_map_tests.rs`, `crates/soldier_core/src/execution/open_runtime_wiring_tests.rs`

2. `LAG-004` (intent hash canonical serialization):
   - Implementation: `crates/soldier_core/src/idempotency/hash.rs`
   - Tests: `crates/soldier_core/tests/test_idempotency.rs`, `crates/soldier_core/tests/adversarial_gi_enforcement.rs`

3. `LAG-005` (reject reason completeness):
   - Implementation: `crates/soldier_core/src/execution/reject_reason_generated.rs`, `crates/soldier_core/src/execution/reject_reason.rs`, `specs/status/status_reason_registries_manifest.json`
   - Tests: `crates/soldier_core/tests/test_reject_reason.rs`

4. `LAG-006` (`sid8` base32 derivation):
   - Implementation: `crates/soldier_core/src/execution/label.rs`
   - Tests: `crates/soldier_core/src/execution/label_tests.rs`, `crates/soldier_core/src/execution/label_prop_tests.rs`, `crates/soldier_core/src/execution/pipeline_intent_determinism_tests.rs`

5. `LAG-007` (label matching full identity):
   - Implementation: `crates/soldier_core/src/recovery/label_match.rs`
   - Tests: `crates/soldier_core/tests/test_label_match.rs`

---

*Last updated: 2026-03-02. Add new entries as gaps are discovered; mark DONE when the implementation matches the contract and tests cover the behavior.*

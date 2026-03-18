# Story Premortem: S2-001

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S2-001 -- Intent hash from quantized fields
- Contract clause(s): §1.1 Labeling & Idempotency Contract, §1.1.1 Canonical Quantization (Pre-Hash & Pre-Dispatch), CSP-002 (Idempotency & Deduplication), CSP.2.1 (Stable Intent Identity)
- Acceptance tests: AT-201, AT-343, AT-928, AT-218
- Touch scope: `crates/soldier_core/src/idempotency/hash.rs`, `crates/soldier_core/src/idempotency/mod.rs`, `crates/soldier_core/src/lib.rs`, `crates/soldier_core/tests/test_idempotency.rs`
- **Risk rating**: MED
  - The PRD currently marks this as **LOW**, but this premortem elevates it to **MED** because the idempotency/persistence boundary (intent_hash feeds WAL deduplication) can cause silent duplicate dispatches on restart.
  - If accepted, update the PRD risk rationale/rating to MED to keep documentation and gating aligned.
  - Touches idempotency/persistence boundary (intent_hash feeds WAL deduplication).
  - Getting this wrong produces silent duplicate dispatches on restart -- double position exposure.
  - Not HIGH because: no direct order placement, no funds movement, no risk limit changes. The hash function itself is pure computation with no side effects. However, its *consumers* (WAL, label, dedup) are safety-critical, making correctness here a prerequisite for their safety guarantees.
  - The risk is **non-determinism** or **input leakage** (timestamps, raw floats), not direct financial loss. But non-determinism in the hash breaks the entire dedup chain silently.

## 1) Clause audit (contract -> AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-201 | Definitions (intent classification) | "if an intent cannot be classified, it MUST be treated as OPEN" | MUST | Yes -- provide unknown action, verify OPEN classification |
| AT-343 | §1.1 (Intent Identity) | "two intents with identical canonical fields evaluated at different wall-clock times ... the two intent_hash values are identical" | MUST (implicit -- "identical" is a hard requirement) | Yes -- compute hash at t0 and t1, assert equality |
| AT-928 | §1.1.1 (Idempotency Rules) | "WAL already contains intent_hash for a pending intent ... it is a NOOP (no dispatch; no new WAL entry)" | MUST | Yes -- insert hash in WAL, re-evaluate same hash, assert dispatch_count=0 |
| AT-218 | §1.1.1 (Canonical Quantization) | "two codepaths compute the same intent fields ... both hashes are identical" | MUST (implicit) | Yes -- compute hash via two different call paths, assert equality |

**Note on AT-201**: This AT is about intent *classification* (fail-closed to OPEN), not about hashing. The PRD lists it as an enforcing AT for this story, but the enforcement point is intent classification, not the hash function. S2-001's hash implementation does not directly enforce AT-201. The connection is indirect: the hash must be computed after classification, and classification failures (OPEN) still produce valid hashes. This premortem treats AT-201 as a **contextual** AT for this story -- the hash function must not interfere with or circumvent intent classification. The story should not claim to *primarily own* AT-201's enforcement; that belongs to the intent classifier story.

**Note on LabelTooLong reason code**: The PRD lists `RejectReason::LabelTooLong` as a reason code for this story, but label length enforcement belongs to S2-002 (Label encoding). The connection is that `intent_hash` feeds into the `ih16` field of the s4 label, so a malformed hash could theoretically affect label length. In practice, the hash output is a fixed-width 64-bit value formatted as 16 hex chars, so it cannot cause label overflow. This reason code is contextual, not directly enforced by the hash function.

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement -- AT-201 noted as contextual, not directly enforced by hash

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | S2-000 (Quantization rounding) is complete and provides `qty_steps: u64` and `price_ticks: u64` (or equivalent integer types) as outputs | If quantization outputs are `f64` (e.g., `qty_q` as a float), hashing floats reintroduces non-determinism. The hash function signature must accept integer types, not floats. | Type-level enforcement: hash function takes `u64` for qty and price, not `f64`. Compile error if caller passes float. | Must verify at implementation time that S2-000 exports integer step/tick counts. |
| 2 | `xxhash64` is the hash algorithm, not SHA-256, BLAKE3, or another hash | Using a different algorithm changes all downstream consumers (label ih16, WAL dedup keys). CONTRACT.md §1.1 explicitly says `xxhash64`. | Test: compute known input, assert output matches xxhash64 reference value (golden vector). | Must verify correct crate (`xxhash-rust` or equivalent) is used. |
| 3 | Hash input fields are concatenated with a deterministic separator or framing, not just raw concatenation; this assumes Deribit instrument and side inputs are ASCII. If a non-ASCII instrument, side, or group_id appears, fallback to length-prefix framing is required. | Raw concatenation of `"BTC"` + `"USD"` is identical to `"BTCU"` + `"SD"` -- a classic hash collision via ambiguous field boundaries. Without separators or length-prefixed framing, distinct inputs can produce identical hashes. | Test: construct two inputs where raw concatenation is identical but field values differ (e.g., instrument `"AB"` + side `"CD"` vs. instrument `"ABC"` + side `"D"`), assert hashes differ. | Not specified in CONTRACT.md -- must be a design decision (§4). |
| 4 | The hash input field order is fixed and canonical: `instrument + side + qty_q + limit_price_q + group_id + leg_idx` per CONTRACT.md §1.1 | If field order varies (e.g., due to struct field iteration order or HashMap), the hash is non-deterministic across codepaths. | Test: construct identical inputs in two different struct instantiation orders, assert same hash. AT-218 covers this. | CONTRACT.md specifies the order explicitly. |
| 5 | `side` is serialized as a stable, canonical string (e.g., `"Buy"`, `"Sell"`), not as an enum discriminant integer that could change across versions | If `side` is serialized as `0`/`1` and the enum variant order changes in a future refactor, all existing WAL hashes become invalid and dedup breaks silently. | Test: assert hash of `Side::Buy` is stable across versions by including a golden vector with known hash output. | Must verify serialization format at implementation time. |
| 6 | `group_id` is a UUID string in a canonical format (lowercase, with or without dashes -- but always the same format) | If `group_id` formatting varies (e.g., uppercase vs lowercase hex, with vs without dashes), the same logical group produces different hashes. | Test: compute hash with `"550e8400-e29b-41d4-a716-446655440000"` and `"550E8400-E29B-41D4-A716-446655440000"`, assert they either produce the same hash (if normalized) or the normalization is enforced upstream. | Must decide canonical format (§4). |
| 7 | `leg_idx` is `0` or `1` per CONTRACT.md, serialized as its integer value, not as a string | If `leg_idx` is serialized as `"0"` (string) in one codepath and `0` (integer bytes) in another, hashes diverge. AT-218 requires identical hashes across codepaths. | Test: AT-218 covers this -- two codepaths must produce identical hashes. | Must enforce at type level. |
| 8 | The hash function is a pure function with no hidden state (no RNG seed, no process-local counter, no mutable hasher state leaking between calls) | If the hasher accumulates state between calls (e.g., a seeded hasher reused without reset), sequential hash computations interfere with each other. | Test: compute hash(A), hash(B), hash(A) again -- assert first and third are identical. | Verify hasher is fresh per call. |
| 9 | `instrument` is the exchange instrument ID string (e.g., `"BTC-PERPETUAL"`), not a numeric internal ID that could be remapped | If `instrument` is an internal numeric ID, the hash is coupled to a mapping table. Restarting with a different mapping table invalidates all WAL hashes. | Test: golden vector with a specific instrument string. | CONTRACT.md uses string instrument IDs. |
| 10 | The xxhash64 output is formatted consistently when stored in WAL and when compared for dedup (e.g., always as 16-char lowercase hex, or always as raw `u64`) | If one codepath stores the hash as uppercase hex and another compares as lowercase hex, dedup fails silently (WAL lookup misses). | Test: store hash, look up same hash, assert match. AT-928 covers the WAL dedup path. | Must enforce canonical formatting at storage boundary. |

## 3) Top 7 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | **f64 non-determinism in hash input**: Hash function accepts `qty_q` and `limit_price_q` as `f64` instead of integer steps/ticks. IEEE 754 floats have multiple representations for the same logical value (e.g., `+0.0` vs `-0.0`, NaN payloads, denormals). Two codepaths computing the same quantity may produce bitwise-different `f64` values, causing hash divergence. This is the highest-risk failure mode because it is **silent** -- the hash "works" in simple tests but diverges under specific numeric edge cases (e.g., values near denormal boundaries, negative zero from subtraction vs. literal zero). | Unit test with edge-case float values: `+0.0` vs `-0.0`, subnormals, values that round differently depending on FPU mode. Property test: hash(quantize(raw)) == hash(quantize(raw)) across process restarts. | **Type-level prevention**: hash function signature accepts `u64` (qty_steps, price_ticks), not `f64`. Compile error blocks the wrong type. This is Design Pattern §0.4: harder to misuse > easier to audit. | AT-218 (if tests include float edge cases), AT-343 (if tests include different process instances) |
| 2 | **Timestamp leakage into hash**: A `created_at`, `evaluated_at`, or `received_at` timestamp field is included in the hash input, either explicitly (developer adds it thinking "more unique is better") or implicitly (hash operates on a struct that includes timestamp fields via `#[derive(Hash)]` or similar). | AT-343 directly tests this: compute hash at different wall-clock times, assert equality. But the test only catches it if the clock actually advances between the two computations (not if both run in the same nanosecond). | CONTRACT.md hard rule: "Do NOT include wall-clock timestamps in the idempotency hash." Enforcement: hash function signature enumerates its inputs explicitly (no struct-level derive). | AT-343 |
| 3 | **Field boundary ambiguity causing collisions**: Hash input is raw concatenation without separators. Example: `instrument="BTC" + side="SELL"` hashes identically to `instrument="BTCS" + side="ELL"`. This is a hash *collision* for logically distinct intents, causing false dedup -- a legitimate new intent is silently dropped as a "duplicate." The result: an order that should be placed is never sent. | Test: construct two intents with ambiguous field boundaries, assert different hashes. This is not covered by any of the four ATs unless explicitly added as a test case. | Use a deterministic separator (e.g., null byte `\0`) between fields, or length-prefix each field. Alternatively, hash each field individually into a running hasher (xxhash streaming API), which naturally separates fields. | None of the four ATs directly test this. **New test needed.** |
| 4 | **Endianness of integer serialization**: `qty_steps` and `price_ticks` are `u64` values. When fed to the hasher as bytes, big-endian vs. little-endian serialization produces different hashes. If one codepath uses `to_le_bytes()` and another uses `to_be_bytes()` (or native endian), hashes diverge across codepaths or across architectures. | AT-218 (two codepaths, same hash) catches this if the two codepaths use different byte orders. But if both codepaths consistently use the wrong endianness, AT-218 passes and the hash is merely "different from what another architecture would compute" -- this only matters for cross-architecture WAL portability. | Fix the byte order in the hash function (e.g., always `to_le_bytes()`). Add a golden vector test that asserts a specific hash output for known inputs, anchoring the byte order. | AT-218 (partially), golden vector test (must be added) |
| 5 | **Extra fields in hash that happen to not vary in test fixtures**: The hash function includes an extra field (e.g., `strat_id`, `reduce_only`, or even `exchange_name`) that is not part of the CONTRACT.md canonical set `{instrument, side, qty_q, limit_price_q, group_id, leg_idx}`. If all test fixtures use the same value for this extra field, all four ATs pass. But in production, two intents with identical canonical fields but different `strat_id` values produce different hashes -- dedup fails to catch duplicates, allowing double dispatch. | **Devil's advocate test**: hold canonical fields constant, vary non-canonical fields (strat_id, reduce_only, created_at, exchange_name), assert hash is unchanged. If hash changes when a non-canonical field changes, the hash includes too many fields. | Review hash function input list against CONTRACT.md §1.1 canonical field list. The hash function should accept exactly 6 named parameters, not a struct with extra fields. | None of the four ATs directly test this. **New test needed** (vary non-canonical fields, assert hash unchanged). |
| 6 | **Hash algorithm mismatch (not xxhash64)**: Implementation uses a different hash (e.g., `std::hash::DefaultHasher`, SHA-256, or xxhash32) instead of xxhash64. The hash "works" (deterministic, collision-resistant) but produces different values than what the label encoder (S2-002) expects for `ih16`. Label dedup and WAL dedup use different hash values, breaking the identity chain. | Golden vector test: compute hash of known input, assert it matches the xxhash64 reference value. Without this, any deterministic hash passes all four ATs. | Pin the exact crate and algorithm in the implementation. Golden vector test anchors the choice. | None of the four ATs test the specific algorithm. **Golden vector test needed.** |
| 7 | **Hasher seed varies across runs or across codepaths**: xxhash64 accepts an optional seed parameter. If one codepath uses seed=0 and another uses seed=42 (or a random seed), hashes diverge. Some xxhash implementations default to a non-zero seed. | AT-218 catches this if the two codepaths happen to use different seeds. But if both use the same wrong seed, the hash is merely "different from the reference" -- only a golden vector test catches this. | Fix seed to 0 (the conventional default) explicitly in the hash function. Assert in golden vector test. | AT-218 (partially), golden vector test (must be added) |

## 4) Open decisions (resolve before coding)

### Decision: Hash input representation -- integer steps/ticks vs. reconstructed f64
- **What is ambiguous / missing**: CONTRACT.md §1.1 says `intent_hash = xxhash64(instrument + side + qty_q + limit_price_q + group_id + leg_idx)`. The notation `qty_q` and `limit_price_q` is ambiguous: are these the *reconstructed* float values (`qty_steps * amount_step`) or the raw integer step/tick counts? The PRD story S2-001 acceptance criteria say "those integer values (plus stable strings) are used, not raw f64," which implies integer step/tick counts. But CONTRACT.md §1.1.1 defines `qty_q` as `round_down(raw_qty, amount_step)`, which is a float operation producing a float result.
- **Evidence**: CONTRACT.md §1.1.1: "`qty_q = round_down(raw_qty, amount_step)`" (float). PRD S2-001 acceptance: "quantized qty_steps and price_ticks ... those integer values (plus stable strings) are used, not raw f64." PRD S2-001 step 3: "Use qty_steps and price_ticks (integers) alongside instrument, side, group_id, and leg_idx in the hash material."
- **Options**:
  1. Option A -- Hash the integer step/tick counts (`qty_steps: u64`, `price_ticks: u64`). Deterministic by construction. No f64 non-determinism risk. But requires that the quantization layer (S2-000) exposes integer step counts, not just the reconstructed float.
  2. Option B -- Hash the reconstructed float values (`qty_q: f64`, `limit_price_q: f64`) as their `to_le_bytes()` representation. Matches CONTRACT.md notation. But introduces f64 non-determinism risk (FM-1).
- **Chosen**: A -- Hash integer step/tick counts. The PRD explicitly requires this. Design Pattern §0.1 says "decisions use real quantities, not proxies" -- integer step counts are the real canonical representation; the reconstructed float is a derived proxy. Design Pattern §0.4: harder to misuse (compiler rejects f64 at the type boundary).
- **Why not others**: Option B re-introduces the exact class of bug this story exists to prevent. The whole point of S2-001 is to hash quantized *integer* fields, not floats.
- **Scope control**:
  - What we're NOT doing yet: changing CONTRACT.md notation from `qty_q`/`limit_price_q` to `qty_steps`/`price_ticks`. The contract uses the float notation; the implementation uses integers. This is acceptable because the contract says "quantized fields" and the PRD clarifies "integer values."
  - What unblocks us if this choice is wrong: if S2-000 does not expose integer step counts, we can add accessors without changing the quantization logic.

### Decision: Field separator strategy for hash input
- **What is ambiguous / missing**: CONTRACT.md §1.1 says `xxhash64(instrument + side + qty_q + limit_price_q + group_id + leg_idx)`. The `+` operator is not specified -- is it string concatenation, byte concatenation, or sequential hasher feeds?
- **Evidence**: CONTRACT.md §1.1: the notation `instrument + side + qty_q + ...` does not specify a separator or framing mechanism. FM-3 above demonstrates the collision risk of raw concatenation.
- **Options**:
  1. Option A -- Feed each field sequentially into the xxhash64 streaming hasher as typed bytes (strings as UTF-8 bytes, integers as `to_le_bytes()`). The hasher's internal state naturally separates the feeds. **But**: xxhash64 streaming is sensitive to feed boundaries -- `hasher.write(b"AB"); hasher.write(b"CD")` may or may not equal `hasher.write(b"ABCD")` depending on implementation. This must be verified.
  2. Option B -- Concatenate all fields with a null byte (`\0`) separator into a single byte buffer, then hash the buffer in one shot. Clear field boundaries, no ambiguity about streaming behavior.
  3. Option C -- Length-prefix each field (4-byte little-endian length + field bytes) into a single buffer, then hash. Most robust against collisions, but more complex.
- **Chosen**: B -- Null-byte separated concatenation, then single-shot hash. Simple, deterministic, no streaming API ambiguity. Null byte cannot appear in instrument names, side strings, or UUID group_ids, so it is a safe separator. Integer fields are formatted as their decimal string representation (or fixed-width byte representation) before concatenation.
- **Why not others**: Option A depends on xxhash streaming semantics that vary by implementation. Option C is more robust but adds complexity (Design Pattern §0.3: smallest surface area change). Option B is sufficient because the field types cannot contain null bytes.
- **Scope control**:
  - What we're NOT doing yet: supporting arbitrary binary instrument names. If instrument names could contain null bytes, Option C would be required. Current Deribit instrument names are ASCII strings.
  - What unblocks us if this choice is wrong: switching from B to C is a single-function change with a golden vector update.

### Decision: Integer serialization format for hash input
- **What is ambiguous / missing**: `qty_steps` and `price_ticks` are `u64` integers. How are they represented in the hash input buffer? Options: decimal string (e.g., `"12345"`), little-endian 8-byte binary, big-endian 8-byte binary.
- **Evidence**: No contract guidance. This is an implementation detail.
- **Options**:
  1. Option A -- Decimal string representation (e.g., `"12345"`). Human-readable if the hash input buffer is logged. Variable length.
  2. Option B -- Fixed 8-byte little-endian binary (`to_le_bytes()`). Fixed width, no parsing ambiguity, slightly more compact.
- **Chosen**: B -- Little-endian binary. Fixed width eliminates any possibility of field-boundary confusion with the separator (a decimal string `"0"` is 1 byte, `"12345"` is 5 bytes -- variable width). Little-endian is the native byte order on x86/ARM, minimizing unnecessary byte swaps. The golden vector test anchors this choice.
- **Why not others**: Option A introduces variable-width fields, which combined with the separator strategy (Decision 2) works fine but is less clean. Option B is canonical in binary hashing.
- **Scope control**:
  - What we're NOT doing yet: cross-architecture WAL portability (which would require big-endian for network byte order). Current deployment target is single architecture.
  - What unblocks us if this choice is wrong: changing byte order requires updating the golden vector and rehashing any persisted WAL entries (migration story).

### Decision: xxhash64 seed value
- **What is ambiguous / missing**: xxhash64 takes an optional seed parameter. CONTRACT.md does not specify a seed value.
- **Evidence**: No contract guidance. Default seed varies by implementation (usually 0).
- **Options**:
  1. Option A -- Seed = 0 (conventional default).
  2. Option B -- Seed = a fixed non-zero constant (e.g., derived from a project name hash).
- **Chosen**: A -- Seed = 0. Conventional, matches reference implementations, simplest. The golden vector test anchors this.
- **Why not others**: Option B adds no security value (xxhash is not a cryptographic hash) and makes debugging harder.
- **Scope control**: N/A -- trivial decision.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate

| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-343 | Hash includes `strat_id` in addition to the 6 canonical fields. All test fixtures use the same `strat_id`, so two intents at different times still hash identically. | The hash is non-minimal: changing `strat_id` (e.g., strategy rename) causes the same logical intent to produce a different hash. WAL dedup fails to catch the duplicate. Double dispatch on strategy rename. | **New test**: hold all 6 canonical fields constant, vary `strat_id` across two calls, assert hash is identical. If hash changes, the implementation includes a non-canonical field. |
| AT-343 | Hash uses `f64` representation of `qty_q` (reconstructed float) instead of `u64` `qty_steps`. All test fixtures use "clean" float values (e.g., 0.1, 1.0) that have exact IEEE 754 representations, so the hash is deterministic in tests. | In production, values near denormal boundaries or values computed via different arithmetic paths (e.g., `3 * 0.01` vs `0.03`) produce bitwise-different `f64`, causing hash divergence for the same logical quantity. AT-343 passes because test fixtures avoid these edge cases. | **New test**: construct two intents where the float representation of `qty_q` differs bitwise (`+0.0` vs `-0.0`, or `0.1 + 0.2` vs `0.3`) but the integer step count is identical. Assert hashes are identical. This test *fails* if the hash uses raw f64 bytes. |
| AT-343 | Hash is computed from a Rust struct via `#[derive(Hash)]`, which happens to exclude timestamp fields because they are in a separate struct. The hash *also* includes `reduce_only: bool` which does not vary in test fixtures. | The hash includes `reduce_only`, violating the canonical field list. In production, the same order intent with `reduce_only=true` vs `reduce_only=false` produces different hashes. Since dedup is hash-based, a re-sent intent with a changed classification is not deduped, causing potential double dispatch. | **New test**: same 6 canonical fields, one intent with `reduce_only=true` and one with `reduce_only=false`, assert hashes are identical. |
| AT-218 | Both "codepaths" in the test are actually the same function called twice with the same inputs. The test proves the function is deterministic (given same inputs, same output) but does NOT prove two *different* call sites produce the same hash. | If a second call site constructs the hash input differently (e.g., different field order, different serialization), AT-218 passes but the two codepaths diverge in production. | **Tighten AT-218 test**: the two codepaths must construct the hash input via genuinely different paths (e.g., one from a struct, one from individual fields; or one from a deserialized message, one from a fresh construction). |
| AT-928 | WAL dedup works because the test stores and looks up the same hash, but the hash itself includes a non-canonical field (e.g., `exchange_name`). All test fixtures use the same exchange, so dedup succeeds. | In a multi-exchange scenario (or if the exchange field changes), the same logical intent on a different exchange produces a different hash, and dedup fails to catch it. WAL contains both entries, and both are dispatched. | **New test**: same canonical fields, different `exchange_name`, assert same hash. (This is a variant of the "extra fields" test from AT-343 tightening.) |
| AT-928 | WAL dedup works, but the hash is a 32-bit hash (xxhash32) instead of 64-bit. For the small number of intents in the test, no collisions occur. | In production with thousands of intents, the birthday paradox makes 32-bit collisions likely. A false collision causes a legitimate intent to be silently dropped as a "duplicate." No dispatch, lost order. | **Golden vector test**: compute hash of known input, assert it is a 64-bit value matching the xxhash64 reference output. This anchors both the algorithm and the output width. |
| AT-218 | Hash uses `std::collections::hash_map::DefaultHasher` which is deterministic *within a single process run* but may use a random seed across runs (SipHash with random key). AT-218 passes because both codepaths run in the same process. | On process restart, the hasher seed changes, all WAL hashes are invalid, and dedup breaks completely. Every previously-recorded intent is "new" and gets re-dispatched. | **Golden vector test**: assert specific hash output for known input. Run the test, kill the process, run it again, assert same output. (Or simply: the golden vector is a constant in the test source code, which proves cross-run stability.) |

- [x] Every AT has at least one wrong impl identified (AT-201 excluded as contextual, see §1 note)
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one -- the golden vector test and the "vary non-canonical fields" tests collectively make the correct implementation (xxhash64 of exactly 6 canonical integer/string fields) the path of least resistance

## 6) Proof plan (AT -> enforcement -> tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-343 | WAL (hash computation) | `test_idempotency::hash_identical_at_different_times` | Yes (include timestamp in input, assert hash changes -- then remove, assert hash is time-independent) | Yes (exclude timestamp, two different timestamps produce same hash) | `hash_equality` (assert hash(t0) == hash(t1)) | Yes -- isolates time-independence of hash |
| AT-218 | WAL (hash computation) | `test_idempotency::hash_identical_across_codepaths` | Yes (change field order in one codepath, assert hash diverges -- proves the canonical ordering matters) | Yes (both codepaths produce same hash for same inputs) | `hash_equality` (assert hash_A == hash_B) | Yes -- isolates cross-codepath determinism |
| AT-928 | WAL (dedup lookup) | `test_idempotency::wal_dedup_noop_on_duplicate_hash` | Yes (insert hash, re-insert same hash, assert dispatch_count == 0) | Yes (insert hash, insert *different* hash, assert dispatch_count == 1 for the second) | `dispatch_count` (0 for duplicate, 1 for unique) | Yes -- isolates WAL dedup behavior |
| AT-201 | Intent classifier (not hash) | Not directly tested by this story | N/A | N/A | N/A | N/A -- AT-201 is contextual for this story; primary enforcement is in the intent classifier story |

**Additional required tests (from §5 wrong-impl analysis):**

| Test | What it proves | Source |
|------|---------------|--------|
| `test_idempotency::golden_vector_xxhash64` | Hash algorithm is xxhash64 with seed=0; output matches reference value | FM-6, FM-7, §5 wrong-impl gates |
| `test_idempotency::hash_ignores_non_canonical_fields` | Hash is unchanged when non-canonical fields (strat_id, reduce_only, exchange_name) vary | FM-5, §5 wrong-impl gates |
| `test_idempotency::hash_uses_integer_steps_not_float` | Hash uses u64 qty_steps/price_ticks, not f64 qty_q/limit_price_q | FM-1, §5 wrong-impl gates |
| `test_idempotency::hash_field_boundary_no_collision` | Ambiguous field concatenation does not produce false collisions | FM-3 |

- [x] Every safety-critical AT has TRIP + NON-TRIP -- AT-343, AT-218, AT-928 all have both
- [x] Every test proves causality (not just existence) -- hash_equality or dispatch_count, not "function exists"
- [x] Each AT isolates one clause (removing enforcement fails exactly this AT)
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix -- AT-201 explicitly excluded as contextual

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: Intent hash is non-deterministic or includes extra/missing fields. On process restart, WAL dedup fails to recognize previously-recorded intents. All in-flight intents are treated as "new" and re-dispatched. Result: double position exposure. For a strangle strategy with two legs, this means 4 orders instead of 2, doubling the intended position size. Worst case: 2x max position limit exposure before any risk gate catches the overshoot.
- **Fail-closed cap on loss**: WAL fsync required before dispatch ack. The WAL itself is the dedup mechanism -- if the hash is wrong, the WAL *still records* the intent (just with a wrong hash), so a second evaluation with the same wrong hash will still dedup correctly within a single process run. The failure mode is specifically **cross-restart**: the restarted process computes a different hash for the same intent and does not find it in the WAL. The fail-closed cap is therefore the position limit enforced by PolicyGuard -- even if duplicates are dispatched, the position limit should catch the overshoot and transition to ReduceOnly. However, this depends on the position limit being tighter than 2x the intended position, which is a configuration concern.
- **Drift metric**: N/A -- determinism is a property, not a metric. There is no runtime signal that "the hash is computing correctly." The proof is the golden vector test and the cross-restart determinism test. If these pass, the property holds. If the xxhash crate is upgraded and the golden vector test breaks, that is the detection signal.
- **Loss boundary**: Position limit (PolicyGuard) caps the blast radius of duplicate dispatch. ReduceOnly mode is triggered if position exceeds limit. Kill switch is available for emergency. Time bound: the duplicate dispatch happens at restart, which is an operator-initiated event (not a continuous risk).
- **Rollback plan**: If the hash function is found to be wrong after deployment, rollback is: (1) stop the process, (2) `git revert` the hash change, (3) wipe the WAL (since hashes are now inconsistent with the new/reverted function), (4) reconcile positions from exchange REST API, (5) restart. The WAL wipe is the dangerous step -- it loses the dedup history. The reconciliation step (3) must be run before restart to prevent re-dispatch of previously-sent intents.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: The intent_hash feeds into:
  1. WAL dedup (§2.4 Durable Intent Ledger): hash is the dedup key
  2. Label encoding (§1.1): `ih16` field in the s4 label is the first 16 hex chars of intent_hash
  3. TruthCapsule linkage (§2.5): capsules are keyed by `(group_id, leg_idx, intent_hash)`
  4. Corrective actions: `ReplaceIOC(intent_hash, new_limit_price)` references intent_hash

  Changing the hash function after any of these consumers are implemented requires a coordinated migration. Since S2-001 is early in the sequence (Slice 2), consumers S2-002 (label), S2-003+ (WAL), and later stories have not yet been implemented, so the risk of breaking existing consumers is low.

- **If conflict with CONTRACT.md**: No conflict. CONTRACT.md §1.1 specifies `xxhash64(instrument + side + qty_q + limit_price_q + group_id + leg_idx)` and this story implements exactly that, using integer representations per the PRD clarification.

- Files with recent churn or shared ownership:
  - `crates/soldier_core/src/idempotency/hash.rs` -- new file (created by this story), no churn
  - `crates/soldier_core/src/idempotency/mod.rs` -- module declaration, minimal churn
  - `crates/soldier_core/src/lib.rs` -- module re-export, high churn (touched by every story that adds a module)
  - `crates/soldier_core/tests/test_idempotency.rs` -- new file, no churn

- Struct fields I'm assuming exist (verify before coding):
  - `qty_steps: u64` and `price_ticks: u64` from S2-000's quantization output. If S2-000 exposes only `qty_q: f64` and `limit_price_q: f64`, this story must either (a) add step/tick accessors to S2-000's output or (b) recompute step counts from the float values (which reintroduces the f64 risk).
  - `instrument: String` (or `InstrumentId(String)` newtype)
  - `side: Side` enum with canonical string serialization
  - `group_id: String` (UUID format)
  - `leg_idx: u8` or `u32`

- State machine transitions affected: None. The hash function is pure computation with no state machine interaction.

- **Cross-story dependency note**: S2-000 (Quantization) is the direct dependency. S2-002 (Label encoding) depends on this story's output (intent_hash). S2-003+ (WAL, dedup) depend on the hash for dedup correctness. The interface contract is: this story exports a function `compute_intent_hash(instrument, side, qty_steps, price_ticks, group_id, leg_idx) -> u64` that is deterministic, xxhash64-based, and time-independent.

## 9) Constraint I expect to hit

Prior Postmortem: NONE (no S2-000 postmortem exists)
Reused Guardrail: NONE (no prior postmortem in this slice)

- Carry-forward from prior postmortem: N/A -- no S2-000 postmortem found.
- What will slow me down: Verifying that S2-000 exports integer step/tick counts (not just float qty_q/limit_price_q). If S2-000 only exposes floats, this story must either extend S2-000's API or accept the f64 risk. The PRD steps say "Ensure callers pass quantized integer fields into the hashing function," which implies the integer types must be available, but whether S2-000 actually provides them is an implementation detail that must be checked.
- Exploit: If S2-000 exposes only floats, compute `qty_steps = (qty_q / amount_step).round() as u64` and `price_ticks = (limit_price_q / tick_size).round() as u64` at the hash boundary. This reconstructs integers from floats, which is safe as long as the float values are exact multiples of the step/tick size (which they are, by construction from S2-000's rounding). Add a debug assertion that the reconstruction is exact: `debug_assert!((qty_steps as f64) * amount_step == qty_q)`.
- Smallest fix that prevents it next time: S2-000 should export both the float (`qty_q`, `limit_price_q`) and integer (`qty_steps`, `price_ticks`) representations. The float is needed for order payloads; the integer is needed for hashing. Adding both outputs to S2-000's return type makes downstream consumers' type requirements explicit.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

- **YELLOW**: All ATs are traced and have proof plans with TRIP + NON-TRIP. All failure modes have detection and mitigation. All decisions are resolved. However, several gaps require new tests beyond the four claimed ATs, and the AT-201 ownership is questionable (contextual, not directly enforced by hash). All gaps are explicitly deferred with owners and target slices below.

**Debt Register** (required if YELLOW):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| Golden vector test (xxhash64 reference output for known input) not in any AT | Med | No AT specifies the exact algorithm output; any deterministic hash passes AT-343/AT-218. Golden vector is the only anchor. | S2-001 implementer | S2-001 implementation | `test_idempotency::golden_vector_xxhash64` with hardcoded expected hash value |
| Non-canonical field exclusion test not in any AT | Med | AT-343 and AT-218 do not test that hash ignores non-canonical fields (strat_id, reduce_only, etc.). A wrong impl that includes extra fields passes all ATs if fixtures do not vary those fields. | S2-001 implementer | S2-001 implementation | `test_idempotency::hash_ignores_non_canonical_fields` |
| Field boundary collision test not in any AT | Low | FM-3 is a theoretical risk; null-byte separator eliminates it. But no AT proves the separator works. | S2-001 implementer | S2-001 implementation | `test_idempotency::hash_field_boundary_no_collision` |
| AT-201 is listed as enforcing but is contextual for this story | Low | AT-201 is about intent classification fail-closed, not about hashing. This story should not claim primary enforcement of AT-201. | PRD maintainer | PRD cleanup | Remove AT-201 from S2-001's `enforcing_contract_ats` or add a note that it is contextual |
| S2-000 integer type export not verified | Low | Whether S2-000 exports `qty_steps`/`price_ticks` as `u64` is unknown until implementation. If it exports only floats, the exploit in FM-1 must be applied. | S2-001 implementer | S2-001 implementation | Verify S2-000 API at implementation start; add integer accessors if missing |
| Cross-restart determinism test (golden vector across process restarts) | Med | AT-218 tests within a single process. No AT proves hash stability across restarts. The golden vector test implicitly proves this (hardcoded expected value), but an explicit cross-restart test would be stronger evidence. | S2-001 implementer | S2-001 implementation or evidence story | `test_intent_determinism` (evidence story) covers this; verify it uses the same hash function |

YELLOW with all debt tracked and assigned to target slices. No RED blockers. All YELLOW items are addressable within S2-001 implementation (no external dependencies except the AT-201 PRD cleanup, which is low severity).

**Exit criteria (definition of done, before I start):**
- [x] §1 clause audit: every AT traced to normative clause -- 4 ATs traced; AT-201 noted as contextual
- [x] §2 all assumptions validated or killed -- 10 assumptions documented with test strategies
- [x] §3 all failure modes have detection + mitigation -- 7 modes identified, all with detection and mitigation
- [x] §4 all decisions resolved, grounded in evidence -- 4 decisions resolved with CONTRACT.md and PRD references
- [x] §5 wrong impl gate: every AT tightened, no easy wrong impl survives -- 7 wrong impls identified with tightening tests
- [x] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN -- AT-343, AT-218, AT-928 all have both; AT-201 excluded as contextual
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan -- double-position worst case documented; PolicyGuard position limit is the cap; rollback plan includes WAL wipe + reconciliation
- [x] §8 conflict scan clean (no CONTRACT.md conflicts) -- clean; cross-story dependencies on S2-000 (input) and S2-002 (output) noted
- [x] No new debt without owner + target slice -- 6 debt items tracked in register with owners and target slices

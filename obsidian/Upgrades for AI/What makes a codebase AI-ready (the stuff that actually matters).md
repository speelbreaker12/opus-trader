

### 1) Your #1 constraint is feedback latency (TOC)

If the AI can’t get a tight “change → test → signal” loop, it will **guess**, and guessing is where quality dies.

**Non-negotiables**

- One command to run the relevant tests fast: `test`, `lint`, `typecheck`, `smoke`
    
- Deterministic tests (no flaky “maybe pass”)
    
- Clear failures (error messages that point to _one_ cause)
    
- Golden tests / snapshots for boundaries that matter (inputs → outputs)
    

If your tests take 20 minutes or fail randomly, your system is telling the AI: _“Just vibe it.”_

### 2) Deep modules, but with “hard borders”

Deep modules are good. But “deep modules” without enforcement become **fake boundaries**.

**Enforcement options**

- Folder + import rules (lint rule: you can’t import across domains except via interface)
    
- Explicit public API file (single re-export surface)
    
- Dependency direction rules (domain → application → infrastructure; never reverse)
    
- No cross-domain “utility” dumping ground (that’s where architecture goes to die)
    

### 3) Make the interface the contract, and lock it with tests

This is the cheat code for delegating internals to AI.

- **Interface** = types + invariants + examples
    
- **Tests** = executable contract
    
- **Internals** = replaceable
    

If you can’t state the invariants, you don’t have a module—you have a pile of code.

### 4) Progressive disclosure, not “clever”

AI is a new hire with amnesia. So design for:

- `README.md` at module root: purpose, invariants, how to test, examples
    
- “Start here” index file: exports + high-level flow
    
- Minimal indirection (no 7-layer factory chains unless you love suffering)
    

### 5) Kill the “shared state hydra”

Nothing wrecks AI edits faster than hidden global state and side effects.

Prefer:

- explicit inputs/outputs
    
- pure functions at the core
    
- side effects at the edges (ports/adapters)
    
- dependency injection that is boring and obvious
    

### 6) One source of truth for behavior

If behavior is described in 5 places (docs, comments, tests, config, runtime flags), AI will pick the wrong one.

Pick _one_:

- Tests + public interface docs are canonical
    
- Everything else is secondary
    

---

## The 20-year-old books I’d bet your trading platform on

### **A Philosophy of Software Design** — John Ousterhout

You already cited it. Keep it. It’s the best “complexity is the enemy” framing, and deep modules are the right instinct.

### **Working Effectively with Legacy Code** — Michael Feathers (2004)

This is _the_ playbook for making an un-AI-ready codebase AI-ready:

- finding seams
    
- characterizing tests
    
- incremental refactors without breaking production
    

If you only buy one: buy this.

### **Test-Driven Development: By Example** — Kent Beck

Not because TDD is a religion—because it teaches **tight feedback loops** and small verified steps, which is exactly what AI needs.

### **Domain-Driven Design** — Eric Evans (2003)

AI struggles when domain concepts are smeared across files. DDD gives you:

- bounded contexts (aka real module borders)
    
- ubiquitous language (naming that prevents wrong edits)
    
- domain model clarity
    

### **Patterns of Enterprise Application Architecture** — Martin Fowler (2002)

You don’t need all the patterns. You need the _separation instincts_:

- transaction boundaries
    
- layering
    
- mapping between domain and persistence
    

### **Pragmatic Programmer** (1999) + **Code Complete** (2004)

These are “taste calibrators.” The biggest AI failures happen where humans had no taste to begin with.

### Optional if you want to go hardcore on constraints:

- **Object-Oriented Software Construction** — Bertrand Meyer (Design by Contract mindset)
    
- **Refactoring** — Fowler (1999) (mechanical refactor moves = safer AI work)
    

---

## The ruthless truth (only saying it once)

If your system can’t tell you quickly and reliably whether a change improved or broke behavior, you’re not building an AI-coded system—you’re running a lottery.

---

## If you want to apply this to _your_ trading codebase

Your highest leverage move is to define **a small set of “deep modules”** that match your actual mental map, then enforce import boundaries and add characterization tests at those seams.

For your platform, examples of deep modules usually look like:

- Market Data / Vol Surface ingestion (pure transformations + caching at edge)
    
- Strategy engine (pure decision function)
    
- Risk gate (explicit invariants, fail-closed)
    
- Execution + order state machine (idempotency + WAL)
    
- Portfolio/accounting reconciliation
    

Make each of those a “public interface + tests + replaceable internals” box.

If you want, paste just your top-level repo tree (folders only). I’ll tell you where your boundaries are currently fake, where coupling is hiding, and what 3 modules you should deep-module first for maximum feedback speed.
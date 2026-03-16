# SKILL: TDD Reference (Companion Docs)

This directory contains reference documents for test-driven development in this codebase. These companion docs are bundled with the TDD workflow and should be consulted during implementation.

## Index

| Doc | Purpose |
|-----|---------|
| [tests.md](tests.md) | Good vs bad tests — integration-style over implementation-coupled |
| [mocking.md](mocking.md) | When to mock (system boundaries only), Rust-specific patterns |
| [deep-modules.md](deep-modules.md) | Ousterhout's deep module principle applied to our codebase |
| [interface-design.md](interface-design.md) | Interface design for testability |
| [refactoring.md](refactoring.md) | Refactor candidates after GREEN phase |

## Usage

These docs are reference material, not a workflow. The workflow lives in:
- `superpowers:test-driven-development` (the superpowers TDD skill)
- `SKILLS/acceptance-test.md` (contract-aligned AT generation)

Consult these docs when:
- Writing a new test and unsure whether it tests behavior or implementation
- Deciding whether to mock a dependency
- Designing a module interface for testability
- Looking for refactor opportunities after tests pass

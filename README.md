# tripwire

[![CI](https://github.com/elijahr/tripwire/actions/workflows/ci.yml/badge.svg)](https://github.com/elijahr/tripwire/actions/workflows/ci.yml)

[![Release](https://img.shields.io/github/v/release/elijahr/tripwire)](https://github.com/elijahr/tripwire/releases/latest)
[![License](https://img.shields.io/github/license/elijahr/tripwire)](LICENSE)
[![Nim](https://img.shields.io/badge/Nim-2.2%2B-yellow.svg)](https://nim-lang.org)

Test mocking framework with three-guarantee enforcement

## Quick Start

```nim
import tripwire

echo hello()
```

## Development

The `justfile` is the canonical command surface for common tasks:

```bash
just setup        # Install dependencies
just test         # Run test suite
just lint         # Check formatting (nph) and nimble check
just fmt          # Auto-format codebase with nph

just build        # Build release artifacts
```

## Upstream Updates

This project was initialized via [Polyform](https://github.com/axiomantic/polyform). To update boilerplate, CI workflows, and tooling from upstream:

```bash
uvx copier update --trust
```

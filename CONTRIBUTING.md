# Contributing to TestcontainerEx

Thank you for your interest in contributing!

## Prerequisites

- Elixir 1.15+
- Docker or Podman running locally
- `mix` and `hex` up to date (`mix local.hex && mix local.rebar`)

## Running the test suite

```bash
cp .env.example .env
# Edit .env and uncomment your container runtime

mix deps.get
mix test
```

## Running only unit tests (no Docker required)

```bash
mix test --exclude integration
```

## Code style

- Run `mix format` before committing.
- Run `mix credo --strict` and fix all issues.
- All public functions must have `@doc` and `@spec`.

## Branch naming

- `feat/<short-description>` for new features
- `fix/<short-description>` for bug fixes
- `docs/<short-description>` for documentation-only changes

## Pull request checklist

- [ ] Tests pass (`mix test`)
- [ ] No Credo warnings (`mix credo --strict`)
- [ ] Docs build without warnings (`mix docs`)
- [ ] `CHANGELOG.md` updated under `[Unreleased]`

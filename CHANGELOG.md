# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Typed `TestcontainerEx.Error` struct for all public API errors.
- `TestcontainerEx.Retry` module with exponential-backoff retry helper.
- `TestcontainerEx.LogConsumer` for streaming container logs to Logger.
- `TestcontainerEx.Container.Behaviour` for defining custom container types.
- `start_container_async/1` and `await_container/2` for parallel container setup.
- `with_log_consumer/2` builder for streaming container logs to Logger.
- Wait-strategy poll telemetry events (`[:testcontainer_ex, :wait_strategy, :poll]`).
- Correlation / request IDs in logs and telemetry.
- Architecture decision records (ADRs).

### Changed
- `stop_container/1` is now idempotent — returns `{:ok, :already_stopped}` if the
  container is not running.
- All public functions return `{:ok, _} | {:error, TestcontainerEx.Error.t()}`.
- Wait-strategy failures include last container logs in error context.

## [0.7.2] — 2025-06-18

### Changed
- Improved retry logic for container creation and start.
- Better error handling for Docker API transient failures.

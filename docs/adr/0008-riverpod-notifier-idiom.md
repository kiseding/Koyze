# ADR 0008 — One Riverpod notifier idiom

- **Status:** Accepted
- **Date:** 2026-10-26
- **Context:** review item #11, "统一 Riverpod Notifier 范式"

## Problem

The codebase carried two state-management idioms side by side:

- `StateNotifierProvider` for the stateful screens (settings, player position,
  search, cloud session, sync, equalizer, leaderboard, recommendations) — 12
  providers and 22 notifier classes;
- `NotifierProvider` for everything written after Riverpod 2 was adopted.

Both compile, but the split leaks into review and onboarding: two base classes
with different lifecycles, two ways to override a provider in a test, two
answers to "where does the value live". Riverpod 3 removes `StateNotifier`
entirely, so the migration had to happen eventually — deferring it only raises
the price.

The migration looked mechanical and was not. `StateNotifier` exposes `state`
from the constructor onward and has a `mounted` flag and a `dispose()` hook;
`Notifier` has none of that:

| `StateNotifier` | `Notifier` (2.6) |
| --- | --- |
| `state` readable at construction | throws `LateInitializationError` until `build()` runs in a container |
| `mounted` | does not exist |
| `dispose()` | does not exist; use `ref.onDispose` |
| `overrideWith((ref) => ...)` | `overrideWith(() => ...)` |
| `addListener(listener, fireImmediately:)` | provider listeners only |

That matters because **73 test call sites construct these notifiers directly**.
They do it deliberately: a test that drives a state machine through a
`ProviderContainer` is coupled to Riverpod, and the behaviours those tests
guard — stale-response races, generation counters, persistence rollback — have
nothing to do with Riverpod.

## Decision

Migrate every `StateNotifier` to `Notifier`, and put the compatibility layer in
one place instead of in 22 subclasses.

### `BuildlessNotifier` (`lib/core/state/buildless_notifier.dart`)

An abstract `Notifier<T>` that:

- keeps the canonical value in a plain field, so `value` reads synchronously
  before or after `build()`;
- mirrors that field into `state` on every `publish()`, swallowing the
  `LateInitializationError` a directly-constructed instance would hit;
- provides `mounted` (a `_disposed` flag) and `dispose()` for tests, with
  `onTeardown()` as the override point for timers and subscriptions;
- provides `addListener`/`removeListener` so the one test that asserts
  "unchanged positions do not notify" keeps working without a container.

### `PersistedSetting<T>` (`lib/core/storage/persisted_setting.dart`)

The twelve persisted scalar settings (accent colour, theme mode, audio quality,
download quality, …) share three problems: a stale disk read landing after a
user edit, overlapping writes, and rollback when a write fails.
`PersistedSetting` owns those rules as a plain object; `_PersistedSettingNotifier`
is a thin adapter. The rules are now testable without Riverpod, and there is one
copy of them instead of twelve.

### Constructor duality

Notifiers that start async work on construction keep doing so when a test
injects the seam, and start it from `build()` when hosted by a provider. Each
such class carries a `_started` guard so the work runs at most once:

```dart
LeaderboardLayoutNotifier({StorageLoader? storage})
  : _storage = storage ?? (() => StorageService.instance),
    super(const []) {
  if (storage != null) _startLoad();   // direct instantiation
}

@override
List<LeaderboardLayoutItem> build() {
  _startLoad();                        // provider-hosted
  return super.build();
}
```

This is the same shape across ten notifiers; the alternative — teaching every
test to build a container — was rejected as more coupling for no extra
coverage.

## Consequences

- One idiom: `grep -r "extends StateNotifier" lib/` returns nothing.
- Overrides in tests are uniformly `overrideWith(() => ...)`; the old
  `(ref) =>` form no longer compiles, which is a useful forcing function.
- `BuildlessNotifier` is a compatibility shim, not an ideal base class. When
  Riverpod 3 lands, `Notifier` gains a disposal hook and the shim should be
  reduced to `value`/`publish` or removed together with the direct-construction
  tests.
- Direct instantiation is still allowed. It is a real capability (state machine
  tests) and not an accident, so it is documented on the base class rather than
  left implicit.

## Rejected alternatives

- **Rewrite the 77 call sites against `ProviderContainer`.** More code, more
  coupling, slower tests, no new assertions.
- **Keep `StateNotifier` for the "hard" notifiers.** That is how the split
  happened in the first place; mixed idioms age badly.
- **A global mutable override for the storage seam.** Tried for
  `SelfHostedKindNotifier`, then reverted: module-level mutable state makes
  tests order-dependent, which is worse than the constructor parameter.

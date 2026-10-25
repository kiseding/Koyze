import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Base for notifiers that must stay usable outside a `ProviderContainer`.
///
/// The migration from `StateNotifierProvider` to `NotifierProvider` (review
/// item #11) has one sharp edge: `StateNotifier` exposes `state` from the
/// moment it is constructed, while `Notifier.state` throws until `build()` has
/// run inside a container. Fifteen notifiers in this codebase are constructed
/// directly by tests — 73 call sites — precisely because that let a test drive
/// a state machine without booting Riverpod.
///
/// This class restores the old affordance without giving up `Notifier`:
///
/// * the canonical value lives in [_value], which exists from construction;
/// * [value] reads it synchronously, before or after `build()`;
/// * [publish] writes it and mirrors it into Riverpod's `state` when the
///   notifier is container-attached.
///
/// Subclasses call `super(initial)` and route every state change through
/// [publish] rather than assigning `state` directly, otherwise a direct
/// instantiation and a provider-hosted instance would diverge.
abstract class BuildlessNotifier<T> extends Notifier<T> {
  BuildlessNotifier(T initial) : _value = initial;

  T _value;
  bool _disposed = false;

  /// The current value, readable before [build] has run.
  T get value => _value;

  /// Mirrors `StateNotifier.mounted`: true until the provider is disposed, or
  /// until [dispose] is called on a directly-constructed instance.
  ///
  /// `Notifier` itself has no such flag, but several notifiers guard async
  /// continuations with `if (!mounted) return;` and a test may drive the same
  /// code path without a container.
  bool get mounted => !_disposed;

  @override
  T build() {
    ref.onDispose(_release);
    return _value;
  }

  /// Sets the value and mirrors it into Riverpod when attached.
  @protected
  void publish(T next) {
    // Publishing after teardown would reach into a disposed provider element.
    if (_disposed) return;
    final previous = _value;
    _value = next;
    try {
      state = next;
    } catch (_) {
      // Not attached to a `ProviderContainer` (direct instantiation).
    }
    _notifyListeners(previous, next);
  }

  final List<void Function(T value)> _listeners = [];

  /// Registers a listener fired on every effective [publish].
  ///
  /// `StateNotifier` offered this, and `position_rebuild_test` relies on it to
  /// assert that unchanged positions do not notify anyone. Under Riverpod the
  /// provider's own listeners do the work; this list stays empty in production.
  ///
  /// [fireImmediately] mirrors the `StateNotifier` signature: when true the
  /// listener is called once with the current value.
  void addListener(
    void Function(T value) listener, {
    bool fireImmediately = false,
  }) {
    _listeners.add(listener);
    if (fireImmediately) listener(_value);
  }

  void removeListener(void Function(T value) listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners(T previous, T next) {
    if (identical(previous, next) || _listeners.isEmpty) return;
    for (final listener in List.of(_listeners)) {
      listener(next);
    }
  }

  /// Called when the provider is disposed, and by [dispose] for a directly
  /// constructed instance. Subclasses override this instead of `dispose()`.
  @protected
  void onTeardown() {}

  /// Releases resources for a directly-constructed instance.
  ///
  /// Under Riverpod, disposal goes through `ref.onDispose` in [build]; this
  /// method exists so a test that never creates a container can still tear the
  /// notifier down deterministically.
  void dispose() {
    if (_disposed) return;
    _release();
  }

  void _release() {
    if (_disposed) return;
    _disposed = true;
    _listeners.clear();
    onTeardown();
  }
}

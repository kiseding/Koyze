import 'package:flutter_test/flutter_test.dart';
import 'support/source_text.dart';

/// Guards the release-build contract between Pigeon JNI plugins and R8.
///
/// `shared_preferences_android` 2.5+ (Pigeon JNI) does not talk to Java over a
/// MethodChannel anymore: the generated Dart bindings resolve Java members with
/// `JNI GetMethodID` using the *original* JVM name and descriptor. If R8 renames
/// a type that appears in such a descriptor (for example
/// `kotlin.coroutines.Continuation`), every lookup fails in release builds and
/// the app dies during bootstrap with:
///
///   NoSuchMethodError: no non-static method
///   "Lio/flutter/plugins/sharedpreferences/SharedPreferencesApiRegistrar;.getAll(
///      Ljava/lang/String;Ljava/util/List;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;"
///
/// `package:jni` additionally loads `kotlin.coroutines.Continuation`,
/// `kotlin.Result`, `kotlin.Result$Failure`, `kotlin.coroutines.intrinsics.*` and
/// `kotlin.Unit` by name, so those keep their members as well.
void main() {
  test('release proguard rules keep the Kotlin types used by Pigeon JNI', () {
    final rules = readSource('android/app/proguard-rules.pro');

    // Descriptor types must never be renamed.
    expect(rules, contains('-keepnames class kotlin.**'));

    // Types resolved reflectively by package:jni must still exist.
    expect(rules, contains('-keep class kotlin.coroutines.** { *; }'));
    expect(rules, contains('-keep class kotlin.Result { *; }'));
    expect(rules, contains(r'-keep class kotlin.Result$Failure { *; }'));
    expect(rules, contains('-keep class kotlin.Unit { *; }'));

    // Renaming would silently reintroduce the startup crash.
    expect(rules, isNot(contains('-dontobfuscate')));
  });
}

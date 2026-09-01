# Flutter plugin registration uses Class.forName / generated constructors.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.plugin.common.PluginRegistry$PluginRegistrantCallback { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }

# Host activity, media playback service, and JNI/native plugins.
-keep class com.koyze.app.** { *; }
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.ryanheise.audio_session.** { *; }
-keep class com.ryanheise.just_audio.** { *; }
-keep class io.abner.flutter_js.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class es.antonborri.home_widget.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.flutter_plugin_android_lifecycle.** { *; }
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod,Exception
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn javax.annotation.**
-dontwarn aQute.bnd.annotation.**
-dontwarn com.google.errorprone.annotations.**

-keep class **.R
-keep class **.R$* {
    <fields>;
}

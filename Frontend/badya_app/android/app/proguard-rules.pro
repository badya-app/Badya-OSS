# Flutter engine classes — keep everything used by the engine/embedding.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter engine embedder (generated plugin registrant).
-keep class io.flutter.embedding.** { *; }

# Firebase — accessed via reflection by the google-services tooling & SDKs.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# flutter_local_notifications — reflection-based scheduling (exact alarms, boot receivers).
-keep class com.dexterous.** { *; }

# permission_handler — uses native callback names.
-keep class com.permission_handler.** { *; }

# Keep generic signatures & attributes needed by reflection-based serialization.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses,EnclosingMethod

# Don't strip line numbers/timestamps from exceptions (useful for crash reports).
-keepattributes SourceFile,LineNumberTable

# Play Core (deferred components) — referenced by the Flutter engine loader at runtime.
# R8 fails on these unless kept: com.google.android.play.core.splitinstall / tasks.
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Google Play Billing Library
-keep class com.android.vending.billing.** { *; }
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**


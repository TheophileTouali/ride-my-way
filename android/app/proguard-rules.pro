# ---------- Stripe ----------
-keep class com.stripe.** { *; }
-dontwarn com.stripe.**

# Le module PushProvisioning peut être référencé mais pas packagé
-dontwarn com.stripe.android.pushProvisioning.**

# ---------- (Réfs transitoires) React Native Stripe ----------
-keep class com.reactnativestripesdk.** { *; }
-dontwarn com.reactnativestripesdk.**

# ---------- Google Wallet / Pay ----------
-keep class com.google.android.gms.wallet.** { *; }
-dontwarn com.google.android.gms.wallet.**

# ---------- OkHttp / Okio ----------
-dontwarn okhttp3.**
-dontwarn okio.**

# ---------- Kotlin metadata ----------
-keep class kotlin.Metadata { *; }

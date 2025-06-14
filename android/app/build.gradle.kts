plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // ✅ requis pour Firebase
}


android {
    namespace = "com.example.ride_my_way"
    compileSdk = flutter.compileSdkVersion
     ndkVersion = "27.0.1207973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.ride_my_way"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
dependencies {
    // Plateforme BoM Firebase : versions synchronisées
    implementation(platform("com.google.firebase:firebase-bom:33.15.0"))

    // Exemple avec Firebase Auth (tu peux ajouter Analytics, Firestore, etc.)
    implementation("com.google.firebase:firebase-auth")
    // implementation("com.google.firebase:firebase-analytics") // facultatif
}


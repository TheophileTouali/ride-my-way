pluginManagement {
    val p = java.util.Properties()
    file("local.properties").inputStream().use { p.load(it) }
    val flutterSdkPath = p.getProperty("flutter.sdk") ?: error("flutter.sdk not set in local.properties")

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // dépôt du plugin Flutter
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

// IMPORTANT : déclare aussi les dépôts pour résoudre les dépendances de tous les modules
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        // dépôt des artefacts Flutter (ex: engine, embedding)
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // OK avec SDK 35 / Kotlin 2.1.10 / Gradle 8.9+
    id("com.android.application") version "8.7.2" apply false
    id("com.android.library")     version "8.7.2" apply false
    id("org.jetbrains.kotlin.android") version "2.1.10" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")

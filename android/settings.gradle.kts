// android/settings.gradle.kts

pluginManagement {
    // Récupérer flutter.sdk depuis local.properties
    val properties = java.util.Properties()
    val localPropertiesFile = file("local.properties")

    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { properties.load(it) }
    } else {
        error("local.properties file not found. Please create it and set flutter.sdk=/chemin/vers/flutter")
    }

    val flutterSdkPath = properties.getProperty("flutter.sdk")
        ?: error("flutter.sdk not set in local.properties")

    // Inclure le build Flutter (plugin dev.flutter.flutter-plugin-loader)
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // Dépôt Flutter (facultatif mais pratique)
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

// IMPORTANT : déclarer les dépôts pour toutes les dépendances
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        // Dépôt des artefacts Flutter (engine, embedding, etc.)
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

plugins {
    // Plugin Flutter officiel (fourni par le includeBuild ci-dessus)
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // Plugins Android / Kotlin utilisés par ton projet
    id("com.android.application") version "8.11.1" apply false
    id("com.android.library")     version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.10" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

// Déclare le module app
include(":app")

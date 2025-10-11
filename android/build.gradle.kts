import org.gradle.api.tasks.Delete
import org.gradle.api.tasks.Copy

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

/**
 * Copie l'APK debug produit par :app vers build/app/outputs/flutter-apk/app-debug.apk
 * pour que Flutter le retrouve même si la copie interne échoue (chemins avec espaces, etc.).
 */
val debugApk = layout.projectDirectory
    .dir("app/build/outputs/apk/debug")
    .file("app-debug.apk")

val flutterOutDir = layout.projectDirectory
    .dir("../build/app/outputs/flutter-apk")

tasks.register<Copy>("copyDebugApkForFlutter") {
    from(debugApk)
    into(flutterOutDir)
    rename { "app-debug.apk" }
}

/**
 * Quand :app:assembleDebug termine, on déclenche la copie ci-dessus.
 */
project(":app") {
    tasks.named("assembleDebug").configure {
        finalizedBy(rootProject.tasks.named("copyDebugApkForFlutter"))
    }
}

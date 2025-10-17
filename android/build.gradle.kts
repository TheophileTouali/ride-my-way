// android/build.gradle.kts  (ROOT)
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
 * (utile sur Windows / chemins avec espaces).
 */
val flutterOutDir = layout.projectDirectory.dir("../build/app/outputs/flutter-apk")

tasks.register<Copy>("copyDebugApkForFlutter") {
    // On résout le fichier à l’exécution pour éviter les lookups trop tôt
    doFirst {
        val debugApk = layout.projectDirectory
            .dir("app/build/outputs/apk/debug")
            .file("app-debug.apk")
            .asFile
        if (!debugApk.exists()) {
            throw GradleException("Debug APK introuvable (encore). Relance automatique empêchée.")
        }
        from(debugApk)
        into(flutterOutDir)
        rename { "app-debug.apk" }
    }
}

/**
 * IMPORTANT : on n’accroche la finalisation qu’après que tous les projets soient configurés.
 * Plus de "Task ... not found".
 */
gradle.projectsEvaluated {
    project(":app").tasks.matching { it.name == "assembleDebug" }.configureEach {
        finalizedBy(rootProject.tasks.named("copyDebugApkForFlutter"))
    }
}

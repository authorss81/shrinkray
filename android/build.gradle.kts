allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Force every plugin module to compile against API 36.
//
// Each Gradle module carries its own `compileSdk`, so pinning only the app is not
// enough: `flutter_plugin_android_lifecycle` declares that its callers compile
// against 36, and Gradle's AAR metadata check fails `:file_picker`'s own
// `checkReleaseAarMetadata` before the app is even considered. The message names
// the plugin, not this app, which makes it look like an upstream bug.
//
// 36 is the highest API any current dependency needs. Lowering it will re-break
// the same check; raising it is the correct move when a future plugin asks.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            compileSdk = 36
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

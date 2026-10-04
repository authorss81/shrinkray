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
// `afterEvaluate` rather than `plugins.withId`: a `withId` callback runs the
// moment the plugin is applied, which is *before* the module's own build script
// reaches its `android { compileSdk = ... }` line. Setting the value there works
// and is then silently overwritten, which is what run 37200193147 showed -
// ":file_picker is currently compiled against android-34" despite the override.
//
// 36 is the highest API any current dependency needs. Lowering it re-breaks the
// same check; raising it is the move when a future plugin asks for more.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { extension ->
            when (extension) {
                is com.android.build.gradle.LibraryExtension -> extension.compileSdk = 36
                is com.android.build.gradle.AppExtension -> extension.compileSdk = 36
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

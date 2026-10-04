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
// Force every plugin module to compile against API 36.
//
// Each Gradle module carries its own `compileSdk`, so pinning only the app is not
// enough: `flutter_plugin_android_lifecycle` declares that its callers compile
// against 36, and Gradle's AAR metadata check fails `:file_picker`'s own
// `checkReleaseAarMetadata` before the app is even considered. The message names
// the plugin, not this app, which makes it look like an upstream bug.
//
// Two things that this has to get right, both learned the hard way:
//
// * `afterEvaluate`, not `plugins.withId`. A withId callback runs the moment the
//   plugin is applied, before the module's own script reaches its
//   `android { compileSdk 34 }` line - so the override is applied and then
//   silently overwritten. Run 37200193147 failed with byte-identical output to
//   the run before it, which is what made that look like the fix doing nothing.
//
// * Dynamic dispatch, not a named AGP class. This project is on AGP 9, where
//   `com.android.build.gradle.LibraryExtension` and `AppExtension` no longer
//   exist; naming either is a script compilation error (run 37200790505). Every
//   AGP version exposes `compileSdk` as a property on the `android` extension, so
//   setting it through the property map needs no class on the classpath at all.
//
// 36 is the highest API any current dependency needs. Lowering it re-breaks the
// same check; raising it is the move when a future plugin asks for more.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { android ->
            android.javaClass.methods
                .firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
                ?.invoke(android, 36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

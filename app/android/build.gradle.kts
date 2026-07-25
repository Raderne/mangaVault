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
// Flutter 3.44 defaults compileSdk to 34 and doesn't propagate the app override to
// plugin modules. file_picker's flutter_plugin_android_lifecycle needs API 36+, so
// force compileSdk 36 across every Android module (plugins included). Registered
// before evaluationDependsOn(":app") below so the afterEvaluate hook isn't added
// after a project has already been evaluated.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let { ext ->
            ext.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

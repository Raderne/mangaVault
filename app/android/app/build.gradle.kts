import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. `android/key.properties` is git-ignored and written by the
// release workflow from repo secrets (or by hand for a local release build).
//
// This matters more than usual for a sideloaded app: Android refuses to install
// an update whose signature differs from the installed build, so every release
// after 1.0.0 must be signed with the *same* keystore. Losing it means users
// have to uninstall and lose nothing but their patience — the vault is on the
// server — but it is still a one-way door. Back the keystore up off-machine.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "dev.mangavault.mangavault"
    // file_picker's transitive flutter_plugin_android_lifecycle requires API 36+;
    // pin explicitly rather than relying on the Flutter default (34).
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.mangavault.mangavault"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug key when no keystore is configured, so a
            // local `flutter run --release` still works. A build published to
            // GitHub Releases must never take that path — the workflow writes
            // key.properties first, and `verify-signing` below fails the build
            // if it somehow didn't.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Loud in the build log when a release build falls back to debug keys. CI
// additionally verifies the *signature* of the finished APK with apksigner —
// `gradlew` is not in the repo (Flutter's .gitignore), so a gradle-side guard
// task would be unreachable there.
gradle.taskGraph.whenReady {
    if (!hasReleaseKeystore && allTasks.any { it.name.contains("Release") }) {
        logger.warn(
            "WARNING: building release with DEBUG signing keys — " +
                "no android/key.properties found. Never publish this APK.",
        )
    }
}

dependencies {
    // MainActivity's installer channel uses androidx.core.content.FileProvider.
    // It arrives transitively via the Flutter embedding, but the updater breaks
    // in a non-obvious way if that ever changes — so depend on it directly.
    implementation("androidx.core:core-ktx:1.13.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

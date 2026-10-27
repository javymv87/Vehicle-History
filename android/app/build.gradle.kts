import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The fixed signing key (CLAUDE.md, "Signing"). `android/key.properties`
// points to a keystore kept outside the repository; both are git-ignored and
// never committed. When the file is absent (CI, a PC without the key) the
// build falls back to Gradle's default debug signing and still succeeds.
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) {
        keyPropertiesFile.inputStream().use { load(it) }
    }
}
val hasFixedKey = keyPropertiesFile.exists()

android {
    namespace = "io.github.javymv87.vehicle_history"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.javymv87.vehicle_history"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Mode 2 of the Drive link (flutter_appauth): the browser comes back
        // to the app through this scheme, the reversed id of the Android
        // OAuth client (Google's convention; "Enable custom URI scheme" is on
        // in that client's advanced settings). Must match driveRedirectUrl.
        manifestPlaceholders["appAuthRedirectScheme"] =
            "com.googleusercontent.apps.724262826629-83b26p1jk89l4bgjtpb0dqk41h77ebfd"
    }

    signingConfigs {
        if (hasFixedKey) {
            create("fixed") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        // Debug and release share the fixed key, so every build installs over
        // the previous one: a different signature would force an uninstall,
        // which deletes the data.
        val signing = signingConfigs.getByName(if (hasFixedKey) "fixed" else "debug")
        debug {
            signingConfig = signing
        }
        release {
            signingConfig = signing
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

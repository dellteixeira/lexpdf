import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.lexpdf.lexpdf_app"
    // Pin Android 16 / API 36 explicitly so release compatibility cannot drift
    // with a Flutter SDK default. CI also validates the targetSdk embedded in
    // the final APK, not just this Gradle configuration.
    compileSdk = 36
    // AndroidX PDF 1.0.0-beta01 publishes APIs against SDK Extension 19.
    // This changes the compile surface only; runtime capability is still
    // checked explicitly through SdkExtensions before opening the viewer.
    compileSdkExtension = 19
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.lexpdf.lexpdf_app"
        // AndroidX PDF beta currently requires Android 12 / API 31+.
        // The Galaxy Tab S6 Lite test device satisfies this requirement.
        minSdk = 31
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // CI hardening can still compile without private signing material.
            // Distribution builds provide android/key.properties at runtime and
            // therefore use the persistent release keystore configured above.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Google AndroidX PDF: Apache-2.0, no commercial SDK watermark.
    implementation("androidx.appcompat:appcompat:1.8.0")
    implementation("androidx.pdf:pdf-viewer-fragment:1.0.0-beta01")
    implementation("androidx.pdf:pdf-ink:1.0.0-beta01")

    // pdf-ink is built on AndroidX Ink 1.0.0. Keep these direct pins explicit
    // so stylus authoring remains deterministic across dependency resolution.
    implementation("androidx.ink:ink-authoring:1.0.0")
    implementation("androidx.ink:ink-brush:1.0.0")
    implementation("androidx.ink:ink-geometry:1.0.0")
    implementation("androidx.ink:ink-strokes:1.0.0")

    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.11.0")
}

flutter {
    source = "../.."
}

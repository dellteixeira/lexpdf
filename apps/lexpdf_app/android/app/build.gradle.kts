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
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.lexpdf.lexpdf_app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Apryse trial builds intentionally use an empty key. Production
        // builds inject PDFTRON_LICENSE_KEY through CI/local Gradle properties;
        // never commit a commercial key to this public repository.
        manifestPlaceholders["pdftronLicenseKey"] =
            providers.gradleProperty("PDFTRON_LICENSE_KEY").orElse("").get()

        multiDexEnabled = true
        vectorDrawables.useSupportLibrary = true
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
    // Apryse Android 12.1.0: the same native document SDK family that powers
    // Xodo. The viewer runs in a dedicated Android Activity/process so Flutter
    // and its PDFium stack do not compete for the renderer heap.
    implementation("com.pdftron:pdftron:12.1.0")
    implementation("com.pdftron:tools:12.1.0")
    implementation("androidx.multidex:multidex:2.0.1")
}

flutter {
    source = "../.."
}

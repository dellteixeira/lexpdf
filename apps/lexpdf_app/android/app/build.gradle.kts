import java.io.FileInputStream
import java.net.URI
import java.security.MessageDigest
import java.util.Properties
import java.util.zip.ZipInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val pdfJsVersion = "6.3.289"
val pdfJsArchiveSha256 = "98c5832ffe7af4edd59853476a478c0d4d4d76dd49c1701f4c86f7182725cdf9"
val pdfJsArchiveUrl =
    "https://github.com/mozilla/pdf.js/releases/download/v$pdfJsVersion/pdfjs-$pdfJsVersion-dist.zip"
val generatedPdfJsAssets = layout.buildDirectory.dir("generated/pdfjsAssets")

val preparePdfJsAssets by tasks.registering {
    outputs.dir(generatedPdfJsAssets)
    inputs.property("pdfJsVersion", pdfJsVersion)
    inputs.property("pdfJsArchiveSha256", pdfJsArchiveSha256)

    doLast {
        val outputRoot = generatedPdfJsAssets.get().asFile
        val marker = outputRoot.resolve(".pdfjs-$pdfJsVersion-$pdfJsArchiveSha256")
        if (marker.isFile) return@doLast

        outputRoot.deleteRecursively()
        outputRoot.mkdirs()

        val archive = temporaryDir.resolve("pdfjs-$pdfJsVersion-dist.zip")
        URI(pdfJsArchiveUrl).toURL().openStream().use { input ->
            archive.outputStream().use { output -> input.copyTo(output) }
        }

        val actualDigest = MessageDigest.getInstance("SHA-256")
            .digest(archive.readBytes())
            .joinToString("") { "%02x".format(it) }
        check(actualDigest == pdfJsArchiveSha256) {
            "PDF.js archive checksum mismatch: expected $pdfJsArchiveSha256, got $actualDigest"
        }

        val requiredFiles = setOf(
            "build/pdf.mjs",
            "build/pdf.worker.mjs",
        )
        val extractedRequired = mutableSetOf<String>()

        ZipInputStream(archive.inputStream().buffered()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (entry.isDirectory) continue
                val normalized = entry.name.replace('\\', '/')
                val relative = when {
                    normalized.endsWith("/build/pdf.mjs") ||
                        normalized == "build/pdf.mjs" -> "build/pdf.mjs"
                    normalized.endsWith("/build/pdf.worker.mjs") ||
                        normalized == "build/pdf.worker.mjs" -> "build/pdf.worker.mjs"
                    normalized.contains("/standard_fonts/") ->
                        "standard_fonts/" + normalized.substringAfterLast("/standard_fonts/")
                    normalized.startsWith("standard_fonts/") -> normalized
                    normalized.contains("/wasm/") ->
                        "wasm/" + normalized.substringAfterLast("/wasm/")
                    normalized.startsWith("wasm/") -> normalized
                    else -> null
                } ?: continue

                val destination = outputRoot.resolve("pdfjs/$relative")
                destination.parentFile.mkdirs()
                destination.outputStream().use { output -> zip.copyTo(output) }
                if (relative in requiredFiles) extractedRequired += relative
            }
        }

        check(extractedRequired == requiredFiles) {
            "PDF.js distribution is missing required runtime files: " +
                (requiredFiles - extractedRequired).joinToString()
        }
        marker.writeText("pdfjs=$pdfJsVersion\nsha256=$pdfJsArchiveSha256\n")
    }
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

    sourceSets.getByName("main").assets.srcDir(generatedPdfJsAssets.get().asFile)

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
    // Stable Google Ink stack. PDF rendering itself uses the platform
    // android.graphics.pdf.PdfRenderer (API 21+) instead of any viewer SDK.
    implementation("androidx.appcompat:appcompat:1.8.0")
    implementation("androidx.ink:ink-authoring:1.0.0")
    implementation("androidx.ink:ink-brush:1.0.0")
    implementation("androidx.ink:ink-rendering:1.0.0")
    implementation("androidx.ink:ink-strokes:1.0.0")
    implementation("androidx.ink:ink-storage:1.0.0")
}

tasks.named("preBuild").configure {
    dependsOn(preparePdfJsAssets)
}

flutter {
    source = "../.."
}

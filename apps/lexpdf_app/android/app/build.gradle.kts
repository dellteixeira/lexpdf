import java.io.FileInputStream
import java.net.URI
import java.security.MessageDigest
import java.util.Base64
import java.util.Properties
import java.util.zip.ZipInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val pdfJsVersion = "6.3.289"
val pdfJsNpmIntegritySha512 =
    "ZHjSVpDa3D6izMq8/04lvkhkATUmL9px6ChPaXc1k6nU2Mrhlg1/7F0bdUqCwUjw3NsPTfPZsMDUU6ZIcRaeQw=="
val pdfJsPackageUrl =
    "https://registry.npmjs.org/pdfjs-dist/-/pdfjs-dist-$pdfJsVersion.tgz"
val generatedPdfJsAssets = layout.buildDirectory.dir("generated/pdfjsAssets")

val preparePdfJsAssets by tasks.registering {
    outputs.dir(generatedPdfJsAssets)
    inputs.property("pdfJsVersion", pdfJsVersion)
    inputs.property("pdfJsNpmIntegritySha512", pdfJsNpmIntegritySha512)

    doLast {
        val outputRoot = generatedPdfJsAssets.get().asFile
        val marker =
            outputRoot.resolve(".pdfjs-$pdfJsVersion-${pdfJsNpmIntegritySha512.hashCode()}")
        if (marker.isFile) return@doLast

        outputRoot.deleteRecursively()
        outputRoot.mkdirs()

        val archive = temporaryDir.resolve("pdfjs-dist-$pdfJsVersion.tgz")
        URI(pdfJsPackageUrl).toURL().openStream().use { input ->
            archive.outputStream().use { output -> input.copyTo(output) }
        }

        val actualIntegrity =
            Base64.getEncoder().encodeToString(
                MessageDigest.getInstance("SHA-512").digest(archive.readBytes()),
            )
        check(actualIntegrity == pdfJsNpmIntegritySha512) {
            "PDF.js npm package integrity mismatch: expected $pdfJsNpmIntegritySha512, got $actualIntegrity"
        }

        val extractedRoot = temporaryDir.resolve("pdfjs-npm")
        extractedRoot.deleteRecursively()
        extractedRoot.mkdirs()
        copy {
            from(tarTree(resources.gzip(archive)))
            into(extractedRoot)
        }

        val packageRoot = extractedRoot.resolve("package")
        val requiredFiles =
            listOf(
                packageRoot.resolve("build/pdf.min.mjs"),
                packageRoot.resolve("build/pdf.worker.min.mjs"),
            )
        check(requiredFiles.all { it.isFile }) {
            "PDF.js npm package is missing the minified runtime modules."
        }

        val assetRoot = outputRoot.resolve("pdfjs")
        assetRoot.mkdirs()
        requiredFiles.forEach { source ->
            val destination = assetRoot.resolve("build/${source.name}")
            destination.parentFile.mkdirs()
            source.copyTo(destination, overwrite = true)
        }

        for (directory in listOf("standard_fonts", "wasm")) {
            val sourceDir = packageRoot.resolve(directory)
            check(sourceDir.isDirectory) {
                "PDF.js npm package is missing required directory: $directory"
            }
            sourceDir.copyRecursively(
                assetRoot.resolve(directory),
                overwrite = true,
            )
        }

        marker.writeText(
            "pdfjs=$pdfJsVersion\n" +
                "npm-sha512=$pdfJsNpmIntegritySha512\n" +
                "runtime=minified\n",
        )
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

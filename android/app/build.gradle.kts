import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (DC-005/SEC-003/RD-001). `key.properties` is gitignored —
// generated locally, never committed. Deliberately fails the build (rather
// than silently falling back to debug signing, the exact defect these
// findings describe) if it's missing for a release build.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystoreProperties = keystorePropertiesFile.exists()
if (hasKeystoreProperties) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.niswah.niswah"
    // flutter.compileSdkVersion (36, bundled with Flutter 3.47.0) is one
    // version behind what flutter_secure_storage 11.x requires (37) —
    // pinned explicitly rather than left to the Flutter-derived default,
    // which silently breaks every release build (RD-009 emergency-build
    // drill, 2026-09-06) the moment that dependency is present.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (uses java.time APIs on
        // API levels below 26) — without this, `flutter build apk --release`
        // fails at `:app:checkReleaseAarMetadata` (cross-referenced in
        // 00_09 §13; this closes that gap).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.niswah.niswah"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystoreProperties) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // No more silent debug-signing fallback (DC-005/SEC-003): a
            // release build without `key.properties` now fails loudly at
            // configuration time instead of producing a store-unpublishable,
            // debug-signed artifact that looks like a real release build.
            signingConfig = if (hasKeystoreProperties) {
                signingConfigs.getByName("release")
            } else {
                throw GradleException(
                    "android/key.properties not found — a release build requires " +
                    "a real signing keystore (DC-005/SEC-003). See " +
                    "production-readiness-results/release-deployment/ for the " +
                    "keystore-generation and custody procedure. Debug-signing a " +
                    "release build is exactly the defect this check prevents."
                )
            }
        }
    }
}

dependencies {
    // Required by flutter_local_notifications alongside
    // isCoreLibraryDesugaringEnabled above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

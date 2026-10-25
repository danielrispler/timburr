import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: env vars (CI) win over android/key.properties (local). Neither is committed.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(env: String, prop: String): String? = System.getenv(env) ?: keyProps.getProperty(prop)
val releaseStoreFile = signingValue("TIMBURR_KEYSTORE_PATH", "storeFile")

android {
    namespace = "io.github.danielrispler.timburr"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications needs java.time on older Androids.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.danielrispler.timburr"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStoreFile != null) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile)
                storePassword = signingValue("TIMBURR_KEYSTORE_PASSWORD", "storePassword")
                keyAlias = signingValue("TIMBURR_KEY_ALIAS", "keyAlias")
                keyPassword = signingValue("TIMBURR_KEY_PASSWORD", "keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // No keystore configured: fall back to debug keys so `flutter run --release` still works.
            // On CI that would publish a debug-signed APK, so fail instead.
            signingConfig = signingConfigs.findByName("release")
                ?: if (System.getenv("CI").isNullOrEmpty()) signingConfigs.getByName("debug")
                else throw GradleException("CI release build has no keystore: set TIMBURR_KEYSTORE_PATH")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

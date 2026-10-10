import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = rootProject.file("key.properties")
val signingValues = Properties().apply { if (signingFile.exists()) signingFile.inputStream().use { load(it) } }
val pushFile = rootProject.file("push.properties")
val pushValues = Properties().apply { if (pushFile.exists()) pushFile.inputStream().use { load(it) } }

android {
    namespace = "com.miaoban.miaoban"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    buildFeatures { buildConfig = true }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Provisional package; confirm before signing the first release.
        applicationId = "com.miaoban.miaoban"
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
        for (key in listOf("FCM_PROJECT_ID", "FCM_APP_ID", "FCM_API_KEY", "FCM_SENDER_ID")) {
            buildConfigField("String", key, "\"" + pushValues.getProperty(key, "").replace("\\", "\\\\").replace("\"", "\\\"") + "\"")
        }
    }

    signingConfigs {
        if (signingFile.exists()) create("userRelease") {
            keyAlias = signingValues.getProperty("keyAlias") ?: error("Missing keyAlias")
            keyPassword = signingValues.getProperty("keyPassword") ?: error("Missing keyPassword")
            storeFile = file(signingValues.getProperty("storeFile") ?: error("Missing storeFile"))
            storePassword = signingValues.getProperty("storePassword") ?: error("Missing storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = if (signingFile.exists()) signingConfigs.getByName("userRelease") else null
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation(platform("com.google.firebase:firebase-bom:35.0.0"))
    implementation("com.google.firebase:firebase-messaging")
}

flutter {
    source = "../.."
}

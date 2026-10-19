// Sill for Android: the Mac's windows on an Android phone or tablet, over the shared core
// (clients/core). Platform APIs only: MediaCodec for HEVC (hardware on every Android device that
// decodes HEVC), a SurfaceView, the Android Keystore for the device key at rest. No AndroidX.
// API 29 and later: TLS 1.3 and ALPN in the platform's TLS.
//   gradle :android:assembleDebug        build/outputs/apk/debug/android-debug.apk
//   gradle :android:lintDebug            Android lint
//   gradle :android:testDebugUnitTest    the pure helpers' tests (dp, insets, the fold's mapping, Back, reorder)
plugins {
    id("com.android.application")
    kotlin("android")
}

android {
    namespace = "me.saffer.sill.android"
    compileSdk = 35
    defaultConfig {
        applicationId = "me.saffer.sill"
        minSdk = 29
        targetSdk = 35
        versionCode = 1
        versionName = "0.6.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    lint {
        abortOnError = true
        warningsAsErrors = false
        checkDependencies = true
    }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    implementation(project(":core"))
    // The pure helpers around core's layouts (src/test: no android.* in them), on the JVM.
    testImplementation(kotlin("test-junit"))
}

// Sill's clients that are not Swift (docs/clients-plan.md): the shared core, the Windows client
// (a JVM desktop app) and the Android app. The Mac host and the iPhone and iPad app are
// Package.swift and iOSClient/, untouched by this build.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "sill-clients"
include(":core", ":swing-ui", ":desktop")
// The Android app needs the Android SDK: built only where one is configured (ANDROID_HOME,
// ANDROID_SDK_ROOT or local.properties' sdk.dir), so the core and the Windows client build anywhere.
val androidSdk = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
    ?: file("local.properties").takeIf { it.exists() }?.readLines()
        ?.firstOrNull { it.startsWith("sdk.dir=") }?.substringAfter("=")
if (androidSdk != null && file(androidSdk).isDirectory) include(":android")

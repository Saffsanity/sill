// Sill's apps that are not Swift (docs/clients-plan.md): the shared core, the Windows client (a JVM
// desktop app), the Android app, and the Windows and Linux hosts (host-core, the door and the
// session for any host; host, the platforms). The Mac host and the iPhone and iPad app are
// Package.swift and iOSClient/, untouched by this build.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
// Java toolchains on demand: the hosts need JDK 25 (the foreign function API, for Win32 and Xlib);
// Gradle fetches one where none is installed, on a developer's machine and on CI alike.
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "sill-clients"
include(":core", ":swing-ui", ":desktop", ":host-core", ":host")
// The Android app needs the Android SDK: built only where one is configured (ANDROID_HOME,
// ANDROID_SDK_ROOT or local.properties' sdk.dir), so the core and the Windows client build anywhere.
val androidSdk = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
    ?: file("local.properties").takeIf { it.exists() }?.readLines()
        ?.firstOrNull { it.startsWith("sdk.dir=") }?.substringAfter("=")
if (androidSdk != null && file(androidSdk).isDirectory) include(":android")

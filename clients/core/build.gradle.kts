// The core every non-Swift client shares, as Sources/StreamProtocol is shared by the Mac and the
// iPhone and iPad app: the wire, pairing, identity, TLS with pinned keys, discovery and the session.
// Plain Kotlin on the JVM with no dependency but the standard library, so it runs unchanged on
// Windows (the desktop client) and Android (API 29 and later: TLS 1.3 and ALPN).
plugins {
    kotlin("jvm")
    `java-test-fixtures`
}

// Built with whatever JDK runs Gradle (17 or later), for a Java 17 runtime: what Android's D8 and a
// jpackage'd Windows runtime both take.
java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    // The model Mac (src/testFixtures) is shared with the desktop client's tests.
    testFixturesImplementation(kotlin("stdlib"))
    testImplementation(kotlin("test-junit5"))
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
    // The wire test writes this core's encodings here for clients/wire-vectors/generate.sh --check.
    systemProperty("sill.wireOut", layout.buildDirectory.file("kotlin-wire.json").get().asFile.path)
    testLogging { events("failed"); showStandardStreams = true; exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL }
}

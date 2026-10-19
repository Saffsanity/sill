// What every Sill host that is not the Mac does the Mac's way (docs/clients-plan.md, "Hosts"):
// the TLS door with pairing, the trust list, the Bonjour responder, the sessions with their pacing,
// the catalog, kinds 16 and 18, and the Mac's input made the PC's. Pure Kotlin over the core; the
// platform (capture, encoding, windows, input) is an interface the host module implements.
plugins {
    kotlin("jvm")
    `java-test-fixtures`
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    api(project(":core"))
    testImplementation(testFixtures(project(":core")))
    testImplementation(kotlin("test-junit5"))
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
    testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL; showStandardStreams = true }
}

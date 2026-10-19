// The Swing side of the shared design layer (docs/ui-parity.md): the iOS app's tokens
// (core/ui/Tokens.kt) as AWT colours and fonts, its glyphs, its curves on a Swing timer, and the
// dark scrollbars, for the Windows client and the Windows and Linux hosts. No dependency but the
// core and the JDK.
plugins {
    kotlin("jvm")
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
    testImplementation(kotlin("test-junit5"))
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
    systemProperty("java.awt.headless", "true")
}

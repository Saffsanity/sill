// Sill for Windows: a JVM desktop app over the shared core (clients/core), the Mac's windows on a
// PC. Swing for the windows (in the JDK), FFmpeg for HEVC (the one library: Windows has no HEVC
// decoder of its own without the Store's paid extension; docs/BRIEF.md has the decision), Direct3D
// 11 for it when the GPU has one. `jpackage` makes the Windows installer with its own Java runtime.
//   gradle :desktop:run                 run it (any OS with a display; Windows is the target)
//   gradle :desktop:test                the decoder against real HEVC, input and the stream end to end
//   gradle :desktop:jpackage            on Windows: build/jpackage/Sill-<version>.msi (needs WiX 3 on PATH)
plugins {
    kotlin("jvm")
    application
}

val sillVersion = "0.6.0"
version = sillVersion

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

val ffmpegVersion = "7.1.1-1.5.12"
val javacppVersion = "1.5.12"
// The native builds the app carries: Windows x64 (the product) and Linux x64 (this repository's
// tests and CI). Another platform: add its classifier here.
val nativePlatforms = listOf("windows-x86_64", "linux-x86_64")

dependencies {
    implementation(project(":core"))
    implementation(project(":swing-ui"))
    implementation("org.bytedeco:javacpp:$javacppVersion")
    implementation("org.bytedeco:ffmpeg:$ffmpegVersion")
    for (p in nativePlatforms) {
        runtimeOnly("org.bytedeco:javacpp:$javacppVersion:$p")
        runtimeOnly("org.bytedeco:ffmpeg:$ffmpegVersion:$p")
    }
    testImplementation(testFixtures(project(":core")))
    testImplementation(kotlin("test-junit5"))
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

application {
    mainClass.set("me.saffer.sill.desktop.MainKt")
    applicationName = "Sill"
}

tasks.jar {
    manifest { attributes("Implementation-Title" to "Sill", "Implementation-Version" to sillVersion) }
}

tasks.test {
    useJUnitPlatform { excludeTags("ui") }
    systemProperty("java.awt.headless", "true")
    testLogging { events("failed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL; showStandardStreams = true }
}

// The real windows on a display (Xvfb on Linux: `xvfb-run -a gradle :desktop:uiTest`): the connect
// window, a session with the model Mac, clicks and keys through java.awt.Robot, and screenshots in
// build/ui-shots/.
tasks.register<Test>("uiTest") {
    group = "verification"
    testClassesDirs = sourceSets.test.get().output.classesDirs
    classpath = sourceSets.test.get().runtimeClasspath
    useJUnitPlatform { includeTags("ui") }
    systemProperty("sill.shots", layout.buildDirectory.dir("ui-shots").get().asFile.path)
    testLogging { events("failed", "passed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL; showStandardStreams = true }
    finalizedBy("uiTestHiDpi")
}

// The same windows at twice the pixels (a 200 % display): the logical rectangles must not move.
tasks.register<Test>("uiTestHiDpi") {
    group = "verification"
    testClassesDirs = sourceSets.test.get().output.classesDirs
    classpath = sourceSets.test.get().runtimeClasspath
    useJUnitPlatform { includeTags("ui") }
    systemProperty("sill.shots", layout.buildDirectory.dir("ui-shots").get().asFile.path)
    jvmArgs("-Dsun.java2d.uiScale=2")
    testLogging { events("failed", "passed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL; showStandardStreams = true }
}

// The Windows installer: the app's jars and a trimmed Java runtime (jlink, through jpackage), per
// user, with a Start menu entry. Run on Windows with the JDK's jpackage and WiX 3 on PATH.
val packagingWindows = System.getProperty("os.name").lowercase().startsWith("windows")
// The app's jars without the other platform's native builds (FFmpeg's are most of the size).
val jpackageInput = tasks.register<Sync>("jpackageInput") {
    from(tasks.installDist.map { layout.buildDirectory.dir("install/Sill/lib") })
    exclude(if (packagingWindows) "*-linux-x86_64.jar" else "*-windows-x86_64.jar")
    into(layout.buildDirectory.dir("jpackage-input"))
    dependsOn(tasks.installDist)
}

tasks.register<Exec>("jpackage") {
    group = "distribution"
    dependsOn(jpackageInput)
    val lib = layout.buildDirectory.dir("jpackage-input")
    val out = layout.buildDirectory.dir("jpackage")
    val windows = packagingWindows
    val jpackage = File(System.getProperty("java.home"), "bin/" + if (windows) "jpackage.exe" else "jpackage")
    doFirst { out.get().asFile.deleteRecursively() }
    commandLine(listOf(jpackage.path,
        // -Psill.jpackageType=app-image skips the installer (no WiX needed): CI checks the image.
        "--type", (project.findProperty("sill.jpackageType") as String?) ?: if (windows) "msi" else "app-image",
        "--name", "Sill", "--app-version", sillVersion, "--vendor", "Sill",
        "--description", "The Mac's windows on this PC",
        "--input", lib.get().asFile.path, "--main-jar", "desktop-$sillVersion.jar",
        "--main-class", "me.saffer.sill.desktop.MainKt",
        "--dest", out.get().asFile.path,
        "--add-modules", "java.desktop,java.logging,java.naming,jdk.crypto.ec,jdk.crypto.cryptoki,jdk.unsupported",
        "--java-options", "-Dsun.java2d.d3d=true",
    ) + when {
        // The installer: per user, a Start menu entry and a shortcut; upgrades replace the install.
        windows && project.findProperty("sill.jpackageType") == null -> listOf("--win-per-user-install", "--win-menu", "--win-shortcut",
            "--win-dir-chooser", "--win-upgrade-uuid", "6f0c2f2e-6a4b-4e8e-9d6a-5c1a8f3b2d71")
        // CI's app image: a console launcher, so `Sill.exe --self-test` prints and returns its result.
        windows -> listOf("--win-console")
        else -> emptyList()
    })
}

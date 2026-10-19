// Sill for Windows and Linux as hosts (docs/clients-plan.md, "Hosts"): the computer's windows on
// the iPhone, iPad, Android and Windows clients, as the Mac's are. The door, pairing and sessions
// are host-core's; this module is the platforms: capture and HEVC with FFmpeg (x11grab or gdigrab;
// NVENC, Quick Sync, VAAPI, Media Foundation or x265), windows and input through the operating
// system's own libraries with the JDK's foreign function API (Xlib and XTest on Linux, user32 on
// Windows), the UI Sill.app has (the tray's status menu, Settings, the pairing window with its QR
// code and the log, in host/ui, on swing-ui) and a headless command line.
//   gradle :host:run --args="--headless"      run a host (a display: X11 on Linux)
//   gradle :host:test                         the encoder, the X11 platform, the host end to end, its UI (with Xvfb)
//   gradle :host:jpackage                     on Windows: an MSI (WiX 3); elsewhere an app image
plugins {
    kotlin("jvm")
    application
}

val sillVersion = "0.6.0"
version = sillVersion

// The foreign function API (java.lang.foreign) is final from Java 22; 25 is the LTS.
// Built and run with 25, as bytecode for 22 (the newest Kotlin 2.1 writes).
java { toolchain { languageVersion.set(JavaLanguageVersion.of(25)) } }
kotlin {
    jvmToolchain(25)
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_22) }
}
tasks.withType<JavaCompile>().configureEach { sourceCompatibility = "22"; targetCompatibility = "22" }

val ffmpegVersion = "7.1.1-1.5.12"
val javacppVersion = "1.5.12"
// FFmpeg's GPL build: the only one with a software HEVC encoder (x265), for a PC without a hardware
// one. Distributed, the host is therefore GPLv3 as a whole (the source stays Apache-2.0); BRIEF.md.
val nativePlatforms = listOf("windows-x86_64", "linux-x86_64")
// JavaCPP loads the natives whose classifier ends in this extension: the GPL build's.
val gplNatives = "-Dorg.bytedeco.javacpp.platform.extension=-gpl"

dependencies {
    implementation(project(":host-core"))
    implementation(project(":swing-ui"))            // the clients' Swing primitives (fonts, glyphs, curves)
    implementation("org.bytedeco:javacpp:$javacppVersion")
    implementation("org.bytedeco:ffmpeg:$ffmpegVersion")
    for (p in nativePlatforms) {
        runtimeOnly("org.bytedeco:javacpp:$javacppVersion:$p")
        runtimeOnly("org.bytedeco:ffmpeg:$ffmpegVersion:$p-gpl")
    }
    testImplementation(testFixtures(project(":core")))
    testImplementation(project(":desktop"))          // the Windows client's decoder, to check the host's pictures
    testImplementation(kotlin("test-junit5"))
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

application {
    mainClass.set("me.saffer.sill.host.HostMainKt")
    applicationName = "SillHost"
    applicationDefaultJvmArgs = listOf("--enable-native-access=ALL-UNNAMED", gplNatives)
}

tasks.jar { manifest { attributes("Implementation-Title" to "Sill Host", "Implementation-Version" to sillVersion) } }

tasks.test {
    useJUnitPlatform()
    jvmArgs("--enable-native-access=ALL-UNNAMED", gplNatives)
    // The X11 tests need a display: run under xvfb-run (CI does); without one they skip.
    environment("SILL_TEST_DISPLAY", System.getenv("DISPLAY") ?: "")
    testLogging { events("failed", "passed"); exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL; showStandardStreams = true }
}

val packagingWindows = System.getProperty("os.name").lowercase().startsWith("windows")
val jpackageInput = tasks.register<Sync>("jpackageInput") {
    from(layout.buildDirectory.dir("install/SillHost/lib"))
    exclude(if (packagingWindows) "*-linux-x86_64*.jar" else "*-windows-x86_64*.jar")
    into(layout.buildDirectory.dir("jpackage-input"))
    dependsOn(tasks.installDist)
}

tasks.register<Exec>("jpackage") {
    group = "distribution"
    dependsOn(jpackageInput)
    val out = layout.buildDirectory.dir("jpackage")
    val launcher = javaToolchains.launcherFor { languageVersion.set(JavaLanguageVersion.of(25)) }
    doFirst { out.get().asFile.deleteRecursively() }
    val type = (project.findProperty("sill.jpackageType") as String?) ?: if (packagingWindows) "msi" else "app-image"
    commandLine(listOf(launcher.get().metadata.installationPath.file(if (packagingWindows) "bin/jpackage.exe" else "bin/jpackage").asFile.path,
        "--type", type, "--name", "SillHost", "--app-version", sillVersion, "--vendor", "Sill",
        "--description", "This computer's windows on your other devices",
        "--input", layout.buildDirectory.dir("jpackage-input").get().asFile.path, "--main-jar", "host-$sillVersion.jar",
        "--main-class", "me.saffer.sill.host.HostMainKt", "--dest", out.get().asFile.path,
        "--add-modules", "java.desktop,java.logging,java.management,jdk.unsupported",
        "--java-options", "--enable-native-access=ALL-UNNAMED", "--java-options", gplNatives,
    ) + when {
        packagingWindows && type == "msi" -> listOf("--win-per-user-install", "--win-menu", "--win-shortcut", "--win-upgrade-uuid", "0b6d3a8e-2f61-4c7e-9a43-1d2b5e7f9c10")
        packagingWindows -> listOf("--win-console")
        else -> emptyList()
    })
}

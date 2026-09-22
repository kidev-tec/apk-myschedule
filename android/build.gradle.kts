allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// share_plus 12 fixa kotlin-gradle-plugin:2.2.0 no buildscript e o CI não
// resolve esse artefato. Alinha com o Kotlin do app (2.2.20).
subprojects {
    buildscript {
        repositories {
            google()
            mavenCentral()
            gradlePluginPortal()
        }
        configurations.classpath {
            resolutionStrategy.eachDependency {
                if (requested.group == "org.jetbrains.kotlin" &&
                    requested.name == "kotlin-gradle-plugin" &&
                    requested.version == "2.2.0"
                ) {
                    useVersion("2.2.20")
                }
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

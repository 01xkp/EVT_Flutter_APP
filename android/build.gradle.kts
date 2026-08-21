allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val configuredBuildDir = providers.gradleProperty("evtBuildDir").orNull
val newBuildDir: Directory =
    if (configuredBuildDir == null) {
        rootProject.layout.buildDirectory
            .dir("../../build")
            .get()
    } else {
        rootProject.layout.dir(providers.provider { rootProject.file(configuredBuildDir) }).get()
    }
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    if (name == "reactive_ble_mobile") {
        pluginManager.withPlugin("com.android.library") {
            // flutter_reactive_ble 5.5.0 still declares API 33, below its AndroidX requirements.
            extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension> {
                finalizeDsl { extension ->
                    extension.compileSdk = 37
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

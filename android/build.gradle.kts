allprojects {
    repositories {
        google()
        mavenCentral()
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
// flutter_blue_plus 1.x compiles against android-33, below what its AndroidX dependencies need.
// Version 2.x conflicts with connectivity_plus, so raise old plugins' compileSdk instead.
subprojects {
    if (name != "app") {
        afterEvaluate {
            extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.let {
                if ((it.compileSdk ?: 0) < 34) it.compileSdk = 36
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

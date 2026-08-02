import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La clé de signature de release vit hors du dépôt : `android/key.properties`
// (ignoré par git, comme le .jks lui-même). Format et procédure de création :
// HOWTO.md, « Construire un APK à distribuer ».
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

// Un APK de release signé avec la clé de debug s'installe très bien — et se
// distribue tout aussi bien. Le prix se paie à la mise à jour suivante : Android
// refuse une mise à jour signée d'une autre clé que la précédente. Il faut alors
// désinstaller, donc perdre les capteurs appairés, la session du site et les
// sorties enregistrées mais pas encore exportées. D'où l'arrêt franc ici plutôt
// qu'un repli silencieux sur la clé de debug : le jour où la clé manque, on veut
// le savoir avant d'avoir diffusé le fichier, pas après.
val buildsRelease = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
if (buildsRelease && !hasReleaseKey) {
    throw GradleException(
        "Build de release sans clé de signature : android/key.properties est introuvable. " +
            "Voir HOWTO.md, section « Construire un APK à distribuer »."
    )
}

android {
    namespace = "ch.logicraft.sports.companion"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Préfixe du site, suffixe qui distingue du TWA `ch.logicraft.sports`
        // (l'emballage PWA du repo Rails) : les deux peuvent coexister sur un
        // même téléphone. Ne plus jamais en changer une fois l'appli diffusée —
        // pour Android, un autre applicationId est une autre application : deux
        // icônes, aucune reprise des données.
        applicationId = "ch.logicraft.sports.companion"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Vient du `+N` de `version:` dans pubspec.yaml. À incrémenter à chaque
        // APK diffusé : Android refuse d'installer par-dessus un versionCode
        // supérieur ou égal, et échoue par un « application non installée » qui
        // ne dit pas pourquoi.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else null
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

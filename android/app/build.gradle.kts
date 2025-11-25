import java.io.FileInputStream
import java.util.Properties

// ---------------------------------------------------------------------
// 💡 1. API Key 로딩 로직 (Kotlin DSL) - 파일 최상단에서 한 번만 실행
// ---------------------------------------------------------------------
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")

if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { inputStream ->
        localProperties.load(inputStream)
    }
}
// 💡 [수정] local.properties 파일에서 "google.mapsApiKey" 값을 읽어오도록 변경합니다.
val mapApiKey: String? = localProperties.getProperty("google.mapsApiKey")

// ---------------------------------------------------------------------

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.sports_app1"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.sports_app1"

        // 지도 SDK 요구사항에 따라 minSdkVersion 21 이상 확인
        minSdk = flutter.minSdkVersion

        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 💡 2. Manifest Placeholders 설정 (읽어온 API 키 값을 Manifest에 주입)
        // Manifest가 요구하는 "MAP_API_KEY" 변수에, local.properties에서 읽어온 실제 키를 주입합니다.
        manifestPlaceholders["MAP_API_KEY"] = mapApiKey ?: ""
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.10.0")

    // 💡 Google Maps SDK 종속성 (버전 최신화 권장: 18.2.0 유지)
    implementation("com.google.android.gms:play-services-maps:18.2.0")
}
import java.io.FileInputStream
import java.util.Properties

// ---------------------------------------------------------------------
// 💡 1. API Key 로딩 (local.properties)
// ---------------------------------------------------------------------
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")

if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { inputStream ->
        localProperties.load(inputStream)
    }
}
val mapApiKey: String? = localProperties.getProperty("google.mapsApiKey")

// ---------------------------------------------------------------------
// 💡 2. [추가됨] 앱 서명 키 로딩 (key.properties)
// ---------------------------------------------------------------------
val keystoreProperties = Properties()
// key.properties 파일이 android 폴더 바로 아래에 있어야 합니다.
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { inputStream ->
        keystoreProperties.load(inputStream)
    }
}

plugins {
    id("com.android.application")
    id("kotlin-android")
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
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Manifest에 API 키 주입
        manifestPlaceholders["MAP_API_KEY"] = mapApiKey ?: ""
    }

    // 💡 3. [추가됨] 서명 설정 (Signing Configs)
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            // 💡 4. [수정됨] 위에서 만든 "release" 서명 설정을 적용
            signingConfig = signingConfigs.getByName("release")

            // 코드 난독화/축소 설정 (기본값 false, 필요시 true 변경)
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.10.0")
    implementation("com.google.android.gms:play-services-maps:18.2.0")
}
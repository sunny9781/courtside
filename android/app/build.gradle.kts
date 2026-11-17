plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Build number and version come from the build machine (GitHub), so every published build is newer.
val buildNumber = (project.findProperty("buildNumber") as String?)?.toIntOrNull() ?: 1
val appVersion = (project.findProperty("appVersion") as String?) ?: "1.0"

android {
    namespace = "ca.sunny9781.courtside"
    compileSdk = 35

    defaultConfig {
        applicationId = "ca.sunny9781.courtside"
        minSdk = 26
        targetSdk = 35
        versionCode = buildNumber
        versionName = appVersion
    }

    // The signing key lives in GitHub secrets (never in the code). Updates only install over the top when every
    // build is signed with the same key.
    val keystorePath = System.getenv("COURTSIDE_KEYSTORE")
    signingConfigs {
        create("release") {
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storePassword = System.getenv("COURTSIDE_KEYSTORE_PASSWORD")
                keyAlias = "courtside"
                keyPassword = System.getenv("COURTSIDE_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Shrinks the app (unused code and icons removed) so updates need less free space on the TV.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (keystorePath != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.tv:tv-material:1.0.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.5.1")
    implementation("androidx.media3:media3-ui:1.5.1")
    implementation("io.coil-kt:coil-compose:2.7.0")
}

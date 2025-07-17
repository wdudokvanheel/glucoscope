package com.bitechular.glucoscope

import android.app.Activity
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.core.view.WindowCompat
import androidx.hilt.navigation.compose.hiltViewModel
import com.bitechular.glucoscope.extensions.isLight
import com.bitechular.glucoscope.preference.GlucoScopePreferences
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.screens.AppNavigationView
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            val prefs: GlucoScopePreferences = hiltViewModel()

            StatusBarUpdater(prefs)

            CompositionLocalProvider(PreferenceModel provides prefs) {
                AppNavigationView()
            }
        }
    }

    @Composable
    fun StatusBarUpdater(prefs: GlucoScopePreferences) {
        val ctx = LocalContext.current
        LaunchedEffect(prefs.theme.background, prefs.theme.isLight) {
            val window = (ctx as Activity).window
            WindowCompat.getInsetsController(
                window,
                window.decorView
            ).isAppearanceLightStatusBars = prefs.theme.isLight
        }
    }
}
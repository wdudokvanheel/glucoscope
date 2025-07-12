package com.bitechular.glucoscope

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.hilt.navigation.compose.hiltViewModel
import com.bitechular.glucoscope.preference.GlucoScopePreferences
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.GlucoScopeApp
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            val preferences: GlucoScopePreferences = hiltViewModel()

            CompositionLocalProvider(PreferenceModel provides preferences) {
                GlucoScopeApp()
            }
        }
    }
}
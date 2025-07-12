package com.bitechular.glucoscope

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.bitechular.glucoscope.ui.GlucoScopeApp
import com.bitechular.glucoscope.ui.theme.GlucoScopeTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        enableEdgeToEdge()

        setContent {
            GlucoScopeTheme {
                GlucoScopeApp()
            }
        }
    }
}
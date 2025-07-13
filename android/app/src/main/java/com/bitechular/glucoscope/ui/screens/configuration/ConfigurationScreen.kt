package com.bitechular.glucoscope.ui.screens.configuration

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.screens.configuration.components.GlucoScopeBottomBar


@Composable
fun ConfigurationScreen() {
    val prefs = PreferenceModel.current
    val configNavigation = rememberNavController()

    Scaffold(
        bottomBar = { GlucoScopeBottomBar(configNavigation) }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(prefs.theme.background)
        ) {
            NavHost(
                navController = configNavigation,
                startDestination = "glucose",
                modifier = Modifier.padding(padding)
            ) {
                composable("themes") { Text("Themes") }
                composable("glucose") { Text("Glucose values") }
                composable("connection") { Text("Connection") }
                composable("about") { Text("About") }
            }
        }
    }
}
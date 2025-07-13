package com.bitechular.glucoscope.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.screens.configuration.ConfigurationScreen
import com.bitechular.glucoscope.ui.screens.main.MainScreen

sealed class Screen(val route: String) {
    object Main : Screen("main")
    object Config : Screen("config")
}

val Navigator = staticCompositionLocalOf<NavHostController> {
    error("No NavController provided")
}

@Composable
fun NavigationContainer() {
    val navController = rememberNavController()

    CompositionLocalProvider(Navigator provides navController) {
        val prefs = PreferenceModel.current

        Scaffold(
            modifier = Modifier
                .fillMaxSize()
        ) { innerPadding ->
            Column(
                Modifier
                    .background(prefs.theme.background)
                    .padding(innerPadding)
                    .fillMaxSize()
            ) {
                NavHost(
                    navController = navController,
                    startDestination = Screen.Main.route
                ) {
                    composable(Screen.Main.route) { MainScreen() }
                    composable(Screen.Config.route) { ConfigurationScreen() }
                }
            }
        }
    }
}
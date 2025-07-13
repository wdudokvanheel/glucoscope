package com.bitechular.glucoscope.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.bitechular.glucoscope.ui.screens.configuration.ConfigurationScreen
import com.bitechular.glucoscope.ui.screens.main.MainScreen

sealed class Screen(val route: String) {
    object Main : Screen("main")
    object Config : Screen("config")
}

val AppNavigator = staticCompositionLocalOf<NavHostController> {
    error("No NavController provided")
}

@Composable
fun NavigationContainer() {
    val navController = rememberNavController()

    CompositionLocalProvider(AppNavigator provides navController) {
        NavHost(
            navController = navController,
            startDestination = Screen.Main.route
        ) {
            composable(Screen.Main.route) { MainScreen() }
            composable(Screen.Config.route) { ConfigurationScreen() }
        }
    }
}
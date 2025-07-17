package com.bitechular.glucoscope.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.screens.configuration.ConfigurationTabsView
import com.bitechular.glucoscope.ui.screens.main.MainScreen
import com.bitechular.glucoscope.ui.screens.onboarding.OnboardingView

sealed class AppScreen(val route: String) {
    object Main : AppScreen("main")
    object Config : AppScreen("config")
    object Onboarding : AppScreen("onboarding")
}

val AppNavigator = staticCompositionLocalOf<NavHostController> {
    error("No NavController provided")
}

@Composable
fun AppNavigationView() {
    val navController = rememberNavController()
    val prefs = PreferenceModel.current

    val start = if (prefs.repositoryConfiguration == null) {
        AppScreen.Onboarding.route
    } else {
        AppScreen.Onboarding.route
    }

    CompositionLocalProvider(AppNavigator provides navController) {
        NavHost(
            navController = navController,
            startDestination = start
        ) {
            composable(AppScreen.Onboarding.route) { OnboardingView() }
            composable(AppScreen.Main.route) { MainScreen() }
            composable(AppScreen.Config.route) { ConfigurationTabsView() }
        }
    }
}
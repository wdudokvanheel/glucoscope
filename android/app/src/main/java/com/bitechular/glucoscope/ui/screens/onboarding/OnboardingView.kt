package com.bitechular.glucoscope.ui.screens.onboarding

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.scaffold.MinimalScaffold
import com.bitechular.glucoscope.ui.components.scaffold.MinimalScaffoldTopBar
import com.bitechular.glucoscope.ui.screens.AppNavigator
import com.bitechular.glucoscope.ui.screens.onboarding.model.OnboardingViewModel
import com.bitechular.glucoscope.ui.screens.onboarding.steps.StepConnectionSettings
import com.bitechular.glucoscope.ui.screens.onboarding.steps.StepConnectionTest
import com.bitechular.glucoscope.ui.screens.onboarding.steps.StepConnectionType
import com.bitechular.glucoscope.ui.screens.onboarding.steps.StepIntro

@Composable
fun OnboardingView() {
    val prefs = PreferenceModel.current
    val appNavigator = AppNavigator.current
    val navController = rememberNavController()

    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    val viewModel: OnboardingViewModel = hiltViewModel()

    MinimalScaffold(
        background = prefs.theme.background,
        topBar = {
            MinimalScaffoldTopBar(
                title = "GlucoScope",
                showBackButton = currentRoute != "intro",
                onBackClick = { navController.popBackStack() }
            )
        },
    ) {
        NavHost(
            navController = navController,
            startDestination = "intro",
            modifier = Modifier.fillMaxSize()
        ) {
            composable("intro") { StepIntro(navController) }
            composable("connectiontype") { StepConnectionType(viewModel, navController) }
            composable("connectionsettings") { StepConnectionSettings(viewModel, navController) }
            composable("connectiontest") {
                StepConnectionTest(viewModel) { config ->
                    prefs.setRepositoryConfiguration(config)
                }
            }
        }
    }
}

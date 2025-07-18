package com.bitechular.glucoscope.ui.screens.configuration

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.InvertColors
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.scaffold.MinimalScaffold
import com.bitechular.glucoscope.ui.components.scaffold.MinimalScaffoldTopBar
import com.bitechular.glucoscope.ui.screens.AppNavigator
import com.bitechular.glucoscope.ui.screens.configuration.components.ConfigurationNavigationBar
import com.bitechular.glucoscope.ui.screens.configuration.tabs.AboutTab
import com.bitechular.glucoscope.ui.screens.configuration.tabs.ConnectionSettingsTab
import com.bitechular.glucoscope.ui.screens.configuration.tabs.GlucoseValuesTab
import com.bitechular.glucoscope.ui.screens.configuration.tabs.ThemeSelectorTab


data class ConfigurationTab(
    val route: String,
    val label: String,
    val icon: ImageVector
)

@Composable
fun ConfigurationTabsView() {
    val tabs = listOf(
        ConfigurationTab("themes", "Themes", Icons.Outlined.Palette),
        ConfigurationTab("glucose", "Glucose values", Icons.Filled.InvertColors),
        ConfigurationTab("connection", "Connection", Icons.Outlined.Language),
        ConfigurationTab("about", "About", Icons.Outlined.Info)
    )

    val prefs = PreferenceModel.current
    val appNavigator = AppNavigator.current
    val navController = rememberNavController()

    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route
    val currentTitle = tabs.firstOrNull { it.route == currentRoute }?.label.orEmpty()

    MinimalScaffold(
        background = prefs.theme.background,
        topBar = {
            MinimalScaffoldTopBar(
                title = currentTitle,
                onBackClick = { appNavigator.popBackStack() }
            )
        },
        bottomBar = { ConfigurationNavigationBar(navController, tabs) }
    ) {
        NavHost(
            navController = navController,
            startDestination = "themes",
            modifier = Modifier.fillMaxSize()
        ) {
            composable("themes") { ThemeSelectorTab() }
            composable("glucose") { GlucoseValuesTab() }
            composable("connection") { ConnectionSettingsTab() }
            composable("about") { AboutTab() }
        }
    }
}
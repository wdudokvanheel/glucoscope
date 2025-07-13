package com.bitechular.glucoscope.ui.screens.configuration

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.InvertColors
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.screens.AppNavigator
import com.bitechular.glucoscope.ui.screens.configuration.components.ConfigurationBottomBar
import com.bitechular.glucoscope.ui.screens.configuration.components.ConfigurationTab
import com.bitechular.glucoscope.ui.screens.configuration.components.ConfigurationTopBar
import com.bitechular.glucoscope.ui.screens.configuration.features.GlucoseValuesScreen


@Composable
fun ConfigurationScreen() {
    val tabs = listOf(
        ConfigurationTab("themes", "Themes", Icons.Outlined.Palette),
        ConfigurationTab("glucose", "Glucose values", Icons.Filled.InvertColors),
        ConfigurationTab("connection", "Connection", Icons.Outlined.Language),
        ConfigurationTab("about", "About", Icons.Outlined.Info)
    )

    val prefs = PreferenceModel.current
    val appNavigator = AppNavigator.current
    val configNavigation = rememberNavController()

    val navBackStackEntry by configNavigation.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route
    val currentTitle = tabs.firstOrNull { it.route == currentRoute }?.label.orEmpty()

    Scaffold(
        topBar = {
            ConfigurationTopBar(
                title = currentTitle,
                onBackClick = {
                    appNavigator.popBackStack()
                }
            )
        },
        bottomBar = { ConfigurationBottomBar(configNavigation, tabs) }

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
                composable("glucose") { GlucoseValuesScreen() }
                composable("connection") { Text("Connection") }
                composable("about") { Text("About") }
            }
        }
    }
}


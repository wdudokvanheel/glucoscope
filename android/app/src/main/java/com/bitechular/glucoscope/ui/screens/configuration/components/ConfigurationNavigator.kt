package com.bitechular.glucoscope.ui.screens.configuration.components

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalRippleConfiguration
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.sp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.currentBackStackEntryAsState
import com.bitechular.glucoscope.preference.PreferenceModel

data class ConfigurationTab(
    val route: String,
    val label: String,
    val icon: ImageVector
)


@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConfigurationTopBar(
    title: String,
    onBackClick: () -> Unit
) {
    val prefs = PreferenceModel.current

    CenterAlignedTopAppBar(
        navigationIcon = {
            IconButton(onClick = onBackClick) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back",
                    tint = prefs.theme.accent
                )
            }
        },
        title = {
            Text(
                text = title,
                color = prefs.theme.text
            )
        },
        colors = androidx.compose.material3.TopAppBarDefaults
            .centerAlignedTopAppBarColors(
                containerColor = prefs.theme.background,
                navigationIconContentColor = prefs.theme.accent,
                titleContentColor = prefs.theme.text
            )
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConfigurationBottomBar(navController: NavHostController, items: List<ConfigurationTab>) {
    val prefs = PreferenceModel.current
    CompositionLocalProvider(LocalRippleConfiguration provides null) {

        NavigationBar(
            containerColor = prefs.theme.surface,
        ) {
            val navBackStackEntry by navController.currentBackStackEntryAsState()
            val currentRoute = navBackStackEntry?.destination?.route

            items.forEach { screen ->
                val selected = currentRoute == screen.route
                NavigationBarItem(
                    selected = selected,
                    onClick = {
                        if (!selected) {
                            navController.navigate(screen.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        }
                    },
                    icon = {
                        Icon(
                            imageVector = screen.icon,
                            contentDescription = screen.label,
                            tint = if (selected) prefs.theme.accent else prefs.theme.text.copy(alpha = 0.65f)
                        )
                    },
                    label = {
                        Text(
                            text = screen.label,
                            fontSize = 12.sp,
                            color = if (selected) prefs.theme.accent else prefs.theme.text.copy(
                                alpha = 0.65f
                            )
                        )
                    },
                    alwaysShowLabel = true,
                    colors = NavigationBarItemDefaults.colors(
                        selectedIconColor = prefs.theme.accent,
                        selectedTextColor = prefs.theme.accent,
                        unselectedIconColor = prefs.theme.text.copy(alpha = 0.65f),
                        unselectedTextColor = prefs.theme.text.copy(alpha = 0.65f),
                        indicatorColor = Color.Transparent
                    )
                )
            }
        }
    }
}
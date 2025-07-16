package com.bitechular.glucoscope.ui.screens.configuration.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import androidx.navigation.NavGraph.Companion.findStartDestination
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

    Box(
        modifier = Modifier
            .fillMaxWidth()
    ) {
        IconButton(
            onClick = onBackClick,
            modifier = Modifier.align(Alignment.CenterStart)
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "Back",
                tint = prefs.theme.accent
            )
        }

        Text(
            text = title,
            color = prefs.theme.text,
            modifier = Modifier.align(Alignment.Center),
            fontSize = 28.sp
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConfigurationBottomBar(
    navController: NavController,
    items: List<ConfigurationTab>,
) {
    val prefs = PreferenceModel.current
    val currentRoute by navController.currentBackStackEntryAsState()
    val interactionSource = remember { MutableInteractionSource() }

    Surface(
        color = prefs.theme.surface,
    ) {
        Row(
            modifier = Modifier
                .padding(
                    WindowInsets.safeDrawing
                        .only(WindowInsetsSides.Bottom)
                        .asPaddingValues()
                )
                .padding(top = 8.dp)
                .fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically
        ) {
            items.forEach { screen ->
                val selected = currentRoute?.destination?.route == screen.route
                val tint = if (selected) prefs.theme.accent
                else prefs.theme.text.copy(alpha = 0.65f)

                Column(
                    modifier = Modifier
                        .weight(1f)
                        .clickable(
                            interactionSource = interactionSource,
                            indication = null
                        ) {
                            if (!selected) {
                                navController.navigate(screen.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            }
                        }
                        .padding(vertical = 4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Icon(
                        imageVector = screen.icon,
                        contentDescription = screen.label,
                        tint = tint
                    )
                    Spacer(Modifier.height(2.dp))
                    Text(
                        text = screen.label,
                        fontSize = 12.sp,
                        color = tint
                    )
                }
            }
        }
    }
}
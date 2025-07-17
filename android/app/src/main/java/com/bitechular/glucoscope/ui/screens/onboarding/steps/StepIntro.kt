package com.bitechular.glucoscope.ui.screens.onboarding.steps

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ShowChart
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.bitechular.glucoscope.GlucoScopeApplication
import com.bitechular.glucoscope.data.model.DemoRepositoryConfiguration
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.themed.ThemedAccentButton
import com.bitechular.glucoscope.ui.components.themed.ThemedSection
import com.bitechular.glucoscope.ui.graphics.ThemedLogoGraphic
import com.bitechular.glucoscope.ui.screens.configuration.components.ConfigurationTabView

@Composable
fun StepIntro(navigator: NavHostController) {
    val prefs = PreferenceModel.current
    var showDemoDialog by remember { mutableStateOf(false) }

    ConfigurationTabView(
        graphic = { ThemedLogoGraphic(Modifier.padding(16.dp)) },

        content = {
            ThemedSection(
                modifier = Modifier,
                innerPadding = 16.dp
            ) {
                LazyColumn(modifier = Modifier.padding(0.dp)) {
                    items(1) {
                        Text(
                            text = "Welcome to ${GlucoScopeApplication.APP_NAME}",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = prefs.theme.text
                        )
                        Spacer(Modifier.height(2.dp))
                        Text(
                            text = "Beautiful blood glucose visualization for diabetics",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Light,
                            color = prefs.theme.text
                        )
                        Spacer(Modifier.height(12.dp))
                        OnboardFeatureList()
                        Spacer(Modifier.height(12.dp))
                        ThemedAccentButton("Get started") {
                            navigator.navigate(route = "connectiontype")
                        }

                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 8.dp),

                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(
                                "Demo mode",
                                fontSize = 11.sp,
                                modifier = Modifier
                                    .alpha(0.8f)
                                    .clickable(
                                        interactionSource = remember { MutableInteractionSource() },
                                        indication = null
                                    ) {
                                        showDemoDialog = true
                                    },
                                color = prefs.theme.text
                            )
                        }
                    }
                }
            }
        }
    )

    if (showDemoDialog) {
        AlertDialog(
            onDismissRequest = { showDemoDialog = false },
            title = { Text("Start demo mode?") },
            text = {
                Text(
                    "Demo mode allows you to use the full app, but using fake data. " +
                            "You can setup a connection later in the settings menu. Start GlucoScope in demo mode?"
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showDemoDialog = false
                    prefs.setRepositoryConfiguration(DemoRepositoryConfiguration())
                }) {
                    Text("Start", color = prefs.theme.text)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDemoDialog = false }) {
                    Text("Cancel", color = prefs.theme.lowColor)
                }
            },
            containerColor = prefs.theme.surface,
            titleContentColor = prefs.theme.text,
            textContentColor = prefs.theme.text,
            iconContentColor = prefs.theme.accent,
            shape = RoundedCornerShape(8.dp),
        )
    }
}

private data class FeatureItem(
    val icon: ImageVector,
    val title: String,
    val description: String
)

private val onboardFeatures = listOf(
    FeatureItem(
        icon = Icons.Default.Visibility,
        title = "Instant insight",
        description = "Quickly see your current and past levels without thinking"
    ),
    FeatureItem(
        icon = Icons.AutoMirrored.Filled.ShowChart,
        title = "Beautiful graphs",
        description = "Select one of the many themes to customize your experience"
    ),
    FeatureItem(
        icon = Icons.Default.Timer,
        title = "Real time updates",
        description = "Values are updated often so you never miss a high or low"
    )
)

@Composable
fun OnboardFeatureList() {
    val prefs = PreferenceModel.current

    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth()
    ) {
        onboardFeatures.forEach() { feature ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth()
            ) {
                Icon(
                    imageVector = feature.icon,
                    contentDescription = feature.title,
                    modifier = Modifier.size(32.dp),
                    tint = prefs.theme.text
                )
                Spacer(Modifier.width(16.dp))
                Column(
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(
                        text = feature.title,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = prefs.theme.text
                    )
                    Text(
                        text = feature.description,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Light,
                        color = prefs.theme.text,
                        modifier = Modifier.alpha(0.9f)
                    )
                }
            }
        }
    }
}
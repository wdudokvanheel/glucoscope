package com.bitechular.glucoscope.ui.screens.onboarding.steps

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bitechular.glucoscope.data.model.RepositoryConfiguration
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.themed.ThemedAccentButton
import com.bitechular.glucoscope.ui.components.themed.ThemedSection
import com.bitechular.glucoscope.ui.graphics.ThemedConnectionTestGraphic
import com.bitechular.glucoscope.ui.screens.configuration.components.ConfigurationTabView
import com.bitechular.glucoscope.ui.screens.onboarding.model.ConnectionTestState
import com.bitechular.glucoscope.ui.screens.onboarding.model.OnboardingViewModel

@Composable
fun StepConnectionTest(viewModel: OnboardingViewModel, completeOnboarding: (RepositoryConfiguration) -> Unit ) {
    val prefs = PreferenceModel.current
    viewModel.connectionTestState = null

    ConfigurationTabView(
        graphic = {
            ThemedConnectionTestGraphic(state = viewModel.connectionTestState)
        },

        content = {
            ThemedSection(
                modifier = Modifier,
                innerPadding = 16.dp
            ) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Text(
                        "Connection test",
                        color = prefs.theme.text,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 24.sp
                    )
                    Text(
                        "GlucoScope will now verify your connection settings to see if everything works correctly.",
                        color = prefs.theme.text,
                        fontSize = 14.sp,
                    )

                    Spacer(Modifier.height(8.dp))

                    if (viewModel.connectionTestState != ConnectionTestState.Success) {
                        ThemedAccentButton("Test now") {
                            viewModel.testConnection()
                        }
                    } else {
                        ThemedAccentButton("Start using GlucoScope") {
                            completeOnboarding(viewModel.createConfig())
                        }
                    }
                }
            }
        }
    )
}
package com.bitechular.glucoscope.ui.screens.onboarding.steps

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.themed.ThemedAccentButton
import com.bitechular.glucoscope.ui.components.themed.ThemedSection
import com.bitechular.glucoscope.ui.components.themed.ThemedSegmentedSelector
import com.bitechular.glucoscope.ui.graphics.ThemedConnectionTypeGraphic
import com.bitechular.glucoscope.ui.screens.configuration.components.ConfigurationTabView
import com.bitechular.glucoscope.ui.screens.configuration.tabs.ServerType
import com.bitechular.glucoscope.ui.screens.onboarding.model.OnboardingViewModel

@Composable
fun StepConnectionType(viewModel: OnboardingViewModel, navigator: NavHostController) {
    val prefs = PreferenceModel.current

    ConfigurationTabView(
        graphic = { ThemedConnectionTypeGraphic() },

        content = {
            ThemedSection(
                modifier = Modifier,
                innerPadding = 16.dp
            ) {
                Column(
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        "Connection type",
                        color = prefs.theme.text,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 24.sp
                    )
                    Text(
                        "In order to retrieve your blood glucose values, we need to connect to a cloud service.",
                        color = prefs.theme.text,
                        fontSize = 14.sp,
                    )

                    Spacer(Modifier.height(8.dp))

                    Text(
                        "Are you using Nightscout or a GlucoScope Server to store your blood glucose values?",
                        color = prefs.theme.text,
                        fontSize = 14.sp,
                    )
                    Spacer(Modifier.height(2.dp))

                    ThemedSegmentedSelector(
                        options = listOf("GlucoScope", "Nightscout"),
                        selected = viewModel.connectionType.ordinal,
                        onSelect = { index ->
                            viewModel.connectionType = ServerType.entries.toTypedArray()[index]
                        },
                        modifier = Modifier.fillMaxWidth()
                    )

                    Spacer(Modifier.height(12.dp))
                    ThemedAccentButton("Continue") {
                        navigator.navigate(route = "connectionsettings")
                    }
                }
            }
        }
    )
}
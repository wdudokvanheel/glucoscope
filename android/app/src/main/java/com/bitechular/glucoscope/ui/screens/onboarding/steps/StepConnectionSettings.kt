package com.bitechular.glucoscope.ui.screens.onboarding.steps

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.themed.ThemedAccentButton
import com.bitechular.glucoscope.ui.components.themed.ThemedSection
import com.bitechular.glucoscope.ui.components.themed.ThemedTextbox
import com.bitechular.glucoscope.ui.graphics.ThemedConnectionTypeGraphic
import com.bitechular.glucoscope.ui.screens.configuration.components.ConfigurationTabView
import com.bitechular.glucoscope.ui.screens.onboarding.model.OnboardingViewModel

@Composable
fun StepConnectionSettings(viewModel: OnboardingViewModel, navigator: NavHostController) {
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
                        "Connection settings",
                        color = prefs.theme.text,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 24.sp
                    )
                    Spacer(Modifier.height(8.dp))

                    Text(
                        "Enter the address of your GlucoScope server",
                        color = prefs.theme.text,
                        fontSize = 14.sp,
                    )
                    ThemedTextbox(
                        viewModel.url,
                        placeholder = "Server address",
                        textAlign = TextAlign.Start,
                        onValueChange = { viewModel.url = it },
                    )

                    Spacer(Modifier.height(8.dp))

                    Text(
                        "Optionally enter the API token required for authentication",
                        color = prefs.theme.text,
                        fontSize = 14.sp,
                    )
                    ThemedTextbox(
                        viewModel.apiToken,
                        placeholder = "API Token",
                        textAlign = TextAlign.Start,
                        onValueChange = { viewModel.apiToken = it },
                        isPassword =  true
                    )

                    ThemedAccentButton("Test connection") {
                        navigator.navigate(route = "connectiontest")
                    }
                }
            }
        }
    )
}
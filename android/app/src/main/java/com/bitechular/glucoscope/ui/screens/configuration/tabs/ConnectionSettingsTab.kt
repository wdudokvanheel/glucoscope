package com.bitechular.glucoscope.ui.screens.configuration.tabs

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bitechular.glucoscope.data.model.DemoRepositoryConfiguration
import com.bitechular.glucoscope.data.model.GlucoScopeRepositoryConfiguration
import com.bitechular.glucoscope.data.model.NightscoutRepositoryConfiguration
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.themed.ThemedAccentButton
import com.bitechular.glucoscope.ui.components.themed.ThemedSection
import com.bitechular.glucoscope.ui.components.themed.ThemedSegmentedSelector
import com.bitechular.glucoscope.ui.components.themed.ThemedTextbox
import com.bitechular.glucoscope.ui.graphics.ThemedServerSettingsGraphic
import com.bitechular.glucoscope.ui.screens.configuration.components.ConfigurationTabView

enum class ServerType { GLUCOSCOPE, NIGHTSCOUT }

@Composable
fun ConnectionSettingsTab() {
    val prefs = PreferenceModel.current

    val currentConfig = prefs.repositoryConfiguration

    var serverType by rememberSaveable { mutableStateOf(ServerType.NIGHTSCOUT) }
    var url by rememberSaveable { mutableStateOf("") }
    var apiToken by rememberSaveable { mutableStateOf("") }
    var demoMode = false

    if (currentConfig != null) {
        when (currentConfig) {
            is GlucoScopeRepositoryConfiguration -> {
                serverType = ServerType.GLUCOSCOPE
                url = currentConfig.url
                apiToken = currentConfig.apiToken.orEmpty()
            }

            is NightscoutRepositoryConfiguration -> {
                serverType = ServerType.NIGHTSCOUT
                url = currentConfig.url
                apiToken = currentConfig.apiToken.orEmpty()
            }

            is DemoRepositoryConfiguration -> {
                serverType = ServerType.GLUCOSCOPE
                url = ""
                apiToken = ""
                demoMode = true
            }
        }
    }

    val saveSettings = {
        val config = when (serverType) {
            ServerType.GLUCOSCOPE -> GlucoScopeRepositoryConfiguration(url, apiToken)
            ServerType.NIGHTSCOUT -> NightscoutRepositoryConfiguration(url, apiToken)
        }

        prefs.setRepositoryConfiguration(config)
    }

    @Composable
    fun ConnectionSettingsEditor() {
        ThemedSection(innerPadding = 8.dp) {
            Column(
                modifier = Modifier
                    .fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ThemedSegmentedSelector(
                    options = listOf("GlucoScope", "Nightscout"),
                    selected = serverType.ordinal,
                    onSelect = { index ->
                        serverType = ServerType.entries.toTypedArray()[index]
                    },
                    modifier = Modifier.fillMaxWidth()
                )

                ThemedTextbox(
                    value = url,
                    onValueChange = { url = it },
                    placeholder = "Server URL",
                    textAlign = TextAlign.Start,
                    modifier = Modifier.fillMaxWidth()
                )

                ThemedTextbox(
                    value = apiToken,
                    onValueChange = { apiToken = it },
                    placeholder = "API Token (optional)",
                    textAlign = TextAlign.Start,
                    modifier = Modifier.fillMaxWidth(),
                    isPassword = true
                )

                Button(
                    onClick = { saveSettings() },
                    shape = RoundedCornerShape(8.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = prefs.theme.accent,
                        contentColor = prefs.theme.indicatorLabel
                    ),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text("Save connection settings")
                }
            }
        }
    }

    ConfigurationTabView(
        graphic = { ThemedServerSettingsGraphic() },
    ) {
        if (demoMode) {
            ThemedSection(innerPadding = 8.dp) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = "Demo mode",
                        fontSize = 24.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = prefs.theme.text
                    )

                    Text(
                        "Currently in demonstration mode. Please run the setup to connect to a sever.",
                        fontSize = 14.sp,
                        color = prefs.theme.text
                    )

                    Spacer(Modifier.height(8.dp))

                    ThemedAccentButton("Setup GlucoScope") {
                        prefs.repositoryConfiguration = null
                    }
                }
            }
        } else {
            ConnectionSettingsEditor()
        }
    }
}

package com.bitechular.glucoscope.ui.screens.onboarding

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bitechular.glucoscope.data.datasource.DataSourceService
import com.bitechular.glucoscope.data.model.GlucoScopeRepositoryConfiguration
import com.bitechular.glucoscope.data.model.NightscoutRepositoryConfiguration
import com.bitechular.glucoscope.data.model.RepositoryConfiguration
import com.bitechular.glucoscope.ui.screens.configuration.tabs.ServerType
import dagger.hilt.android.lifecycle.HiltViewModel
import jakarta.inject.Inject
import kotlinx.coroutines.launch

@HiltViewModel
class OnboardingViewModel @Inject constructor(
    private val dataSourceService: DataSourceService,
) : ViewModel() {
    var connectionType by mutableStateOf(ServerType.GLUCOSCOPE)
    var url by mutableStateOf("")
    var apiToken by mutableStateOf("")
    var connectionTestState: ConnectionTestState? by mutableStateOf(null)

    fun testConnection() {
        connectionTestState = ConnectionTestState.Pending

        viewModelScope.launch {
            connectionTestState =
                try {
                    val config = createConfig()
                    val ok = dataSourceService.testConnection(config)

                    if (ok) {
                        ConnectionTestState.Success
                    } else {
                        ConnectionTestState.Failed("Failed")
                    }
                } catch (e: Exception) {
                    ConnectionTestState.Failed(e.toString())
                } as ConnectionTestState?
        }
    }

    fun createConfig(): RepositoryConfiguration =
        when (connectionType) {
            ServerType.GLUCOSCOPE -> GlucoScopeRepositoryConfiguration(url, apiToken)
            ServerType.NIGHTSCOUT -> NightscoutRepositoryConfiguration(url, apiToken)
        }
}
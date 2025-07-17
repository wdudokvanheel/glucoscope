package com.bitechular.glucoscope.ui.screens.onboarding

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.bitechular.glucoscope.ui.screens.configuration.tabs.ServerType
import dagger.hilt.android.lifecycle.HiltViewModel
import jakarta.inject.Inject

@HiltViewModel
class OnboardingViewModel @Inject constructor(
) : ViewModel() {
    var connectionType by mutableStateOf(ServerType.GLUCOSCOPE)

}
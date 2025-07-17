package com.bitechular.glucoscope.ui.screens.onboarding.model

sealed interface ConnectionTestState {
    object Pending : ConnectionTestState
    data class Failed(val message: String) : ConnectionTestState
    object Success : ConnectionTestState
}
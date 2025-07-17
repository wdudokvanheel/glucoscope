package com.bitechular.glucoscope.ui.screens.onboarding

sealed interface ConnectionTestState {
    object Pending : ConnectionTestState
    data class Failed(val message: String) : ConnectionTestState
    object Success : ConnectionTestState
}
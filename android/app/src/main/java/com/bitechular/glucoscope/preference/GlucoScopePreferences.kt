package com.bitechular.glucoscope.preference

import android.R.attr.theme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import dagger.hilt.android.lifecycle.HiltViewModel
import androidx.lifecycle.ViewModel
import jakarta.inject.Inject

@HiltViewModel
class GlucoScopePreferences @Inject constructor() : ViewModel() {
    var username by mutableStateOf("Lumi")
    var theme by mutableStateOf(GlucoScopeTheme())
}

class GlucoScopeTheme(
    background: Color = Color(0xFF999999),
    text: Color = Color(0xFF000000)
) {
    var background by mutableStateOf(background)
    var text by mutableStateOf(text)
}
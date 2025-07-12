package com.bitechular.glucoscope.preference

import androidx.compose.runtime.staticCompositionLocalOf

val PreferenceModel = staticCompositionLocalOf<GlucoScopePreferences> {
    error("Preferences not provided")
}

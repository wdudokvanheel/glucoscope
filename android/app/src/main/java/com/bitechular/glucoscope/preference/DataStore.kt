package com.bitechular.glucoscope.preference

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.dataStore
import com.bitechular.glucoscope.preference.dto.GlucoScopePreferencesDto

val Context.settingsDataStore: DataStore<GlucoScopePreferencesDto> by dataStore(
    fileName = "glucoscope_settings.json",
    serializer = SettingsSerializer
)
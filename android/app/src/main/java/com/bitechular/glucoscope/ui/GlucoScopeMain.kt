package com.bitechular.glucoscope.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import com.bitechular.glucoscope.preference.GlucoScopePreferences
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.screens.PrefTest


@Composable
fun GlucoScopeApp() {
    val preferences: GlucoScopePreferences = hiltViewModel()

    CompositionLocalProvider(PreferenceModel provides preferences) {
        Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
            Column {
                PrefTest(
                    modifier = Modifier
                        .padding(innerPadding)
                )
                PrefTest(
                    modifier = Modifier
                        .padding(innerPadding)
                )
                PrefTest(
                    modifier = Modifier
                        .padding(innerPadding)
                        .fillMaxHeight()
                )
            }
        }
    }
}
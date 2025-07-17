package com.bitechular.glucoscope.ui.components.indicator

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.screens.AppNavigator
import com.bitechular.glucoscope.ui.screens.AppScreen


@Composable
fun SettingsButton(
    modifier: Modifier = Modifier,
    color: Color
){
    val prefs = PreferenceModel.current
    val navigator = AppNavigator.current

    IconButton(
        onClick = {
            navigator.navigate(AppScreen.Config.route)
        },
        modifier = modifier
            .padding(8.dp)
    ) {
        Icon(
            imageVector = Icons.Default.Menu,
            contentDescription = "Menu",
            tint = color
        )
    }
}
package com.bitechular.glucoscope.ui.components.scaffold

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.sp
import com.bitechular.glucoscope.preference.PreferenceModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MinimalScaffoldTopBar(
    title: String,
    onBackClick: () -> Unit
) {
    val prefs = PreferenceModel.current

    Box(
        modifier = Modifier
            .fillMaxWidth()
    ) {
        IconButton(
            onClick = onBackClick,
            modifier = Modifier.align(Alignment.CenterStart)
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "Back",
                tint = prefs.theme.accent
            )
        }

        Text(
            text = title,
            color = prefs.theme.text,
            modifier = Modifier.align(Alignment.Center),
            fontSize = 28.sp
        )
    }
}
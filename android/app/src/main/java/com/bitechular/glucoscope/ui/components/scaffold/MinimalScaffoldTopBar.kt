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
    onBackClick: () -> Unit,
    showBackButton: Boolean = true,
) {
    val prefs = PreferenceModel.current

    Box(
        modifier = Modifier
            .fillMaxWidth()
    ) {
        // Hide & disable button to make sure the size of the top bar stay the same whether it's visible or not
        IconButton(
            onClick = onBackClick,
            modifier = Modifier.align(Alignment.CenterStart),
            enabled = showBackButton
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = "Back",
                tint = prefs.theme.accent.copy(alpha = if (showBackButton) 1f else 0f)
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
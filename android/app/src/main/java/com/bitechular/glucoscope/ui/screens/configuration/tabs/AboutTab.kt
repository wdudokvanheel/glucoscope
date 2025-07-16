package com.bitechular.glucoscope.ui.screens.configuration.tabs

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.bitechular.glucoscope.GlucoScopeApplication
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.ui.components.themed.ThemedSection
import com.bitechular.glucoscope.ui.graphics.ThemedLogoGraphic
import com.bitechular.glucoscope.ui.screens.configuration.components.ConfigurationTabView
import com.patrykandpatrick.vico.core.cartesian.axis.BaseAxis

@Composable
fun AboutTab() {
    val prefs = PreferenceModel.current

    ConfigurationTabView(
        graphic = { ThemedLogoGraphic(Modifier.padding(16.dp)) },
    ) {
        ThemedSection(innerPadding = 8.dp) {
            Column(
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                AboutContent(onEraseAll = {

                })
            }
        }
    }
}

@Composable
fun AboutContent(
    modifier: Modifier = Modifier,
    onEraseAll: () -> Unit
) {
    val context = LocalContext.current
    val prefs = PreferenceModel.current

    val (versionName, versionCode) = remember {
        val pm = context.packageManager
        val pkg = pm.getPackageInfo(context.packageName, 0)
        pkg.versionName to pkg.longVersionCode
    }

    var showEraseDialog by remember { mutableStateOf(false) }

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Column {
            Text(
                text = GlucoScopeApplication.APP_NAME,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                color = prefs.theme.text
            )
            Text(
                text = "Android client v$versionName",
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Light,
                modifier = Modifier.alpha(0.9f),
                color = prefs.theme.text
            )
        }


        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            LinkText("Source code", GlucoScopeApplication.URL_SOURCE, context)
            LinkText("License", GlucoScopeApplication.URL_LICENSE, context)
            LinkText("Privacy Policy", GlucoScopeApplication.URL_PRIVACY, context)
        }

        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            TextButton(onClick = { showEraseDialog = true }) {
                Text(
                    text = "Erase all data",
                    color = prefs.theme.text,
                    modifier = Modifier.alpha(0.75f).padding(0.dp),
                    fontSize = 10.sp
                )
            }
        }
    }

    /* ── Confirmation dialog ──────────────────────────────────────────────── */
    if (showEraseDialog) {
        AlertDialog(
            onDismissRequest = { showEraseDialog = false },
            title = { BaseAxis.Size.Text("Are you sure you want to erase all data?") },
            text = { Text("This action cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showEraseDialog = false
                        onEraseAll()
                    }
                ) { Text(
                    "Erase", color = prefs.theme.text.copy(alpha = 0.65f),
                ) }
            },
            dismissButton = {
                TextButton(onClick = { showEraseDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}

/* Helper to make link-like text ------------------------------------------------ */
@Composable
fun LinkText(label: String, url: String, context: Context) {
    val prefs = PreferenceModel.current

    Text(
        text = label,
        color = prefs.theme.text,
        modifier = Modifier.clickable {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }
    )
}

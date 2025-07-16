package com.bitechular.glucoscope.ui.screens.configuration.features

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import com.bitechular.glucoscope.data.repository.DemoDataRepository
import com.bitechular.glucoscope.preference.GlucoScopeTheme
import com.bitechular.glucoscope.preference.PreferenceModel
import com.bitechular.glucoscope.preference.dto.ThemeDto
import com.bitechular.glucoscope.preference.dto.toTheme
import com.bitechular.glucoscope.ui.components.graph.ThemedGraph
import com.bitechular.glucoscope.ui.components.themed.ThemedSection
import com.bitechular.glucoscope.ui.screens.configuration.components.ThemeSwatch
import kotlinx.serialization.json.Json

@Composable
fun ThemeSelectorScreen() {
    val prefs = PreferenceModel.current
    val demoDataSource = DemoDataRepository()
    val themes = loadThemesFromAssets()

    val testData by produceState(initialValue = emptyList<GlucoseMeasurement>(), key1 = Unit) {
        value = demoDataSource.getLatestEntries(9, 5)
    }
    Column(
    ) {
        Column(
            modifier = Modifier
                .clip(RoundedCornerShape(8.dp))
                .padding(horizontal = 16.dp)
                .border(
                    width = 1.dp,
                    color = prefs.theme.surface,
                    shape = RoundedCornerShape(8.dp)
                )
        ) {
            ThemedGraph(
                testData, modifier = Modifier
                    .padding(8.dp)
                    .fillMaxWidth()
                    .fillMaxHeight(1 / 3f)
            )
        }

        ThemedSection(innerPadding = false) {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(4.dp),
                contentPadding = PaddingValues(vertical = 0.dp),
                modifier = Modifier.padding(horizontal = 8.dp)
            ) {
                itemsIndexed(
                    themes,
                    key = { _, theme -> theme.name + theme.variant }) { index, theme ->
                    Column {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    prefs.theme = theme
                                }
                                .padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = theme.name,
                                color = if (prefs.theme == theme) theme.accent else prefs.theme.text,
                                fontWeight = if (prefs.theme == theme) FontWeight.SemiBold else FontWeight.Normal,
                            )

                            if (theme.variant.isNotEmpty()) {
                                Text(
                                    text = "– ${theme.variant}",
                                    modifier = Modifier.padding(start = 4.dp),
                                    color = (if (prefs.theme == theme) theme.accent else prefs.theme.text)
                                        .copy(alpha = 0.75f),
                                    fontWeight = if (prefs.theme == theme) FontWeight.Normal else FontWeight.Light,
                                )
                            }

                            Spacer(modifier = Modifier.weight(1f))

                            ThemeSwatch(theme = theme)
                        }

                        if (index < themes.lastIndex) {
                            HorizontalDivider(
                                color = prefs.theme.text.copy(alpha = 0.5f),
                                thickness = 1.dp,
                                modifier = Modifier.padding(top = 2.dp)
                            )
                        }
                    }
                }
            }

        }

    }
}

@Composable
fun loadThemesFromAssets(): List<GlucoScopeTheme> {
    val context = LocalContext.current
    val jsonText = remember {
        context.assets.open("themes.json")
            .bufferedReader()
            .use { it.readText() }
    }

    return remember(jsonText) {
        Json { ignoreUnknownKeys = true }
            .decodeFromString<List<ThemeDto>>(jsonText)
            .map { t -> t.toTheme() }
            .sortedBy { it.name }
    }
}


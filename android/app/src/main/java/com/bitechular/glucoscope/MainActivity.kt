package com.bitechular.glucoscope

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.ui.Modifier
import androidx.lifecycle.lifecycleScope
import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import com.bitechular.glucoscope.data.repository.DataSource
import com.bitechular.glucoscope.data.repository.DemoDataSource
import com.bitechular.glucoscope.ui.components.graph.Graph
import com.bitechular.glucoscope.ui.theme.GlucoScopeTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    var dataSource: DataSource = DemoDataSource()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        lifecycleScope.launch {
            val data = dataSource.getLatestEntries(hours = 9, window = 5)
            setContentUi(data)
        }

    }

    private fun setContentUi(data: List<GlucoseMeasurement>) {
        setContent {
            GlucoScopeTheme {
                Scaffold(modifier = Modifier.Companion.fillMaxSize()) { innerPadding ->
                    Graph(
                        data,
                        modifier = Modifier.Companion
                            .padding(innerPadding)
                            .fillMaxHeight()
                    )
                }
            }
        }
    }
}
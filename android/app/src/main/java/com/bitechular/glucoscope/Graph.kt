package com.bitechular.glucoscope

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.bitechular.glucoscope.data.GlucoseMeasurement
import com.patrykandpatrick.vico.compose.cartesian.CartesianChartHost
import com.patrykandpatrick.vico.compose.cartesian.axis.rememberBottom
import com.patrykandpatrick.vico.compose.cartesian.axis.rememberEnd
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLineCartesianLayer
import com.patrykandpatrick.vico.compose.cartesian.rememberCartesianChart
import com.patrykandpatrick.vico.compose.cartesian.rememberVicoZoomState
import com.patrykandpatrick.vico.core.cartesian.Zoom
import com.patrykandpatrick.vico.core.cartesian.axis.Axis
import com.patrykandpatrick.vico.core.cartesian.axis.HorizontalAxis
import com.patrykandpatrick.vico.core.cartesian.axis.VerticalAxis
import com.patrykandpatrick.vico.core.cartesian.data.CartesianChartModelProducer
import com.patrykandpatrick.vico.core.cartesian.data.lineSeries
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToInt

@Composable
fun Graph(
    measurements: List<GlucoseMeasurement>,
    modifier: Modifier = Modifier
) {
    if (measurements.isEmpty()) {
        Text("No measurements yet", modifier.fillMaxSize())
        return
    }

    /* -------- data into the model -------- */
    val producer = remember { CartesianChartModelProducer() }
    LaunchedEffect(measurements) {
        producer.runTransaction {
            lineSeries {
                val xs = measurements.indices.map(Int::toDouble)          // 0,1,2…
                val ysLog = measurements.map { log10(it.value) }
                series(x = xs, y = ysLog)
            }
        }
    }


    val minInt = 2
    val maxInt = 20

    val logPlacer = remember(minInt, maxInt) {
        IntegerLogItemPlacer(minInt, maxInt)
    }

    val endAxis = VerticalAxis.rememberEnd(
        itemPlacer = logPlacer,
        valueFormatter = { _, v, _ ->
            10.0.pow(v).roundToInt().toString()
        }
    )

    fun Double.toLdt(): LocalDateTime {
        val inst = if (this > 1E11) Instant.ofEpochMilli(this.toLong())
        else Instant.ofEpochSecond(this.toLong())
        return inst.atZone(ZoneId.systemDefault()).toLocalDateTime()
    }

    val ptsPerHour = remember(measurements) {
        val firstHour = measurements.first().time.toLdt().truncatedTo(ChronoUnit.HOURS)
        val idx =
            measurements.indexOfFirst { it.time.toLdt().truncatedTo(ChronoUnit.HOURS) != firstHour }
        if (idx <= 0) 1 else idx          // fallback if all samples in same hour
    }


    val bottomAxis = HorizontalAxis.rememberBottom(
        valueFormatter = { _, value, _ ->
            val i = value.roundToInt().coerceIn(0, measurements.lastIndex)
            val hour = measurements[i].time.toLdt().hour
            "%02d:00".format(hour)
        },
        itemPlacer = remember {
            HorizontalAxis.ItemPlacer.aligned(
                spacing = { ptsPerHour * 2 },      // every other hour
                addExtremeLabelPadding = false
            )
        }
    )

    /* -------- assemble chart -------- */
    val chart = rememberCartesianChart(
        rememberLineCartesianLayer(),
        endAxis   = endAxis,
        bottomAxis = bottomAxis
    )

    val zoomState = rememberVicoZoomState(
        initialZoom = Zoom.Content,
        minZoom = Zoom.Content,
        maxZoom = Zoom.Content
    )

    CartesianChartHost(
        chart = chart,
        modelProducer = producer,
        zoomState = zoomState,
        modifier = modifier.fillMaxSize()
    )
}
package com.bitechular.glucoscope

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import com.bitechular.glucoscope.data.GlucoseMeasurement
import com.patrykandpatrick.vico.compose.cartesian.CartesianChartHost
import com.patrykandpatrick.vico.compose.cartesian.axis.rememberBottom
import com.patrykandpatrick.vico.compose.cartesian.axis.rememberEnd
import com.patrykandpatrick.vico.compose.cartesian.layer.continuous
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLine
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLineCartesianLayer
import com.patrykandpatrick.vico.compose.cartesian.rememberCartesianChart
import com.patrykandpatrick.vico.compose.cartesian.rememberVicoZoomState
import com.patrykandpatrick.vico.compose.common.fill
import com.patrykandpatrick.vico.core.cartesian.Zoom
import com.patrykandpatrick.vico.core.cartesian.axis.HorizontalAxis
import com.patrykandpatrick.vico.core.cartesian.axis.VerticalAxis
import com.patrykandpatrick.vico.core.cartesian.data.CartesianChartModelProducer
import com.patrykandpatrick.vico.core.cartesian.data.lineSeries
import com.patrykandpatrick.vico.core.cartesian.layer.LineCartesianLayer
import com.patrykandpatrick.vico.core.common.shader.ShaderProvider
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToInt

@Composable
fun Graph(
    measurements: List<GlucoseMeasurement>,
    rangeLow: Double = 2.5,
    rangeHigh: Double = 20.0,
    lowThreshold: Double = 4.0,
    highThreshold: Double = 7.0,
    upperThreshold: Double = 10.0,
    upperColor: Color = Color(0xFFFF006E),
    lowColor: Color = Color(0xFFFF006E),
    inRangeColor: Color = Color(0xFF00C853),
    highColor: Color = Color(0xFFFFD600),
    xAxisStep: Int = 1,
    yAxisValues: List<Double> = listOf(3.0, 4.0, 5.0, 6.0, 7.0, 10.0, 15.0, 20.0),
    modifier: Modifier = Modifier,
) {

    if (measurements.isEmpty()) {
        Text("No measurements yet", modifier.fillMaxSize())
        return
    }

    require(rangeLow > 0 && rangeHigh > rangeLow) { "Both bounds must be > 0 and low < high." }

    val producer = remember { CartesianChartModelProducer() }
    LaunchedEffect(measurements) {
        producer.runTransaction {
            lineSeries {
                val xs = measurements.indices.map(Int::toDouble)
                val ys = measurements.map { log10(it.value) }
                series(x = xs, y = ys)
            }
        }
    }

    val minLog = log10(rangeLow)
    val maxLog = log10(rangeHigh)

    val midLow = androidx.compose.ui.graphics.lerp(
        lowColor.linear(),
        inRangeColor.linear(),
        0.50f
    ).toSrgb()

    val gradient = remember(
        rangeLow, rangeHigh,
        lowThreshold, highThreshold, upperThreshold
    ) {

        ShaderProvider { _, left, top, right, bottom ->
            fun frac(v: Double): Float {
                val span = log10(rangeHigh) - log10(rangeLow)
                return ((log10(rangeHigh) - log10(v)) / span).toFloat()
            }

            val lowBand = lowThreshold * 0.04
            val highBand = highThreshold * 0.0214

            val pos = floatArrayOf(
                0f,
                frac(upperThreshold),
                frac(highThreshold),
                frac(highThreshold - highBand * 1.5),
                frac(lowThreshold + lowBand),
                frac(lowThreshold),
                frac(lowThreshold - lowBand),
                1f
            )

            val col = intArrayOf(
                upperColor.toArgb(),
                upperColor.toArgb(),
                highColor.toArgb(),
                inRangeColor.toArgb(),
                inRangeColor.toArgb(),
                midLow.toArgb(),
                lowColor.toArgb(),
                lowColor.toArgb()
            )

            android.graphics.LinearGradient(
                left, top, left, bottom,
                col, pos, android.graphics.Shader.TileMode.CLAMP
            )
        }
    }

    val rangeProvider = remember(minLog, maxLog) {
        FixedLogRangeProvider(minLog, maxLog)
    }

    val colouredLine = LineCartesianLayer.rememberLine(
        stroke = LineCartesianLayer.LineStroke.continuous(thickness = 4.dp),
        pointConnector = LineCartesianLayer.PointConnector.cubic(curvature = 0.5f),
        fill = LineCartesianLayer.LineFill.single(fill(gradient))
    )

    val lineLayer = rememberLineCartesianLayer(
        lineProvider = LineCartesianLayer.LineProvider.series(listOf(colouredLine)),
        rangeProvider = rangeProvider
    )

    val tickLogs = yAxisValues.map { log10(it) }
    val yPlacer = remember { FixedLogTickPlacer(tickLogs) }

    val endAxis = VerticalAxis.rememberEnd(
        itemPlacer = yPlacer,
        valueFormatter = { _, v, _ -> // v is log10(original)
            10.0.pow(v).roundToInt().toString()
        }
    )

    fun Double.toLdt(): LocalDateTime {
        val inst = if (this > 1E11) Instant.ofEpochMilli(this.toLong())
        else Instant.ofEpochSecond(this.toLong())
        return inst.atZone(ZoneId.systemDefault()).toLocalDateTime()
    }

    val hourXs = remember(measurements) {
        buildList {
            var lastHour = -1
            measurements.forEachIndexed { idx, m ->
                val hour = m.time.toLdt().hour           // 0-23
                if (hour != lastHour) {                  // first sample of a new hour
                    add(idx.toDouble())                  // x-index in Vico’s space
                    lastHour = hour
                }
            }
        }
    }

    val bottomAxis = HorizontalAxis.rememberBottom(
        valueFormatter = { _, x, _ ->
            val i = x.toInt().coerceIn(0, measurements.lastIndex)
            "%02d:00".format(measurements[i].time.toLdt().hour)
        },
        itemPlacer = remember(hourXs) { HourTickPlacer(hourXs, labelStep = xAxisStep) }
    )

    val chart = rememberCartesianChart(
        lineLayer,
        endAxis = endAxis,
        bottomAxis = bottomAxis,
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

private fun Color.linear() = Color(
    red = red.pow(2.2f),
    green = green.pow(2.2f),
    blue = blue.pow(2.2f),
    alpha = alpha
)

private fun Color.toSrgb() = Color(
    red = red.pow(1 / 2.2f),
    green = green.pow(1 / 2.2f),
    blue = blue.pow(1 / 2.2f),
    alpha = alpha
)
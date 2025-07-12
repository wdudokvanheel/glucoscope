package com.bitechular.glucoscope.ui.components.graph

import android.graphics.LinearGradient
import android.graphics.Shader
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import com.patrykandpatrick.vico.compose.cartesian.CartesianChartHost
import com.patrykandpatrick.vico.compose.cartesian.axis.rememberBottom
import com.patrykandpatrick.vico.compose.cartesian.layer.continuous
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLine
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLineCartesianLayer
import com.patrykandpatrick.vico.compose.cartesian.rememberVicoZoomState
import com.patrykandpatrick.vico.compose.common.fill
import com.patrykandpatrick.vico.core.cartesian.CartesianChart
import com.patrykandpatrick.vico.core.cartesian.Zoom
import com.patrykandpatrick.vico.core.cartesian.axis.HorizontalAxis
import com.patrykandpatrick.vico.core.cartesian.axis.VerticalAxis
import com.patrykandpatrick.vico.core.cartesian.data.CartesianChartModelProducer
import com.patrykandpatrick.vico.core.cartesian.data.lineSeries
import com.patrykandpatrick.vico.core.cartesian.layer.LineCartesianLayer
import com.patrykandpatrick.vico.core.common.Fill
import com.patrykandpatrick.vico.core.common.component.LineComponent
import com.patrykandpatrick.vico.core.common.component.TextComponent
import com.patrykandpatrick.vico.core.common.shader.ShaderProvider
import com.patrykandpatrick.vico.core.common.shape.DashedShape
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToInt

@Composable
fun ColoredLineGraph(
    measurements: List<GlucoseMeasurement>,
    graphMin: Double = 2.5,
    graphMax: Double = 20.0,
    lowThreshold: Double = 4.0,
    highThreshold: Double = 7.0,
    upperThreshold: Double = 10.0,
    upperColor: Color = Color(0xFFFF006E),
    lowColor: Color = Color(0xFFFF006E),
    inRangeColor: Color = Color(0xFF00C853),
    highColor: Color = Color(0xFFFFD600),
    axisLabelColor: Color = Color(0xFF000000),
    axisLinesColor: Color = Color(0xFF999999),
    xAxisStep: Int = 2,
    yAxisValues: List<Double> = listOf(3.0, 4.0, 5.0, 6.0, 7.0, 10.0, 15.0, 20.0),
    modifier: Modifier = Modifier,
) {

    if (measurements.isEmpty()) {
        Text("No measurements yet", modifier.fillMaxSize())
        return
    }

    require(graphMin > 0 && graphMax > graphMin) { "Both bounds must be > 0 and low < high." }

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

    val minLog = log10(graphMin)
    val maxLog = log10(graphMax)

    val rangeProvider = remember(minLog, maxLog) {
        FixedLogRangeProvider(minLog, maxLog)
    }

    // Blend between the two colors for a nice gradient
    val midLowColor = lerp(
        lowColor.linear(),
        inRangeColor.linear(),
        0.50f
    ).toSrgb()

    val lineGradient = remember(
        graphMin, graphMax,
        lowThreshold, highThreshold, upperThreshold,
        lowColor, highColor, upperColor, inRangeColor
    ) {

        ShaderProvider { _, left, top, right, bottom ->
            fun frac(v: Double): Float {
                val span = log10(graphMax) - log10(graphMin)
                return ((log10(graphMax) - log10(v)) / span).toFloat()
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
                midLowColor.toArgb(),
                lowColor.toArgb(),
                lowColor.toArgb()
            )

            LinearGradient(
                left, top, left, bottom,
                col, pos, Shader.TileMode.CLAMP
            )
        }
    }

    val colouredLine = LineCartesianLayer.rememberLine(
        stroke = LineCartesianLayer.LineStroke.continuous(thickness = 4.dp),
        pointConnector = LineCartesianLayer.PointConnector.cubic(curvature = 0.5f),
        fill = LineCartesianLayer.LineFill.single(fill(lineGradient))
    )

    val lineLayer = rememberLineCartesianLayer(
        lineProvider = LineCartesianLayer.LineProvider.series(listOf(colouredLine)),
        rangeProvider = rangeProvider
    )

    val yPlacer = remember(yAxisValues) { FixedLogTickPlacer(yAxisValues.map { log10(it) }) }

    val axisLabel = remember(axisLabelColor) {
        TextComponent(
            textSizeSp = 12f,
            lineCount = 1,
            truncateAt = null,
            color = axisLabelColor.toArgb(),
        )
    }

    val endAxisLine = remember(axisLinesColor) {
        LineComponent(
            fill = Fill(axisLinesColor.toArgb()),
            thicknessDp = 1f,
        )
    }

    val bottomAxisLine = remember(axisLinesColor) {
        LineComponent(
            fill = Fill(axisLinesColor.toArgb()),
            thicknessDp = 1f,
            shape = DashedShape(),
        )
    }

    val endAxis = VerticalAxis.end(
        itemPlacer = yPlacer,
        valueFormatter = { _, v, _ -> // v is log10(original)
            10.0.pow(v).roundToInt().toString()
        },
        label = axisLabel,
        guideline = endAxisLine,
        line = null
    )

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
            "%02d".format(measurements[i].time.toLdt().hour)
        },
        itemPlacer = remember(hourXs) { HourTickPlacer(hourXs, labelStep = xAxisStep) },
        label = axisLabel,
        guideline = bottomAxisLine,
        line = null
    )

    val chart = remember(axisLinesColor, axisLabelColor, graphMin, graphMax, yAxisValues) {
        CartesianChart(
            lineLayer,
            endAxis = endAxis,
            bottomAxis = bottomAxis,
        )
    }

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

private fun Double.toLdt(): LocalDateTime {
    val inst = if (this > 1E11) Instant.ofEpochMilli(this.toLong())
    else Instant.ofEpochSecond(this.toLong())
    return inst.atZone(ZoneId.systemDefault()).toLocalDateTime()
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
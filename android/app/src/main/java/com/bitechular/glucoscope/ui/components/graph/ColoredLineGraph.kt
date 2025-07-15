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
import com.bitechular.glucoscope.extensions.linear
import com.bitechular.glucoscope.extensions.toSrgb
import com.patrykandpatrick.vico.compose.cartesian.CartesianChartHost
import com.patrykandpatrick.vico.compose.cartesian.axis.rememberBottom
import com.patrykandpatrick.vico.compose.cartesian.layer.continuous
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLine
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLineCartesianLayer
import com.patrykandpatrick.vico.compose.cartesian.rememberVicoZoomState
import com.patrykandpatrick.vico.compose.common.fill
import com.patrykandpatrick.vico.core.cartesian.CartesianChart
import com.patrykandpatrick.vico.core.cartesian.CartesianDrawingContext
import com.patrykandpatrick.vico.core.cartesian.Zoom
import com.patrykandpatrick.vico.core.cartesian.axis.HorizontalAxis
import com.patrykandpatrick.vico.core.cartesian.axis.VerticalAxis
import com.patrykandpatrick.vico.core.cartesian.data.CartesianChartModelProducer
import com.patrykandpatrick.vico.core.cartesian.data.lineSeries
import com.patrykandpatrick.vico.core.cartesian.decoration.Decoration
import com.patrykandpatrick.vico.core.cartesian.layer.LineCartesianLayer
import com.patrykandpatrick.vico.core.common.Fill
import com.patrykandpatrick.vico.core.common.Position
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

    xAxisStep: Int = 2,
    yAxisLabels: List<Double> = listOf(3.0, 4.0, 5.0, 6.0, 7.0, 10.0, 15.0, 20.0),

    inRangeColor: Color = Color(0xFF00C853),
    lowColor: Color = Color(0xFFFF006E),
    highColor: Color = Color(0xFFFFD600),
    upperColor: Color = Color(0xFFFF006E),
    axisXLegendColor: Color = Color(0xFF000000),
    axisYLegendColor: Color = Color(0xFF999999),
    axisXGridLineColor: Color = Color(0xFF999999),
    axisYGridLineColor: Color = Color(0xFF999999),

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
        stroke = LineCartesianLayer.LineStroke.continuous(thickness = 3.dp),
        pointConnector = LineCartesianLayer.PointConnector.cubic(curvature = 0.5f),
        fill = LineCartesianLayer.LineFill.single(fill(lineGradient))
    )

    val lineLayer = rememberLineCartesianLayer(
        lineProvider = LineCartesianLayer.LineProvider.series(listOf(colouredLine)),
        rangeProvider = rangeProvider
    )

    val yPlacer = remember(yAxisLabels) { FixedLogTickPlacer(yAxisLabels.map { log10(it) }) }

    val xAxisLegend = remember(axisXLegendColor) {
        TextComponent(
            textSizeSp = 12f,
            lineCount = 1,
            truncateAt = null,
            color = axisXLegendColor.toArgb(),
        )
    }

    val yAxisLegend = remember(axisYLegendColor) {
        TextComponent(
            textSizeSp = 12f,
            lineCount = 1,
            truncateAt = null,
            color = axisYLegendColor.toArgb(),
        )
    }

    val yAxisLine = remember(axisYGridLineColor) {
        LineComponent(
            fill = Fill(axisYGridLineColor.toArgb()),
            thicknessDp = 0.5f,
        )
    }

    val xAxisLine = remember(axisXGridLineColor) {
        LineComponent(
            fill = Fill(axisXGridLineColor.toArgb()),
            thicknessDp = 0.5f,
            shape = DashedShape(dashLengthDp = 2f),
        )
    }

    val yAxis = VerticalAxis.end(
        itemPlacer = yPlacer,
        valueFormatter = { _, v, _ -> // v is log10(original)
            10.0.pow(v).roundToInt().toString()
        },
        label = yAxisLegend,
        guideline = yAxisLine,
        line = null
    )

    val xAxisLabelList = remember(measurements) {
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

    val hourDecoration = rememberHourLabelsDecoration(
        xIndices = xAxisLabelList,
        labelStep = xAxisStep,
        color = axisXLegendColor,
        hours = xAxisLabelList.map { idx ->
            measurements[idx.toInt()].time.toLdt().hour
        }
    )

    val bottomAxis = HorizontalAxis.rememberBottom(
        valueFormatter = { _, x, _ ->
            val i = x.toInt().coerceIn(0, measurements.lastIndex)
            "%02d".format(measurements[i].time.toLdt().hour)
        },
        itemPlacer = remember(xAxisLabelList, xAxisStep) {
            HourTickPlacer(xAxisLabelList, labelStep = xAxisStep)
        },
        label = null,
        guideline = xAxisLine,
        line = null,
        tickLength = 0.dp
    )

    val chart = remember(
        axisXGridLineColor,
        axisYGridLineColor,
        axisXLegendColor,
        axisYLegendColor,
        xAxisLabelList,
        graphMin,
        graphMax,
        yAxisLabels,
        lowColor,
        highColor,
        upperColor,
        inRangeColor,
        lowThreshold,
        highThreshold,
        upperThreshold,
    ) {
        CartesianChart(
            lineLayer,
            endAxis = yAxis,
            bottomAxis = bottomAxis,
            decorations = listOf(hourDecoration)
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
        modifier = modifier.fillMaxSize(),
        animateIn = false,
        animationSpec = null,
    )
}

private fun Double.toLdt(): LocalDateTime {
    val inst = if (this > 1E11) Instant.ofEpochMilli(this.toLong())
    else Instant.ofEpochSecond(this.toLong())
    return inst.atZone(ZoneId.systemDefault()).toLocalDateTime()
}

@Composable
fun rememberHourLabelsDecoration(
    xIndices: List<Double>,
    hours: List<Int>,
    labelStep: Int = 2,
    color: Color = Color.White,
    textSizeSp: Float = 12f,
    gapDp: Float = 4f,
): Decoration = remember(xIndices, hours, labelStep, color, textSizeSp, gapDp) {

    val label = TextComponent(
        textSizeSp = textSizeSp,
        color = color.toArgb(),
        lineCount = 1,
    )

    object : Decoration {
        override fun drawOverLayers(context: CartesianDrawingContext) {
            val gapPx = gapDp * context.density
            val y = context.layerBounds.bottom - label.getHeight(context)
            val stepPx = context.layerDimensions.xSpacing
            val minX = context.ranges.minX
            val xStep = context.ranges.xStep
            val leftPx = context.layerBounds.left
            val rightPx = context.layerBounds.right
            val scroll = context.scroll

            hours.forEachIndexed { i, hr ->
                // Same filtering HourTickPlacer applies
                if (i == 0 || (i - 1) % labelStep != 0) {
                    return@forEachIndexed
                }

                val domainΔ = (xIndices[i] - minX) / xStep
                val gridPx = leftPx + domainΔ * stepPx - scroll

                // Bounding check (skip if the label would clip)
                val text = "%02d".format(hr)
                val width = label.getWidth(context, text)
                val xEnd = gridPx + gapPx
                val xStart = xEnd - width

                if (xStart < leftPx || xEnd > rightPx) {
                    return@forEachIndexed
                }

                label.draw(
                    context = context,
                    text = text,
                    x = xEnd.toFloat(),
                    y = y,
                    horizontalPosition = Position.Horizontal.End,
                    verticalPosition = Position.Vertical.Bottom,
                )
            }
        }
    }
}

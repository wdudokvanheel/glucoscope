package com.bitechular.glucoscope

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.patrykandpatrick.vico.compose.common.shader.verticalGradient
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TileMode
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
import com.patrykandpatrick.vico.core.cartesian.Zoom
import com.patrykandpatrick.vico.core.cartesian.axis.HorizontalAxis
import com.patrykandpatrick.vico.core.cartesian.axis.VerticalAxis
import com.patrykandpatrick.vico.core.cartesian.data.CartesianChartModelProducer
import com.patrykandpatrick.vico.core.cartesian.data.lineSeries
import com.patrykandpatrick.vico.core.cartesian.layer.LineCartesianLayer
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.roundToInt
import com.patrykandpatrick.vico.compose.cartesian.layer.rememberLine
import com.patrykandpatrick.vico.compose.common.fill
import com.patrykandpatrick.vico.core.common.shader.ShaderProvider

private val RED = Color(0xFFFF006E)
private val GREEN = Color(0xFF00C853)
private val YELLOW = Color(0xFFFFD600)

@Composable
fun Graph(
    measurements: List<GlucoseMeasurement>,
    rangeLow: Double = 2.5,
    rangeHigh: Double = 20.0,
    modifier: Modifier = Modifier
) {

    if (measurements.isEmpty()) {
        Text("No measurements yet", modifier.fillMaxSize())
        return
    }

    require(rangeLow > 0 && rangeHigh > rangeLow) { "Both bounds must be > 0 and low < high." }

    /* -------- data into the model -------- */
    val producer = remember { CartesianChartModelProducer() }
    LaunchedEffect(measurements) {
        producer.runTransaction {
            lineSeries {
                val xs = measurements.indices.map(Int::toDouble)
                val ys = measurements.map { log10(it.value) }   // LOG TRANSFORM
                series(x = xs, y = ys)
            }
        }
    }

    val minLog = log10(rangeLow)
    val maxLog = log10(rangeHigh)

    val diffLog = maxLog - minLog
    fun stop(threshold: Double) =
        ((log10(threshold) - minLog) / diffLog)
            .toFloat()
            .coerceIn(0f, 1f)

    val gradient = remember(minLog, maxLog) {
        ShaderProvider.Companion.verticalGradient(
            colors = arrayOf(
                RED, RED,          // < 4 mmol/L  → red
                GREEN, GREEN,      // 4–7         → green
                YELLOW,            // 7–10        → yellow → red
                RED, RED           // > 10        → red
            ),
            positions = floatArrayOf(
                0f,
                stop(4.0), stop(4.0),
                stop(7.0), stop(7.0),
                stop(10.0), 1f
            )
        )
    }

    val rangeProvider = remember(minLog, maxLog) {
        FixedLogRangeProvider(minLog, maxLog)
    }

    val colouredLine = LineCartesianLayer.rememberLine(
        // stroke thickness etc.
        stroke = LineCartesianLayer.LineStroke.continuous(thickness = 2.dp),
        // gradient fill – `fill()` converts the ShaderProvider for you
        fill = LineCartesianLayer.LineFill.single(fill(gradient)),
    )

    val lineProvider = LineCartesianLayer.LineProvider.series(listOf(colouredLine))

    /* keep your fixed range provider, nothing changes there */
    val lineLayer = rememberLineCartesianLayer(
        lineProvider = lineProvider,
        rangeProvider = rangeProvider          // ← your FixedLogRangeProvider
    )


    val tickInts = (ceil(rangeLow).toInt()..floor(rangeHigh).toInt())
    val tickLogs = tickInts.map { log10(it.toDouble()) }
    val endAxis = VerticalAxis.rememberEnd(
        itemPlacer = remember(tickLogs) { WholeNumberLogPlacer(tickLogs) },
        valueFormatter = { _, v, _ -> 10.0.pow(v).roundToInt().toString() },
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
        lineLayer,                       // ← use the existing layer
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
        zoomState = zoomState,         // unchanged
        modifier = modifier.fillMaxSize()
    )
}
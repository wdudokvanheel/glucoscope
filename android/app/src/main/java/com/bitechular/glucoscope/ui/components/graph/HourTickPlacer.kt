package com.bitechular.glucoscope.ui.components.graph

import com.patrykandpatrick.vico.core.cartesian.CartesianDrawingContext
import com.patrykandpatrick.vico.core.cartesian.CartesianMeasuringContext
import com.patrykandpatrick.vico.core.cartesian.axis.HorizontalAxis
import com.patrykandpatrick.vico.core.cartesian.layer.CartesianLayerDimensions

class HourTickPlacer(
    private val hourXs: List<Double>,   // x-indices whose minute == 0
    private val labelStep: Int = 1,
) : HorizontalAxis.ItemPlacer {

    private fun ticksIn(r: ClosedFloatingPointRange<Double>) =
        hourXs.dropWhile { it < r.start }.takeWhile { it <= r.endInclusive }

    private fun labelsIn(r: ClosedFloatingPointRange<Double>): List<Double> {
        val t = ticksIn(r)
        return if (t.isNotEmpty()) t.filterIndexed { i, _ -> i % labelStep == 0 }
        else listOf(r.start)                    // fallback label
    }

    override fun getLineValues(
        context: CartesianDrawingContext,
        visibleXRange: ClosedFloatingPointRange<Double>,
        fullXRange: ClosedFloatingPointRange<Double>,
        maxLabelWidth: Float,
    ) = ticksIn(visibleXRange)

    override fun getLabelValues(
        context: CartesianDrawingContext,
        visibleXRange: ClosedFloatingPointRange<Double>,
        fullXRange: ClosedFloatingPointRange<Double>,
        maxLabelWidth: Float,
    ) = labelsIn(visibleXRange)

    /* — measurement-time: ALWAYS return ≥1 label — */
    override fun getHeightMeasurementLabelValues(
        context: CartesianMeasuringContext,
        layerDimensions: CartesianLayerDimensions,
        fullXRange: ClosedFloatingPointRange<Double>,
        maxLabelWidth: Float,
    ) = labelsIn(fullXRange)                    // never empty

    override fun getWidthMeasurementLabelValues(
        context: CartesianMeasuringContext,
        layerDimensions: CartesianLayerDimensions,
        fullXRange: ClosedFloatingPointRange<Double>,
    ): List<Double> {
        val all = hourXs.filterIndexed { i, _ -> i % labelStep == 0 }
        return all.ifEmpty { listOf(fullXRange.start) }  // ≥1
    }

    /* margins & top-tick shift */
    override fun getStartLayerMargin(context: CartesianMeasuringContext, layerDimensions: CartesianLayerDimensions, tickThickness: Float, maxLabelWidth: Float) = 0f
    override fun getEndLayerMargin  (context: CartesianMeasuringContext, layerDimensions: CartesianLayerDimensions, tickThickness: Float, maxLabelWidth: Float) = 0f
}

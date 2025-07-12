package com.bitechular.glucoscope.ui.components.graph

import com.patrykandpatrick.vico.core.cartesian.CartesianDrawingContext
import com.patrykandpatrick.vico.core.cartesian.CartesianMeasuringContext
import com.patrykandpatrick.vico.core.cartesian.axis.HorizontalAxis
import com.patrykandpatrick.vico.core.cartesian.layer.CartesianLayerDimensions

class HourTickPlacer(
    private val hourXs: List<Double>,
    private val labelStep: Int = 1,
) : HorizontalAxis.ItemPlacer {
    private val firstTick = hourXs.firstOrNull()

    private fun ticksIn(r: ClosedFloatingPointRange<Double>) =
        hourXs.dropWhile { it < r.start }.takeWhile { it <= r.endInclusive }

    private fun labelsIn(r: ClosedFloatingPointRange<Double>) =
        ticksIn(r)
            .filterIndexed { i, _ -> i % labelStep == 0 }
            .filterNot { it == firstTick }

    override fun getLineValues(
        context: CartesianDrawingContext,
        visibleXRange: ClosedFloatingPointRange<Double>,
        fullXRange: ClosedFloatingPointRange<Double>,
        maxLabelWidth: Float,
    ) = labelsIn(visibleXRange)

    override fun getLabelValues(
        context: CartesianDrawingContext,
        visibleXRange: ClosedFloatingPointRange<Double>,
        fullXRange: ClosedFloatingPointRange<Double>,
        maxLabelWidth: Float,
    ) = labelsIn(visibleXRange)

    override fun getHeightMeasurementLabelValues(
        context: CartesianMeasuringContext,
        layerDimensions: CartesianLayerDimensions,
        fullXRange: ClosedFloatingPointRange<Double>,
        maxLabelWidth: Float,
    ) = labelsIn(fullXRange)

    override fun getWidthMeasurementLabelValues(
        context: CartesianMeasuringContext,
        layerDimensions: CartesianLayerDimensions,
        fullXRange: ClosedFloatingPointRange<Double>,
    ): List<Double> {
        val all = hourXs.filterIndexed { i, _ -> i % labelStep == 0 }
        return all.ifEmpty { listOf(fullXRange.start) }
    }

    override fun getStartLayerMargin(context: CartesianMeasuringContext, layerDimensions: CartesianLayerDimensions, tickThickness: Float, maxLabelWidth: Float) = 0f
    override fun getEndLayerMargin  (context: CartesianMeasuringContext, layerDimensions: CartesianLayerDimensions, tickThickness: Float, maxLabelWidth: Float) = 0f
}

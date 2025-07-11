package com.bitechular.glucoscope

import com.patrykandpatrick.vico.core.cartesian.CartesianDrawingContext
import com.patrykandpatrick.vico.core.cartesian.CartesianMeasuringContext
import com.patrykandpatrick.vico.core.cartesian.axis.HorizontalAxis
import com.patrykandpatrick.vico.core.cartesian.layer.CartesianLayerDimensions

/**
 * Places a grid/tick at *every* hour and a label at every `labelStep`-th hour.
 *
 * @param ptsPerHour  number of data points that fall into one hour (12 when you sample every 5 min).
 * @param labelStep   how many ticks you skip between labels (2 = every other label).
 */
class HourItemPlacer(
    private val ptsPerHour: Int,
    private val labelStep: Int = 2,
) : HorizontalAxis.ItemPlacer {

    private fun ticks(lastX: Int) =
        (0..lastX step ptsPerHour).map(Int::toDouble)

    private fun labels(lastX: Int) =
        (0..lastX step ptsPerHour * labelStep).map(Int::toDouble)

    // ───────── values used at draw-time ─────────
    override fun getLineValues(
        context: CartesianDrawingContext,
        visibleXRange: ClosedFloatingPointRange<Double>,
        fullXRange: ClosedFloatingPointRange<Double>,
        maxLabelWidth: Float
    ): List<Double>? = ticks(context.layerBounds.right.toInt())

    override fun getStartLayerMargin(
        context: CartesianMeasuringContext,
        layerDimensions: CartesianLayerDimensions,
        tickThickness: Float,
        maxLabelWidth: Float
    ): Float = 0f

    override fun getEndLayerMargin(
        context: CartesianMeasuringContext,
        layerDimensions: CartesianLayerDimensions,
        tickThickness: Float,
        maxLabelWidth: Float
    ): Float = 0f

    override fun getLabelValues(
        context: CartesianDrawingContext,
        visibleXRange: ClosedFloatingPointRange<Double>,
        fullXRange: ClosedFloatingPointRange<Double>,
        maxLabelWidth: Float
    ): List<Double> = labels(context.layerBounds.right.toInt())

    // ───────── values used during measurement ─────────
    override fun getHeightMeasurementLabelValues(
        context: CartesianMeasuringContext,
        layerDimensions: CartesianLayerDimensions,
        fullXRange: ClosedFloatingPointRange<Double>,
        maxLabelWidth: Float
    ): List<Double> = labels(context.ranges.maxX.toInt())

    override fun getWidthMeasurementLabelValues(
        context: CartesianMeasuringContext,
        layerDimensions: CartesianLayerDimensions,
        fullXRange: ClosedFloatingPointRange<Double>
    ): List<Double> = labels(context.ranges.maxX.toInt())
}

package com.bitechular.glucoscope

import com.patrykandpatrick.vico.core.cartesian.CartesianDrawingContext
import com.patrykandpatrick.vico.core.cartesian.CartesianMeasuringContext
import com.patrykandpatrick.vico.core.cartesian.axis.HorizontalAxis
import com.patrykandpatrick.vico.core.cartesian.layer.CartesianLayerDimensions

class HourTickPlacer(
    private val hourXs: List<Double>,   // x-indices whose minute == 0
    private val labelStep: Int = 1,     // 2 = every other label
) : HorizontalAxis.ItemPlacer {

    /* — helpers — */
    private fun ticksIn(r: ClosedFloatingPointRange<Double>) =
        hourXs.dropWhile { it < r.start }.takeWhile { it <= r.endInclusive }

    private fun labelsIn(r: ClosedFloatingPointRange<Double>): List<Double> {
        val t = ticksIn(r)
        return if (t.isNotEmpty()) t.filterIndexed { i, _ -> i % labelStep == 0 }
        else listOf(r.start)                    // fallback label
    }

    /* — draw-time — */
    override fun getLineValues(
        ctx: CartesianDrawingContext,
        visibleXRange: ClosedFloatingPointRange<Double>,
        fullXRange: ClosedFloatingPointRange<Double>,
        maxLabelWidth: Float,
    ) = ticksIn(visibleXRange)

    override fun getLabelValues(
        ctx: CartesianDrawingContext,
        visibleXRange: ClosedFloatingPointRange<Double>,
        fullXRange: ClosedFloatingPointRange<Double>,
        maxLabelWidth: Float,
    ) = labelsIn(visibleXRange)

    /* — measurement-time: ALWAYS return ≥1 label — */
    override fun getHeightMeasurementLabelValues(
        ctx: CartesianMeasuringContext,
        dims: CartesianLayerDimensions,
        fullXRange: ClosedFloatingPointRange<Double>,
        maxLabelWidth: Float,
    ) = labelsIn(fullXRange)                    // never empty

    override fun getWidthMeasurementLabelValues(
        ctx: CartesianMeasuringContext,
        dims: CartesianLayerDimensions,
        fullXRange: ClosedFloatingPointRange<Double>,
    ): List<Double> {
        val all = hourXs.filterIndexed { i, _ -> i % labelStep == 0 }
        return if (all.isNotEmpty()) all else listOf(fullXRange.start)  // ≥1
    }

    /* margins & top-tick shift */
    override fun getStartLayerMargin(ctx: CartesianMeasuringContext, dims: CartesianLayerDimensions, t: Float, m: Float) = 0f
    override fun getEndLayerMargin  (ctx: CartesianMeasuringContext, dims: CartesianLayerDimensions, t: Float, m: Float) = 0f
}

package com.bitechular.glucoscope

import com.patrykandpatrick.vico.core.cartesian.CartesianDrawingContext
import com.patrykandpatrick.vico.core.cartesian.CartesianMeasuringContext
import com.patrykandpatrick.vico.core.cartesian.axis.Axis
import com.patrykandpatrick.vico.core.cartesian.axis.VerticalAxis
import com.patrykandpatrick.vico.core.common.Position

class WholeNumberLogPlacer(
    private val ticks: List<Double>,
) : VerticalAxis.ItemPlacer {

    /* – label & guideline positions – */
    private fun all() = ticks
    override fun getLabelValues(
        ctx: CartesianDrawingContext,
        h: Float,
        m: Float,
        p: Axis.Position.Vertical
    ) = all()

    override fun getLineValues(
        ctx: CartesianDrawingContext,
        h: Float,
        m: Float,
        p: Axis.Position.Vertical
    ) = all()

    override fun getHeightMeasurementLabelValues(
        ctx: CartesianMeasuringContext,
        p: Axis.Position.Vertical
    ) = all()

    override fun getWidthMeasurementLabelValues(
        ctx: CartesianMeasuringContext,
        h: Float,
        m: Float,
        p: Axis.Position.Vertical
    ) = all()

    /* – **DON’T** shift the top tick out of view – */
    override fun getShiftTopLines(ctx: CartesianDrawingContext) = false

    /* – no extra margins – */
    override fun getBottomLayerMargin(
        ctx: CartesianMeasuringContext,
        vp: Position.Vertical,
        m: Float,
        t: Float
    ) = 0f

    override fun getTopLayerMargin(
        ctx: CartesianMeasuringContext,
        vp: Position.Vertical,
        m: Float,
        t: Float
    ) = 0f
}
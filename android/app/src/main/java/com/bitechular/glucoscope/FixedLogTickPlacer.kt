package com.bitechular.glucoscope

import com.patrykandpatrick.vico.core.cartesian.CartesianDrawingContext
import com.patrykandpatrick.vico.core.cartesian.CartesianMeasuringContext
import com.patrykandpatrick.vico.core.cartesian.axis.Axis
import com.patrykandpatrick.vico.core.cartesian.axis.VerticalAxis
import com.patrykandpatrick.vico.core.common.Position

class FixedLogTickPlacer(private val ticks: List<Double>) : VerticalAxis.ItemPlacer {
    private fun v() = ticks
    override fun getLabelValues(
        context: CartesianDrawingContext,
        axisHeight: Float,
        maxLabelHeight: Float,
        position: Axis.Position.Vertical
    ) = v()

    override fun getLineValues(
        context: CartesianDrawingContext,
        axisHeight: Float,
        maxLabelHeight: Float,
        position: Axis.Position.Vertical
    ) = v()

    override fun getHeightMeasurementLabelValues(
        context: CartesianMeasuringContext,
        position: Axis.Position.Vertical
    ) = v()

    override fun getWidthMeasurementLabelValues(
        context: CartesianMeasuringContext,
        axisHeight: Float,
        maxLabelHeight: Float,
        position: Axis.Position.Vertical
    ) = v()

    override fun getShiftTopLines(context: CartesianDrawingContext) = false

    override fun getBottomLayerMargin(
        context: CartesianMeasuringContext,
        verticalLabelPosition: Position.Vertical,
        maxLabelHeight: Float,
        maxLineThickness: Float
    ): Float = 0f

    override fun getTopLayerMargin(
        context: CartesianMeasuringContext,
        verticalLabelPosition: Position.Vertical,
        maxLabelHeight: Float,
        maxLineThickness: Float
    ) = 0f
}
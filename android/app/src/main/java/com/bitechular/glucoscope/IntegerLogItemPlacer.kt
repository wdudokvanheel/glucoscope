package com.bitechular.glucoscope

import com.patrykandpatrick.vico.core.cartesian.CartesianDrawingContext
import com.patrykandpatrick.vico.core.cartesian.CartesianMeasuringContext
import com.patrykandpatrick.vico.core.cartesian.axis.Axis
import com.patrykandpatrick.vico.core.cartesian.axis.VerticalAxis
import com.patrykandpatrick.vico.core.common.Position
import kotlin.math.log10

class IntegerLogItemPlacer(
    min: Int,
    max: Int
) : VerticalAxis.ItemPlacer {

    private val ticks = (min..max).map { log10(it.toDouble()) }

    /*— helper used by several overrides —*/
    private fun tickValues() = ticks

    // ───────────────────────────────────
    // • label & guideline positions
    // ───────────────────────────────────
    override fun getLabelValues(
        context: CartesianDrawingContext,
        axisHeight: Float,
        maxLabelHeight: Float,
        position: Axis.Position.Vertical
    ): List<Double> = tickValues()

    override fun getLineValues(
        context: CartesianDrawingContext,
        axisHeight: Float,
        maxLabelHeight: Float,
        position: Axis.Position.Vertical
    ): List<Double>? = tickValues()

    // ───────────────────────────────────
    // • measuring-phase helpers
    // ───────────────────────────────────
    override fun getHeightMeasurementLabelValues(
        context: CartesianMeasuringContext,
        position: Axis.Position.Vertical
    ): List<Double> = tickValues()

    override fun getWidthMeasurementLabelValues(
        context: CartesianMeasuringContext,
        axisHeight: Float,
        maxLabelHeight: Float,
        position: Axis.Position.Vertical
    ): List<Double> = tickValues()

    // ───────────────────────────────────
    // • margins & top-tick shift
    // ───────────────────────────────────
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

    override fun getShiftTopLines(context: CartesianDrawingContext) = true
}
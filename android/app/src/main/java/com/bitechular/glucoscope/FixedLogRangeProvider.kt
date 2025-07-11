package com.bitechular.glucoscope

import com.patrykandpatrick.vico.core.cartesian.data.CartesianLayerRangeProvider
import com.patrykandpatrick.vico.core.common.data.ExtraStore

class FixedLogRangeProvider(
    private val minLog: Double,
    private val maxLog: Double,
) : CartesianLayerRangeProvider {

    override fun getMinY(minY: Double, maxY: Double, extraStore: ExtraStore) = minLog
    override fun getMaxY(minY: Double, maxY: Double, extraStore: ExtraStore) = maxLog

    // leave X-range untouched
    override fun getMinX(minX: Double, maxX: Double, extraStore: ExtraStore) = minX
    override fun getMaxX(minX: Double, maxX: Double, extraStore: ExtraStore) = maxX
}

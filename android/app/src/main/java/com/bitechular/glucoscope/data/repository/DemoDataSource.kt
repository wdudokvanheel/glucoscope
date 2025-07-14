package com.bitechular.glucoscope.data.repository

import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.random.Random

class DemoDataSource : DataSource {
    private object C {
        const val historyHours = 24
        const val baseInterval = 90.0
        const val noiseAmp = 0.6
        const val spikeChance = 0.06
        const val spikeAmp = 3.0
        const val minG = 3.0
        const val maxG = 14.5
        const val inertia = 0.8
    }

    private val measurements = mutableListOf<GlucoseMeasurement>()
    private var lastValue = 6.5

    init {
        generateInitial()
    }

    override suspend fun testConnection() = true

    override suspend fun getLatestEntries(hours: Int, window: Int): List<GlucoseMeasurement> {
        update()
        val cutoff = (System.currentTimeMillis() / 1000.0) - hours * 3600
        val recent = measurements.filter { it.time >= cutoff }
        return if (window > 1) aggregate(recent, window) else recent
    }

    private fun generateInitial() {
        val now = System.currentTimeMillis() / 1000.0
        val start = now - C.baseInterval * C.historyHours * 60
        var t = start
        while (t <= now) {
            measurements.add(GlucoseMeasurement(t, gen(now, t)))
            t += C.baseInterval
        }
    }

    private fun update() {
        if (measurements.isEmpty()) return
        var lastT = measurements.last().time
        val now = System.currentTimeMillis() / 1000.0
        while (lastT + C.baseInterval <= now) {
            lastT += C.baseInterval
            measurements.add(GlucoseMeasurement(lastT, gen(now, lastT)))
        }
        val cutoff = now - C.historyHours * 3600
        val idx = measurements.indexOfFirst { it.time >= cutoff }
        if (idx > 0) repeat(idx) { measurements.removeAt(0) }
    }

    private fun gen(now: Double, pointTime: Double): Double {
        val age = now - pointTime
        val window = 9 * 3600.0
        val t = max(0.0, min(1.0, (window - age) / window))
        val baseline = 5.5
        val peak = 12.0
        val valley = 3.0
        val target = when (t) {
            in 0.0..0.2 -> {
                val p = (t - 0.0) / 0.2
                baseline - (baseline - valley) * (1 - cos(p * PI)) / 2
            }

            in 0.2..0.35 -> {
                val p = (t - 0.2) / 0.15
                baseline + (peak - baseline) * p.pow(0.6)
            }

            in 0.35..0.65 -> peak + Random.nextDouble(-0.3, 0.3)
            in 0.65..0.85 -> {
                val p = (t - 0.65) / 0.2
                peak - (peak - baseline) * p.pow(1.2)
            }

            else -> baseline
        }
        var value = lastValue + (target - lastValue) * C.inertia
        value += Random.nextDouble(-C.noiseAmp, C.noiseAmp)
        if (Random.nextDouble() < C.spikeChance) value += Random.nextDouble(-C.spikeAmp, C.spikeAmp)
        value = min(max(value, C.minG), C.maxG)
        lastValue = value
        return value
    }

    private fun aggregate(data: List<GlucoseMeasurement>, window: Int): List<GlucoseMeasurement> {
        val out = mutableListOf<GlucoseMeasurement>()
        var i = 0
        while (i < data.size) {
            val slice = data.subList(i, min(i + window, data.size))
            val avgV = slice.sumOf { it.value } / slice.size
            val avgT = slice.sumOf { it.time } / slice.size
            out.add(GlucoseMeasurement(avgT, avgV))
            i += window
        }
        return out
    }
}
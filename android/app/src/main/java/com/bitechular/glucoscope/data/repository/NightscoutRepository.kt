package com.bitechular.glucoscope.data.repository

import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import com.bitechular.glucoscope.data.model.NightscoutRepositoryConfiguration
import com.bitechular.glucoscope.data.model.toMmol
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.math.roundToLong

class NightscoutRepository(
    private val configuration: NightscoutRepositoryConfiguration
) : DataSourceRepository {

    /* ---------- shared infra ---------- */

    private val client = OkHttpClient.Builder()
        .callTimeout(15, TimeUnit.SECONDS)
        .build()

    private val json = Json { ignoreUnknownKeys = true }

    private val baseUrl: String
        get() = if (!configuration.url.lowercase().startsWith("http")) {
            "https://${configuration.url}"
        } else {
            configuration.url
        }


    /**
     * GET {baseUrl}/api/v1/status.json[?token=…]
     * Returns true when `status == "ok"`.
     */
    override suspend fun testConnection(): Boolean = withContext(Dispatchers.IO) {
        // Build `/api/v1/status.json`
        val httpUrlBuilder = "$baseUrl/api/v1/status.json".toHttpUrl().newBuilder()
        configuration.apiToken?.let { httpUrlBuilder.addQueryParameter("token", it) }
        val request = makeRequest(httpUrlBuilder.build().toString())

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) return@withContext false
            val body = response.body?.string() ?: return@withContext false
            json.decodeFromString<NightscoutStatusReplyDto>(body).status.lowercase() == "ok"
        }
    }

    /**
     * GET {baseUrl}/api/v1/entries.json?find[date][gte]=…&count=…[&token=…]
     *
     * Nightscout always returns 1-minute records.
     * If `window > 1` we aggregate into `window`-minute buckets; otherwise we return the
     * original points ordered oldest-to-newest (Nightscout sends newest first).
     */
    override suspend fun getLatestEntries(hours: Int, window: Int): List<GlucoseMeasurement> =
        withContext(Dispatchers.IO) {
            val nowMillis = System.currentTimeMillis()
            val pastMillis = nowMillis - hours * 60L * 60 * 1000   // hours ago
            val count = hours * 60                                  // max rows Nightscout will send

            val httpUrlBuilder = "$baseUrl/api/v1/entries.json".toHttpUrl().newBuilder()
                .addQueryParameter("find[date][\$gte]", pastMillis.toString())
                .addQueryParameter("count", count.toString())

            configuration.apiToken?.let { httpUrlBuilder.addQueryParameter("token", it) }

            val request = makeRequest(httpUrlBuilder.build().toString())

            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    throw IOException("Unexpected HTTP ${response.code}")
                }
                val body = response.body?.string() ?: throw IOException("Empty body")
                val entries: List<NightscoutEntryDto> = json.decodeFromString(body)

                if (window > 1) {
                    groupEntriesIntoIntervals(entries, window)
                } else {
                    // Nightscout sends newest-first; reverse to ascending
                    entries.asReversed().map { it.toGlucoseMeasurement() }
                }
            }
        }

    /* ---------- helpers -------------------------------------------------- */

    private fun makeRequest(url: String): Request {
        val builder = Request.Builder().url(url)
        // Nightscout uses token query param, *not* Authorization header,
        // but we keep this here for parity / future proofing.
        configuration.apiToken?.trim()?.takeIf { it.isNotEmpty() }?.let {
            builder.header("Authorization", "Bearer $it")
        }
        return builder.build()
    }

    /**
     * Aggregates raw 1-minute Nightscout readings into `window`-minute buckets
     * using an arithmetic mean on glucose and timestamp.
     */
    private fun groupEntriesIntoIntervals(
        entries: List<NightscoutEntryDto>,
        window: Int
    ): List<GlucoseMeasurement> {
        val intervalMillis = window * 60L * 1000
        val buckets = entries.groupBy { (it.date / intervalMillis).toInt() }

        return buckets.values.map { bucket ->
            val avgSgv = bucket.sumOf { it.sgv } / bucket.size
            val avgDate = bucket.sumOf { it.date } / bucket.size
            GlucoseMeasurement(time = avgDate / 1000.0, value = avgSgv.toMmol())
        }.sortedBy { it.time }
    }

    /* ---------- DTOs / extensions ---------------------------------------- */

    @Serializable
    private data class NightscoutStatusReplyDto(val status: String)

    @Serializable
    private data class NightscoutEntryDto(
        val sgv: Double, // mg/dL
        val date: Long   // epoch ms
    ) {
        fun toGlucoseMeasurement(): GlucoseMeasurement =
            GlucoseMeasurement(time = date / 1000.0, value = sgv.toMmol())
    }

    /** mg/dL ➜ mmol/L conversion (≈ divide by 18). */
    private fun Double.toMmol(): Double = (this / 18.0 * 1000).roundToLong() / 1000.0
}
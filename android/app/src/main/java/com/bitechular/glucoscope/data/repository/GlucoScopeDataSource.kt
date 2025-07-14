package com.bitechular.glucoscope.data.repository

import com.bitechular.glucoscope.data.model.GlucoseMeasurement
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.util.concurrent.TimeUnit

class GlucoScopeDataSource(
    private val configuration: GlucoScopeDataSourceConfiguration
) : DataSource {

    private val client = OkHttpClient.Builder()
        .callTimeout(15, TimeUnit.SECONDS)
        .build()

    private val json = Json { ignoreUnknownKeys = true }

    private val baseUrl: String
        get() = if (!configuration.url.lowercase().startsWith("http")) {
            "https://${configuration.url}/api/s1"
        } else {
            "${configuration.url}/api/s1"
        }

    override suspend fun testConnection(): Boolean = withContext(Dispatchers.IO) {
        val request = makeRequest("$baseUrl/status")
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) return@withContext false
            val body = response.body?.string() ?: return@withContext false
            json.decodeFromString<GlucoScopeStatusReplyDto>(body).status.lowercase() == "ok"
        }
    }

    override suspend fun getLatestEntries(hours: Int, window: Int): List<GlucoseMeasurement> =
        withContext(Dispatchers.IO) {
            val httpUrl = "$baseUrl/entries/last".toHttpUrl().newBuilder()
                .addQueryParameter("hours", hours.toString())
                .addQueryParameter("window", window.toString())
                .build()
            val request = makeRequest(httpUrl.toString())
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) throw IOException("Unexpected code ${response.code}")
                val body = response.body?.string() ?: throw IOException("Empty body")
                json.decodeFromString(body)
            }
        }

    private fun makeRequest(url: String): Request {
        val builder = Request.Builder().url(url)
        configuration.apiToken?.trim()?.takeIf { it.isNotEmpty() }?.let {
            builder.header("Authorization", "Bearer $it")
        }
        return builder.build()
    }

    @Serializable
    private data class GlucoScopeStatusReplyDto(val status: String)
}
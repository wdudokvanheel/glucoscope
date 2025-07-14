package com.bitechular.glucoscope.preference

import androidx.datastore.core.Serializer
import com.bitechular.glucoscope.preference.dto.GlucoScopePreferencesDto
import kotlinx.serialization.json.Json
import java.io.InputStream
import java.io.OutputStream

object SettingsSerializer : Serializer<GlucoScopePreferencesDto> {
    override val defaultValue = GlucoScopePreferencesDto()

    private val json = Json {
        classDiscriminator = "type"
        encodeDefaults = true
        ignoreUnknownKeys = true
    }

    override suspend fun readFrom(input: InputStream): GlucoScopePreferencesDto =
        try {
            val txt = input.readBytes().decodeToString()
            println("Loaded settings: $txt")
            Json.decodeFromString(
                GlucoScopePreferencesDto.serializer(),
                txt
            )
        } catch (e: Exception) {
            defaultValue
        }


    override suspend fun writeTo(t: GlucoScopePreferencesDto, output: OutputStream) {
        val serialized = json.encodeToString(GlucoScopePreferencesDto.serializer(), t)
        println("Writing settings: $serialized")
        output.write(serialized.encodeToByteArray())
    }
}
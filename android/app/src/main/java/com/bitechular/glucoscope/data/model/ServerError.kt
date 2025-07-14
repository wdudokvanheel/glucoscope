package com.bitechular.glucoscope.data.model

import java.io.IOException

sealed class ServerError(message: String) : IOException(message) {
    object Unauthorized : ServerError("401 / 403 – unauthorized")
    object NotFound     : ServerError("404 – not found")
    data class Server(val code: Int) : ServerError("HTTP $code")
}

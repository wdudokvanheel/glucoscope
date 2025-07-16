package com.bitechular.glucoscope

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class GlucoScopeApplication : Application() {

    companion object {
        const val APP_NAME     = "GlucoScope"
        const val URL_LICENSE  = "https://wdudokvanheel.github.io/glucoscope/license.html"
        const val URL_PRIVACY  = "https://wdudokvanheel.github.io/glucoscope/privacy.html"
        const val URL_SOURCE   = "https://github.com/wdudokvanheel/glucoscope/"
    }
}
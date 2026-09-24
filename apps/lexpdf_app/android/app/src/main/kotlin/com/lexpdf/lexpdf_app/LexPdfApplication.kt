package com.lexpdf.lexpdf_app

import android.app.Application

class LexPdfApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        PdfCrashDiagnostics.installUncaughtExceptionCapture(this)
    }
}

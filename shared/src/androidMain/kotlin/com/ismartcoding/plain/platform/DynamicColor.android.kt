package com.ismartcoding.plain.platform

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext

@Composable
actual fun rememberDynamicColorScheme(useDarkTheme: Boolean): ColorScheme? {
    if (!isSPlus()) return null
    val context = LocalContext.current
    return remember(useDarkTheme, context) {
        if (useDarkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
    }
}

actual fun isDynamicColorAvailable(): Boolean = isSPlus()

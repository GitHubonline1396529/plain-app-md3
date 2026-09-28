package com.ismartcoding.plain.platform

import androidx.compose.material3.ColorScheme
import androidx.compose.runtime.Composable

@Composable
actual fun rememberDynamicColorScheme(useDarkTheme: Boolean): ColorScheme? = null

actual fun isDynamicColorAvailable(): Boolean = false

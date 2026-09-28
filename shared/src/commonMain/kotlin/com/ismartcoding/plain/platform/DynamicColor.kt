package com.ismartcoding.plain.platform

import androidx.compose.material3.ColorScheme
import androidx.compose.runtime.Composable

/**
 * Material You dynamic color scheme sourced from the system wallpaper.
 *
 * Returns null when the platform cannot provide one (iOS, or Android < 12),
 * so callers fall back to the fixed brand schemes.
 */
@Composable
expect fun rememberDynamicColorScheme(useDarkTheme: Boolean): ColorScheme?

/** True when the platform supports Material You dynamic color. */
expect fun isDynamicColorAvailable(): Boolean

package com.ismartcoding.plain.preferences

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.remember
import com.ismartcoding.plain.data.DUpdateInfo
import com.ismartcoding.plain.platform.Locale
import kotlinx.coroutines.flow.map

data class Settings(
    val darkTheme: Int,
    val amoledDarkTheme: Boolean,
    val dynamicColor: Boolean,
    val pdfFollowDarkTheme: Boolean,
    val locale: Locale?,
    val updateInfo: DUpdateInfo,
)

val LocalLocale = compositionLocalOf<Locale?> { null }

@Composable
fun SettingsProvider(onLoaded: () -> Unit = {}, content: @Composable () -> Unit) {
    val defaultSettings = Settings(
        darkTheme = DarkThemePreference.default,
        amoledDarkTheme = AmoledDarkThemePreference.default,
        dynamicColor = DynamicColorPreference.default,
        pdfFollowDarkTheme = PdfFollowDarkThemePreference.default,
        locale = null,
        updateInfo = DUpdateInfo(),
    )
    // Null initial distinguishes "store not read yet" from "read and equals the
    // default": callers (e.g. MainActivity) keep the splash on screen until the
    // real theme preference is known, so the first visible frame is correct.
    val settingsState = remember {
        appDataStore.dataFlow.map {
            Settings(
                darkTheme = DarkThemePreference.get(it),
                amoledDarkTheme = AmoledDarkThemePreference.get(it),
                dynamicColor = DynamicColorPreference.get(it),
                pdfFollowDarkTheme = PdfFollowDarkThemePreference.get(it),
                locale = LanguagePreference.getLocale(it),
                updateInfo = UpdateInfoPreference.getValue(it),
            )
        }
    }.collectAsState(initial = null as Settings?)
    val settings = settingsState.value ?: defaultSettings
    val loaded = settingsState.value != null
    LaunchedEffect(loaded) { if (loaded) onLoaded() }

    CompositionLocalProvider(
        LocalDarkTheme provides settings.darkTheme,
        LocalAmoledDarkTheme provides settings.amoledDarkTheme,
        LocalDynamicColor provides settings.dynamicColor,
        LocalPdfFollowDarkTheme provides settings.pdfFollowDarkTheme,
        LocalLocale provides settings.locale,
        LocalUpdateInfo provides settings.updateInfo,
        LocalNewVersion provides settings.updateInfo.newVersion,
        LocalSkipVersion provides settings.updateInfo.skipVersion,
        LocalNewVersionPublishDate provides settings.updateInfo.publishDate,
        LocalNewVersionLog provides settings.updateInfo.log,
        LocalNewVersionSize provides settings.updateInfo.size,
        LocalAutoCheckUpdate provides settings.updateInfo.autoCheckUpdate,
    ) {
        content()
    }
}
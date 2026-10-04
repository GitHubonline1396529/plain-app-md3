package com.ismartcoding.plain

object Constants {
    const val SSL_NAME = "Plain"
    const val DATABASE_NAME = "plain.db"
    const val NOTIFICATION_CHANNEL_ID = "default"
    const val CHAT_NOTIFICATION_CHANNEL_ID = "peer_chat"
    const val MAX_READABLE_TEXT_FILE_SIZE = 10 * 1024 * 1024 // 10 MB
    const val SUPPORT_EMAIL = "support@plainapp.app"
    // Fork divergence: point at this fork's own releases. Upstream's URL makes
    // the updater offer an APK signed with upstream's key, which cannot install
    // over this build (same applicationId, different signature) - the user
    // downloads ~60 MB and then fails at install time.
    // Known limitation: upstream's Version parser reads only three numeric
    // components, so "3.3.25-md3.2" parses as 3.3.0. Consequence: this fork
    // will not be told about later -md3.N releases. Harmless, just no notice.
    const val LATEST_RELEASE_URL = "https://api.github.com/repos/GitHubonline1396529/plain-app-md3/releases/latest"
    const val ONE_DAY = 24 * 60 * 60L
    const val ONE_DAY_MS = ONE_DAY * 1000L
    const val KEY_STORE_FILE_NAME = "keystore.bks"
    const val MAX_MESSAGE_LENGTH = 2048
    const val TEXT_FILE_SUMMARY_LENGTH = 250
    const val EXTRA_MEDIA_PATH = "media_path"
}

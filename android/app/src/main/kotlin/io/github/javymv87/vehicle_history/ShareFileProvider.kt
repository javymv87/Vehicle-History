package io.github.javymv87.vehicle_history

import androidx.core.content.FileProvider

/**
 * Serves the copies made by `shareFiles` (`cache/share/`, see
 * `res/xml/share_paths.xml`) to the app the user shares them with.
 *
 * A subclass of its own, so its manifest entry never merges with the
 * provider that `open_filex` declares.
 */
class ShareFileProvider : FileProvider()

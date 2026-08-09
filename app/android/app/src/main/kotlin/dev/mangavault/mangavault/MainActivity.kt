package dev.mangavault.mangavault

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hosts the APK installer channel.
 *
 * Manga Vault is sideloaded from GitHub Releases, so updating means handing an
 * APK to Android's package installer. That needs the per-app "install unknown
 * apps" grant, which the user can only give from Settings — so the channel
 * exposes the *check* and the *route to Settings* alongside the install itself.
 * A plugin that only fired the intent would leave the app unable to tell an
 * ungranted permission apart from a corrupt download.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "dev.mangavault/installer"
        const val APK_MIME = "application/vnd.android.package-archive"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(canRequestInstalls())
                    "openInstallSettings" -> result.success(openInstallSettings())
                    "install" -> install(call.argument<String>("path"), result)
                    else -> result.notImplemented()
                }
            }
    }

    /** Below API 26 the grant is install-time, so it is always effectively held. */
    private fun canRequestInstalls(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        } catch (error: android.content.ActivityNotFoundException) {
            // Some OEM builds hide the per-app screen; the global list is the
            // next best landing spot.
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                true
            } catch (fallbackError: android.content.ActivityNotFoundException) {
                false
            }
        }
    }

    private fun install(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("no_path", "No APK path supplied.", null)
            return
        }
        val apk = File(path)
        if (!apk.exists()) {
            result.error("missing_file", "The downloaded update is gone.", null)
            return
        }
        if (!canRequestInstalls()) {
            result.error("not_permitted", "Install from unknown sources is off.", null)
            return
        }

        // A raw file:// Uri throws FileUriExposedException on API 24+; the
        // installer is a different process, so it needs a content:// Uri it has
        // been granted read access to.
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, APK_MIME)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(intent)
            result.success(true)
        } catch (error: android.content.ActivityNotFoundException) {
            result.error("no_installer", "No package installer on this device.", null)
        }
    }
}

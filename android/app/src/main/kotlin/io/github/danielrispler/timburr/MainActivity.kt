package io.github.danielrispler.timburr

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Hands files shared to Timburr (GPX/TCX) to Dart: `takeShared` returns and clears what arrived at launch, `shared` is pushed when the app is already open. */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: List<Map<String, Any?>> = emptyList()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "timburr/share")
        ch.setMethodCallHandler { call, result ->
            if (call.method == "takeShared") {
                result.success(pending)
                pending = emptyList()
            } else result.notImplemented()
        }
        channel = ch
        pending = read(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val files = read(intent)
        if (files.isNotEmpty()) channel?.invokeMethod("shared", files)
    }

    @Suppress("DEPRECATION")
    private fun read(intent: Intent?): List<Map<String, Any?>> {
        val uris = when (intent?.action) {
            Intent.ACTION_SEND -> listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            Intent.ACTION_SEND_MULTIPLE -> intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            else -> emptyList()
        }
        return uris.mapNotNull { uri ->
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return@mapNotNull null
                var name = uri.lastPathSegment ?: "shared"
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst() && !it.isNull(0)) name = it.getString(0)
                }
                mapOf("name" to name, "bytes" to bytes)
            } catch (e: Exception) {
                Log.w("timburr/share", "could not read $uri", e) // the preview just won't list it
                null
            }
        }
    }
}

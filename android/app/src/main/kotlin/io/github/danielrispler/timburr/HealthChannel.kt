package io.github.danielrispler.timburr

import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * Thin Health Connect reads for Dart (lib/data/health_connect.dart). Read only: Timburr never writes to Health Connect.
 * `status` → available / update / unavailable; `granted` → whether exercise sessions may be read; `request` → the system prompt; `disconnect` → revokes
 * every permission; `sessions(from, to)` → each exercise session with the heart-rate samples, distance and calories its own app wrote during it.
 */
class HealthChannel(private val activity: ComponentActivity) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val exercise = HealthPermission.getReadPermission(ExerciseSessionRecord::class)
    private val heartRate = HealthPermission.getReadPermission(HeartRateRecord::class)
    private val distance = HealthPermission.getReadPermission(DistanceRecord::class)
    private val total = HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class)
    private val active = HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class)
    private val permissions = setOf(exercise, heartRate, distance, total, active)
    private var waiting: MethodChannel.Result? = null

    // Registered while the activity is being constructed, as the activity-result API requires.
    private val launcher: ActivityResultLauncher<Set<String>> =
        activity.registerForActivityResult(PermissionController.createRequestPermissionResultContract()) { granted ->
            waiting?.success(granted.contains(exercise))
            waiting = null
        }

    private val client by lazy { HealthConnectClient.getOrCreate(activity) }

    fun close() = scope.cancel()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(
                when (HealthConnectClient.getSdkStatus(activity)) {
                    HealthConnectClient.SDK_AVAILABLE -> "available"
                    HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "update"
                    else -> "unavailable"
                }
            )
            "granted" -> run(result) { granted().contains(exercise) }
            "request" -> {
                waiting?.success(false) // a prompt already open loses to the new one
                waiting = result
                launcher.launch(permissions)
            }
            "disconnect" -> run(result) { client.permissionController.revokeAllPermissions(); null }
            "sessions" -> run(result) {
                sessions(Instant.ofEpochMilli(call.argument<Long>("from")!!), Instant.ofEpochMilli(call.argument<Long>("to")!!))
            }
            else -> result.notImplemented()
        }
    }

    private fun run(result: MethodChannel.Result, block: suspend () -> Any?) {
        scope.launch {
            try {
                result.success(block())
            } catch (e: Exception) {
                result.error("health_connect", e.toString(), null)
            }
        }
    }

    private suspend fun granted(): Set<String> = client.permissionController.getGrantedPermissions()

    private suspend fun sessions(from: Instant, to: Instant): List<Map<String, Any?>> {
        val granted = granted()
        if (!granted.contains(exercise)) return emptyList()
        val out = mutableListOf<Map<String, Any?>>()
        var token: String? = null
        do {
            val page = client.readRecords(ReadRecordsRequest(ExerciseSessionRecord::class, TimeRangeFilter.between(from, to), pageToken = token))
            for (s in page.records) out.add(session(s, granted))
            token = page.pageToken
        } while (token != null)
        return out
    }

    private suspend fun session(s: ExerciseSessionRecord, granted: Set<String>): Map<String, Any?> {
        val range = TimeRangeFilter.between(s.startTime, s.endTime)
        val origin = setOf(s.metadata.dataOrigin) // only the session's own app: other apps' steps and distance don't belong to it
        val times = mutableListOf<Long>()
        val bpm = mutableListOf<Long>()
        if (granted.contains(heartRate)) {
            var token: String? = null
            do {
                val page = client.readRecords(ReadRecordsRequest(HeartRateRecord::class, range, dataOriginFilter = origin, pageToken = token))
                for (r in page.records) for (sample in r.samples) {
                    if (sample.time < s.startTime || sample.time > s.endTime) continue
                    times.add(sample.time.toEpochMilli())
                    bpm.add(sample.beatsPerMinute)
                }
                token = page.pageToken
            } while (token != null)
        }
        val metrics = buildSet {
            if (granted.contains(distance)) add(DistanceRecord.DISTANCE_TOTAL)
            if (granted.contains(total)) add(TotalCaloriesBurnedRecord.ENERGY_TOTAL)
            if (granted.contains(active)) add(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)
        }
        val totals = if (metrics.isEmpty()) null else client.aggregate(AggregateRequest(metrics, range, origin))
        return mapOf(
            "id" to s.metadata.id,
            "type" to s.exerciseType,
            "start" to s.startTime.toEpochMilli(),
            "end" to s.endTime.toEpochMilli(),
            "distanceM" to totals?.get(DistanceRecord.DISTANCE_TOTAL)?.inMeters,
            "totalKcal" to totals?.get(TotalCaloriesBurnedRecord.ENERGY_TOTAL)?.inKilocalories,
            "activeKcal" to totals?.get(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)?.inKilocalories,
            "hrTimes" to times,
            "hrBpm" to bpm,
        )
    }
}

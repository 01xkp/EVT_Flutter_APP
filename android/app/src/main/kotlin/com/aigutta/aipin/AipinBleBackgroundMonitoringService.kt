package com.aigutta.aipin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * Keeps the process hosting Flutter/RxAndroidBle eligible for long-lived
 * connected-device work while the activity is backgrounded.
 *
 * It deliberately does not create a BluetoothGatt instance. The existing
 * Flutter transport remains the sole owner of the device connection and its
 * Notify/Indicate CCC subscriptions, preventing a duplicate GATT connection.
 */
class AipinBleBackgroundMonitoringService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            actionStart -> {
                val deviceId = intent.getStringExtra(extraDeviceId).orEmpty()
                val deviceName = intent.getStringExtra(extraDeviceName).orEmpty()
                try {
                    startAsForeground(deviceName)
                    markActive()
                    Log.i(logTag, "【后台BLE】前台保活已启动 deviceId=$deviceId deviceName=$deviceName")
                } catch (error: Exception) {
                    markFailed(error)
                    Log.e(
                        logTag,
                        "【后台BLE】前台保活启动失败 type=${error.javaClass.simpleName}",
                        error,
                    )
                    stopSelf(startId)
                }
            }
            else -> {
                markFailed(IllegalArgumentException("unknown_action"))
                Log.w(logTag, "【后台BLE】忽略未知服务动作 action=${intent?.action}")
                stopSelf()
            }
        }
        // This service cannot reconstruct the Flutter-owned GATT session after
        // process death, so a system restart must not advertise a false link.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        // stopService() does not route through onStartCommand(), so foreground
        // cleanup belongs in the service lifecycle callback rather than an
        // otherwise unreachable stop action.
        stopAsForeground()
        markInactiveUnlessFailed()
        Log.i(logTag, "【后台BLE】前台保活服务已销毁")
        super.onDestroy()
    }

    private fun startAsForeground(deviceName: String) {
        val notification = createNotification(deviceName.ifBlank { "AIPIN 设备" })
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                notificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(notificationId, notification)
        }
    }

    private fun stopAsForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun createNotification(deviceName: String): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    notificationChannelId,
                    "AIPIN 蓝牙连接",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "保持已认证设备的蓝牙数据监听"
                    setShowBadge(false)
                },
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentTitle("AIPIN 声存")
            .setContentText("正在保持与 $deviceName 的蓝牙数据连接")
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val logTag = "AIPIN_BLE"
        private const val notificationChannelId = "aipin_ble_background_monitoring"
        private const val notificationId = 41019
        private const val actionStart = "com.aigutta.aipin.action.START_BLE_MONITORING"
        private const val extraDeviceId = "device_id"
        private const val extraDeviceName = "device_name"
        private const val stateInactive = "inactive"
        private const val stateStarting = "starting"
        private const val stateActive = "active"
        private const val stateFailed = "failed"

        @Volatile
        private var monitoringState = stateInactive

        @Volatile
        private var monitoringFailure: String? = null

        fun start(context: Context, deviceId: String, deviceName: String) {
            monitoringState = stateStarting
            monitoringFailure = null
            val intent = Intent(context, AipinBleBackgroundMonitoringService::class.java).apply {
                action = actionStart
                putExtra(extraDeviceId, deviceId)
                putExtra(extraDeviceName, deviceName)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (error: Exception) {
                markFailed(error)
                throw error
            }
        }

        fun stop(context: Context) {
            monitoringState = "stopping"
            context.stopService(Intent(context, AipinBleBackgroundMonitoringService::class.java))
        }

        fun status(): Map<String, Any?> = mapOf(
            "state" to monitoringState,
            "failure" to monitoringFailure,
        )

        private fun markActive() {
            monitoringState = stateActive
            monitoringFailure = null
        }

        private fun markFailed(error: Exception) {
            monitoringState = stateFailed
            monitoringFailure = error.javaClass.simpleName
        }

        private fun markInactiveUnlessFailed() {
            if (monitoringState != stateFailed) {
                monitoringState = stateInactive
                monitoringFailure = null
            }
        }
    }
}

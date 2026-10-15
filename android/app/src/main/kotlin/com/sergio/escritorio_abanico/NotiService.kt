package com.sergio.escritorio_abanico

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/** Notificaciones activas que se muestran como bocadillos en el escritorio. */
object NotiBridge {
    val items = LinkedHashMap<String, StatusBarNotification>()
    var onChange: (() -> Unit)? = null
    var service: NotiService? = null
}

class NotiService : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        NotiBridge.service = this
        NotiBridge.items.clear()
        try {
            activeNotifications?.forEach { add(it) }
        } catch (e: Exception) {}
        NotiBridge.onChange?.invoke()
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        if (NotiBridge.service === this) NotiBridge.service = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        add(sbn)
        NotiBridge.onChange?.invoke()
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (NotiBridge.items.remove(sbn.key) != null) NotiBridge.onChange?.invoke()
    }

    private fun add(sbn: StatusBarNotification) {
        if (!keep(sbn)) return
        NotiBridge.items.remove(sbn.key)
        NotiBridge.items[sbn.key] = sbn
    }

    private fun keep(sbn: StatusBarNotification): Boolean {
        if (sbn.packageName == packageName) return false
        if (sbn.isOngoing) return false
        val n = sbn.notification
        if ((n.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return false
        val cat = n.category
        if (cat == Notification.CATEGORY_TRANSPORT || cat == Notification.CATEGORY_SERVICE || cat == Notification.CATEGORY_PROGRESS) return false
        val ex = n.extras
        val title = ex.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = ex.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        return title.isNotBlank() || text.isNotBlank()
    }
}

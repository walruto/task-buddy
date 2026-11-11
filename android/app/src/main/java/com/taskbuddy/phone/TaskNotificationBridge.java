package com.taskbuddy.phone;

import android.Manifest;
import android.app.Activity;
import android.app.AlarmManager;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.webkit.JavascriptInterface;

import org.json.JSONArray;
import org.json.JSONObject;

import java.time.ZoneId;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

final class TaskNotificationBridge {
    static final String CHANNEL_ID = "task_due_reminders";
    static final String PREFS = "task_buddy_notifications";
    private static final String SCHEDULED_IDS = "scheduled_ids";
    private static final String ASKED_PERMISSION = "asked_permission";

    private final Activity activity;
    private final AlarmManager alarms;
    private final SharedPreferences preferences;

    TaskNotificationBridge(Activity activity) {
        this.activity = activity;
        alarms = (AlarmManager) activity.getSystemService(Context.ALARM_SERVICE);
        preferences = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        ensureChannel(activity);
    }

    @JavascriptInterface
    public void requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < 33
            || activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
            || preferences.getBoolean(ASKED_PERMISSION, false)) return;

        preferences.edit().putBoolean(ASKED_PERMISSION, true).apply();
        activity.runOnUiThread(() -> activity.requestPermissions(
            new String[] { Manifest.permission.POST_NOTIFICATIONS },
            1001
        ));
    }

    @JavascriptInterface
    public void syncTasks(String json) {
        try {
            JSONArray tasks = new JSONArray(json);
            Set<String> nextIDs = new HashSet<>();
            for (int index = 0; index < tasks.length(); index++) {
                JSONObject task = tasks.getJSONObject(index);
                String id = task.getString("id");
                String dueDate = task.optString("due_date", "");
                String dueTime = task.optString("due_time", "");
                if (dueDate.isEmpty() || "null".equals(dueDate)) continue;
                nextIDs.add(id);
                schedule(id, task.getString("title"), dueDate, dueTime);
            }

            Set<String> oldIDs = new HashSet<>(preferences.getStringSet(SCHEDULED_IDS, Collections.emptySet()));
            oldIDs.removeAll(nextIDs);
            for (String id : oldIDs) cancel(id);
            preferences.edit().putStringSet(SCHEDULED_IDS, nextIDs).apply();
        } catch (Exception ignored) {
            // The web client keeps the task visible if Android cannot schedule it.
        }
    }

    private void schedule(String id, String title, String dueDate, String dueTime) {
        String notifiedKey = "notified:" + id + ":" + dueDate + ":" + dueTime;
        if (preferences.getBoolean(notifiedKey, false)) return;

        Intent intent = new Intent(activity, TaskReminderReceiver.class)
            .putExtra("task_id", id)
            .putExtra("task_title", title)
            .putExtra("due_date", dueDate)
            .putExtra("due_time", dueTime);
        PendingIntent pending = PendingIntent.getBroadcast(
            activity,
            requestCode(id),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        long triggerAt = ReminderTime.triggerMillis(dueDate, dueTime, System.currentTimeMillis(), ZoneId.systemDefault());
        alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending);
    }

    private void cancel(String id) {
        Intent intent = new Intent(activity, TaskReminderReceiver.class);
        PendingIntent pending = PendingIntent.getBroadcast(
            activity,
            requestCode(id),
            intent,
            PendingIntent.FLAG_NO_CREATE | PendingIntent.FLAG_IMMUTABLE
        );
        if (pending != null) {
            alarms.cancel(pending);
            pending.cancel();
        }
    }

    static int requestCode(String id) { return id.hashCode() & 0x7fffffff; }

    static void ensureChannel(Context context) {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationChannel channel = new NotificationChannel(
            CHANNEL_ID,
            "Task reminders",
            NotificationManager.IMPORTANCE_DEFAULT
        );
        channel.setDescription("Reminders for Task Buddy due dates");
        context.getSystemService(NotificationManager.class).createNotificationChannel(channel);
    }
}

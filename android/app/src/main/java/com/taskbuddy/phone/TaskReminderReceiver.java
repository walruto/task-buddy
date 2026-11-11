package com.taskbuddy.phone;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;

public final class TaskReminderReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (Build.VERSION.SDK_INT >= 33
            && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return;

        String id = intent.getStringExtra("task_id");
        String title = intent.getStringExtra("task_title");
        String dueDate = intent.getStringExtra("due_date");
        String dueTime = intent.getStringExtra("due_time");
        if (id == null || title == null || dueDate == null) return;
        if (dueTime == null) dueTime = "";

        TaskNotificationBridge.ensureChannel(context);
        Intent open = new Intent(context, MainActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent contentIntent = PendingIntent.getActivity(
            context,
            TaskNotificationBridge.requestCode(id),
            open,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        Notification notification = new Notification.Builder(context, TaskNotificationBridge.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_buddy_notification)
            .setContentTitle("Task Buddy reminder")
            .setContentText(title)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build();
        context.getSystemService(NotificationManager.class)
            .notify(TaskNotificationBridge.requestCode(id), notification);
        context.getSharedPreferences(TaskNotificationBridge.PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean("notified:" + id + ":" + dueDate + ":" + dueTime, true)
            .apply();
    }
}

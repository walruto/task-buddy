package com.taskbuddy.phone;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;

final class ReminderTime {
    private ReminderTime() {}

    static long triggerMillis(String dueDate, String dueTime, long nowMillis, ZoneId zone) {
        LocalTime time = dueTime == null || dueTime.isEmpty() || "null".equals(dueTime)
            ? LocalTime.of(9, 0)
            : LocalTime.parse(dueTime);
        long deadline = LocalDate.parse(dueDate)
            .atTime(time)
            .atZone(zone)
            .toInstant()
            .toEpochMilli();
        return Math.max(deadline, nowMillis + 3_000L);
    }
}

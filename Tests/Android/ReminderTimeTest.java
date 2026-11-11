package com.taskbuddy.phone;

import java.time.Instant;
import java.time.ZoneId;
import java.time.ZonedDateTime;

public final class ReminderTimeTest {
    public static void main(String[] args) {
        ZoneId zone = ZoneId.of("America/Los_Angeles");
        long now = Instant.parse("2026-11-03T20:00:00Z").toEpochMilli();
        long expected = ZonedDateTime.of(2026, 11, 4, 9, 0, 0, 0, zone).toInstant().toEpochMilli();
        assert ReminderTime.triggerMillis("2026-11-04", "09:00:00", now, zone) == expected;
        long afternoon = ZonedDateTime.of(2026, 11, 4, 14, 30, 0, 0, zone).toInstant().toEpochMilli();
        assert ReminderTime.triggerMillis("2026-11-04", "14:30:00", now, zone) == afternoon;
        assert ReminderTime.triggerMillis("2026-11-04", "", now, zone) == expected;
        assert ReminderTime.triggerMillis("2026-11-03", "09:00:00", now, zone) == now + 3_000L;
        System.out.println("Android reminder scheduling checks passed.");
    }
}

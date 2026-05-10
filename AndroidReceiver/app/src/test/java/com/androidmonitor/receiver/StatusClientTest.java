package com.androidmonitor.receiver;

import org.json.JSONObject;
import org.junit.Test;

import static org.junit.Assert.assertEquals;

public final class StatusClientTest {
    @Test
    public void statusSnapshotUsesJsonValues() throws Exception {
        JSONObject object = new JSONObject()
                .put("host", "mac")
                .put("timestamp", "2026-05-10T11:00:00+08:00")
                .put("uptime", "1h")
                .put("uptime_seconds", 3600)
                .put("cpu", "cpu")
                .put("memory", "mem")
                .put("disk", "disk")
                .put("network", "net")
                .put("command_output", "cmd")
                .put("build_status", "green")
                .put("log_tail", "tail");

        StatusSnapshot snapshot = StatusSnapshot.fromJson(object);

        assertEquals("mac", snapshot.host);
        assertEquals("2026-05-10T11:00:00+08:00", snapshot.timestamp);
        assertEquals("1h", snapshot.uptime);
        assertEquals(3600, snapshot.uptimeSeconds);
        assertEquals("cpu", snapshot.cpu);
        assertEquals("mem", snapshot.memory);
        assertEquals("disk", snapshot.disk);
        assertEquals("net", snapshot.network);
        assertEquals("cmd", snapshot.commandOutput);
        assertEquals("green", snapshot.buildStatus);
        assertEquals("tail", snapshot.logTail);
    }

    @Test
    public void statusSnapshotDefaultsMissingValues() {
        StatusSnapshot snapshot = StatusSnapshot.fromJson(new JSONObject());

        assertEquals("Mac", snapshot.host);
        assertEquals("", snapshot.timestamp);
        assertEquals("", snapshot.uptime);
        assertEquals(0, snapshot.uptimeSeconds);
        assertEquals("", snapshot.cpu);
        assertEquals("", snapshot.memory);
        assertEquals("", snapshot.disk);
        assertEquals("", snapshot.network);
        assertEquals("", snapshot.commandOutput);
        assertEquals("", snapshot.buildStatus);
        assertEquals("", snapshot.logTail);
    }
}

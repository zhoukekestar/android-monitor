package com.androidmonitor.receiver;

import org.json.JSONObject;

final class StatusSnapshot {
    final String host;
    final String timestamp;
    final String uptime;
    final int uptimeSeconds;
    final String cpu;
    final String memory;
    final String disk;
    final String network;
    final String commandOutput;
    final String buildStatus;
    final String logTail;

    private StatusSnapshot(
            String host,
            String timestamp,
            String uptime,
            int uptimeSeconds,
            String cpu,
            String memory,
            String disk,
            String network,
            String commandOutput,
            String buildStatus,
            String logTail
    ) {
        this.host = host;
        this.timestamp = timestamp;
        this.uptime = uptime;
        this.uptimeSeconds = uptimeSeconds;
        this.cpu = cpu;
        this.memory = memory;
        this.disk = disk;
        this.network = network;
        this.commandOutput = commandOutput;
        this.buildStatus = buildStatus;
        this.logTail = logTail;
    }

    static StatusSnapshot fromJson(JSONObject object) {
        return new StatusSnapshot(
                object.optString("host", "Mac"),
                object.optString("timestamp", ""),
                object.optString("uptime", ""),
                object.optInt("uptime_seconds", 0),
                object.optString("cpu", ""),
                object.optString("memory", ""),
                object.optString("disk", ""),
                object.optString("network", ""),
                object.optString("command_output", ""),
                object.optString("build_status", ""),
                object.optString("log_tail", "")
        );
    }
}

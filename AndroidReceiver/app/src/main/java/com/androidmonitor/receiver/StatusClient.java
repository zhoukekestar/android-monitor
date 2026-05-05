package com.androidmonitor.receiver;

import android.util.Log;

import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

final class StatusClient implements Runnable {
    interface Listener {
        void onStatusConnecting(String status);
        void onSnapshot(StatusSnapshot snapshot);
        void onStatusError(String message);
    }

    private static final String TAG = "AndroidMonitorStatus";
    private static final String HOST = "127.0.0.1";
    private static final int PORT = 38889;

    private final Listener listener;
    private volatile boolean running = true;
    private Socket socket;

    StatusClient(Listener listener) {
        this.listener = listener;
    }

    @Override
    public void run() {
        while (running) {
            try {
                connectAndRead();
            } catch (Exception e) {
                if (running) {
                    String message = e.getMessage() == null ? e.toString() : e.getMessage();
                    listener.onStatusError(message);
                    Log.w(TAG, "Status connection failed", e);
                    sleep(1200);
                }
            } finally {
                close();
            }
        }
    }

    void stop() {
        running = false;
        close();
    }

    private void connectAndRead() throws Exception {
        listener.onStatusConnecting("Connecting to status panel");
        socket = new Socket();
        socket.setTcpNoDelay(true);
        socket.setKeepAlive(true);
        socket.connect(new InetSocketAddress(HOST, PORT), 2000);
        listener.onStatusConnecting("Connected to status panel");

        DataInputStream input = new DataInputStream(new BufferedInputStream(socket.getInputStream()));
        while (running) {
            JSONObject object = new JSONObject(readLine(input));
            if (!"status_snapshot".equals(object.optString("type"))) {
                continue;
            }
            StatusSnapshot snapshot = StatusSnapshot.fromJson(object);
            Log.i(TAG, "Status snapshot received from " + snapshot.host + " at " + snapshot.timestamp);
            listener.onSnapshot(snapshot);
        }
    }

    private String readLine(DataInputStream input) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream(1024);
        while (true) {
            int value = input.read();
            if (value < 0) {
                throw new IllegalStateException("Disconnected from status panel");
            }
            if (value == '\n') {
                return new String(out.toByteArray(), StandardCharsets.UTF_8);
            }
            out.write(value);
        }
    }

    private void close() {
        Socket oldSocket = socket;
        socket = null;
        if (oldSocket != null) {
            try {
                oldSocket.close();
            } catch (Exception e) {
                Log.d(TAG, "Socket close failed", e);
            }
        }
    }

    private void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        }
    }

    static final class StatusSnapshot {
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
}

package com.androidmonitor.receiver;

import android.os.Build;
import android.util.Log;
import android.view.Surface;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedOutputStream;
import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.EOFException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

final class StreamClient implements Runnable {
    interface Listener {
        void onStatus(String status);
        void onConfig(int width, int height, int fps, int bitrateMbps);
        void onStats(long decodedFrames, long droppedFrames, double inputFps, double bitrateMbps);
        void onError(String message);
    }

    private static final String TAG = "AndroidMonitorStream";
    private static final String HOST = "127.0.0.1";
    private static final int PORT = 38888;
    private static final int MAGIC = 0x414D4F4E;
    private static final int HEADER_SIZE = 24;
    private static final int MAX_PAYLOAD_BYTES = 16 * 1024 * 1024;
    private static final long DECODED_STATS_INTERVAL_MS = 250;

    private final Surface surface;
    private final Listener listener;
    private volatile boolean running = true;
    private Socket socket;
    private H264Decoder decoder;
    private OutputStream controlOutput;
    private final Object controlLock = new Object();
    private final int screenWidth;
    private final int screenHeight;
    private long latestDecodedFrames;
    private long latestDroppedFrames;
    private double latestInputFps;
    private double latestBitrateMbps;
    private long statsWindowStartMs;
    private long statsWindowBytes;
    private long statsWindowFrames;
    private long decodedStatsLastSentMs;
    private long decodedStatsLastSentFrames;

    StreamClient(Surface surface, int screenWidth, int screenHeight, Listener listener) {
        this.surface = surface;
        this.screenWidth = screenWidth;
        this.screenHeight = screenHeight;
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
                    sendError(message);
                    listener.onError(message);
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
        listener.onStatus("Connecting to " + HOST + ":" + PORT);
        socket = new Socket();
        socket.setTcpNoDelay(true);
        socket.setKeepAlive(true);
        socket.connect(new InetSocketAddress(HOST, PORT), 2000);
        listener.onStatus("Connected; waiting for stream config");

        controlOutput = new BufferedOutputStream(socket.getOutputStream());
        sendClientHello();

        DataInputStream input = new DataInputStream(new BufferedInputStream(socket.getInputStream()));
        JSONObject config = new JSONObject(readLine(input));
        int width = config.optInt("width", 1024);
        int height = config.optInt("height", 600);
        int fps = config.optInt("fps", 15);
        int bitrateMbps = config.optInt("bitrate_mbps", 0);
        String codec = config.optString("codec", "h264");
        String format = config.optString("format", "annexb");

        if (!"h264".equals(codec) || !"annexb".equals(format)) {
            throw new IllegalStateException("Unsupported stream: " + codec + "/" + format);
        }

        listener.onConfig(width, height, fps, bitrateMbps);
        resetStatsWindow();
        decoder = new H264Decoder(surface, width, height, new H264Decoder.StatsListener() {
            @Override
            public void onStats(long decodedFrames, long droppedFrames) {
                latestDecodedFrames = decodedFrames;
                latestDroppedFrames = droppedFrames;
                listener.onStats(decodedFrames, droppedFrames, latestInputFps, latestBitrateMbps);
                maybeSendDecodedStats(decodedFrames);
            }
        });
        decoder.start();
        listener.onStatus("Decoding " + width + "x" + height + " H.264");

        byte[] header = new byte[HEADER_SIZE];
        while (running) {
            input.readFully(header);
            PacketHeader packet = parseHeader(header);
            if (packet.payloadLength <= 0 || packet.payloadLength > MAX_PAYLOAD_BYTES) {
                throw new IllegalStateException("Invalid payload length: " + packet.payloadLength);
            }
            byte[] payload = new byte[packet.payloadLength];
            input.readFully(payload);
            if (packet.type == 2) {
                recordIncomingVideoPacket(packet.payloadLength + HEADER_SIZE);
                decoder.queueFrame(payload, packet.presentationTimestampNs / 1000L);
            }
        }
    }

    private void resetStatsWindow() {
        latestDecodedFrames = 0;
        latestDroppedFrames = 0;
        latestInputFps = 0.0;
        latestBitrateMbps = 0.0;
        statsWindowStartMs = System.currentTimeMillis();
        statsWindowBytes = 0;
        statsWindowFrames = 0;
        decodedStatsLastSentMs = 0;
        decodedStatsLastSentFrames = -1;
    }

    private void recordIncomingVideoPacket(int packetBytes) {
        statsWindowFrames++;
        statsWindowBytes += packetBytes;

        long now = System.currentTimeMillis();
        long elapsedMs = now - statsWindowStartMs;
        if (elapsedMs < 1000) {
            return;
        }

        latestInputFps = statsWindowFrames * 1000.0 / elapsedMs;
        latestBitrateMbps = statsWindowBytes * 8.0 / elapsedMs / 1000.0;
        statsWindowStartMs = now;
        statsWindowBytes = 0;
        statsWindowFrames = 0;
        listener.onStats(latestDecodedFrames, latestDroppedFrames, latestInputFps, latestBitrateMbps);
        sendStats();
    }

    private void maybeSendDecodedStats(long decodedFrames) {
        if (decodedFrames <= 0 || decodedFrames == decodedStatsLastSentFrames) {
            return;
        }

        long now = System.currentTimeMillis();
        if (decodedStatsLastSentFrames > 0 && now - decodedStatsLastSentMs < DECODED_STATS_INTERVAL_MS) {
            return;
        }

        decodedStatsLastSentFrames = decodedFrames;
        decodedStatsLastSentMs = now;
        sendStats();
    }

    private void sendClientHello() throws Exception {
        JSONObject hello = new JSONObject();
        hello.put("type", "client_hello");
        hello.put("manufacturer", Build.MANUFACTURER);
        hello.put("model", Build.MODEL);
        hello.put("api_level", Build.VERSION.SDK_INT);
        hello.put("screen_width", screenWidth);
        hello.put("screen_height", screenHeight);
        hello.put("supported_codecs", new JSONArray().put("h264"));
        sendJsonLine(hello);
    }

    private void sendStats() {
        try {
            JSONObject stats = new JSONObject();
            stats.put("type", "stats");
            stats.put("decoded_frames", latestDecodedFrames);
            stats.put("dropped_frames", latestDroppedFrames);
            stats.put("input_fps", latestInputFps);
            stats.put("bitrate_mbps", latestBitrateMbps);
            sendJsonLine(stats);
        } catch (Exception e) {
            Log.w(TAG, "Failed to send stats", e);
        }
    }

    private void sendError(String message) {
        try {
            JSONObject error = new JSONObject();
            error.put("type", "error");
            error.put("message", message);
            sendJsonLine(error);
        } catch (Exception e) {
            Log.w(TAG, "Failed to send error", e);
        }
    }

    void sendTouch(String action, float normalizedX, float normalizedY) {
        try {
            sendJsonLine(touchControl(action, normalizedX, normalizedY).toJson());
        } catch (Exception e) {
            Log.w(TAG, "Failed to send touch", e);
        }
    }

    void sendScroll(float normalizedX, float normalizedY, float normalizedDeltaX, float normalizedDeltaY) {
        try {
            sendJsonLine(scrollControl(normalizedX, normalizedY, normalizedDeltaX, normalizedDeltaY).toJson());
        } catch (Exception e) {
            Log.w(TAG, "Failed to send scroll", e);
        }
    }

    static TouchControl touchControl(String action, float normalizedX, float normalizedY) {
        return new TouchControl(action, clamp01(normalizedX), clamp01(normalizedY), 0.0f, 0.0f, false);
    }

    static TouchControl scrollControl(float normalizedX, float normalizedY, float normalizedDeltaX, float normalizedDeltaY) {
        return new TouchControl("scroll", clamp01(normalizedX), clamp01(normalizedY), normalizedDeltaX, normalizedDeltaY, true);
    }

    private void sendJsonLine(JSONObject object) throws Exception {
        synchronized (controlLock) {
            if (controlOutput == null) {
                return;
            }
            controlOutput.write(object.toString().getBytes(StandardCharsets.UTF_8));
            controlOutput.write('\n');
            controlOutput.flush();
        }
    }

    static PacketHeader parseHeader(byte[] header) throws EOFException {
        int magic = readInt(header, 0);
        if (magic != MAGIC) {
            throw new EOFException("Bad packet magic: 0x" + Integer.toHexString(magic));
        }

        int version = header[4] & 0xff;
        if (version != 1) {
            throw new EOFException("Unsupported packet version: " + version);
        }

        PacketHeader packet = new PacketHeader();
        packet.type = header[5] & 0xff;
        packet.flags = readShort(header, 6);
        packet.sequence = readInt(header, 8);
        packet.presentationTimestampNs = readLong(header, 12);
        packet.payloadLength = readInt(header, 20);
        return packet;
    }

    private String readLine(DataInputStream input) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream(256);
        while (true) {
            int value = input.read();
            if (value < 0) {
                throw new EOFException("Disconnected before config");
            }
            if (value == '\n') {
                return new String(out.toByteArray(), StandardCharsets.UTF_8);
            }
            out.write(value);
        }
    }

    private void close() {
        H264Decoder oldDecoder = decoder;
        decoder = null;
        controlOutput = null;
        if (oldDecoder != null) {
            oldDecoder.stop();
        }

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

    private static float clamp01(float value) {
        if (value < 0.0f) {
            return 0.0f;
        }
        if (value > 1.0f) {
            return 1.0f;
        }
        return value;
    }

    private static int readShort(byte[] data, int offset) {
        return ((data[offset] & 0xff) << 8)
                | (data[offset + 1] & 0xff);
    }

    private static int readInt(byte[] data, int offset) {
        return ((data[offset] & 0xff) << 24)
                | ((data[offset + 1] & 0xff) << 16)
                | ((data[offset + 2] & 0xff) << 8)
                | (data[offset + 3] & 0xff);
    }

    private static long readLong(byte[] data, int offset) {
        return ((long) (data[offset] & 0xff) << 56)
                | ((long) (data[offset + 1] & 0xff) << 48)
                | ((long) (data[offset + 2] & 0xff) << 40)
                | ((long) (data[offset + 3] & 0xff) << 32)
                | ((long) (data[offset + 4] & 0xff) << 24)
                | ((long) (data[offset + 5] & 0xff) << 16)
                | ((long) (data[offset + 6] & 0xff) << 8)
                | ((long) (data[offset + 7] & 0xff));
    }

    static final class PacketHeader {
        int type;
        int flags;
        int sequence;
        long presentationTimestampNs;
        int payloadLength;
    }

    static final class TouchControl {
        final String action;
        final float x;
        final float y;
        final float deltaX;
        final float deltaY;
        final boolean hasScrollDelta;

        TouchControl(String action, float x, float y, float deltaX, float deltaY, boolean hasScrollDelta) {
            this.action = action;
            this.x = x;
            this.y = y;
            this.deltaX = deltaX;
            this.deltaY = deltaY;
            this.hasScrollDelta = hasScrollDelta;
        }

        JSONObject toJson() throws Exception {
            JSONObject touch = new JSONObject();
            touch.put("type", "touch");
            touch.put("action", action);
            touch.put("x", x);
            touch.put("y", y);
            if (hasScrollDelta) {
                touch.put("delta_x", deltaX);
                touch.put("delta_y", deltaY);
            }
            return touch;
        }
    }
}

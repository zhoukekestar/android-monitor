package com.androidmonitor.receiver;

import org.json.JSONObject;

import java.io.EOFException;

final class StreamProtocol {
    private static final int MAGIC = 0x414D4F4E;

    private StreamProtocol() {
    }

    static PacketHeader parseHeader(byte[] header) throws EOFException {
        if (header.length < 24) {
            throw new EOFException("Packet header too short: " + header.length);
        }

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

    static TouchControl touchControl(String action, float normalizedX, float normalizedY) {
        return new TouchControl(action, clamp01(normalizedX), clamp01(normalizedY), 0.0f, 0.0f, false);
    }

    static TouchControl scrollControl(float normalizedX, float normalizedY, float normalizedDeltaX, float normalizedDeltaY) {
        return new TouchControl("scroll", clamp01(normalizedX), clamp01(normalizedY), normalizedDeltaX, normalizedDeltaY, true);
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

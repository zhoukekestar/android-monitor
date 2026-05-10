package com.androidmonitor.receiver;

import org.junit.Test;
import org.json.JSONObject;

import java.io.EOFException;
import java.nio.ByteBuffer;

import static org.junit.Assert.assertEquals;

public final class StreamClientTest {
    @Test
    public void parseHeaderReadsBigEndianPacketFields() throws Exception {
        byte[] header = header(
                0x414D4F4E,
                1,
                2,
                1,
                42,
                1_234_567_890_123L,
                4096
        );

        StreamProtocol.PacketHeader packet = StreamProtocol.parseHeader(header);

        assertEquals(2, packet.type);
        assertEquals(1, packet.flags);
        assertEquals(42, packet.sequence);
        assertEquals(1_234_567_890_123L, packet.presentationTimestampNs);
        assertEquals(4096, packet.payloadLength);
    }

    @Test(expected = EOFException.class)
    public void parseHeaderRejectsBadMagic() throws Exception {
        StreamProtocol.parseHeader(header(0x12345678, 1, 2, 1, 42, 1000L, 64));
    }

    @Test(expected = EOFException.class)
    public void parseHeaderRejectsUnsupportedVersion() throws Exception {
        StreamProtocol.parseHeader(header(0x414D4F4E, 2, 2, 1, 42, 1000L, 64));
    }

    @Test(expected = EOFException.class)
    public void parseHeaderRejectsShortHeader() throws Exception {
        StreamProtocol.parseHeader(new byte[23]);
    }

    @Test
    public void touchControlClampsCoordinates() {
        StreamProtocol.TouchControl message = StreamProtocol.touchControl("down", -0.25f, 1.25f);

        assertEquals("down", message.action);
        assertEquals(0.0f, message.x, 0.0001f);
        assertEquals(1.0f, message.y, 0.0001f);
        assertEquals(false, message.hasScrollDelta);
    }

    @Test
    public void scrollControlPreservesSignedDeltas() {
        StreamProtocol.TouchControl message = StreamProtocol.scrollControl(0.5f, 0.25f, 0.125f, -0.375f);

        assertEquals("scroll", message.action);
        assertEquals(0.5f, message.x, 0.0001f);
        assertEquals(0.25f, message.y, 0.0001f);
        assertEquals(0.125f, message.deltaX, 0.0001f);
        assertEquals(-0.375f, message.deltaY, 0.0001f);
        assertEquals(true, message.hasScrollDelta);
    }

    @Test
    public void touchControlSerializesWithoutScrollDeltas() throws Exception {
        JSONObject json = StreamProtocol.touchControl("up", 0.25f, 0.75f).toJson();

        assertEquals("touch", json.getString("type"));
        assertEquals("up", json.getString("action"));
        assertEquals(0.25, json.getDouble("x"), 0.0001);
        assertEquals(0.75, json.getDouble("y"), 0.0001);
        assertEquals(false, json.has("delta_x"));
        assertEquals(false, json.has("delta_y"));
    }

    @Test
    public void scrollControlSerializesScrollDeltas() throws Exception {
        JSONObject json = StreamProtocol.scrollControl(0.5f, 0.25f, 0.125f, -0.375f).toJson();

        assertEquals("touch", json.getString("type"));
        assertEquals("scroll", json.getString("action"));
        assertEquals(0.125, json.getDouble("delta_x"), 0.0001);
        assertEquals(-0.375, json.getDouble("delta_y"), 0.0001);
    }

    private static byte[] header(
            int magic,
            int version,
            int type,
            int flags,
            int sequence,
            long presentationTimestampNs,
            int payloadLength
    ) {
        ByteBuffer buffer = ByteBuffer.allocate(24);
        buffer.putInt(magic);
        buffer.put((byte) version);
        buffer.put((byte) type);
        buffer.putShort((short) flags);
        buffer.putInt(sequence);
        buffer.putLong(presentationTimestampNs);
        buffer.putInt(payloadLength);
        return buffer.array();
    }
}

package com.androidmonitor.receiver;

import org.junit.Test;

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

        StreamClient.PacketHeader packet = StreamClient.parseHeader(header);

        assertEquals(2, packet.type);
        assertEquals(1, packet.flags);
        assertEquals(42, packet.sequence);
        assertEquals(1_234_567_890_123L, packet.presentationTimestampNs);
        assertEquals(4096, packet.payloadLength);
    }

    @Test(expected = EOFException.class)
    public void parseHeaderRejectsBadMagic() throws Exception {
        StreamClient.parseHeader(header(0x12345678, 1, 2, 1, 42, 1000L, 64));
    }

    @Test(expected = EOFException.class)
    public void parseHeaderRejectsUnsupportedVersion() throws Exception {
        StreamClient.parseHeader(header(0x414D4F4E, 2, 2, 1, 42, 1000L, 64));
    }

    @Test
    public void touchControlClampsCoordinates() {
        StreamClient.TouchControl message = StreamClient.touchControl("down", -0.25f, 1.25f);

        assertEquals("down", message.action);
        assertEquals(0.0f, message.x, 0.0001f);
        assertEquals(1.0f, message.y, 0.0001f);
        assertEquals(false, message.hasScrollDelta);
    }

    @Test
    public void scrollControlPreservesSignedDeltas() {
        StreamClient.TouchControl message = StreamClient.scrollControl(0.5f, 0.25f, 0.125f, -0.375f);

        assertEquals("scroll", message.action);
        assertEquals(0.5f, message.x, 0.0001f);
        assertEquals(0.25f, message.y, 0.0001f);
        assertEquals(0.125f, message.deltaX, 0.0001f);
        assertEquals(-0.375f, message.deltaY, 0.0001f);
        assertEquals(true, message.hasScrollDelta);
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

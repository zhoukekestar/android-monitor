package com.androidmonitor.receiver;

import org.junit.Test;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

public final class H264DecoderTest {
    @Test
    public void inspectAnnexBFindsStartupConfigWithFourByteStartCodes() {
        byte[] payload = annexB(
                nal(7, 0x11, 0x22),
                nal(8, 0x33),
                nal(5, 0x44, 0x55),
                nal(1, 0x66)
        );

        AnnexBInspector.FrameInfo frameInfo = AnnexBInspector.inspect(payload, payload.length);

        assertTrue(frameInfo.hasSps);
        assertTrue(frameInfo.hasPps);
        assertTrue(frameInfo.hasIdr);
    }

    @Test
    public void inspectAnnexBFindsThreeByteStartCodes() {
        byte[] payload = new byte[] {
                0, 0, 1, 0x67, 0x11,
                0, 0, 1, 0x68, 0x22,
                0, 0, 1, 0x65, 0x33
        };

        AnnexBInspector.FrameInfo frameInfo = AnnexBInspector.inspect(payload, payload.length);

        assertTrue(frameInfo.hasSps);
        assertTrue(frameInfo.hasPps);
        assertTrue(frameInfo.hasIdr);
    }

    @Test
    public void inspectAnnexBDoesNotTreatDeltaFrameAsPrimingFrame() {
        byte[] payload = annexB(nal(1, 0x11, 0x22));

        AnnexBInspector.FrameInfo frameInfo = AnnexBInspector.inspect(payload, payload.length);

        assertFalse(frameInfo.hasSps);
        assertFalse(frameInfo.hasPps);
        assertFalse(frameInfo.hasIdr);
    }

    @Test
    public void inspectAnnexBTracksPartialConfig() {
        byte[] payload = annexB(nal(7, 0x11), nal(5, 0x22));

        AnnexBInspector.FrameInfo frameInfo = AnnexBInspector.inspect(payload, payload.length);

        assertTrue(frameInfo.hasSps);
        assertFalse(frameInfo.hasPps);
        assertTrue(frameInfo.hasIdr);
    }

    @Test
    public void inspectAnnexBIgnoresLeadingBytesBeforeStartCode() {
        byte[] payload = new byte[] {
                0x45, 0x23,
                0, 0, 0, 1, 0x67,
                0, 0, 0, 1, 0x68,
                0, 0, 0, 1, 0x65
        };

        AnnexBInspector.FrameInfo frameInfo = AnnexBInspector.inspect(payload, payload.length);

        assertTrue(frameInfo.hasSps);
        assertTrue(frameInfo.hasPps);
        assertTrue(frameInfo.hasIdr);
    }

    @Test
    public void inspectAnnexBStopsAtTrailingStartCodeWithoutNalHeader() {
        byte[] payload = new byte[] {0, 0, 1};

        AnnexBInspector.FrameInfo frameInfo = AnnexBInspector.inspect(payload, payload.length);

        assertFalse(frameInfo.hasSps);
        assertFalse(frameInfo.hasPps);
        assertFalse(frameInfo.hasIdr);
    }

    @Test
    public void inspectAnnexBAdvancesWhenPayloadBeginsWithStartCodePattern() {
        byte[] payload = new byte[] {
                0, 0, 1, 0,
                0, 0, 1, 0x65
        };

        AnnexBInspector.FrameInfo frameInfo = AnnexBInspector.inspect(payload, payload.length);

        assertFalse(frameInfo.hasSps);
        assertFalse(frameInfo.hasPps);
        assertTrue(frameInfo.hasIdr);
    }

    private static byte[] annexB(byte[]... nals) {
        int size = 0;
        for (byte[] nal : nals) {
            size += 4 + nal.length;
        }

        byte[] payload = new byte[size];
        int offset = 0;
        for (byte[] nal : nals) {
            payload[offset++] = 0;
            payload[offset++] = 0;
            payload[offset++] = 0;
            payload[offset++] = 1;
            System.arraycopy(nal, 0, payload, offset, nal.length);
            offset += nal.length;
        }
        return payload;
    }

    private static byte[] nal(int type, int... payloadBytes) {
        byte[] nal = new byte[payloadBytes.length + 1];
        nal[0] = (byte) (type & 0x1f);
        for (int i = 0; i < payloadBytes.length; i++) {
            nal[i + 1] = (byte) payloadBytes[i];
        }
        return nal;
    }
}

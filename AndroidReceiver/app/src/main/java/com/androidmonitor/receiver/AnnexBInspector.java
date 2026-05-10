package com.androidmonitor.receiver;

final class AnnexBInspector {
    private static final int NAL_TYPE_IDR = 5;
    private static final int NAL_TYPE_SPS = 7;
    private static final int NAL_TYPE_PPS = 8;

    private AnnexBInspector() {
    }

    static FrameInfo inspect(byte[] data, int size) {
        FrameInfo frameInfo = new FrameInfo();
        int startCodeOffset = findStartCode(data, 0, size);
        while (startCodeOffset >= 0) {
            int startCodeLength = startCodeLength(data, startCodeOffset, size);
            if (startCodeLength == 0) {
                return frameInfo;
            }

            int nalOffset = startCodeOffset + startCodeLength;
            if (nalOffset >= size) {
                return frameInfo;
            }

            int nalType = data[nalOffset] & 0x1f;
            if (nalType == NAL_TYPE_IDR) {
                frameInfo.hasIdr = true;
            } else if (nalType == NAL_TYPE_SPS) {
                frameInfo.hasSps = true;
            } else if (nalType == NAL_TYPE_PPS) {
                frameInfo.hasPps = true;
            }

            startCodeOffset = findStartCode(data, nalOffset, size);
            if (startCodeOffset == nalOffset) {
                startCodeOffset = findStartCode(data, nalOffset + 1, size);
            }
        }
        return frameInfo;
    }

    private static int findStartCode(byte[] data, int offset, int limit) {
        for (int i = offset; i + 2 < limit; i++) {
            if (data[i] != 0 || data[i + 1] != 0) {
                continue;
            }
            if (data[i + 2] == 1) {
                return i;
            }
            if (i + 3 < limit && data[i + 2] == 0 && data[i + 3] == 1) {
                return i;
            }
        }
        return -1;
    }

    private static int startCodeLength(byte[] data, int offset, int limit) {
        if (offset + 2 < limit && data[offset] == 0 && data[offset + 1] == 0 && data[offset + 2] == 1) {
            return 3;
        }
        if (offset + 3 < limit
                && data[offset] == 0
                && data[offset + 1] == 0
                && data[offset + 2] == 0
                && data[offset + 3] == 1) {
            return 4;
        }
        return 0;
    }

    static final class FrameInfo {
        boolean hasSps;
        boolean hasPps;
        boolean hasIdr;
    }
}

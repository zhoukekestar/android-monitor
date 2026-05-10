package com.androidmonitor.receiver;

import android.media.MediaCodec;
import android.media.MediaFormat;
import android.util.Log;
import android.view.Surface;

import java.io.IOException;
import java.nio.ByteBuffer;

final class H264Decoder {
    interface StatsListener {
        void onStats(long decodedFrames, long droppedFrames);
    }

    private static final String TAG = "AndroidMonitorDecoder";
    private static final long INPUT_TIMEOUT_US = 2_000;
    private static final long OUTPUT_TIMEOUT_US = 2_000;
    private static final int MAX_WAITING_LOGS = 5;
    private final Surface surface;
    private final int width;
    private final int height;
    private final StatsListener statsListener;

    private MediaCodec codec;
    private final MediaCodec.BufferInfo bufferInfo = new MediaCodec.BufferInfo();
    private long decodedFrames;
    private long droppedFrames;
    private boolean seenSps;
    private boolean seenPps;
    private boolean decoderPrimed;
    private int waitingForKeyframeDrops;

    H264Decoder(Surface surface, int width, int height, StatsListener statsListener) {
        this.surface = surface;
        this.width = width;
        this.height = height;
        this.statsListener = statsListener;
    }

    void start() throws IOException {
        codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC);
        MediaFormat format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height);
        codec.configure(format, surface, null, 0);
        codec.setVideoScalingMode(MediaCodec.VIDEO_SCALING_MODE_SCALE_TO_FIT);
        codec.start();
        decodedFrames = 0;
        droppedFrames = 0;
        seenSps = false;
        seenPps = false;
        decoderPrimed = false;
        waitingForKeyframeDrops = 0;
    }

    void queueFrame(byte[] data, long presentationTimeUs) {
        if (codec == null) {
            return;
        }

        AnnexBInspector.FrameInfo frameInfo = AnnexBInspector.inspect(data, data.length);
        if (frameInfo.hasSps) {
            seenSps = true;
        }
        if (frameInfo.hasPps) {
            seenPps = true;
        }

        if (!decoderPrimed) {
            if (!frameInfo.hasSps || !frameInfo.hasPps || !frameInfo.hasIdr) {
                droppedFrames++;
                logWaitingForDecoderConfig(frameInfo);
                notifyStats();
                drainOutput(false);
                return;
            }

            decoderPrimed = true;
            Log.i(TAG, "Decoder primed with SPS/PPS and IDR frame");
        }

        try {
            int inputIndex = codec.dequeueInputBuffer(INPUT_TIMEOUT_US);
            if (inputIndex < 0) {
                droppedFrames++;
                notifyStats();
                drainOutput(false);
                return;
            }

            ByteBuffer inputBuffer = codec.getInputBuffer(inputIndex);
            if (inputBuffer == null || data.length > inputBuffer.capacity()) {
                droppedFrames++;
                codec.queueInputBuffer(inputIndex, 0, 0, presentationTimeUs, 0);
                notifyStats();
                drainOutput(false);
                return;
            }

            inputBuffer.clear();
            inputBuffer.put(data);
            codec.queueInputBuffer(inputIndex, 0, data.length, presentationTimeUs, 0);
            drainOutput(true);
        } catch (IllegalStateException e) {
            droppedFrames++;
            Log.w(TAG, "Decoder rejected frame", e);
            notifyStats();
        }
    }

    void stop() {
        if (codec == null) {
            return;
        }

        try {
            drainOutput(true);
            codec.stop();
        } catch (IllegalStateException ignored) {
        } finally {
            codec.release();
            codec = null;
        }
    }

    private void drainOutput(boolean wait) {
        if (codec == null) {
            return;
        }

        long timeout = wait ? OUTPUT_TIMEOUT_US : 0;
        while (true) {
            int outputIndex = codec.dequeueOutputBuffer(bufferInfo, timeout);
            if (outputIndex >= 0) {
                codec.releaseOutputBuffer(outputIndex, true);
                decodedFrames++;
                notifyStats();
                timeout = 0;
            } else if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                Log.i(TAG, "Output format changed: " + codec.getOutputFormat());
            } else {
                return;
            }
        }
    }

    private void notifyStats() {
        if (statsListener != null) {
            statsListener.onStats(decodedFrames, droppedFrames);
        }
    }

    private void logWaitingForDecoderConfig(AnnexBInspector.FrameInfo frameInfo) {
        if (waitingForKeyframeDrops < MAX_WAITING_LOGS || waitingForKeyframeDrops % 60 == 0) {
            Log.i(TAG, "Waiting for H.264 SPS/PPS and IDR before decoding"
                    + " (seenSps=" + seenSps
                    + ", seenPps=" + seenPps
                    + ", frameHasSps=" + frameInfo.hasSps
                    + ", frameHasPps=" + frameInfo.hasPps
                    + ", frameHasIdr=" + frameInfo.hasIdr + ")");
        }
        waitingForKeyframeDrops++;
    }

}

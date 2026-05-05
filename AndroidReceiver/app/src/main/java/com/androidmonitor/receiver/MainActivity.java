package com.androidmonitor.receiver;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.method.ScrollingMovementMethod;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.Window;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.TextView;

import java.util.Locale;

public final class MainActivity extends Activity implements SurfaceHolder.Callback, StreamClient.Listener, StatusClient.Listener {
    private static final String TAG = "AndroidMonitorInput";
    private static final int MODE_DISPLAY = 0;
    private static final int MODE_STATUS = 1;
    private static final long STATS_OVERLAY_INTERVAL_MS = 250;

    private SurfaceView surfaceView;
    private TextView overlay;
    private TextView statusPanel;
    private TextView modeButton;
    private SurfaceHolder currentSurfaceHolder;
    private StreamClient streamClient;
    private Thread streamThread;
    private StatusClient statusClient;
    private Thread statusThread;
    private Handler mainHandler;
    private Runnable touchDisableRunnable;
    private int mode = MODE_DISPLAY;
    private volatile int configuredWidth = 0;
    private volatile int configuredHeight = 0;
    private volatile int configuredFps = 0;
    private volatile int configuredBitrateMbps = 0;
    private volatile String status = "Waiting for surface";
    private volatile long decodedFrames = -1;
    private volatile long droppedFrames = -1;
    private volatile double inputFps = -1.0;
    private volatile double bitrateMbps = -1.0;
    private volatile boolean touchInputEnabled = false;
    private volatile float lastTouchX = 0.5f;
    private volatile float lastTouchY = 0.5f;
    private boolean debugInputLogging = false;
    private boolean scrollGestureActive = false;
    private boolean ignoreTouchUntilUp = false;
    private float lastScrollFocusX = 0.0f;
    private float lastScrollFocusY = 0.0f;
    private volatile long lastStatsOverlayRenderMs = 0L;
    private volatile boolean statsOverlayRenderPending = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        mainHandler = new Handler(Looper.getMainLooper());
        touchInputEnabled = getIntent().getBooleanExtra("touch_enabled", false);
        debugInputLogging = getIntent().getBooleanExtra("debug_input_logging", false);
        if (debugInputLogging) {
            Log.i(TAG, "Touch input initial state: " + touchInputEnabled);
        }

        surfaceView = new SurfaceView(this);
        surfaceView.getHolder().addCallback(this);
        surfaceView.setClickable(true);
        surfaceView.setLongClickable(true);

        overlay = new TextView(this);
        overlay.setTextColor(Color.WHITE);
        overlay.setBackgroundColor(0x99000000);
        overlay.setTypeface(Typeface.MONOSPACE);
        overlay.setTextSize(12);
        overlay.setPadding(14, 10, 14, 10);
        overlay.setText(status);

        statusPanel = new TextView(this);
        statusPanel.setTextColor(0xffd8f5d0);
        statusPanel.setBackgroundColor(Color.BLACK);
        statusPanel.setTypeface(Typeface.MONOSPACE);
        statusPanel.setTextSize(11);
        statusPanel.setGravity(Gravity.START | Gravity.TOP);
        statusPanel.setMovementMethod(new ScrollingMovementMethod());
        statusPanel.setPadding(18, 16, 18, 80);
        statusPanel.setVisibility(View.GONE);

        modeButton = new TextView(this);
        modeButton.setTextColor(Color.WHITE);
        modeButton.setBackgroundColor(0xaa223344);
        modeButton.setTypeface(Typeface.DEFAULT_BOLD);
        modeButton.setTextSize(13);
        modeButton.setPadding(18, 12, 18, 12);
        modeButton.setText("Status");

        FrameLayout.LayoutParams overlayParams = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP | Gravity.START
        );
        FrameLayout.LayoutParams modeParams = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM | Gravity.END
        );
        modeParams.setMargins(0, 0, 16, 16);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        root.addView(surfaceView, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
        ));
        root.addView(statusPanel, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
        ));
        root.addView(overlay, overlayParams);
        root.addView(modeButton, modeParams);
        setContentView(root);

        surfaceView.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                overlay.setVisibility(overlay.getVisibility() == View.VISIBLE ? View.GONE : View.VISIBLE);
            }
        });
        surfaceView.setOnLongClickListener(new View.OnLongClickListener() {
            @Override
            public boolean onLongClick(View v) {
                touchInputEnabled = !touchInputEnabled;
                cancelTouchDisable();
                renderOverlay();
                return true;
            }
        });
        surfaceView.setOnTouchListener(new View.OnTouchListener() {
            @Override
            public boolean onTouch(View v, MotionEvent event) {
                if (!touchInputEnabled) {
                    return false;
                }
                if (debugInputLogging) {
                    Log.i(TAG, "Surface touch action=" + event.getActionMasked() + " pointers=" + event.getPointerCount());
                }
                if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
                    scheduleTouchDisable();
                } else if (event.getActionMasked() == MotionEvent.ACTION_UP
                        || event.getActionMasked() == MotionEvent.ACTION_CANCEL) {
                    cancelTouchDisable();
                }
                sendTouchEvent(v, event);
                return true;
            }
        });
        modeButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                toggleMode();
            }
        });
    }

    @Override
    protected void onDestroy() {
        stopClient();
        stopStatusClient();
        cancelTouchDisable();
        super.onDestroy();
    }

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        currentSurfaceHolder = holder;
        if (mode == MODE_DISPLAY) {
            startClient(holder);
        }
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        currentSurfaceHolder = null;
        stopClient();
    }

    @Override
    public void onStatus(final String status) {
        this.status = status;
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                renderOverlay();
            }
        });
    }

    @Override
    public void onConfig(final int width, final int height, final int fps, final int bitrateMbps) {
        configuredWidth = width;
        configuredHeight = height;
        configuredFps = fps;
        configuredBitrateMbps = bitrateMbps;
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                renderOverlay();
            }
        });
    }

    @Override
    public void onStats(
            final long decodedFrames,
            final long droppedFrames,
            final double inputFps,
            final double bitrateMbps
    ) {
        this.decodedFrames = decodedFrames;
        this.droppedFrames = droppedFrames;
        this.inputFps = inputFps;
        this.bitrateMbps = bitrateMbps;
        scheduleStatsOverlayRender();
    }

    @Override
    public void onError(final String message) {
        status = "Retrying: " + message;
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                renderOverlay();
            }
        });
    }

    @Override
    public void onStatusConnecting(final String status) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                statusPanel.setText(status);
            }
        });
    }

    @Override
    public void onSnapshot(final StatusClient.StatusSnapshot snapshot) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                renderStatusPanel(snapshot);
            }
        });
    }

    @Override
    public void onStatusError(final String message) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                statusPanel.setText("Retrying status panel\n" + message);
            }
        });
    }

    private void startClient(SurfaceHolder holder) {
        stopClient();
        status = "Starting receiver";
        decodedFrames = -1;
        droppedFrames = -1;
        inputFps = -1.0;
        bitrateMbps = -1.0;
        configuredBitrateMbps = 0;
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        streamClient = new StreamClient(holder.getSurface(), metrics.widthPixels, metrics.heightPixels, this);
        streamThread = new Thread(streamClient, "AndroidMonitorStream");
        streamThread.start();
        renderOverlay();
    }

    private void stopClient() {
        StreamClient oldClient = streamClient;
        streamClient = null;
        if (oldClient != null) {
            oldClient.stop();
        }
        streamThread = null;
    }

    private void startStatusClient() {
        stopStatusClient();
        statusClient = new StatusClient(this);
        statusThread = new Thread(statusClient, "AndroidMonitorStatus");
        statusThread.start();
        statusPanel.setText("Starting status panel");
    }

    private void stopStatusClient() {
        StatusClient oldClient = statusClient;
        statusClient = null;
        if (oldClient != null) {
            oldClient.stop();
        }
        statusThread = null;
    }

    private void toggleMode() {
        if (mode == MODE_DISPLAY) {
            mode = MODE_STATUS;
            stopClient();
            touchInputEnabled = false;
            scrollGestureActive = false;
            ignoreTouchUntilUp = false;
            cancelTouchDisable();
            surfaceView.setVisibility(View.GONE);
            overlay.setVisibility(View.GONE);
            statusPanel.setVisibility(View.VISIBLE);
            modeButton.setText("Display");
            startStatusClient();
        } else {
            mode = MODE_DISPLAY;
            stopStatusClient();
            statusPanel.setVisibility(View.GONE);
            surfaceView.setVisibility(View.VISIBLE);
            overlay.setVisibility(View.VISIBLE);
            modeButton.setText("Status");
            if (currentSurfaceHolder != null) {
                startClient(currentSurfaceHolder);
            }
        }
    }

    private void renderOverlay() {
        StringBuilder builder = new StringBuilder();
        builder.append(status);
        if (configuredWidth > 0 && configuredHeight > 0) {
            builder.append('\n')
                    .append(configuredWidth)
                    .append('x')
                    .append(configuredHeight)
                    .append(" @ ")
                    .append(configuredFps)
                    .append(" fps");
            if (configuredBitrateMbps > 0) {
                builder.append(" target=")
                        .append(configuredBitrateMbps)
                        .append(" Mbps");
            }
        }
        if (inputFps >= 0.0 && bitrateMbps >= 0.0) {
            builder.append('\n')
                    .append(String.format(Locale.US, "in=%.1f fps %.2f Mbps", inputFps, bitrateMbps));
        }
        if (decodedFrames >= 0) {
            builder.append('\n')
                    .append("decoded=")
                    .append(decodedFrames)
                    .append(" dropped=")
                    .append(droppedFrames);
        }
        builder.append('\n')
                .append("touch=")
                .append(touchInputEnabled ? "on" : "off");
        overlay.setText(builder.toString());
    }

    private void scheduleStatsOverlayRender() {
        if (mainHandler == null) {
            return;
        }

        long now = System.currentTimeMillis();
        long elapsed = now - lastStatsOverlayRenderMs;
        if (elapsed >= STATS_OVERLAY_INTERVAL_MS) {
            lastStatsOverlayRenderMs = now;
            mainHandler.post(new Runnable() {
                @Override
                public void run() {
                    renderOverlay();
                }
            });
            return;
        }

        if (statsOverlayRenderPending) {
            return;
        }

        statsOverlayRenderPending = true;
        mainHandler.postDelayed(new Runnable() {
            @Override
            public void run() {
                statsOverlayRenderPending = false;
                lastStatsOverlayRenderMs = System.currentTimeMillis();
                renderOverlay();
            }
        }, STATS_OVERLAY_INTERVAL_MS - elapsed);
    }

    private void renderStatusPanel(StatusClient.StatusSnapshot snapshot) {
        StringBuilder builder = new StringBuilder();
        builder.append("Android Monitor Status\n");
        builder.append(snapshot.host).append('\n');
        builder.append(snapshot.timestamp).append("\n\n");
        appendSection(builder, "Command", snapshot.commandOutput);
        appendSection(builder, "Build", snapshot.buildStatus);
        appendSection(builder, "CPU", snapshot.cpu);
        appendSection(builder, "Disk", snapshot.disk);
        appendSection(builder, "Memory", snapshot.memory);
        appendSection(builder, "Network", snapshot.network);
        appendSection(builder, "Logs", snapshot.logTail);
        statusPanel.setText(builder.toString());
    }

    private void appendSection(StringBuilder builder, String title, String value) {
        if (value == null || value.length() == 0) {
            return;
        }
        builder.append("== ").append(title).append(" ==\n");
        builder.append(value).append("\n\n");
    }

    private void scheduleTouchDisable() {
        cancelTouchDisable();
        touchDisableRunnable = new Runnable() {
            @Override
            public void run() {
                touchDisableRunnable = null;
                if (!touchInputEnabled) {
                    return;
                }
                touchInputEnabled = false;
                StreamClient client = streamClient;
                if (client != null) {
                    client.sendTouch("cancel", lastTouchX, lastTouchY);
                }
                renderOverlay();
            }
        };
        mainHandler.postDelayed(touchDisableRunnable, ViewConfiguration.getLongPressTimeout());
    }

    private void cancelTouchDisable() {
        if (touchDisableRunnable != null && mainHandler != null) {
            mainHandler.removeCallbacks(touchDisableRunnable);
            touchDisableRunnable = null;
        }
    }

    private void sendTouchEvent(View view, MotionEvent event) {
        StreamClient client = streamClient;
        if (client == null || view.getWidth() <= 0 || view.getHeight() <= 0) {
            return;
        }

        if (ignoreTouchUntilUp) {
            int action = event.getActionMasked();
            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
                ignoreTouchUntilUp = false;
                cancelTouchDisable();
            }
            return;
        }

        if (event.getPointerCount() >= 2 || scrollGestureActive) {
            handleScrollGesture(view, event, client);
            return;
        }

        String action;
        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                action = "down";
                break;
            case MotionEvent.ACTION_MOVE:
                action = "move";
                break;
            case MotionEvent.ACTION_UP:
                action = "up";
                break;
            case MotionEvent.ACTION_CANCEL:
                action = "cancel";
                break;
            default:
                return;
        }

        lastTouchX = event.getX() / (float) view.getWidth();
        lastTouchY = event.getY() / (float) view.getHeight();
        client.sendTouch(action, lastTouchX, lastTouchY);
    }

    private void handleScrollGesture(View view, MotionEvent event, StreamClient client) {
        int action = event.getActionMasked();
        if (event.getPointerCount() < 2) {
            scrollGestureActive = false;
            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
                cancelTouchDisable();
                ignoreTouchUntilUp = false;
            }
            return;
        }

        cancelTouchDisable();
        float focusX = pointerFocusX(event);
        float focusY = pointerFocusY(event);

        if (!scrollGestureActive || action == MotionEvent.ACTION_POINTER_DOWN) {
            scrollGestureActive = true;
            lastScrollFocusX = focusX;
            lastScrollFocusY = focusY;
            client.sendTouch("cancel", lastTouchX, lastTouchY);
            return;
        }

        if (action != MotionEvent.ACTION_MOVE) {
            if (action == MotionEvent.ACTION_POINTER_UP) {
                scrollGestureActive = false;
                ignoreTouchUntilUp = true;
            } else if (action == MotionEvent.ACTION_CANCEL) {
                scrollGestureActive = false;
                ignoreTouchUntilUp = false;
            }
            return;
        }

        float deltaX = focusX - lastScrollFocusX;
        float deltaY = focusY - lastScrollFocusY;
        lastScrollFocusX = focusX;
        lastScrollFocusY = focusY;

        if (Math.abs(deltaX) < 1.0f && Math.abs(deltaY) < 1.0f) {
            return;
        }

        client.sendScroll(
                focusX / (float) view.getWidth(),
                focusY / (float) view.getHeight(),
                deltaX / (float) view.getWidth(),
                deltaY / (float) view.getHeight()
        );
    }

    private float pointerFocusX(MotionEvent event) {
        float total = 0.0f;
        for (int i = 0; i < event.getPointerCount(); i++) {
            total += event.getX(i);
        }
        return total / (float) event.getPointerCount();
    }

    private float pointerFocusY(MotionEvent event) {
        float total = 0.0f;
        for (int i = 0; i < event.getPointerCount(); i++) {
            total += event.getY(i);
        }
        return total / (float) event.getPointerCount();
    }
}

package dev.campus.jwimport;

import android.app.*;
import android.os.*;
import android.content.*;
import android.net.Uri;
import android.webkit.*;
import android.widget.*;
import android.view.*;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.net.http.SslError;
import org.json.*;
import java.io.*;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** SDK-owned UI. The host launches this activity and reads the confirmed result. */
public final class AcademicImportActivity extends Activity {
    private static final String LOCAL_URL = "file:///android_asset/jwimport/index.html";
    private static final int OPEN_FILE = 81;
    private WebView local, remote;
    private final ArrayList<WebView> parentWindows = new ArrayList<>();
    private boolean desktopMode, closingWindows;
    private LinearLayout remoteLayout;
    private EditText address;
    private Button captureButton;
    private String school = "自定义学校";
    private String entryUrl;
    private String autoReadScript, autoSignature = "";
    private boolean foreground, probing;
    private final Set<String> sessionUrls = new LinkedHashSet<>();
    private int generation;
    private boolean destroyed, startedEntry, busy, finishingResult, localVisible = true, hostPicker;
    private int backgroundColor, surfaceColor, foregroundColor, accentColor, onAccentColor;
    private int separatorColor;
    private ArrayList<String> alternatives = new ArrayList<>();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final ExecutorService files = Executors.newSingleThreadExecutor();
    private final Runnable autoReader = new Runnable() {
        @Override public void run() {
            if (destroyed || !foreground || localVisible || remote == null) return;
            if (!busy && !probing && !finishingResult && autoReadScript != null) {
                WebView view = remote; int token = generation; probing = true;
                view.evaluateJavascript(autoReadScript, value -> {
                    if (token != generation || view != remote) return;
                    probing = false;
                    if (destroyed || !foreground || localVisible || view != remote || token != generation || busy) return;
                    try {
                        Object decoded = new JSONTokener(value).nextValue();
                        if (decoded instanceof String && !((String)decoded).isEmpty() && !decoded.equals(autoSignature)) {
                            autoSignature = (String)decoded; capture(true);
                        }
                    } catch (Exception ignored) { }
                });
            }
            handler.postDelayed(this, 1600);
        }
    };

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        setResult(RESULT_CANCELED);
        try (InputStream in = getAssets().open("jwimport/watch.js")) {
            autoReadScript = AcademicImport.readUtf8(in, 32000);
        } catch (IOException ignored) { }
        hostPicker = getIntent().getBooleanExtra("hostPicker", false);
        boolean dark = getIntent().getBooleanExtra("dark", false);
        backgroundColor = getIntent().getIntExtra("background", dark ? Color.rgb(14,16,19) : Color.rgb(243,242,238));
        surfaceColor = getIntent().getIntExtra("surface", dark ? Color.rgb(25,28,33) : Color.rgb(255,254,252));
        foregroundColor = getIntent().getIntExtra("foreground", dark ? Color.rgb(246,244,239) : Color.rgb(23,25,28));
        accentColor = getIntent().getIntExtra("accent", dark ? Color.rgb(246,244,239) : Color.rgb(23,25,28));
        onAccentColor = getIntent().getIntExtra("onAccent", dark ? Color.rgb(23,25,28) : Color.rgb(255,254,252));
        separatorColor = dark ? Color.rgb(48,54,64) : Color.rgb(220,218,212);
        ArrayList<String> suppliedAlternatives = getIntent().getStringArrayListExtra("entryAlternatives");
        if (suppliedAlternatives != null) alternatives = suppliedAlternatives;
        getWindow().setStatusBarColor(backgroundColor);
        getWindow().setNavigationBarColor(backgroundColor);
        getWindow().getDecorView().setSystemUiVisibility(dark ? 0 : View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        local = new WebView(this);
        local.setBackgroundColor(backgroundColor);
        WebSettings settings = local.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setAllowFileAccess(false); settings.setAllowContentAccess(false);
        settings.setBlockNetworkLoads(true);
        local.addJavascriptInterface(new LocalBridge(), "JwImportNative");
        local.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return !LOCAL_URL.equals(request.getUrl().toString());
            }
            @Override public void onPageFinished(WebView view, String url) {
                if (!startedEntry && LOCAL_URL.equals(url)) {
                    startedEntry = true;
                    local.evaluateJavascript("typeof window.JwImportUI === 'object'", ready -> {
                        if (destroyed) return;
                        if (!"true".equals(ready)) {
                            new AlertDialog.Builder(AcademicImportActivity.this)
                                .setMessage("导入页面未能初始化。请更新 Android System WebView 后重试；宿主也应检查 SDK assets 是否正确打包。")
                                .setPositiveButton("返回", (dialog, which) -> finish()).setCancelable(false).show();
                            return;
                        }
                        String mode = "document.documentElement.classList.toggle('dark'," + dark + ");" +
                            "document.documentElement.classList.toggle('host-picker'," + hostPicker + ");" +
                            "document.documentElement.style.setProperty('--iko-bg','" + cssColor(backgroundColor) + "');" +
                            "document.documentElement.style.setProperty('--iko-surface','" + cssColor(surfaceColor) + "');" +
                            "document.documentElement.style.setProperty('--iko-fg','" + cssColor(foregroundColor) + "');" +
                            "document.documentElement.style.setProperty('--iko-accent','" + cssColor(accentColor) + "');" +
                            "document.documentElement.style.setProperty('--iko-on-accent','" + cssColor(onAccentColor) + "');";
                        local.evaluateJavascript(mode, null);
                        String entry = getIntent().getStringExtra("entryUrl");
                        if (entry != null) openSchool(entry, getIntent().getStringExtra("school"), getIntent().getBooleanExtra("desktop", false));
                    });
                }
            }
        });
        applyInsets(local); setContentView(local); local.loadUrl(LOCAL_URL);
    }

    public final class LocalBridge {
        @JavascriptInterface public void openSchool(String url, String name, boolean desktop) {
            handler.post(() -> AcademicImportActivity.this.openSchool(url, name, desktop));
        }
        @JavascriptInterface public void openFile() {
            handler.post(() -> {
                if (destroyed || finishingResult) return;
                try { startActivityForResult(new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("*/*").addCategory(Intent.CATEGORY_OPENABLE), OPEN_FILE); }
                catch (ActivityNotFoundException e) { notice("设备没有文件选择器，可粘贴学校导出的课表内容。"); }
            });
        }
        @JavascriptInterface public void resumePage() { handler.post(() -> { if (remote != null && !destroyed) showRemote(); }); }
        @JavascriptInterface public void compatibility() { handler.post(AcademicImportActivity.this::requestCompatibility); }
        @JavascriptInterface public void cancel() { handler.post(() -> { if (!finishingResult) finish(); }); }
        @JavascriptInterface public void confirm(String result) {
            handler.post(() -> {
                if (destroyed || finishingResult) return;
                finishingResult = true;
                files.execute(() -> {
                    try {
                        Intent data = AcademicImport.storeResult(AcademicImportActivity.this, result);
                        handler.post(() -> { if (!destroyed) { setResult(RESULT_OK, data); finish(); } });
                    } catch (Exception e) {
                        handler.post(() -> { if (!destroyed) { finishingResult = false; localJs("JwImportUI.confirmFailed()"); notice("导入结果保存失败，请重新确认：" + e.getMessage()); } });
                    }
                });
            });
        }
    }

    private int dp(int n) { return Math.round(n * getResources().getDisplayMetrics().density); }
    private String cssColor(int color) { return String.format(java.util.Locale.ROOT, "#%06X", color & 0xFFFFFF); }
    private void applyInsets(View view) {
        view.setOnApplyWindowInsetsListener((v, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.ime());
                v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            } else v.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(), insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets;
        });
    }
    private Button button(String label, Runnable action) {
        Button b = new Button(this); b.setText(label); b.setAllCaps(false); b.setTextSize(13);
        b.setMinHeight(dp(48)); b.setTextColor(foregroundColor); b.setBackground(solid(surfaceColor, separatorColor));
        b.setOnClickListener(v -> action.run()); return b;
    }
    private GradientDrawable solid(int fill, int stroke) {
        GradientDrawable shape = new GradientDrawable(); shape.setColor(fill); shape.setCornerRadius(dp(12)); shape.setStroke(dp(1), stroke); return shape;
    }
    private Button primaryButton(String label, Runnable action) {
        Button b = button(label, action); b.setTextColor(onAccentColor); b.setBackground(solid(accentColor, accentColor)); return b;
    }
    private boolean validUrl(String url) {
        if (url == null || url.length() > 4096) return false;
        Uri parsed = Uri.parse(url);
        return ("https".equals(parsed.getScheme()) || "http".equals(parsed.getScheme())) && parsed.getHost() != null && parsed.getUserInfo() == null;
    }
    private void openSchool(String url, String name, boolean desktop) {
        if (destroyed || finishingResult) return;
        if (!validUrl(url)) { notice("请输入有效的 http 或 https 学校教务网址"); return; }
        closeRemote();
        url = SchoolEntryRecovery.initial(url);
        entryUrl = url;
        sessionUrls.clear();
        school = name == null || name.isEmpty() ? "自定义学校" : name.substring(0, Math.min(200, name.length()));
        remoteLayout = new LinearLayout(this); remoteLayout.setOrientation(LinearLayout.VERTICAL); applyInsets(remoteLayout);
        remoteLayout.setBackgroundColor(backgroundColor);
        LinearLayout heading = new LinearLayout(this); heading.setGravity(Gravity.CENTER_VERTICAL); heading.setPadding(dp(12), dp(4), dp(8), dp(4));
        TextView help = new TextView(this);
        help.setText(school + "\n打开完整课表后自动读取，确认前不会替换已有课程。");
        help.setTextColor(foregroundColor); help.setTextSize(13); help.setPadding(dp(4), dp(8), dp(4), dp(8));
        heading.addView(help, new LinearLayout.LayoutParams(0, -2, 1));
        Button tools = button("网页工具", () -> { });
        tools.setOnClickListener(v -> showWebTools(tools));
        heading.addView(tools); remoteLayout.addView(heading);
        LinearLayout bar = new LinearLayout(this); bar.setPadding(dp(12), 0, dp(12), dp(6)); bar.setVisibility(View.GONE);
        address = new EditText(this); address.setSingleLine(true); address.setTextSize(12); address.setText(url);
        address.setTextColor(foregroundColor); address.setHintTextColor(foregroundColor);
        address.setBackground(solid(surfaceColor, foregroundColor));
        bar.addView(address, new LinearLayout.LayoutParams(0, dp(48), 1));
        bar.addView(primaryButton("前往", () -> { String target = address.getText().toString().trim(); if (validUrl(target)) remote.loadUrl(target); else notice("网址格式不正确"); }));
        addressBar = bar;
        remoteLayout.addView(bar);
        remote = new WebView(this);
        desktopMode = desktop;
        configureSchoolWindow(remote);
        remoteLayout.addView(remote, new LinearLayout.LayoutParams(-1, 0, 1));
        LinearLayout actions = new LinearLayout(this); actions.setPadding(dp(10), dp(6), dp(10), dp(6));
        Button changeSchool = button("更换学校", () -> {
            if (hostPicker) { closeRemote(); setResult(RESULT_CANCELED); finish(); }
            else { closeRemote(); showLocal(); localJs("JwImportUI.reset()"); }
        });
        actions.addView(changeSchool, new LinearLayout.LayoutParams(0, dp(52), 1));
        captureButton = primaryButton("读取课表", this::capture);
        actions.addView(captureButton, new LinearLayout.LayoutParams(0, -2, 1));
        remoteLayout.addView(actions); showRemote(); remote.loadUrl(url);
    }
    private void configureSchoolWindow(WebView browser) {
        browser.setBackgroundColor(surfaceColor);
        WebSettings settings = browser.getSettings();
        settings.setJavaScriptEnabled(true); settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false); settings.setAllowContentAccess(false);
        settings.setBuiltInZoomControls(true); settings.setDisplayZoomControls(false);
        settings.setUseWideViewPort(true); settings.setLoadWithOverviewMode(true);
        settings.setSupportMultipleWindows(true);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        applyDesktopMode(browser);
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(browser, true);
        // No addJavascriptInterface is ever attached to the university WebView.
        browser.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onCreateWindow(WebView source, boolean isDialog, boolean userGesture, Message result) {
                if (destroyed || closingWindows || finishingResult || source != remote || !userGesture || parentWindows.size() >= 3
                        || result == null || !(result.obj instanceof WebView.WebViewTransport)) return false;
                WebView child = new WebView(AcademicImportActivity.this);
                configureSchoolWindow(child);
                int index = remoteLayout.indexOfChild(source);
                if (index < 0) { child.destroy(); return false; }
                generation++; probing = false; autoSignature = ""; setBusy(false);
                parentWindows.add(source); source.onPause(); remoteLayout.removeView(source);
                remote = child;
                remoteLayout.addView(child, index, new LinearLayout.LayoutParams(-1, 0, 1));
                ((WebView.WebViewTransport)result.obj).setWebView(child); result.sendToTarget();
                return true;
            }
            @Override public void onCloseWindow(WebView window) {
                if (destroyed || closingWindows) return;
                if (window == remote) closeChildWindow();
                else if (parentWindows.remove(window)) { window.stopLoading(); window.destroy(); }
            }
        });
        browser.setWebViewClient(new WebViewClient() {
            private final SchoolEntryRecovery recovery = new SchoolEntryRecovery();
            private boolean recoverEntry(WebView view, WebResourceRequest request, String target) {
                if (target == null || view != remote || destroyed || finishingResult) return false;
                final int token = generation;
                final String failed = request.getUrl().toString();
                handler.post(() -> {
                    if (destroyed || finishingResult || view != remote || token != generation
                        || !failed.equals(view.getUrl())) return;
                    notice("已切换到研究生学生登录页。");
                    view.loadUrl(target);
                });
                return true;
            }
            @Override public void onPageStarted(WebView view, String url, android.graphics.Bitmap icon) {
                if (view == remote) {
                    generation++; autoSignature = ""; probing = false; setBusy(false);
                    if (validUrl(url) && sessionUrls.size() < 64) {
                        Uri clean = Uri.parse(url).buildUpon().clearQuery().fragment(null).build();
                        sessionUrls.add(clean.toString());
                    }
                }
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return !validUrl(request.getUrl().toString());
            }
            @Override public void onPageFinished(WebView view, String url) {
                if (view == remote && address != null) address.setText(url);
            }
            @Override public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
                handler.cancel(); notice("学校网页证书校验失败。请使用学校公布的有效入口。");
            }
            @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (view != remote || destroyed || finishingResult || !request.isForMainFrame()) return;
                if (recoverEntry(view, request, recovery.networkFailure(request.getUrl().toString(), request.getMethod(), request.isForMainFrame(), error.getErrorCode()))) return;
                if (view == remote && request.isForMainFrame()) notice("学校页面暂未打开。可在网页工具中重新打开登录入口，或稍后重试。");
            }
            @Override public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse response) {
                if (view != remote || destroyed || finishingResult || !request.isForMainFrame()) return;
                if (recoverEntry(view, request, recovery.httpFailure(request.getUrl().toString(), request.getMethod(), request.isForMainFrame(), response.getStatusCode()))) return;
                if (view == remote && request.isForMainFrame()) notice("学校网页返回 HTTP " + response.getStatusCode() + "。可在网页工具中重新打开登录入口。");
            }
        });
    }
    private void applyDesktopMode(WebView browser) {
        String userAgent = WebSettings.getDefaultUserAgent(this);
        if (desktopMode) userAgent = userAgent.replaceFirst("\\(Linux;[^)]*\\)", "(X11; Linux x86_64)").replace("Mobile ", "").replace("; wv", "");
        browser.getSettings().setUserAgentString(userAgent);
    }
    private boolean closeChildWindow() {
        if (remote == null || closingWindows || parentWindows.isEmpty()) return false;
        closingWindows = true;
        generation++; probing = false; autoSignature = ""; setBusy(false);
        int index = remoteLayout.indexOfChild(remote);
        remoteLayout.removeView(remote); remote.stopLoading(); remote.destroy();
        remote = parentWindows.remove(parentWindows.size() - 1);
        remoteLayout.addView(remote, Math.max(0, index), new LinearLayout.LayoutParams(-1, 0, 1));
        remote.onResume();
        if (address != null) address.setText(remote.getUrl());
        closingWindows = false;
        return true;
    }
    private LinearLayout addressBar;
    private void showWebTools(View anchor) {
        PopupMenu menu = new PopupMenu(this, anchor);
        menu.getMenu().add("网页后退").setOnMenuItemClickListener(item -> { if (remote != null && remote.canGoBack()) remote.goBack(); else closeChildWindow(); return true; });
        if (!parentWindows.isEmpty()) menu.getMenu().add("关闭当前子窗口").setOnMenuItemClickListener(item -> { closeChildWindow(); return true; });
        menu.getMenu().add(desktopMode ? "切换为手机版网页" : "切换为桌面版网页").setOnMenuItemClickListener(item -> {
            desktopMode = !desktopMode;
            for (WebView window : parentWindows) applyDesktopMode(window);
            if (remote != null) { applyDesktopMode(remote); remote.reload(); }
            return true;
        });
        menu.getMenu().add("重新加载").setOnMenuItemClickListener(item -> { if (remote != null) remote.reload(); return true; });
        menu.getMenu().add("重新打开登录入口").setOnMenuItemClickListener(item -> {
            if (remote != null && validUrl(entryUrl)) remote.loadUrl(entryUrl);
            return true;
        });
        menu.getMenu().add("切换本校账号").setOnMenuItemClickListener(item -> {
            new AlertDialog.Builder(this).setMessage("仅清理本校网页的登录状态，之后需要重新登录。不会删除 IKO 账号、额度或课表，也不会清理其他学校的登录。")
                .setNegativeButton("取消", null).setPositiveButton("切换账号", (dialog, which) -> resetSchoolLogin()).show();
            return true;
        });
        menu.getMenu().add(addressBar != null && addressBar.getVisibility() == View.VISIBLE ? "收起网址" : "编辑网址").setOnMenuItemClickListener(item -> {
            if (addressBar == null) return true;
            boolean show = addressBar.getVisibility() != View.VISIBLE; addressBar.setVisibility(show ? View.VISIBLE : View.GONE);
            if (show && address != null) { address.requestFocus(); address.setSelection(address.length()); ((android.view.inputmethod.InputMethodManager)getSystemService(INPUT_METHOD_SERVICE)).showSoftInput(address, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT); }
            return true;
        });
        for (String alternative : alternatives) {
            if (!validUrl(alternative)) continue;
            String host = Uri.parse(alternative).getHost();
            menu.getMenu().add(SchoolEntryRecovery.isHfutRoot(alternative) ? "统一身份认证（备用）" : "备用入口 · " + host).setOnMenuItemClickListener(item -> {
                if (remote != null) {
                    if (address != null) address.setText(alternative);
                    remote.loadUrl(alternative);
                }
                return true;
            });
        }
        menu.show();
    }
    private void resetSchoolLogin() {
        if (remote == null || destroyed || finishingResult) return;
        final WebView view = remote; final int token = ++generation;
        setBusy(true); autoSignature = ""; probing = false;
        CookieManager manager = CookieManager.getInstance();
        try {
            Map<String,Set<String>> requests = SchoolCookieReset.requests(entryUrl, sessionUrls, manager::getCookie);
            AtomicInteger remaining = new AtomicInteger(requests.values().stream().mapToInt(Set::size).sum());
            AtomicBoolean failed = new AtomicBoolean(), finished = new AtomicBoolean();
            Runnable timeout = () -> {
                if (!finished.compareAndSet(false, true) || destroyed || view != remote || token != generation) return;
                setBusy(false); notice("本校登录状态清理超时，请在学校网页退出账号后重试。");
            };
            Runnable complete = () -> {
                if (!finished.compareAndSet(false, true)) return;
                handler.removeCallbacks(timeout);
                if (destroyed || view != remote || token != generation) return;
                manager.flush(); setBusy(false);
                // Destroy this school's page windows as well as cookies, so
                // sessionStorage and paused child windows cannot restore it.
                openSchool(entryUrl, school, desktopMode);
                if (failed.get()) notice("部分网页登录状态未能清理。若仍提示账号冲突，请在学校原登录页面退出账号后重试。");
            };
            for (String scope : requests.keySet()) WebStorage.getInstance().deleteOrigin(scope);
            if (remaining.get() == 0) { complete.run(); return; }
            handler.postDelayed(timeout, 10000);
            for (Map.Entry<String,Set<String>> request : requests.entrySet()) for (String expired : request.getValue()) {
                manager.setCookie(request.getKey(), expired, ok -> {
                    if (!Boolean.TRUE.equals(ok)) failed.set(true);
                    if (remaining.decrementAndGet() == 0) handler.post(complete);
                });
            }
        } catch (Exception error) {
            setBusy(false); notice("本校登录状态暂未清理。可在学校网页退出账号后重新登录。");
        }
    }
    private void requestCompatibility() {
        if (!hostPicker || remote == null || destroyed || finishingResult) { notice("当前版本无法切换兼容读取"); return; }
        String current = remote.getUrl();
        if (!validUrl(current)) { notice("当前学校网页没有有效的读取地址"); return; }
        CookieManager.getInstance().flush();
        setResult(RESULT_FIRST_USER, new Intent().putExtra("compatibilityUrl", current));
        closeRemote(); finish();
    }
    private void setBusy(boolean value) {
        busy = value;
        if (captureButton != null) { captureButton.setEnabled(!value); captureButton.setText(value ? "读取中…" : "导入课表"); }
    }
    private void capture() {
        capture(false);
    }
    private void capture(boolean automatic) {
        if (remote == null || busy || destroyed) return;
        final int token = ++generation; probing = false; setBusy(true);
        try (InputStream in = getAssets().open("jwimport/provider.js")) {
            remote.evaluateJavascript(AcademicImport.readUtf8(in, AcademicImport.MAX_BYTES), ignored -> poll(token, 0, automatic));
        } catch (Exception e) { setBusy(false); if (!automatic) notice("无法加载采集器"); }
    }
    private void poll(int token, int count, boolean automatic) {
        if (destroyed || remote == null || token != generation) return;
        if (automatic && !foreground) { autoSignature = ""; setBusy(false); return; }
        if (count > 40) { setBusy(false); if (!automatic) notice("读取超时，请等待课表页加载完成再试"); return; }
        remote.evaluateJavascript("JSON.stringify(window.__campusCapture || null)", value -> {
            if (destroyed || remote == null || token != generation) return;
            if (automatic && !foreground) { autoSignature = ""; setBusy(false); return; }
            try {
                Object decoded = new JSONTokener(value).nextValue();
                if (decoded instanceof String && !"null".equals(decoded)) {
                    JSONObject capture = new JSONObject((String) decoded);
                    if (capture.optBoolean("done")) {
                        String payload = capture.toString();
                        if (payload.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > AcademicImport.MAX_BYTES) { setBusy(false); if (!automatic) notice("课表页面超过 4 MB 限制，可导出精简文件后导入"); return; }
                        local.evaluateJavascript("JwImportUI.receiveCapture(" + JSONObject.quote(payload) + "," + JSONObject.quote(school) + "," + automatic + ")", parsed -> {
                            if (destroyed || token != generation) return;
                            setBusy(false);
                            if (automatic && !foreground) { autoSignature = ""; return; }
                            if (!automatic || "true".equals(parsed)) showLocal();
                        });
                        return;
                    }
                }
            } catch (Exception ignored) { }
            handler.postDelayed(() -> poll(token, count + 1, automatic), 300);
        });
    }
    private void localJs(String script) { if (!destroyed) local.evaluateJavascript(script, null); }
    private void showLocal() { localVisible = true; handler.removeCallbacks(autoReader); setContentView(local); }
    private void startAutoReader() { handler.removeCallbacks(autoReader); if (foreground && !localVisible) handler.postDelayed(autoReader, 700); }
    private void showRemote() { localVisible = false; setContentView(remoteLayout); startAutoReader(); }
    private void closeRemote() {
        closingWindows = true;
        handler.removeCallbacks(autoReader); autoSignature = ""; probing = false;
        generation++; busy = false; captureButton = null; address = null; addressBar = null;
        if (remote != null) { remote.stopLoading(); remoteLayout.removeView(remote); remote.destroy(); remote = null; }
        for (WebView window : parentWindows) { window.stopLoading(); window.destroy(); }
        parentWindows.clear();
        closingWindows = false;
    }
    private void notice(String message) { if (!destroyed && !isFinishing()) new AlertDialog.Builder(this).setMessage(message).setPositiveButton("知道了", null).show(); }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != OPEN_FILE || result != RESULT_OK || data == null || data.getData() == null) return;
        Uri uri = data.getData();
        files.execute(() -> {
            try (InputStream in = getContentResolver().openInputStream(uri)) {
                String text = AcademicImport.readUtf8(in, AcademicImport.MAX_BYTES);
                if (text.indexOf('\uFFFD') >= 0) {
                    try (InputStream legacy = getContentResolver().openInputStream(uri)) {
                        byte[] bytes = readBytes(legacy); text = new String(bytes, java.nio.charset.Charset.forName("GB18030"));
                    }
                }
                final String source = text;
                handler.post(() -> { if (!destroyed) { showLocal(); localJs("JwImportUI.receiveSource(" + JSONObject.quote(source) + ",'file')"); } });
            } catch (Exception e) { handler.post(() -> notice("文件读取失败：" + e.getMessage())); }
        });
    }
    private byte[] readBytes(InputStream in) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream(); byte[] buffer = new byte[8192]; int size;
        while ((size = in.read(buffer)) != -1) { if (out.size() + size > AcademicImport.MAX_BYTES) throw new IOException("文件超过 4 MB"); out.write(buffer, 0, size); }
        return out.toByteArray();
    }
    @Override public void onBackPressed() {
        if (finishingResult) return;
        if (!localVisible && remote != null) { if (remote.canGoBack()) remote.goBack(); else if (closeChildWindow()) { } else if (hostPicker) { closeRemote(); setResult(RESULT_CANCELED); finish(); } else { closeRemote(); showLocal(); localJs("JwImportUI.reset()"); } }
        else local.evaluateJavascript("JwImportUI.back()", handled -> { if ("false".equals(handled)) finish(); });
    }
    @Override protected void onDestroy() {
        destroyed = true; generation++; handler.removeCallbacksAndMessages(null); files.shutdown(); closeRemote();
        local.removeJavascriptInterface("JwImportNative"); local.destroy(); super.onDestroy();
    }
    @Override protected void onResume() {
        super.onResume(); foreground = true;
        if (remote != null) remote.onResume();
        startAutoReader();
    }
    @Override protected void onPause() {
        foreground = false; handler.removeCallbacks(autoReader);
        if (remote != null) remote.onPause();
        super.onPause();
    }
}

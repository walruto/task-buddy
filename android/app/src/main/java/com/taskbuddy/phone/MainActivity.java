package com.taskbuddy.phone;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import java.io.IOException;
import java.io.InputStream;

public final class MainActivity extends Activity {
    private static final String APP_ORIGIN = "https://appassets.androidplatform.net";
    private static final int CAMERA_PERMISSION_REQUEST = 41;
    private WebView webView;
    private TaskNotificationBridge notifications;
    private PermissionRequest pendingCameraRequest;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        webView = new WebView(this);
        webView.setBackgroundColor(Color.rgb(21, 18, 25));
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setSafeBrowsingEnabled(true);

        notifications = new TaskNotificationBridge(this);
        webView.addJavascriptInterface(notifications, "TaskBuddyAndroid");
        webView.setWebChromeClient(new BuddyChromeClient());
        webView.setWebViewClient(new LocalAssetClient());
        setContentView(webView);
        webView.loadUrl(startURL(getIntent()));
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (webView != null) webView.loadUrl(startURL(intent));
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (webView != null) webView.evaluateJavascript("if(window.taskBuddyResume){window.taskBuddyResume()}", null);
    }

    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) webView.goBack();
        else super.onBackPressed();
    }

    @Override
    protected void onDestroy() {
        if (pendingCameraRequest != null) pendingCameraRequest.deny();
        if (webView != null) webView.evaluateJavascript("if(window.taskBuddyStopCamera){window.taskBuddyStopCamera()}", null);
        webView.destroy();
        super.onDestroy();
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != CAMERA_PERMISSION_REQUEST || pendingCameraRequest == null) return;
        PermissionRequest request = pendingCameraRequest;
        pendingCameraRequest = null;
        if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            request.grant(new String[]{PermissionRequest.RESOURCE_VIDEO_CAPTURE});
        } else {
            request.deny();
        }
    }

    private final class BuddyChromeClient extends WebChromeClient {
        @Override
        public void onPermissionRequest(PermissionRequest request) {
            Uri origin = request.getOrigin();
            boolean trustedOrigin = APP_ORIGIN.equals(origin.getScheme() + "://" + origin.getHost());
            boolean asksForVideo = false;
            boolean asksForAnythingElse = false;
            for (String resource : request.getResources()) {
                if (PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(resource)) asksForVideo = true;
                else asksForAnythingElse = true;
            }
            if (!trustedOrigin || !asksForVideo || asksForAnythingElse) {
                request.deny();
                return;
            }
            if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                request.grant(new String[]{PermissionRequest.RESOURCE_VIDEO_CAPTURE});
                return;
            }
            if (pendingCameraRequest != null) pendingCameraRequest.deny();
            pendingCameraRequest = request;
            requestPermissions(new String[]{Manifest.permission.CAMERA}, CAMERA_PERMISSION_REQUEST);
        }

        @Override
        public void onPermissionRequestCanceled(PermissionRequest request) {
            if (pendingCameraRequest == request) pendingCameraRequest = null;
        }
    }

    private final class LocalAssetClient extends WebViewClient {
        @Override
        public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
            Uri uri = request.getUrl();
            if (!APP_ORIGIN.equals(uri.getScheme() + "://" + uri.getHost())) return null;

            String path = uri.getPath();
            if (path == null || !path.startsWith("/assets/") || path.contains("..")) return null;
            String assetPath = path.substring("/assets/".length());
            try {
                InputStream stream = getAssets().open(assetPath);
                return new WebResourceResponse(mimeType(assetPath), "UTF-8", stream);
            } catch (IOException error) {
                return null;
            }
        }

        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            Uri uri = request.getUrl();
            if (APP_ORIGIN.equals(uri.getScheme() + "://" + uri.getHost())) return false;
            startActivity(new Intent(Intent.ACTION_VIEW, uri));
            return true;
        }
    }

    private static String mimeType(String path) {
        if (path.endsWith(".html")) return "text/html";
        if (path.endsWith(".css")) return "text/css";
        if (path.endsWith(".js") || path.endsWith(".mjs")) return "application/javascript";
        if (path.endsWith(".png")) return "image/png";
        if (path.endsWith(".webmanifest")) return "application/manifest+json";
        return "application/octet-stream";
    }

    private static String startURL(Intent intent) {
        Uri data = intent == null ? null : intent.getData();
        if (data != null && "taskbuddy".equals(data.getScheme()) && "reset-password".equals(data.getHost())) {
            String fragment = data.getEncodedFragment();
            return APP_ORIGIN + "/assets/index.html" + (fragment == null ? "" : "#" + fragment);
        }
        return APP_ORIGIN + "/assets/index.html";
    }
}

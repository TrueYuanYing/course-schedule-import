package dev.campus.jwimport;

/** Bounded alternate-entry policy. No network requests, cookies or credentials. */
final class SchoolEntryRecovery {
    private static final String STUDENT = "https://gmsstu.hfut.edu.cn/logon";
    private boolean recovered;

    static boolean isHfutRoot(String url) {
        try {
            java.net.URI parsed = java.net.URI.create(url);
            return "https".equalsIgnoreCase(parsed.getScheme())
                && "gmsstu.hfut.edu.cn".equalsIgnoreCase(parsed.getHost())
                && (parsed.getPort() == -1 || parsed.getPort() == 443)
                && parsed.getRawUserInfo() == null && parsed.getRawQuery() == null
                && parsed.getRawFragment() == null
                && (parsed.getRawPath().isEmpty() || "/".equals(parsed.getRawPath()));
        } catch (IllegalArgumentException | NullPointerException ignored) { return false; }
    }
    static String initial(String url) { return isHfutRoot(url) ? STUDENT : url; }
    private String recover(String url, String method, boolean mainFrame) {
        if (recovered || !mainFrame || !"GET".equals(method) || !isHfutRoot(url)) return null;
        recovered = true;
        return STUDENT;
    }
    String httpFailure(String url, String method, boolean mainFrame, int status) {
        return status >= 400 && status != 429 ? recover(url, method, mainFrame) : null;
    }
    String networkFailure(String url, String method, boolean mainFrame, int code) {
        // WebView ERROR_UNKNOWN/HOST_LOOKUP/CONNECT/IO/TIMEOUT/REDIRECT_LOOP only.
        // Authentication, proxy authentication, TLS and throttling remain untouched.
        return code == -1 || code == -2 || code <= -6 && code >= -9
            ? recover(url, method, mainFrame) : null;
    }
}

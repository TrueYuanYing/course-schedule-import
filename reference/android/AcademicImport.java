package dev.campus.jwimport;

import android.content.Context;
import android.content.Intent;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.UUID;

/** Public entry and one-shot result reader. Does not write the host timetable. */
public final class AcademicImport {
    public static final int MAX_BYTES = 4_000_000;
    static final String RESULT_TOKEN = "dev.campus.jwimport.RESULT_TOKEN";
    private static final long RESULT_TTL_MS = 30 * 60 * 1000L;
    private AcademicImport() {}

    public static Intent createIntent(Context context) {
        return new Intent(context, AcademicImportActivity.class);
    }

    public static Intent createIntent(Context context, String url, String school, boolean desktop) {
        if (url == null || url.length() > 4096 || school != null && school.length() > 200)
            throw new IllegalArgumentException("School entry is too long or missing");
        return createIntent(context).putExtra("entryUrl", url).putExtra("school", school).putExtra("desktop", desktop);
    }

    /** Call on RESULT_OK, preferably off the main thread. Consumes the result once. */
    public static synchronized JSONObject readResult(Context context, Intent intent) throws Exception {
        if (intent == null) throw new IOException("Missing result Intent");
        String token = intent.getStringExtra(RESULT_TOKEN);
        if (token == null || !token.matches("[a-f0-9]{32}")) throw new IOException("Invalid result token");
        File result = new File(resultDir(context), token + ".json");
        if (!result.isFile() || System.currentTimeMillis() - result.lastModified() > RESULT_TTL_MS) {
            result.delete(); throw new IOException("Import result is missing or expired; import again");
        }
        try (InputStream in = new FileInputStream(result)) {
            JSONObject data = new JSONObject(readUtf8(in, MAX_BYTES));
            validate(data); return data;
        } finally { result.delete(); }
    }

    static synchronized Intent storeResult(Context context, String json) throws Exception {
        byte[] bytes = json.getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_BYTES) throw new IOException("Result is too large");
        validate(new JSONObject(json));
        File directory = resultDir(context);
        File[] old = directory.listFiles();
        if (old != null) for (File file : old)
            if (System.currentTimeMillis() - file.lastModified() > RESULT_TTL_MS) file.delete();
        String token = UUID.randomUUID().toString().replace("-", "");
        File temp = new File(directory, token + ".tmp"), target = new File(directory, token + ".json");
        try {
            try (FileOutputStream out = new FileOutputStream(temp)) { out.write(bytes); out.getFD().sync(); }
            if (!temp.renameTo(target)) throw new IOException("Cannot save import result");
            return new Intent().putExtra(RESULT_TOKEN, token);
        } finally { temp.delete(); }
    }

    private static File resultDir(Context context) throws IOException {
        File dir = new File(context.getCacheDir(), "jwimport-results");
        if (!dir.isDirectory() && !dir.mkdirs()) throw new IOException("Cannot create import cache");
        return dir;
    }

    static String readUtf8(InputStream in, int max) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream(); byte[] buffer = new byte[8192]; int size;
        while ((size = in.read(buffer)) != -1) {
            if (out.size() + size > max) throw new IOException("Input exceeds 4 MB limit");
            out.write(buffer, 0, size);
        }
        return new String(out.toByteArray(), StandardCharsets.UTF_8);
    }

    static void validate(JSONObject result) throws Exception {
        if (integer(result.get("schemaVersion"), 1, 1) != 1) throw new IOException("Unsupported result schema");
        JSONArray courses = result.getJSONArray("courses");
        if (courses.length() < 1 || courses.length() > 5000) throw new IOException("Invalid course count");
        result.getJSONArray("warnings");
        for (int i = 0; i < courses.length(); i++) {
            JSONObject course = courses.getJSONObject(i);
            Object name = course.get("name");
            if (!(name instanceof String) || ((String) name).trim().isEmpty()) throw new IOException("Invalid course name");
            integer(course.get("day"), 1, 7);
            validateList(course.getJSONArray("sections"), 30);
            validateList(course.getJSONArray("weeks"), 60);
        }
    }

    private static int integer(Object raw, int min, int max) throws IOException {
        if (!(raw instanceof Number)) throw new IOException("Expected integer");
        double value = ((Number) raw).doubleValue();
        if (!Double.isFinite(value) || value != Math.rint(value) || value < min || value > max) throw new IOException("Integer out of range");
        return (int) value;
    }

    private static void validateList(JSONArray values, int max) throws Exception {
        if (values.length() < 1 || values.length() > max) throw new IOException("Invalid range");
        int previous = 0;
        for (int i = 0; i < values.length(); i++) {
            int value = integer(values.get(i), 1, max);
            if (value <= previous) throw new IOException("Invalid range order");
            previous = value;
        }
    }
}

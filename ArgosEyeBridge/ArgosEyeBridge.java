import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;

public class ArgosEyeBridge {

    private static final String API_BASE = "https://api.argoseye.ovh";
    private static String bearerToken = "";
    private static String privateKey = "";
    private static Path requestDir;
    private static Path responseDir;
    private static volatile boolean running = true;

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Usage: ArgosEyeBridge <zomboid-lua-dir> <private-key>");
            System.exit(1);
        }

        Path luaDir = Paths.get(args[0], "ArgosEye");
        privateKey = args[1];

        requestDir = luaDir.resolve("requests");
        responseDir = luaDir.resolve("responses");
        Files.createDirectories(requestDir);
        Files.createDirectories(responseDir);

        Runtime.getRuntime().addShutdownHook(new Thread(() -> running = false));

        System.out.println("[ArgosEyeBridge] Starting...");
        if (!refreshToken()) {
            System.err.println("[ArgosEyeBridge] Failed to get bearer token. Check your private key.");
            System.exit(1);
        }
        System.out.println("[ArgosEyeBridge] Token acquired. Watching " + requestDir);

        ExecutorService pool = Executors.newFixedThreadPool(4);

        while (running) {
            try {
                File[] files = requestDir.toFile().listFiles((d, n) -> n.endsWith(".json"));
                if (files != null) {
                    for (File f : files) {
                        pool.submit(() -> processRequest(f));
                    }
                }
                Thread.sleep(500);
            } catch (InterruptedException e) {
                break;
            } catch (Exception e) {
                System.err.println("[ArgosEyeBridge] Error: " + e.getMessage());
                Thread.sleep(1000);
            }
        }

        pool.shutdown();
        pool.awaitTermination(5, TimeUnit.SECONDS);
        System.out.println("[ArgosEyeBridge] Stopped.");
    }

    private static void processRequest(File file) {
        try {
            String content = new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8);
            Files.delete(file.toPath());

            String name = file.getName();
            String responseJson;

            if (name.startsWith("player_check_")) {
                responseJson = apiPost("/internal_player_state", content);
            } else if (name.startsWith("players_check_")) {
                responseJson = apiPost("/internal_players_check", content);
            } else if (name.startsWith("server_info_")) {
                responseJson = apiPost("/internal_server_info", content);
            } else if (name.startsWith("player_death_")) {
                responseJson = apiPost("/internal_server_death", content);
            } else if (name.startsWith("chat_logs_")) {
                responseJson = apiPost("/internal_server_chat_logs", content);
            } else {
                System.err.println("[ArgosEyeBridge] Unknown request type: " + name);
                return;
            }

            if (responseJson != null) {
                String respName = name.replace(".json", "_resp.json");
                Path respPath = responseDir.resolve(respName);
                Path tmp = responseDir.resolve(respName + ".tmp");
                Files.write(tmp, responseJson.getBytes(StandardCharsets.UTF_8));
                Files.move(tmp, respPath, StandardCopyOption.ATOMIC_MOVE);
            }

        } catch (Exception e) {
            System.err.println("[ArgosEyeBridge] Error processing " + file.getName() + ": " + e.getMessage());
        }
    }

    private static String apiPost(String endpoint, String jsonBody) {
        for (int attempt = 0; attempt < 2; attempt++) {
            try {
                HttpURLConnection conn = (HttpURLConnection) new URL(API_BASE + endpoint).openConnection();
                conn.setRequestMethod("POST");
                conn.setRequestProperty("Content-Type", "application/json");
                conn.setRequestProperty("Authorization", bearerToken);
                conn.setDoOutput(true);
                conn.setConnectTimeout(10000);
                conn.setReadTimeout(15000);

                try (OutputStream os = conn.getOutputStream()) {
                    os.write(jsonBody.getBytes(StandardCharsets.UTF_8));
                }

                int code = conn.getResponseCode();

                if (code == 401 || code == 403) {
                    System.out.println("[ArgosEyeBridge] Token expired, refreshing...");
                    if (refreshToken()) {
                        continue;
                    }
                    return "{\"error\":true,\"code\":" + code + "}";
                }

                InputStream is = (code >= 200 && code < 300) ? conn.getInputStream() : conn.getErrorStream();
                String body = readStream(is);
                conn.disconnect();

                if (code == 200) {
                    return body;
                } else {
                    System.err.println("[ArgosEyeBridge] API " + endpoint + " returned " + code);
                    return "{\"error\":true,\"code\":" + code + "}";
                }

            } catch (Exception e) {
                System.err.println("[ArgosEyeBridge] HTTP error: " + e.getMessage());
                return "{\"error\":true,\"message\":\"" + e.getMessage().replace("\"", "'") + "\"}";
            }
        }
        return "{\"error\":true,\"message\":\"max retries\"}";
    }

    private static boolean refreshToken() {
        try {
            String body = "{\"privateKey\":\"" + privateKey + "\"}";
            HttpURLConnection conn = (HttpURLConnection) new URL(API_BASE + "/internal_get_bearer_token").openConnection();
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json");
            conn.setDoOutput(true);
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(10000);

            try (OutputStream os = conn.getOutputStream()) {
                os.write(body.getBytes(StandardCharsets.UTF_8));
            }

            if (conn.getResponseCode() == 200) {
                String resp = readStream(conn.getInputStream());
                int idx = resp.indexOf("\"token\"");
                if (idx >= 0) {
                    int start = resp.indexOf('"', idx + 7);
                    int end = resp.indexOf('"', start + 1);
                    bearerToken = resp.substring(start + 1, end);
                    System.out.println("[ArgosEyeBridge] Token refreshed.");
                    return true;
                }
            }
            conn.disconnect();
        } catch (Exception e) {
            System.err.println("[ArgosEyeBridge] Token refresh error: " + e.getMessage());
        }
        return false;
    }

    private static String readStream(InputStream is) throws IOException {
        if (is == null) return "";
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        byte[] b = new byte[4096];
        int n;
        while ((n = is.read(b)) != -1) buf.write(b, 0, n);
        is.close();
        return buf.toString("UTF-8");
    }
}

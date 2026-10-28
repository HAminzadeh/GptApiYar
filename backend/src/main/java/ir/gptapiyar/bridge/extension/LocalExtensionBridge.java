package ir.gptapiyar.bridge.extension;

import org.springframework.stereotype.Service;
import java.net.URI;
import java.time.Duration;
import java.util.UUID;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

@Service
public class LocalExtensionBridge {
    // Only an explicitly enabled content script on our own local demo page may poll.
    public record PollRequest(String sessionId, String pageUrl, String title) {}
    public record Job(String id, String message) {}
    public record ResultRequest(String sessionId, String jobId, String message, String error) {}
    public record Status(boolean connected, String title, String pageUrl, String mode) {}
    public record ChatReply(String id, String message, String pageUrl) {}

    private final BlockingQueue<Job> jobs = new LinkedBlockingQueue<>();
    private final ConcurrentMap<String, CompletableFuture<String>> pending = new ConcurrentHashMap<>();
    private final AtomicBoolean sending = new AtomicBoolean(false);
    private volatile String sessionId = "";
    private volatile String pageUrl = "";
    private volatile String title = "";
    private volatile long lastSeenMillis = 0;

    private static void requireDemoPage(String url) {
        try {
            URI uri = URI.create(url);
            if ("http".equals(uri.getScheme()) && "127.0.0.1".equals(uri.getHost())
                    && uri.getPort() == 8787 && "/demo.html".equals(uri.getPath())
                    && uri.getUserInfo() == null && uri.getQuery() == null) return;
        } catch (RuntimeException ignored) { }
        throw new IllegalArgumentException("This connector only supports http://127.0.0.1:8787/demo.html");
    }

    public synchronized Job poll(PollRequest request) {
        if (request == null || request.sessionId() == null ||
                !request.sessionId().matches("[a-zA-Z0-9-]{8,80}")) {
            throw new IllegalArgumentException("Invalid extension session");
        }
        requireDemoPage(request.pageUrl());
        if (!request.sessionId().equals(sessionId)) {
            pending.values().forEach(f -> f.completeExceptionally(
                    new IllegalStateException("The connected extension tab changed")));
            pending.clear();
            jobs.clear();
            sessionId = request.sessionId();
        }
        pageUrl = request.pageUrl();
        title = request.title() == null ? "Local demo" :
                request.title().substring(0, Math.min(120, request.title().length()));
        lastSeenMillis = System.currentTimeMillis();
        Job job = jobs.poll();
        return job != null ? job : new Job(null, null);
    }

    public Status status() {
        boolean alive = !sessionId.isBlank() &&
                System.currentTimeMillis() - lastSeenMillis <= Duration.ofSeconds(6).toMillis();
        return new Status(alive, alive ? title : "", alive ? pageUrl : "", "extension");
    }

    public ChatReply chat(String text) {
        if (text == null || text.isBlank()) throw new IllegalArgumentException("A text message is required");
        if (text.length() > 10000) throw new IllegalArgumentException("Message exceeds 10000 characters");
        if (!status().connected()) throw new IllegalStateException(
                "Extension is not connected. Open the demo page in your normal Chrome and activate it from the GptApiYar extension popup.");
        if (!sending.compareAndSet(false, true))
            throw new IllegalStateException("Another demo request is in progress");

        String id = UUID.randomUUID().toString();
        CompletableFuture<String> completion = new CompletableFuture<>();
        pending.put(id, completion);
        Job job = new Job(id, text);
        jobs.offer(job);
        try {
            String response = completion.get(20, TimeUnit.SECONDS);
            return new ChatReply(id, response, pageUrl);
        } catch (TimeoutException e) {
            throw new IllegalStateException("Extension did not return a demo response within 20 seconds");
        } catch (ExecutionException e) {
            throw new IllegalStateException("Extension failed: " + e.getCause().getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while waiting for the extension");
        } finally {
            jobs.remove(job);
            pending.remove(id);
            sending.set(false);
        }
    }

    public synchronized void result(ResultRequest result) {
        if (result == null || !sessionId.equals(result.sessionId()))
            throw new IllegalArgumentException("Invalid extension session");
        CompletableFuture<String> completion = pending.get(result.jobId());
        if (completion == null) throw new IllegalArgumentException("Unknown or expired job");
        if (result.error() != null && !result.error().isBlank()) {
            completion.completeExceptionally(new IllegalStateException(result.error()));
        } else {
            String text = result.message() == null ? "" : result.message();
            completion.complete(text.substring(0, Math.min(text.length(), 100000)));
        }
    }
}

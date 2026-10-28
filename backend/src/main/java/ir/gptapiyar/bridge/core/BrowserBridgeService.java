package ir.gptapiyar.bridge.core;

import com.microsoft.playwright.*;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import jakarta.annotation.PreDestroy;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Service
public class BrowserBridgeService {
    // Playwright's Java API is single-threaded. All Playwright access is synchronized here.
    private final CdpProbe probe;
    public BrowserBridgeService(CdpProbe probe) { this.probe = probe; }

    private Playwright playwright;
    private Browser browser;
    private Page page;
    private ConnectRequest config;

    public record ConnectRequest(
        String cdpEndpoint,
        String pageUrl,
        String inputSelector,
        String sendSelector,
        String responseSelector,
        String busySelector,
        String fileSelector
    ) {}

    public record BridgeStatus(boolean connected, String pageUrl, String title, String cdpEndpoint) {}
    public record ChatReply(String id, String message, String pageUrl) {}

    private static String required(String value, String label) {
        if (value == null || value.isBlank()) throw new IllegalArgumentException(label + " is required");
        return value.trim();
    }

    private static void validateLocalCdp(String endpoint) {
        URI uri;
        try { uri = URI.create(required(endpoint, "CDP endpoint")); }
        catch (Exception e) { throw new IllegalArgumentException("Invalid CDP endpoint"); }
        String host = uri.getHost();
        if (!("127.0.0.1".equals(host) || "localhost".equalsIgnoreCase(host) || "[::1]".equals(host) || "::1".equals(host))) {
            throw new IllegalArgumentException("CDP must be bound to your local computer (127.0.0.1)");
        }
        if (!("http".equalsIgnoreCase(uri.getScheme()) || "ws".equalsIgnoreCase(uri.getScheme()))) {
            throw new IllegalArgumentException("CDP endpoint must be http:// or ws://");
        }
    }

    public synchronized BridgeStatus connect(ConnectRequest request) {
        validateLocalCdp(request.cdpEndpoint());
        String target = required(request.pageUrl(), "Page URL");
        if (!target.startsWith("http://") && !target.startsWith("https://"))
            throw new IllegalArgumentException("Page URL must start with http:// or https://");
        required(request.inputSelector(), "Input selector");
        required(request.sendSelector(), "Send selector");
        required(request.responseSelector(), "Response selector");

        CdpProbe.Result inspection = probe.inspect(request.cdpEndpoint());
        if (!inspection.reachable()) {
            throw new IllegalStateException(inspection.message());
        }
        disconnect();
        try {
            playwright = Playwright.create();
            browser = playwright.chromium().connectOverCDP(request.cdpEndpoint().trim());
            page = browser.contexts().stream()
                .flatMap(context -> context.pages().stream())
                .filter(p -> !p.isClosed() && matchesPage(p.url(), target))
                .findFirst().orElse(null);
            if (page == null) {
                List<String> available = listTabs();
                disconnect();
                throw new IllegalArgumentException("Matching tab not found. Open the URL first in the CDP Chrome. Tabs: " + available);
            }
            config = request;
            return status();
        } catch (RuntimeException e) {
            disconnect();
            throw e;
        }
    }

    private boolean matchesPage(String tabUrl, String requested) {
        return tabUrl.equals(requested) || tabUrl.startsWith(requested + "?") || tabUrl.startsWith(requested + "#");
    }

    public synchronized BridgeStatus status() {
        if (page == null || page.isClosed()) return new BridgeStatus(false, "", "", "");
        try { return new BridgeStatus(true, page.url(), page.title(), config == null ? "" : config.cdpEndpoint()); }
        catch (RuntimeException ex) { return new BridgeStatus(false, "", "", ""); }
    }

    public synchronized List<String> listTabs() {
        if (browser == null) return List.of();
        List<String> result = new ArrayList<>();
        for (BrowserContext context : browser.contexts())
            for (Page p : context.pages()) if (!p.isClosed()) result.add(p.url());
        return result;
    }

    public synchronized ChatReply send(String message, List<MultipartFile> uploads) {
        if (page == null || page.isClosed() || config == null)
            throw new IllegalStateException("Connect to a browser tab first");
        if ((message == null || message.isBlank()) && uploads.isEmpty())
            throw new IllegalArgumentException("A message or attachment is required");
        List<Path> temporaryFiles = new ArrayList<>();
        try {
            Locator responses = page.locator(config.responseSelector());
            int before = responses.count();
            if (!uploads.isEmpty()) {
                if (config.fileSelector() == null || config.fileSelector().isBlank())
                    throw new IllegalArgumentException("File input selector must be set for attachments");
                Path tempDir = Files.createTempDirectory("gptapiyar-upload-");
                temporaryFiles.add(tempDir);
                for (MultipartFile upload : uploads) {
                    String filename = upload.getOriginalFilename() == null ? "upload.bin" : upload.getOriginalFilename();
                    filename = Path.of(filename.replace('\\', '/')).getFileName().toString();
                    if (filename.isBlank()) filename = "upload.bin";
                    Path temporary = tempDir.resolve(UUID.randomUUID() + "-" + filename);
                    upload.transferTo(temporary);
                    temporaryFiles.add(temporary);
                }
                page.locator(config.fileSelector()).setInputFiles(temporaryFiles.stream().filter(Files::isRegularFile).toArray(Path[]::new));
            }
            if (message != null && !message.isBlank()) page.locator(config.inputSelector()).fill(message);
            page.locator(config.sendSelector()).click();
            // This uses visible DOM, not unofficial/private endpoints. Selectors are page-specific.
            String last = "";
            long stableSince = 0;
            long deadline = System.currentTimeMillis() + 90_000;
            while (System.currentTimeMillis() < deadline) {
                page.waitForTimeout(300);
                if (responses.count() <= before) continue;
                String latest = responses.last().innerText().trim();
                boolean busy = false;
                if (config.busySelector() != null && !config.busySelector().isBlank()) {
                    Locator spinner = page.locator(config.busySelector());
                    busy = spinner.count() > 0 && spinner.first().isVisible();
                }
                if (!latest.equals(last)) { last = latest; stableSince = System.currentTimeMillis(); }
                if (!busy && !latest.isBlank() && System.currentTimeMillis() - stableSince > 1_400) {
                    return new ChatReply(UUID.randomUUID().toString(), latest, page.url());
                }
            }
            throw new IllegalStateException("Timed out waiting for a new completed response. Check DOM selectors and target page.");
        } catch (PlaywrightException e) {
            throw new IllegalStateException("Browser operation failed: " + e.getMessage());
        } catch (java.io.IOException e) {
            throw new IllegalStateException("Upload failed: " + e.getMessage());
        } finally {
            for (int i = temporaryFiles.size() - 1; i >= 0; i--) {
                try { Files.deleteIfExists(temporaryFiles.get(i)); } catch (Exception ignored) {}
            }
        }
    }

    public synchronized void disconnect() {
        config = null;
        page = null;
        browser = null;
        if (playwright != null) {
            try { playwright.close(); } catch (Exception ignored) {}
            playwright = null;
        }
    }

    @PreDestroy
    public void shutdown() { disconnect(); }
}

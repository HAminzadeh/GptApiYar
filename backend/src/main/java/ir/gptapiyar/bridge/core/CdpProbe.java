package ir.gptapiyar.bridge.core;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.stereotype.Component;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

@Component
public class CdpProbe {
    private final HttpClient client = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(2))
        .followRedirects(HttpClient.Redirect.NEVER)
        .build();
    private final ObjectMapper mapper = new ObjectMapper();

    public record Tab(String title, String url) {}
    public record Result(boolean reachable, String message, String browser, List<Tab> tabs) {}

    private URI requireLocalHttp(String endpoint) {
        URI uri;
        try { uri = URI.create(endpoint == null ? "" : endpoint.trim()); }
        catch (Exception ex) { throw new IllegalArgumentException("Invalid CDP URL"); }
        String host = uri.getHost();
        if (!"http".equalsIgnoreCase(uri.getScheme()) ||
            !("127.0.0.1".equals(host) || "localhost".equalsIgnoreCase(host) || "::1".equals(host)) ||
            uri.getPort() <= 0 || uri.getPort() > 65535 ||
            uri.getUserInfo() != null || uri.getRawQuery() != null || uri.getRawFragment() != null ||
            (uri.getPath() != null && !uri.getPath().isEmpty() && !"/".equals(uri.getPath()))) {
            throw new IllegalArgumentException("CDP must be a local http://127.0.0.1:PORT endpoint");
        }
        return uri;
    }

    private JsonNode read(URI uri, String path) throws Exception {
        URI target = new URI("http", null, uri.getHost(), uri.getPort(), path, null, null);
        HttpRequest request = HttpRequest.newBuilder(target)
            .GET().timeout(Duration.ofSeconds(3)).build();
        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200) throw new IllegalStateException("CDP HTTP " + response.statusCode());
        return mapper.readTree(response.body());
    }

    public Result inspect(String endpoint) {
        URI uri = requireLocalHttp(endpoint);
        try {
            JsonNode version = read(uri, "/json/version");
            String browser = version.path("Browser").asText("Chrome");
            JsonNode targets = read(uri, "/json/list");
            List<Tab> tabs = new ArrayList<>();
            if (targets.isArray()) {
                for (JsonNode node : targets) {
                    if (tabs.size() >= 30) break;
                    if (!"page".equals(node.path("type").asText())) continue;
                    tabs.add(new Tab(node.path("title").asText(""),node.path("url").asText("")));
                }
            }
            return new Result(true, "CDP is reachable", browser, tabs);
        } catch (Exception e) {
            return new Result(false, "CDP unavailable: " + e.getClass().getSimpleName() +
                ". Start the separate Chrome CDP window on port " + uri.getPort() + ".", "", List.of());
        }
    }
}
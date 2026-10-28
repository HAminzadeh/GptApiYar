package ir.gptapiyar.bridge.api;

import ir.gptapiyar.bridge.core.BrowserBridgeService;
import ir.gptapiyar.bridge.core.CdpProbe;
import ir.gptapiyar.bridge.core.BrowserBridgeService.ConnectRequest;
import ir.gptapiyar.bridge.core.BrowserBridgeService.BridgeStatus;
import ir.gptapiyar.bridge.core.BrowserBridgeService.ChatReply;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class BrowserController {
    private final BrowserBridgeService bridge;
    private final CdpProbe cdpProbe;

    public BrowserController(BrowserBridgeService bridge, CdpProbe cdpProbe) {
        this.bridge = bridge;
        this.cdpProbe = cdpProbe;
    }

    @GetMapping("/bridge/diagnose")
    public CdpProbe.Result diagnose(@RequestParam(defaultValue = "http://127.0.0.1:9222") String cdpEndpoint) {
        return cdpProbe.inspect(cdpEndpoint);
    }

    @GetMapping("/health")
    public Map<String, Object> health() { return Map.of("ok", true, "service", "gptapiyar-browser-bridge"); }

    @GetMapping("/bridge/status")
    public BridgeStatus status() { return bridge.status(); }

    @GetMapping("/bridge/tabs")
    public List<String> tabs() { return bridge.listTabs(); }

    @PostMapping("/bridge/connect")
    public BridgeStatus connect(@RequestBody ConnectRequest request) { return bridge.connect(request); }

    @PostMapping("/bridge/disconnect")
    public BridgeStatus disconnect() { bridge.disconnect(); return bridge.status(); }

    @PostMapping(value = "/chat", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ChatReply chat(
        @RequestParam(value = "message", required = false, defaultValue = "") String message,
        @RequestParam(value = "files", required = false) List<MultipartFile> files
    ) { return bridge.send(message, files == null ? List.of() : files); }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, String>> invalid(IllegalArgumentException error) {
        return ResponseEntity.badRequest().body(Map.of("error", error.getMessage()));
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<Map<String, String>> unavailable(IllegalStateException error) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", error.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, String>> unexpected(Exception error) {
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("error", error.getClass().getSimpleName() + ": " + error.getMessage()));
    }
}

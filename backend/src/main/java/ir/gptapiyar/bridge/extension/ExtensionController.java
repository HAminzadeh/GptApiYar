package ir.gptapiyar.bridge.extension;

import org.springframework.http.MediaType;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import java.util.Map;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import java.util.List;

@RestController
@RequestMapping("/api/extension")
public class ExtensionController {
    private final LocalExtensionBridge bridge;
    public ExtensionController(LocalExtensionBridge bridge) { this.bridge = bridge; }

    @GetMapping("/status")
    public LocalExtensionBridge.Status status() { return bridge.status(); }

    @PostMapping("/poll")
    public LocalExtensionBridge.Job poll(@RequestBody LocalExtensionBridge.PollRequest request) {
        return bridge.poll(request);
    }

    @PostMapping("/result")
    public java.util.Map<String, Boolean> result(@RequestBody LocalExtensionBridge.ResultRequest request) {
        bridge.result(request);
        return java.util.Map.of("ok", true);
    }

    @PostMapping(value="/chat", consumes=MediaType.MULTIPART_FORM_DATA_VALUE)
    public LocalExtensionBridge.ChatReply chat(
            @RequestParam(value="message", required=false, defaultValue="") String message,
            @RequestParam(value="files", required=false) List<MultipartFile> files) {
        if (files != null && !files.isEmpty())
            throw new IllegalArgumentException("Chrome extension demo currently supports text only. Use the CDP demo for file-upload tests.");
        return bridge.chat(message);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, String>> badRequest(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }

    @ExceptionHandler(IllegalStateException.class)
    public ResponseEntity<Map<String, String>> conflict(IllegalStateException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(Map.of("error", e.getMessage()));
    }
}

package com.lanshare.controller;

import com.lanshare.model.SharedLink;
import com.lanshare.repository.SharedLinkRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;

@RestController
@RequestMapping("/api/links")
public class LinkController {

    private final SharedLinkRepository linkRepository;

    public LinkController(SharedLinkRepository linkRepository) {
        this.linkRepository = linkRepository;
    }

    @PostMapping
    public ResponseEntity<?> createLink(@RequestBody Map<String, String> payload) {
        String rawUrl = payload.get("url");
        String rawTitle = payload.get("title");

        if (rawUrl == null || rawUrl.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "URL is required."));
        }

        String url = rawUrl.trim();
        // Prepend https:// if protocol is missing
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            url = "https://" + url;
        }

        // Validate URL structure
        try {
            URI uri = URI.create(url);
            if (uri.getHost() == null) {
                return ResponseEntity.badRequest().body(Map.of("error", "Invalid URL host."));
            }
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("error", "Invalid URL format: " + e.getMessage()));
        }

        String title = (rawTitle != null && !rawTitle.trim().isEmpty())
                ? rawTitle.trim()
                : generateDefaultTitle(url);

        SharedLink link = new SharedLink(title, url, LocalDateTime.now());
        SharedLink saved = linkRepository.save(link);

        return ResponseEntity.ok(saved);
    }

    @GetMapping
    public ResponseEntity<List<SharedLink>> listLinks() {
        return ResponseEntity.ok(linkRepository.findAllByOrderByCreatedAtDesc());
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Map<String, Object>> deleteLink(@PathVariable Long id) {
        SharedLink link = linkRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Link not found with ID: " + id));

        linkRepository.delete(link);

        return ResponseEntity.ok(Map.of(
                "success", true,
                "message", "Link deleted successfully",
                "id", id
        ));
    }

    private String generateDefaultTitle(String url) {
        try {
            URI uri = URI.create(url);
            String host = uri.getHost();
            if (host != null) {
                String path = uri.getPath();
                if (path != null && path.length() > 1) {
                    String sub = path.length() > 20 ? path.substring(0, 20) + "..." : path;
                    return host + sub;
                }
                return host;
            }
        } catch (Exception ignored) {
        }
        return url.length() > 35 ? url.substring(0, 32) + "..." : url;
    }
}

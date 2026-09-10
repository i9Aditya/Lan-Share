package com.lanshare.controller;

import com.lanshare.model.SharedFile;
import com.lanshare.service.FileStorageService;
import com.lanshare.service.PasswordSecurityService;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.util.UriUtils;

import java.nio.charset.StandardCharsets;
import java.util.*;

@RestController
@RequestMapping("/api/files")
public class FileController {

    private final FileStorageService fileStorageService;
    private final PasswordSecurityService passwordSecurityService;

    public FileController(FileStorageService fileStorageService, PasswordSecurityService passwordSecurityService) {
        this.fileStorageService = fileStorageService;
        this.passwordSecurityService = passwordSecurityService;
    }

    @PostMapping("/upload")
    public ResponseEntity<Map<String, Object>> uploadFiles(
            @RequestParam("files") MultipartFile[] files,
            @RequestParam(value = "password", required = false) String password) {

        if (files == null || files.length == 0) {
            return ResponseEntity.badRequest().body(Map.of("error", "No files provided."));
        }

        // Check if the upload batch would exceed the hard storage quota
        long incomingBatchSize = Arrays.stream(files)
                .filter(f -> f != null && !f.isEmpty())
                .mapToLong(MultipartFile::getSize)
                .sum();

        long currentUsed = fileStorageService.getCurrentUsedStorage();
        long maxStorage = fileStorageService.getMaxStorageSizeBytes();

        if (currentUsed + incomingBatchSize > maxStorage) {
            String quotaMsg = "Storage limit reached. Only " + fileStorageService.getFormattedMaxStorage() + " is available for LAN Share.";
            return ResponseEntity.badRequest().body(Map.of(
                    "error", quotaMsg,
                    "message", quotaMsg
            ));
        }

        // Compute secure password hash if password provided
        String passwordHash = (password != null && !password.trim().isEmpty())
                ? passwordSecurityService.hashPassword(password)
                : null;

        List<SharedFile> savedFiles = new ArrayList<>();
        List<String> errors = new ArrayList<>();

        for (MultipartFile file : files) {
            if (file.isEmpty()) continue;
            try {
                SharedFile saved = fileStorageService.store(file, passwordHash);
                savedFiles.add(saved);
            } catch (Exception e) {
                errors.add("Failed to save " + file.getOriginalFilename() + ": " + e.getMessage());
            }
        }

        if (savedFiles.isEmpty() && !errors.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of(
                    "error", errors.get(0),
                    "message", errors.get(0),
                    "errors", errors
            ));
        }

        Map<String, Object> response = new HashMap<>();
        response.put("uploadedCount", savedFiles.size());
        response.put("files", savedFiles);
        if (!errors.isEmpty()) {
            response.put("errors", errors);
        }

        return ResponseEntity.ok(response);
    }

    @GetMapping
    public ResponseEntity<List<SharedFile>> listFiles() {
        return ResponseEntity.ok(fileStorageService.getAllFiles());
    }

    @PostMapping("/{id}/verify-password")
    public ResponseEntity<?> verifyPassword(
            @PathVariable Long id,
            @RequestBody(required = false) Map<String, String> body) {

        SharedFile sharedFile = fileStorageService.getFileById(id)
                .orElseThrow(() -> new NoSuchElementException("File not found with ID: " + id));

        if (!sharedFile.isProtected()) {
            return ResponseEntity.ok(Map.of("authorized", true, "protected", false));
        }

        String password = (body != null) ? body.get("password") : null;
        if (password == null || !passwordSecurityService.matches(password, sharedFile.getPasswordHash())) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "Incorrect password.", "authorized", false));
        }

        // Generate short-lived temporary access token (valid 5 minutes)
        String token = passwordSecurityService.createTemporaryToken(id, 300);
        return ResponseEntity.ok(Map.of(
                "authorized", true,
                "token", token,
                "fileId", id,
                "expiresIn", 300
        ));
    }

    @GetMapping("/{id}/download")
    public ResponseEntity<?> downloadFile(
            @PathVariable Long id,
            @RequestParam(value = "token", required = false) String token,
            @RequestHeader(value = "X-File-Password", required = false) String passwordHeader,
            @RequestHeader(value = "Accept", required = false) String acceptHeader) {

        SharedFile sharedFile = fileStorageService.getFileById(id)
                .orElseThrow(() -> new NoSuchElementException("File not found with ID: " + id));

        if (!isAccessAuthorized(sharedFile, token, passwordHeader)) {
            if (acceptHeader != null && acceptHeader.contains(MediaType.TEXT_HTML_VALUE)) {
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .contentType(MediaType.TEXT_HTML)
                        .body(renderPasswordPromptHtml(sharedFile, "/api/files/" + id + "/download", "download", null));
            }
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "Password required for this protected file.", "protected", true, "fileId", id));
        }

        return serveFile(sharedFile, false);
    }

    @PostMapping(value = "/{id}/download", consumes = MediaType.APPLICATION_FORM_URLENCODED_VALUE)
    public ResponseEntity<?> downloadFileForm(
            @PathVariable Long id,
            @RequestParam(value = "password", required = false) String password) {

        SharedFile sharedFile = fileStorageService.getFileById(id)
                .orElseThrow(() -> new NoSuchElementException("File not found with ID: " + id));

        if (sharedFile.isProtected()) {
            if (password == null || !passwordSecurityService.matches(password, sharedFile.getPasswordHash())) {
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .contentType(MediaType.TEXT_HTML)
                        .body(renderPasswordPromptHtml(sharedFile, "/api/files/" + id + "/download", "download", "Incorrect password. Please try again."));
            }
        }

        return serveFile(sharedFile, false);
    }

    @GetMapping("/{id}/preview")
    public ResponseEntity<?> previewFile(
            @PathVariable Long id,
            @RequestParam(value = "token", required = false) String token,
            @RequestHeader(value = "X-File-Password", required = false) String passwordHeader,
            @RequestHeader(value = "Accept", required = false) String acceptHeader) {

        SharedFile sharedFile = fileStorageService.getFileById(id)
                .orElseThrow(() -> new NoSuchElementException("File not found with ID: " + id));

        if (!isAccessAuthorized(sharedFile, token, passwordHeader)) {
            if (acceptHeader != null && acceptHeader.contains(MediaType.TEXT_HTML_VALUE)) {
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .contentType(MediaType.TEXT_HTML)
                        .body(renderPasswordPromptHtml(sharedFile, "/api/files/" + id + "/preview", "preview", null));
            }
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("error", "Password required for this protected file.", "protected", true, "fileId", id));
        }

        return serveFile(sharedFile, true);
    }

    @PostMapping(value = "/{id}/preview", consumes = MediaType.APPLICATION_FORM_URLENCODED_VALUE)
    public ResponseEntity<?> previewFileForm(
            @PathVariable Long id,
            @RequestParam(value = "password", required = false) String password) {

        SharedFile sharedFile = fileStorageService.getFileById(id)
                .orElseThrow(() -> new NoSuchElementException("File not found with ID: " + id));

        if (sharedFile.isProtected()) {
            if (password == null || !passwordSecurityService.matches(password, sharedFile.getPasswordHash())) {
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .contentType(MediaType.TEXT_HTML)
                        .body(renderPasswordPromptHtml(sharedFile, "/api/files/" + id + "/preview", "preview", "Incorrect password. Please try again."));
            }
        }

        return serveFile(sharedFile, true);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Map<String, Object>> deleteFile(@PathVariable Long id) {
        fileStorageService.deleteFile(id);
        return ResponseEntity.ok(Map.of(
                "success", true,
                "message", "File deleted successfully",
                "id", id
        ));
    }

    private boolean isAccessAuthorized(SharedFile file, String token, String passwordHeader) {
        if (!file.isProtected()) {
            return true;
        }
        if (passwordHeader != null && !passwordHeader.isBlank()) {
            if (passwordSecurityService.matches(passwordHeader, file.getPasswordHash())) {
                return true;
            }
        }
        if (token != null && !token.isBlank()) {
            if (passwordSecurityService.validateToken(file.getId(), token)) {
                return true;
            }
        }
        return false;
    }

    private ResponseEntity<Resource> serveFile(SharedFile sharedFile, boolean inline) {
        Resource resource = fileStorageService.loadAsResource(sharedFile);

        String encodedFilename = UriUtils.encode(sharedFile.getOriginalFileName(), StandardCharsets.UTF_8);
        String dispositionType = inline ? "inline" : "attachment";
        String contentDisposition = dispositionType + "; filename=\"" + cleanAsciiName(sharedFile.getOriginalFileName()) + "\"; filename*=UTF-8''" + encodedFilename;

        MediaType mediaType = MediaType.APPLICATION_OCTET_STREAM;
        if (sharedFile.getContentType() != null) {
            try {
                mediaType = MediaType.parseMediaType(sharedFile.getContentType());
            } catch (Exception ignored) {
            }
        }

        return ResponseEntity.ok()
                .contentType(mediaType)
                .header(HttpHeaders.CONTENT_DISPOSITION, contentDisposition)
                .header(HttpHeaders.CONTENT_LENGTH, String.valueOf(sharedFile.getSizeBytes()))
                .body(resource);
    }

    private String cleanAsciiName(String filename) {
        return filename.replaceAll("[^a-zA-Z0-9._-]", "_");
    }

    private String renderPasswordPromptHtml(SharedFile file, String actionUrl, String mode, String errorMessage) {
        String safeFileName = escapeHtml(file.getOriginalFileName());
        String safeSize = escapeHtml(file.getFormattedSize());
        String actionTitle = mode.equalsIgnoreCase("preview") ? "Preview" : "Download";
        String errorBlock = (errorMessage != null && !errorMessage.isBlank())
                ? "<div style=\"color:#f87171;background:rgba(239,68,68,0.15);padding:10px 14px;border-radius:8px;margin-bottom:16px;font-size:14px;border:1px solid rgba(239,68,68,0.3);\">" + escapeHtml(errorMessage) + "</div>"
                : "";

        return "<!DOCTYPE html>\n" +
                "<html lang=\"en\">\n" +
                "<head>\n" +
                "  <meta charset=\"UTF-8\">\n" +
                "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n" +
                "  <title>Password Required - " + safeFileName + "</title>\n" +
                "  <style>\n" +
                "    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0b0f19; color: #f1f5f9; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; }\n" +
                "    .card { background: #161e2e; border: 1px solid #283548; border-radius: 16px; padding: 32px; max-width: 420px; width: 100%; box-shadow: 0 12px 30px rgba(0,0,0,0.4); text-align: center; }\n" +
                "    .icon { font-size: 40px; margin-bottom: 12px; }\n" +
                "    h2 { margin: 0 0 8px; font-size: 20px; font-weight: 600; }\n" +
                "    .file-meta { color: #94a3b8; font-size: 14px; margin-bottom: 24px; word-break: break-all; }\n" +
                "    input[type='password'] { width: 100%; padding: 12px 14px; background: #0f172a; border: 1px solid #334155; border-radius: 8px; color: #fff; font-size: 15px; margin-bottom: 18px; box-sizing: border-box; outline: none; transition: border-color 0.2s; }\n" +
                "    input[type='password']:focus { border-color: #3b82f6; }\n" +
                "    button { width: 100%; padding: 12px; background: #3b82f6; color: white; border: none; border-radius: 8px; font-size: 15px; font-weight: 600; cursor: pointer; transition: background 0.2s; }\n" +
                "    button:hover { background: #2563eb; }\n" +
                "    .back-link { display: inline-block; margin-top: 18px; color: #64748b; text-decoration: none; font-size: 13px; }\n" +
                "    .back-link:hover { color: #94a3b8; }\n" +
                "  </style>\n" +
                "</head>\n" +
                "<body>\n" +
                "  <div class=\"card\">\n" +
                "    <div class=\"icon\">🔒</div>\n" +
                "    <h2>Password Protected</h2>\n" +
                "    <div class=\"file-meta\"><strong>" + safeFileName + "</strong> (" + safeSize + ")<br>Enter password to " + actionTitle.toLowerCase() + " this file.</div>\n" +
                "    " + errorBlock + "\n" +
                "    <form method=\"POST\" action=\"" + actionUrl + "\">\n" +
                "      <input type=\"password\" name=\"password\" placeholder=\"Enter file password\" required autofocus autocomplete=\"current-password\">\n" +
                "      <button type=\"submit\">Unlock &amp; " + actionTitle + "</button>\n" +
                "    </form>\n" +
                "    <a href=\"/\" class=\"back-link\">← Return to LAN Share</a>\n" +
                "  </div>\n" +
                "</body>\n" +
                "</html>";
    }

    private String escapeHtml(String text) {
        if (text == null) return "";
        return text.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }
}

package com.lanshare.model;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "shared_files")
public class SharedFile {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String originalFileName;

    @Column(nullable = false, unique = true)
    private String storedFileName;

    private String contentType;

    @Column(nullable = false)
    private long sizeBytes;

    @Column(nullable = false)
    private LocalDateTime uploadTime;

    @Column(name = "password_hash", nullable = true)
    @com.fasterxml.jackson.annotation.JsonIgnore
    private String passwordHash;

    public SharedFile() {
    }

    public SharedFile(String originalFileName, String storedFileName, String contentType, long sizeBytes, LocalDateTime uploadTime) {
        this(originalFileName, storedFileName, contentType, sizeBytes, uploadTime, null);
    }

    public SharedFile(String originalFileName, String storedFileName, String contentType, long sizeBytes, LocalDateTime uploadTime, String passwordHash) {
        this.originalFileName = originalFileName;
        this.storedFileName = storedFileName;
        this.contentType = contentType;
        this.sizeBytes = sizeBytes;
        this.uploadTime = uploadTime;
        this.passwordHash = passwordHash;
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getOriginalFileName() {
        return originalFileName;
    }

    public void setOriginalFileName(String originalFileName) {
        this.originalFileName = originalFileName;
    }

    public String getStoredFileName() {
        return storedFileName;
    }

    public void setStoredFileName(String storedFileName) {
        this.storedFileName = storedFileName;
    }

    public String getContentType() {
        return contentType;
    }

    public void setContentType(String contentType) {
        this.contentType = contentType;
    }

    public long getSizeBytes() {
        return sizeBytes;
    }

    public void setSizeBytes(long sizeBytes) {
        this.sizeBytes = sizeBytes;
    }

    public LocalDateTime getUploadTime() {
        return uploadTime;
    }

    public void setUploadTime(LocalDateTime uploadTime) {
        this.uploadTime = uploadTime;
    }

    public String getPasswordHash() {
        return passwordHash;
    }

    public void setPasswordHash(String passwordHash) {
        this.passwordHash = passwordHash;
    }

    @com.fasterxml.jackson.annotation.JsonProperty("protected")
    public boolean isProtected() {
        return passwordHash != null && !passwordHash.isBlank();
    }

    @com.fasterxml.jackson.annotation.JsonProperty("isProtected")
    public boolean getIsProtected() {
        return isProtected();
    }

    @Transient
    public String getFormattedSize() {
        if (sizeBytes < 1024) {
            return sizeBytes + " B";
        }
        int exp = (int) (Math.log(sizeBytes) / Math.log(1024));
        String pre = "KMGTPE".charAt(exp - 1) + "";
        return String.format("%.2f %sB", sizeBytes / Math.pow(1024, exp), pre);
    }

    @Transient
    public String getFileType() {
        if (contentType != null) {
            if (contentType.startsWith("image/")) return "image";
            if (contentType.startsWith("video/")) return "video";
            if (contentType.startsWith("audio/")) return "audio";
            if (contentType.equals("application/pdf")) return "pdf";
            if (contentType.contains("zip") || contentType.contains("tar") || contentType.contains("compressed") || contentType.contains("rar") || contentType.contains("7z")) return "archive";
            if (contentType.startsWith("text/") || contentType.contains("json") || contentType.contains("javascript") || contentType.contains("xml")) return "code";
        }
        String name = originalFileName != null ? originalFileName.toLowerCase() : "";
        if (name.endsWith(".zip") || name.endsWith(".tar.gz") || name.endsWith(".tgz") || name.endsWith(".rar") || name.endsWith(".7z")) return "archive";
        if (name.endsWith(".pdf")) return "pdf";
        if (name.endsWith(".jpg") || name.endsWith(".jpeg") || name.endsWith(".png") || name.endsWith(".gif") || name.endsWith(".webp") || name.endsWith(".svg")) return "image";
        if (name.endsWith(".mp4") || name.endsWith(".mkv") || name.endsWith(".avi") || name.endsWith(".mov")) return "video";
        if (name.endsWith(".mp3") || name.endsWith(".wav") || name.endsWith(".flac") || name.endsWith(".m4a")) return "audio";
        if (name.endsWith(".txt") || name.endsWith(".md") || name.endsWith(".doc") || name.endsWith(".docx")) return "document";
        return "file";
    }
}

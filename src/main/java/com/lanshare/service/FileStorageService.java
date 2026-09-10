package com.lanshare.service;

import com.lanshare.config.StorageConfig;
import com.lanshare.model.SharedFile;
import com.lanshare.repository.SharedFileRepository;
import jakarta.annotation.PostConstruct;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.net.MalformedURLException;
import java.nio.file.*;
import java.nio.file.attribute.PosixFilePermission;
import java.nio.file.attribute.PosixFilePermissions;
import java.time.LocalDateTime;
import java.util.*;

import com.lanshare.exception.StorageQuotaExceededException;
import java.util.stream.Stream;

@Service
public class FileStorageService {

    private final Path rootLocation;
    private final SharedFileRepository fileRepository;
    private final StorageConfig storageConfig;

    public FileStorageService(StorageConfig storageConfig, SharedFileRepository fileRepository) {
        this.storageConfig = storageConfig;
        this.rootLocation = Paths.get(storageConfig.getLocation()).toAbsolutePath().normalize();
        this.fileRepository = fileRepository;
    }

    @PostConstruct
    public void init() {
        try {
            Files.createDirectories(this.rootLocation);
        } catch (IOException e) {
            throw new RuntimeException("Could not initialize storage directory: " + rootLocation, e);
        }
    }

    public SharedFile store(MultipartFile file) {
        return store(file, null);
    }

    public SharedFile store(MultipartFile file, String passwordHash) {
        if (file == null || file.isEmpty()) {
            throw new IllegalArgumentException("Cannot store empty file.");
        }

        // Hard storage quota check before accepting file
        long currentUsed = getCurrentUsedStorage();
        long maxStorage = getMaxStorageSizeBytes();
        if (currentUsed + file.getSize() > maxStorage) {
            throw new StorageQuotaExceededException("Storage limit reached. Only " + getFormattedMaxStorage() + " is available for LAN Share.");
        }

        String rawFilename = file.getOriginalFilename();
        if (rawFilename == null || rawFilename.trim().isEmpty()) {
            rawFilename = "unnamed_file";
        }

        // Clean path and extract strictly the base file name to avoid path traversal
        String cleaned = StringUtils.cleanPath(rawFilename);
        Path rawPath = Paths.get(cleaned);
        String originalFilename = rawPath.getFileName().toString();

        if (originalFilename.contains("..")) {
            throw new SecurityException("Filename contains invalid path sequence: " + originalFilename);
        }

        // Sanitize file name for safe storage (keep alphanumeric, dots, dashes, underscores)
        String safeName = originalFilename.replaceAll("[^a-zA-Z0-9._-]", "_");
        if (safeName.isEmpty() || safeName.equals(".")) {
            safeName = "file";
        }

        // Generate collision-proof storage name using UUID
        String storedFilename = UUID.randomUUID().toString() + "_" + safeName;

        try {
            Path destinationFile = this.rootLocation.resolve(storedFilename).normalize().toAbsolutePath();

            // Strict security check: ensure destination is within rootLocation
            if (!destinationFile.getParent().equals(this.rootLocation)) {
                throw new SecurityException("Cannot store file outside current storage directory.");
            }

            try (InputStream inputStream = file.getInputStream()) {
                Files.copy(inputStream, destinationFile, StandardCopyOption.REPLACE_EXISTING);
            }

            // Ensure uploaded file is NOT executable (security precaution)
            try {
                Set<PosixFilePermission> perms = PosixFilePermissions.fromString("rw-r--r--");
                Files.setPosixFilePermissions(destinationFile, perms);
            } catch (UnsupportedOperationException ignored) {
                destinationFile.toFile().setExecutable(false, false);
            }

            String contentType = file.getContentType();
            if (contentType == null || contentType.isBlank()) {
                contentType = "application/octet-stream";
            }

            SharedFile sharedFile = new SharedFile(
                    originalFilename,
                    storedFilename,
                    contentType,
                    file.getSize(),
                    LocalDateTime.now(),
                    passwordHash
            );

            return fileRepository.save(sharedFile);
        } catch (IOException e) {
            throw new RuntimeException("Failed to store file: " + originalFilename, e);
        }
    }

    public List<SharedFile> getAllFiles() {
        return fileRepository.findAllByOrderByUploadTimeDesc();
    }

    public Optional<SharedFile> getFileById(Long id) {
        return fileRepository.findById(id);
    }

    public Resource loadAsResource(SharedFile sharedFile) {
        try {
            Path filePath = this.rootLocation.resolve(sharedFile.getStoredFileName()).normalize().toAbsolutePath();

            // Strict path traversal defense
            if (!filePath.getParent().equals(this.rootLocation)) {
                throw new SecurityException("Access to path outside storage directory is forbidden.");
            }

            Resource resource = new UrlResource(filePath.toUri());
            if (resource.exists() && resource.isReadable()) {
                return resource;
            } else {
                throw new RuntimeException("File not found or not readable: " + sharedFile.getOriginalFileName());
            }
        } catch (MalformedURLException e) {
            throw new RuntimeException("Malformed file path: " + sharedFile.getOriginalFileName(), e);
        }
    }

    public void deleteFile(Long id) {
        SharedFile sharedFile = fileRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("File not found with ID: " + id));

        try {
            Path filePath = this.rootLocation.resolve(sharedFile.getStoredFileName()).normalize().toAbsolutePath();
            if (filePath.getParent().equals(this.rootLocation)) {
                Files.deleteIfExists(filePath);
            }
        } catch (IOException e) {
            // Log and continue to delete DB record
            System.err.println("Failed to delete physical file from disk: " + e.getMessage());
        }

        fileRepository.delete(sharedFile);
    }

    public Path getRootLocation() {
        return rootLocation;
    }

    public long getCurrentUsedStorage() {
        if (!Files.exists(this.rootLocation)) {
            return 0L;
        }
        try (Stream<Path> stream = Files.list(this.rootLocation)) {
            return stream.filter(Files::isRegularFile)
                    .mapToLong(p -> {
                        try {
                            return Files.size(p);
                        } catch (IOException e) {
                            return 0L;
                        }
                    }).sum();
        } catch (IOException e) {
            return fileRepository.findAll().stream().mapToLong(SharedFile::getSizeBytes).sum();
        }
    }

    public long getMaxStorageSizeBytes() {
        return storageConfig.getMaxSizeBytes();
    }

    public String getFormattedMaxStorage() {
        return formatSize(getMaxStorageSizeBytes());
    }

    public String getFormattedUsedStorage() {
        return formatSize(getCurrentUsedStorage());
    }

    public String formatSize(long sizeBytes) {
        if (sizeBytes < 1024) return sizeBytes + " B";
        int exp = (int) (Math.log(sizeBytes) / Math.log(1024));
        String pre = "KMGTPE".charAt(exp - 1) + "";
        double val = sizeBytes / Math.pow(1024, exp);
        if (Math.abs(val - Math.round(val)) < 0.05) {
            return String.format(java.util.Locale.ROOT, "%d %sB", Math.round(val), pre);
        }
        return String.format(java.util.Locale.ROOT, "%.1f %sB", val, pre);
    }
}

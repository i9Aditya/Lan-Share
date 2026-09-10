package com.lanshare;

import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

@SpringBootApplication
public class LanShareApplication {

    private static final Logger log = LoggerFactory.getLogger(LanShareApplication.class);

    public static void main(String[] args) {
        ensureDirectoriesExist();
        SpringApplication.run(LanShareApplication.class, args);
    }

    private static void ensureDirectoriesExist() {
        try {
            String sep = FileSystems.getDefault().getSeparator();
            // Resolve data directory
            String dataDir = System.getenv("DATA_DIR");
            if (dataDir == null || dataDir.isBlank()) {
                dataDir = System.getProperty("DATA_DIR", "./data");
            }
            if (dataDir.startsWith("~" + sep) || dataDir.startsWith("~/")) {
                dataDir = System.getProperty("user.home") + dataDir.substring(1);
            }
            Path dbPath = Paths.get(dataDir, "db").toAbsolutePath().normalize();
            Files.createDirectories(dbPath);

            // Resolve storage directory
            String storageDir = System.getenv("STORAGE_DIR");
            if (storageDir == null || storageDir.isBlank()) {
                storageDir = System.getenv("LAN_STORAGE_LOCATION");
            }
            if (storageDir == null || storageDir.isBlank()) {
                storageDir = System.getProperty("STORAGE_DIR", "./data/uploads");
            }
            if (storageDir.startsWith("~" + sep) || storageDir.startsWith("~/")) {
                storageDir = System.getProperty("user.home") + storageDir.substring(1);
            }
            Path storagePath = Paths.get(storageDir).toAbsolutePath().normalize();
            Files.createDirectories(storagePath);
        } catch (Exception e) {
            log.warn("Pre-startup directory preparation notice: {}", e.getMessage());
        }
    }

    @PreDestroy
    public void onShutdown() {
        log.info("LAN Share server received shutdown signal. Commencing graceful shutdown...");
    }
}

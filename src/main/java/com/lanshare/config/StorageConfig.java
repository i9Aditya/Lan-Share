package com.lanshare.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Configuration;

import java.nio.file.FileSystems;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

@Configuration
@ConfigurationProperties(prefix = "lan.storage")
public class StorageConfig {

    private String location = "./data/uploads";
    private String maxStorageSize = "2GB";

    public String getLocation() {
        String sep = FileSystems.getDefault().getSeparator();
        if (location != null && (location.startsWith("~" + sep) || location.startsWith("~/"))) {
            return System.getProperty("user.home") + location.substring(1);
        } else if ("~".equals(location)) {
            return System.getProperty("user.home");
        }
        return location;
    }

    public void setLocation(String location) {
        this.location = location;
    }

    public String getMaxStorageSize() {
        return maxStorageSize;
    }

    public void setMaxStorageSize(String maxStorageSize) {
        this.maxStorageSize = maxStorageSize;
    }

    public long getMaxSizeBytes() {
        return parseSizeToBytes(this.maxStorageSize);
    }

    public static long parseSizeToBytes(String sizeStr) {
        if (sizeStr == null || sizeStr.isBlank()) {
            return 2L * 1024 * 1024 * 1024; // 2 GB default
        }
        String cleaned = sizeStr.trim().toUpperCase();
        long multiplier = 1L;
        if (cleaned.endsWith("GB") || cleaned.endsWith("G")) {
            multiplier = 1024L * 1024 * 1024;
            cleaned = cleaned.replaceAll("[^0-9.]", "");
        } else if (cleaned.endsWith("MB") || cleaned.endsWith("M")) {
            multiplier = 1024L * 1024;
            cleaned = cleaned.replaceAll("[^0-9.]", "");
        } else if (cleaned.endsWith("KB") || cleaned.endsWith("K")) {
            multiplier = 1024L;
            cleaned = cleaned.replaceAll("[^0-9.]", "");
        } else if (cleaned.endsWith("B")) {
            cleaned = cleaned.replaceAll("[^0-9.]", "");
        }
        try {
            double val = Double.parseDouble(cleaned);
            return (long) (val * multiplier);
        } catch (NumberFormatException e) {
            return 2L * 1024 * 1024 * 1024;
        }
    }

    public Path findConfigPath() {
        String envConf = System.getenv("CONF_FILE");
        if (envConf != null && !envConf.isBlank()) {
            Path p = Paths.get(envConf).toAbsolutePath().normalize();
            if (Files.exists(p)) return p;
        }
        String sysConf = System.getProperty("conf.file");
        if (sysConf != null && !sysConf.isBlank()) {
            Path p = Paths.get(sysConf).toAbsolutePath().normalize();
            if (Files.exists(p)) return p;
        }

        // Standard Linux XDG_CONFIG_HOME
        String xdgConfig = System.getenv("XDG_CONFIG_HOME");
        Path userConf;
        if (xdgConfig != null && !xdgConfig.isBlank()) {
            userConf = Paths.get(xdgConfig, "lan-share", "lan-share.conf").toAbsolutePath().normalize();
        } else {
            userConf = Paths.get(System.getProperty("user.home"), ".config", "lan-share", "lan-share.conf").toAbsolutePath().normalize();
        }
        if (Files.exists(userConf)) return userConf;

        Path localConf = Paths.get("lan-share.conf").toAbsolutePath().normalize();
        if (Files.exists(localConf)) return localConf;

        return userConf; // default target
    }

    public synchronized boolean persistMaxStorageSize(String newQuota) {
        if (newQuota == null || newQuota.isBlank()) return false;
        String formatted = newQuota.trim().toUpperCase();
        if (!formatted.matches("^[0-9]+(\\.[0-9]+)?\\s*(GB|G|MB|M|KB|K|B)?$")) {
            return false;
        }
        this.maxStorageSize = formatted;
        Path confPath = findConfigPath();
        try {
            if (confPath.getParent() != null) {
                Files.createDirectories(confPath.getParent());
            }
            List<String> lines = Files.exists(confPath)
                    ? Files.readAllLines(confPath)
                    : new ArrayList<>();
            List<String> updated = new ArrayList<>();
            boolean found = false;
            for (String line : lines) {
                if (line.trim().startsWith("MAX_STORAGE_SIZE=")) {
                    updated.add("MAX_STORAGE_SIZE=" + this.maxStorageSize);
                    found = true;
                } else {
                    updated.add(line);
                }
            }
            if (!found) {
                updated.add("MAX_STORAGE_SIZE=" + this.maxStorageSize);
            }
            Files.write(confPath, updated);
            return true;
        } catch (java.io.IOException e) {
            System.err.println("Failed to write updated quota to " + confPath + ": " + e.getMessage());
            return false;
        }
    }
}

package com.lanshare.controller;

import com.lanshare.repository.SharedFileRepository;
import com.lanshare.repository.SharedLinkRepository;
import com.lanshare.service.FileStorageService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.*;

import com.lanshare.config.StorageConfig;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;

@RestController
@RequestMapping("/api/info")
public class SystemInfoController {

    @Value("${server.port:8080}")
    private int serverPort;

    private final FileStorageService storageService;
    private final StorageConfig storageConfig;
    private final SharedFileRepository fileRepository;
    private final SharedLinkRepository linkRepository;

    public SystemInfoController(FileStorageService storageService,
                                StorageConfig storageConfig,
                                SharedFileRepository fileRepository,
                                SharedLinkRepository linkRepository) {
        this.storageService = storageService;
        this.storageConfig = storageConfig;
        this.fileRepository = fileRepository;
        this.linkRepository = linkRepository;
    }

    @GetMapping
    public ResponseEntity<Map<String, Object>> getSystemInfo() {
        Map<String, Object> info = new HashMap<>();

        List<String> lanIps = getLanIpAddresses();
        info.put("serverPort", serverPort);
        info.put("lanIps", lanIps);

        String primaryIp = lanIps.isEmpty() ? "127.0.0.1" : lanIps.get(0);
        info.put("primaryLanUrl", "http://" + primaryIp + ":" + serverPort);

        // File & Link counts
        long fileCount = fileRepository.count();
        long linkCount = linkRepository.count();
        info.put("fileCount", fileCount);
        info.put("linkCount", linkCount);

        // Storage location and Quota stats
        long usedStorageBytes = storageService.getCurrentUsedStorage();
        long maxStorageBytes = storageService.getMaxStorageSizeBytes();
        long remainingStorageBytes = Math.max(0, maxStorageBytes - usedStorageBytes);
        double usedPercentage = maxStorageBytes > 0 ? ((double) usedStorageBytes / maxStorageBytes) * 100.0 : 0.0;

        info.put("storageLocation", storageService.getRootLocation().toString());
        info.put("usedStorageBytes", usedStorageBytes);
        info.put("maxStorageBytes", maxStorageBytes);
        info.put("remainingStorageBytes", remainingStorageBytes);
        info.put("formattedUsedStorage", formatSize(usedStorageBytes));
        info.put("formattedMaxStorage", formatSize(maxStorageBytes));
        info.put("formattedRemainingStorage", formatSize(remainingStorageBytes));
        info.put("storageUsedPercent", Math.round(usedPercentage * 10.0) / 10.0);
        info.put("storageQuotaText", formatSize(usedStorageBytes) + " / " + formatSize(maxStorageBytes));
        info.put("formattedUsableSpace", formatSize(remainingStorageBytes));

        return ResponseEntity.ok(info);
    }

    @PostMapping("/quota")
    public ResponseEntity<Map<String, Object>> updateQuota(@RequestBody Map<String, String> body) {
        String newQuota = body != null ? body.get("quota") : null;
        if (newQuota == null || newQuota.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "Quota value required (e.g. '2GB', '500MB')."));
        }
        boolean success = storageConfig.persistMaxStorageSize(newQuota);
        if (!success) {
            return ResponseEntity.badRequest().body(Map.of("error", "Invalid quota format. Please use format like '2GB', '512MB'."));
        }
        return ResponseEntity.ok(Map.of(
                "success", true,
                "message", "Storage quota successfully updated to " + storageConfig.getMaxStorageSize(),
                "maxStorageSize", storageConfig.getMaxStorageSize(),
                "maxStorageBytes", storageConfig.getMaxSizeBytes()
        ));
    }

    private List<String> getLanIpAddresses() {
        List<String> ips = new ArrayList<>();
        try {
            Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
            while (interfaces.hasMoreElements()) {
                NetworkInterface iface = interfaces.nextElement();
                if (iface.isLoopback() || !iface.isUp() || iface.isVirtual()) {
                    continue;
                }
                Enumeration<InetAddress> addresses = iface.getInetAddresses();
                while (addresses.hasMoreElements()) {
                    InetAddress addr = addresses.nextElement();
                    if (addr instanceof Inet4Address && !addr.isLoopbackAddress()) {
                        String ip = addr.getHostAddress();
                        // Filter out common docker or bridge networks if present
                        if (!ip.startsWith("172.17.") && !ip.startsWith("172.18.")) {
                            ips.add(ip);
                        }
                    }
                }
            }
        } catch (Exception e) {
            // fallback
        }
        return ips;
    }

    private String formatSize(long sizeBytes) {
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

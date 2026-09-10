package com.lanshare.service;

import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class PasswordSecurityService {

    private final PasswordEncoder passwordEncoder = new BCryptPasswordEncoder();
    private final Map<String, TokenInfo> temporaryTokens = new ConcurrentHashMap<>();

    private record TokenInfo(Long fileId, Instant expiresAt) {}

    public String hashPassword(String rawPassword) {
        if (rawPassword == null || rawPassword.trim().isEmpty()) {
            return null;
        }
        return passwordEncoder.encode(rawPassword.trim());
    }

    public boolean matches(String rawPassword, String encodedHash) {
        if (encodedHash == null || encodedHash.isBlank()) {
            return true; // Not protected
        }
        if (rawPassword == null || rawPassword.isEmpty()) {
            return false;
        }
        return passwordEncoder.matches(rawPassword, encodedHash);
    }

    public String createTemporaryToken(Long fileId, long ttlSeconds) {
        cleanupExpiredTokens();
        String token = UUID.randomUUID().toString().replace("-", "");
        temporaryTokens.put(token, new TokenInfo(fileId, Instant.now().plusSeconds(ttlSeconds)));
        return token;
    }

    public boolean validateToken(Long fileId, String token) {
        if (token == null || token.isBlank()) {
            return false;
        }
        TokenInfo info = temporaryTokens.get(token);
        if (info == null) {
            return false;
        }
        if (Instant.now().isAfter(info.expiresAt())) {
            temporaryTokens.remove(token);
            return false;
        }
        return Objects.equals(info.fileId(), fileId);
    }

    private void cleanupExpiredTokens() {
        Instant now = Instant.now();
        temporaryTokens.entrySet().removeIf(entry -> now.isAfter(entry.getValue().expiresAt()));
    }
}

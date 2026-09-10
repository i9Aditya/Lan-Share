package com.lanshare.repository;

import com.lanshare.model.SharedFile;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface SharedFileRepository extends JpaRepository<SharedFile, Long> {
    List<SharedFile> findAllByOrderByUploadTimeDesc();
    Optional<SharedFile> findByStoredFileName(String storedFileName);
}

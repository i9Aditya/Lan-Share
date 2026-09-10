package com.lanshare.repository;

import com.lanshare.model.SharedLink;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface SharedLinkRepository extends JpaRepository<SharedLink, Long> {
    List<SharedLink> findAllByOrderByCreatedAtDesc();
}

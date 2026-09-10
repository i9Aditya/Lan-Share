package com.lanshare.exception;

public class StorageQuotaExceededException extends RuntimeException {

    public StorageQuotaExceededException(String message) {
        super(message);
    }
}

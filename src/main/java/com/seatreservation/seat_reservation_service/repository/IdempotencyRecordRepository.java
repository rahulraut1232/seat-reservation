package com.seatreservation.seat_reservation_service.repository;

import com.seatreservation.seat_reservation_service.entity.IdempotencyRecord;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface IdempotencyRecordRepository
        extends JpaRepository<IdempotencyRecord, Long> {

    Optional<IdempotencyRecord> findByUserIdAndIdempotencyKey(
            String userId,
            String idempotencyKey
    );

    boolean existsByUserIdAndIdempotencyKey(
            String userId,
            String idempotencyKey
    );
}
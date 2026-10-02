package com.seatreservation.seat_reservation_service.exception;

public class IdempotencyConflictException extends RuntimeException {

    public IdempotencyConflictException(String idempotencyKey) {
        super(
                "Idempotency key was already used with a different request: "
                        + idempotencyKey
        );
    }
}
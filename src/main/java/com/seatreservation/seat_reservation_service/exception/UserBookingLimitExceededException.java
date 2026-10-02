package com.seatreservation.seat_reservation_service.exception;

public class UserBookingLimitExceededException extends RuntimeException {

    public UserBookingLimitExceededException(
            int currentSeats,
            int requestedSeats,
            int limit) {

        super(
                "Per-user booking limit exceeded. "
                        + "Current active seats: " + currentSeats
                        + ", requested: " + requestedSeats
                        + ", limit: " + limit
        );
    }
}
package com.seatreservation.seat_reservation_service.exception;

public class ShowNotFoundException extends RuntimeException {

    public ShowNotFoundException(Long showId) {
        super("Show not found: " + showId);
    }
}
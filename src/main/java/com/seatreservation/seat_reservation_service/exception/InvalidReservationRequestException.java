package com.seatreservation.seat_reservation_service.exception;

public class InvalidReservationRequestException
        extends RuntimeException {

    public InvalidReservationRequestException(String message) {
        super(message);
    }
}

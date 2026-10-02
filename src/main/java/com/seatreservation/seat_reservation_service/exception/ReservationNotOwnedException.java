package com.seatreservation.seat_reservation_service.exception;

public class ReservationNotOwnedException extends RuntimeException {

    public ReservationNotOwnedException() {
        super("You are not allowed to access this reservation");
    }
}
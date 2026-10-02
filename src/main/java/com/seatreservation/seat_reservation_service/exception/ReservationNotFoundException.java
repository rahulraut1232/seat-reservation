package com.seatreservation.seat_reservation_service.exception;

public class ReservationNotFoundException extends RuntimeException {

    public ReservationNotFoundException(String reservationId) {
        super("Reservation not found: " + reservationId);
    }
}
package com.seatreservation.seat_reservation_service.exception;

public class SeatAlreadyTakenException extends RuntimeException {

    public SeatAlreadyTakenException(String seatNumber) {
        super("Seat already taken: " + seatNumber);
    }
}
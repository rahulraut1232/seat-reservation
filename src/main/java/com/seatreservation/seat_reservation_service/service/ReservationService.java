package com.seatreservation.seat_reservation_service.service;

import com.seatreservation.seat_reservation_service.entity.Reservation;

import java.util.List;

public interface ReservationService {

    Reservation reserve(
            Long showId,
            String userId,
            List<String> seatNumbers,
            String idempotencyKey
    );

    void cancel(
            String reservationId,
            String userId
    );
}
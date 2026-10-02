package com.seatreservation.seat_reservation_service.dto;

import com.seatreservation.seat_reservation_service.entity.Reservation;
import com.seatreservation.seat_reservation_service.entity.ReservationStatus;

import java.util.List;

public record ReservationResponse(

        String reservation_id,

        Long show_id,

        String user_id,

        List<String> seats,

        Long amount_paise,

        ReservationStatus status

) {

    public static ReservationResponse from(
            Reservation reservation) {

        List<String> seats =
                reservation.getReservationSeats()
                        .stream()
                        .map(reservationSeat ->
                                reservationSeat
                                        .getSeat()
                                        .getSeatNumber()
                        )
                        .sorted()
                        .toList();

        return new ReservationResponse(
                reservation.getId(),
                reservation.getShow().getId(),
                reservation.getUserId(),
                seats,
                reservation.getAmountPaise(),
                reservation.getStatus()
        );
    }
}
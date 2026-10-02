package com.seatreservation.seat_reservation_service.dto;

import com.seatreservation.seat_reservation_service.entity.SeatStatus;

public record SeatResponse(

        String seat,

        SeatStatus status

) {

    public static SeatResponse from(
            String seatNumber,
            SeatStatus status) {

        return new SeatResponse(
                seatNumber,
                status
        );
    }
}
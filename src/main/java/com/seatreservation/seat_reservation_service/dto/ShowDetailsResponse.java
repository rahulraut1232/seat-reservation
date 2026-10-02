package com.seatreservation.seat_reservation_service.dto;

import com.seatreservation.seat_reservation_service.entity.Seat;
import com.seatreservation.seat_reservation_service.entity.SeatStatus;
import com.seatreservation.seat_reservation_service.entity.Show;

import java.util.List;

public record ShowDetailsResponse(

        Long id,

        String name,

        Long price_paise,

        Integer per_user_limit,

        Integer total_seats,

        Integer available_seats,

        Integer held_seats,

        Integer confirmed_seats,

        List<SeatResponse> seats

) {

    public static ShowDetailsResponse from(
            Show show,
            List<Seat> seatEntities) {

        List<SeatResponse> seats =
                seatEntities.stream()
                        .map(seat ->
                                SeatResponse.from(
                                        seat.getSeatNumber(),
                                        seat.getStatus()
                                )
                        )
                        .toList();

        int total = seatEntities.size();

        int available = (int) seatEntities.stream()
                .filter(seat ->
                        seat.getStatus()
                                == SeatStatus.AVAILABLE)
                .count();

        int held = (int) seatEntities.stream()
                .filter(seat ->
                        seat.getStatus()
                                == SeatStatus.HELD)
                .count();

        int confirmed = (int) seatEntities.stream()
                .filter(seat ->
                        seat.getStatus()
                                == SeatStatus.CONFIRMED)
                .count();

        return new ShowDetailsResponse(
                show.getId(),
                show.getName(),
                show.getPricePaise(),
                show.getPerUserLimit(),
                total,
                available,
                held,
                confirmed,
                seats
        );
    }
}
package com.seatreservation.seat_reservation_service.dto;

import java.util.List;

public record ShowResponse(

        Long id,

        String name,

        List<String> seats,

        Long price_paise,

        Integer per_user_limit

) {
}
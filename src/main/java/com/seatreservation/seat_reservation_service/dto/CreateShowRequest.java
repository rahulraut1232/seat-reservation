package com.seatreservation.seat_reservation_service.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

import java.util.List;

public record CreateShowRequest(

        @NotBlank(message = "Show name is required")
        String name,

        @NotEmpty(message = "At least one seat is required")
        List<@NotBlank(message = "Seat number cannot be blank") String> seats,

        @Min(value = 0, message = "Price cannot be negative")
        Long price_paise

) {
}
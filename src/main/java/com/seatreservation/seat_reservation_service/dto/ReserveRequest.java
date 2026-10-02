package com.seatreservation.seat_reservation_service.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

import java.util.List;

public record ReserveRequest(

        @NotEmpty(message = "At least one seat is required")
        List<@NotBlank(message = "Seat number cannot be blank") String> seats,

        @NotBlank(message = "Idempotency key is required")
        String idempotency_key

) {
}
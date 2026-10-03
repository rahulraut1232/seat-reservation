package com.seatreservation.seat_reservation_service.controller;

import com.seatreservation.seat_reservation_service.dto.ReservationResponse;
import com.seatreservation.seat_reservation_service.dto.ReserveRequest;
import com.seatreservation.seat_reservation_service.entity.Reservation;
import com.seatreservation.seat_reservation_service.service.ReservationService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController
public class ReservationController {

    private final ReservationService reservationService;

    public ReservationController(
            ReservationService reservationService) {

        this.reservationService = reservationService;
    }

    /*
     * ---------------------------------------------------------
     * RESERVE SEATS
     * ---------------------------------------------------------
     *
     * POST /shows/{showId}/reserve
     *
     * Request:
     *
     * {
     *   "seats": ["A1", "A2"],
     *   "idempotency_key": "abc-123"
     * }
     *
     * The user ID is NOT accepted from the request body.
     * It comes from the authenticated bearer token.
     */
    @PostMapping("/shows/{showId}/reserve")
    public ResponseEntity<ReservationResponse> reserve(
            @PathVariable Long showId,
            @Valid @RequestBody ReserveRequest request,
            Authentication authentication) {

        String userId = authentication.getName();

        Reservation reservation =
                reservationService.reserve(
                        showId,
                        userId,
                        request.seats(),
                        request.idempotency_key()
                );

        ReservationResponse response =
                ReservationResponse.from(reservation);

        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body(response);
    }

    /*
     * ---------------------------------------------------------
     * CANCEL RESERVATION
     * ---------------------------------------------------------
     *
     * POST /reservations/{reservationId}/cancel
     *
     * The owner is obtained from Authentication.
     *
     * The client cannot provide userId in the request.
     *
     * The service verifies that the authenticated user owns
     * the reservation before releasing the seats.
     */
    @PostMapping("/reservations/{reservationId}/cancel")
    public ResponseEntity<ReservationResponse> cancel(
            @PathVariable String reservationId,
            Authentication authentication) {

        String userId = authentication.getName();

        Reservation reservation =
                reservationService.cancel(
                        reservationId,
                        userId
                );

        ReservationResponse response =
                ReservationResponse.from(reservation);

        return ResponseEntity
                .ok(response);
    }
}
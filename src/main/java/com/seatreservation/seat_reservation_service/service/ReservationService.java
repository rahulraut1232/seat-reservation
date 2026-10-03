package com.seatreservation.seat_reservation_service.service;

import com.seatreservation.seat_reservation_service.entity.Reservation;

import java.util.List;

public interface ReservationService {

    /*
     * ---------------------------------------------------------
     * RESERVE SEATS
     * ---------------------------------------------------------
     *
     * Atomically reserves the requested seats for the user.
     *
     * The userId comes from the authenticated token.
     */
    Reservation reserve(
            Long showId,
            String userId,
            List<String> seatNumbers,
            String idempotencyKey
    );

    /*
     * ---------------------------------------------------------
     * CANCEL RESERVATION
     * ---------------------------------------------------------
     *
     * Cancels a reservation owned by the authenticated user.
     *
     * The implementation must:
     *
     * 1. Verify that the reservation exists.
     * 2. Verify that userId owns the reservation.
     * 3. Serialize concurrent cancellation/reservation activity.
     * 4. Lock the reservation's seats.
     * 5. Release the seats back to AVAILABLE.
     * 6. Update the user's active booking count.
     * 7. Mark the reservation as CANCELLED.
     *
     * Returning the reservation allows the controller to return
     * the resulting state to the client.
     */
    Reservation cancel(
            String reservationId,
            String userId
    );
}
package com.seatreservation.seat_reservation_service.exception;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.time.LocalDateTime;

@RestControllerAdvice
public class GlobalExceptionHandler {

    /*
     * ---------------------------------------------------------
     * 400 BAD REQUEST
     * ---------------------------------------------------------
     *
     * Invalid input from the client.
     */
    @ExceptionHandler(InvalidReservationRequestException.class)
    public ResponseEntity<ErrorResponse> handleInvalidRequest(
            InvalidReservationRequestException ex) {

        return buildResponse(
                HttpStatus.BAD_REQUEST,
                "INVALID_REQUEST",
                ex.getMessage()
        );
    }

    /*
     * ---------------------------------------------------------
     * 404 NOT FOUND
     * ---------------------------------------------------------
     */

    @ExceptionHandler(ShowNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleShowNotFound(
            ShowNotFoundException ex) {

        return buildResponse(
                HttpStatus.NOT_FOUND,
                "SHOW_NOT_FOUND",
                ex.getMessage()
        );
    }

    @ExceptionHandler(ReservationNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleReservationNotFound(
            ReservationNotFoundException ex) {

        return buildResponse(
                HttpStatus.NOT_FOUND,
                "RESERVATION_NOT_FOUND",
                ex.getMessage()
        );
    }

    /*
     * ---------------------------------------------------------
     * 409 CONFLICT
     * ---------------------------------------------------------
     *
     * These are expected business-level declines.
     *
     * IMPORTANT:
     * They must NOT become HTTP 500.
     */

    @ExceptionHandler(SeatAlreadyTakenException.class)
    public ResponseEntity<ErrorResponse> handleSeatAlreadyTaken(
            SeatAlreadyTakenException ex) {

        return buildResponse(
                HttpStatus.CONFLICT,
                "SEAT_ALREADY_TAKEN",
                ex.getMessage()
        );
    }

    @ExceptionHandler(UserBookingLimitExceededException.class)
    public ResponseEntity<ErrorResponse> handleUserBookingLimit(
            UserBookingLimitExceededException ex) {

        return buildResponse(
                HttpStatus.CONFLICT,
                "USER_BOOKING_LIMIT_EXCEEDED",
                ex.getMessage()
        );
    }

    @ExceptionHandler(IdempotencyConflictException.class)
    public ResponseEntity<ErrorResponse> handleIdempotencyConflict(
            IdempotencyConflictException ex) {

        return buildResponse(
                HttpStatus.CONFLICT,
                "IDEMPOTENCY_CONFLICT",
                ex.getMessage()
        );
    }

    @ExceptionHandler(ReservationNotOwnedException.class)
    public ResponseEntity<ErrorResponse> handleReservationNotOwned(
            ReservationNotOwnedException ex) {

        return buildResponse(
                HttpStatus.FORBIDDEN,
                "RESERVATION_NOT_OWNED",
                ex.getMessage()
        );
    }

    /*
     * ---------------------------------------------------------
     * FALLBACK
     * ---------------------------------------------------------
     *
     * Unexpected errors should still return a controlled
     * response instead of exposing stack traces.
     *
     * NOTE:
     * The assignment's "zero 5xx" requirement applies to
     * expected domain declines. Genuine infrastructure/
     * programming failures can still legitimately be 500.
     */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleUnexpectedException(
            Exception ex) {

        return buildResponse(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "INTERNAL_SERVER_ERROR",
                "An unexpected error occurred"
        );
    }

    /*
     * ---------------------------------------------------------
     * RESPONSE BUILDER
     * ---------------------------------------------------------
     */

    private ResponseEntity<ErrorResponse> buildResponse(
            HttpStatus status,
            String errorCode,
            String message) {

        ErrorResponse response =
                new ErrorResponse(
                        LocalDateTime.now(),
                        status.value(),
                        errorCode,
                        message
                );

        return ResponseEntity
                .status(status)
                .body(response);
    }

    /*
     * ---------------------------------------------------------
     * ERROR RESPONSE DTO
     * ---------------------------------------------------------
     */

    public record ErrorResponse(
            LocalDateTime timestamp,
            int status,
            String errorCode,
            String message
    ) {
    }
}
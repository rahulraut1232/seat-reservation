package com.seatreservation.seat_reservation_service.service;

import com.seatreservation.seat_reservation_service.entity.*;
import com.seatreservation.seat_reservation_service.exception.*;
import com.seatreservation.seat_reservation_service.repository.*;
import io.micrometer.core.instrument.Counter;
import jakarta.transaction.Transactional;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;
import java.util.List;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.Set;

@Service
public class ReservationServiceImpl implements ReservationService {

    private final ShowRepository showRepository;
    private final SeatRepository seatRepository;
    private final ReservationRepository reservationRepository;
    private final IdempotencyRecordRepository idempotencyRecordRepository;
    private final UserShowBookingRepository userShowBookingRepository;
    private final Counter reservationsConfirmedCounter;
    private final Counter seatTakenDeclinedCounter;
    private final Counter perUserLimitDeclinedCounter;
    private final Counter idempotencyReplayCounter;

    public ReservationServiceImpl(
            ShowRepository showRepository,
            SeatRepository seatRepository,
            ReservationRepository reservationRepository,
            IdempotencyRecordRepository idempotencyRecordRepository,
            UserShowBookingRepository userShowBookingRepository,
            Counter reservationsConfirmedCounter,
            Counter seatTakenDeclinedCounter,
            Counter perUserLimitDeclinedCounter,
            Counter idempotencyReplayCounter) {

        this.showRepository = showRepository;
        this.seatRepository = seatRepository;
        this.reservationRepository = reservationRepository;
        this.idempotencyRecordRepository = idempotencyRecordRepository;
        this.userShowBookingRepository = userShowBookingRepository;
        this.reservationsConfirmedCounter = reservationsConfirmedCounter;
        this.seatTakenDeclinedCounter = seatTakenDeclinedCounter;
        this.perUserLimitDeclinedCounter = perUserLimitDeclinedCounter;
        this.idempotencyReplayCounter = idempotencyReplayCounter;
    }

    @Override
    @Transactional
    public Reservation reserve(
            Long showId,
            String userId,
            List<String> seatNumbers,
            String idempotencyKey) {

        validateReservationRequest(
                showId,
                userId,
                seatNumbers,
                idempotencyKey
        );

        /*
         * Normalize and sort seats.
         *
         * Sorting gives every transaction the same lock order.
         * This helps prevent deadlocks for multi-seat requests.
         */
        List<String> requestedSeats =
                normalizeSeatNumbers(seatNumbers);

        /*
         * Load show.
         */
        Show show = showRepository.findById(showId)
                .orElseThrow(() ->
                        new ShowNotFoundException(showId)
                );

        /*
         * ---------------------------------------------------------
         * USER + SHOW ROW
         * ---------------------------------------------------------
         *
         * Create the row if this is the first booking attempt
         * from this user for this show.
         *
         * PostgreSQL ON CONFLICT DO NOTHING makes this safe
         * under concurrent first-time requests.
         */
        userShowBookingRepository.createIfAbsent(
                showId,
                userId
        );

        /*
         * Lock the user-show row.
         *
         * Every reservation for the same user + show must acquire
         * this lock before checking/updating activeSeatCount.
         */
        UserShowBooking userShowBooking =
                userShowBookingRepository.findForUpdate(
                        showId,
                        userId
                ).orElseThrow(() ->
                        new IllegalStateException(
                                "User-show booking record could not be created"
                        )
                );

        /*
         * ---------------------------------------------------------
         * IDEMPOTENCY
         * ---------------------------------------------------------
         */
        String requestHash =
                createRequestHash(
                        showId,
                        requestedSeats
                );

        var existingRecord =
                idempotencyRecordRepository
                        .findByUserIdAndIdempotencyKey(
                                userId,
                                idempotencyKey
                        );

        if (existingRecord.isPresent()) {

            IdempotencyRecord record =
                    existingRecord.get();

            /*
             * Same key + different request = 409.
             */
            if (!record.getRequestHash()
                    .equals(requestHash)) {

                throw new IdempotencyConflictException(
                        idempotencyKey
                );
            }

            idempotencyReplayCounter.increment();

            /*
             * Same key + same request.
             *
             * Return the original reservation.
             */
            return record.getReservation();
        }

        /*
         * ---------------------------------------------------------
         * PER-USER LIMIT
         * ---------------------------------------------------------
         *
         * This check is concurrency-safe because the
         * UserShowBooking row is locked.
         */
        int currentActiveSeats =
                userShowBooking.getActiveSeatCount();

        int requestedSeatCount =
                requestedSeats.size();

        int perUserLimit =
                show.getPerUserLimit();

        if (currentActiveSeats + requestedSeatCount
                > perUserLimit) {
            perUserLimitDeclinedCounter.increment();

            throw new UserBookingLimitExceededException(
                    currentActiveSeats,
                    requestedSeatCount,
                    perUserLimit
            );
        }

        /*
         * ---------------------------------------------------------
         * LOCK REQUESTED SEATS
         * ---------------------------------------------------------
         *
         * PESSIMISTIC_WRITE translates to row-level locking
         * in PostgreSQL.
         *
         * Seats are returned in seatNumber ASC order.
         */
        List<Seat> seats =
                seatRepository.findSeatsForUpdate(
                        showId,
                        requestedSeats
                );

        /*
         * ---------------------------------------------------------
         * CHECK SEAT EXISTENCE
         * ---------------------------------------------------------
         */
        if (seats.size() != requestedSeats.size()) {

            Set<String> foundSeats =
                    new HashSet<>();

            for (Seat seat : seats) {
                foundSeats.add(
                        seat.getSeatNumber()
                );
            }

            List<String> missingSeats =
                    new ArrayList<>();

            for (String requestedSeat : requestedSeats) {

                if (!foundSeats.contains(requestedSeat)) {
                    missingSeats.add(requestedSeat);
                }
            }

            throw new InvalidReservationRequestException(
                    "Requested seat(s) do not exist: "
                            + missingSeats
            );
        }

        /*
         * ---------------------------------------------------------
         * CHECK AVAILABILITY
         * ---------------------------------------------------------
         *
         * All-or-nothing behavior.
         *
         * If one seat is unavailable, the entire request fails.
         */
        for (Seat seat : seats) {

            if (seat.getStatus()
                    != SeatStatus.AVAILABLE) {
                seatTakenDeclinedCounter.increment();

                throw new SeatAlreadyTakenException(
                        seat.getSeatNumber()
                );
            }
        }

        /*
         * ---------------------------------------------------------
         * CALCULATE AMOUNT
         * ---------------------------------------------------------
         *
         * Price is stored in paise.
         *
         * No floating-point arithmetic.
         */
        long amountPaise;

        try {

            amountPaise =
                    Math.multiplyExact(
                            show.getPricePaise(),
                            (long) requestedSeatCount
                    );

        } catch (ArithmeticException ex) {

            throw new InvalidReservationRequestException(
                    "Reservation amount is too large"
            );
        }

        /*
         * ---------------------------------------------------------
         * CREATE RESERVATION
         * ---------------------------------------------------------
         */
        Reservation reservation =
                new Reservation();

        reservation.setShow(show);
        reservation.setUserId(userId);
        reservation.setAmountPaise(amountPaise);
        reservation.setStatus(
                ReservationStatus.CONFIRMED
        );
        reservation.setCreatedAt(
                LocalDateTime.now()
        );

        /*
         * Explicit cancellation model:
         * reservations are confirmed immediately,
         * so expiresAt is not required.
         */
        reservation.setExpiresAt(null);

        reservation =
                reservationRepository.save(
                        reservation
                );

        /*
         * ---------------------------------------------------------
         * CONFIRM SEATS
         * ---------------------------------------------------------
         */
        for (Seat seat : seats) {

            seat.setStatus(
                    SeatStatus.CONFIRMED
            );

            ReservationSeat reservationSeat =
                    new ReservationSeat(
                            reservation,
                            seat
                    );

            reservation
                    .getReservationSeats()
                    .add(reservationSeat);
        }

        /*
         * Because Reservation has:
         *
         * cascade = CascadeType.ALL
         *
         * ReservationSeat records will also be persisted.
         */
        reservation =
                reservationRepository.save(
                        reservation
                );

        /*
         * ---------------------------------------------------------
         * UPDATE USER ACTIVE SEAT COUNT
         * ---------------------------------------------------------
         */
        userShowBooking.setActiveSeatCount(
                currentActiveSeats
                        + requestedSeatCount
        );

        userShowBookingRepository.save(
                userShowBooking
        );

        /*
         * ---------------------------------------------------------
         * IDEMPOTENCY RECORD
         * ---------------------------------------------------------
         */
        IdempotencyRecord idempotencyRecord =
                new IdempotencyRecord(
                        userId,
                        idempotencyKey,
                        requestHash,
                        reservation
                );

        idempotencyRecordRepository.save(
                idempotencyRecord
        );

        reservationsConfirmedCounter.increment();

        return reservation;
    }

    @Override
    @Transactional
    public void cancel(
            String reservationId,
            String userId) {

        validateCancellationRequest(
                reservationId,
                userId
        );

        /*
         * ---------------------------------------------------------
         * LOAD RESERVATION
         * ---------------------------------------------------------
         */
        Reservation reservation =
                reservationRepository.findById(
                        reservationId
                ).orElseThrow(() ->
                        new ReservationNotFoundException(
                                reservationId
                        )
                );

        /*
         * ---------------------------------------------------------
         * OWNER CHECK
         * ---------------------------------------------------------
         *
         * userId MUST come from authentication.
         */
        if (!reservation.getUserId()
                .equals(userId)) {

            throw new ReservationNotOwnedException();
        }

        /*
         * ---------------------------------------------------------
         * IDEMPOTENT CANCEL
         * ---------------------------------------------------------
         *
         * Calling cancel again on an already cancelled
         * reservation does nothing.
         */
        if (reservation.getStatus()
                == ReservationStatus.CANCELLED) {

            return;
        }

        /*
         * Only active reservations can be cancelled.
         */
        if (reservation.getStatus()
                != ReservationStatus.CONFIRMED
                && reservation.getStatus()
                != ReservationStatus.HELD) {

            throw new InvalidReservationRequestException(
                    "Reservation cannot be cancelled in status: "
                            + reservation.getStatus()
            );
        }

        Show show =
                reservation.getShow();

        /*
         * ---------------------------------------------------------
         * LOCK USER-SHOW ROW
         * ---------------------------------------------------------
         *
         * IMPORTANT:
         *
         * Reservation and cancellation both acquire:
         *
         * 1. UserShowBooking lock
         * 2. Seat locks
         *
         * in the same order.
         */
        userShowBookingRepository.createIfAbsent(
                show.getId(),
                userId
        );

        UserShowBooking userShowBooking =
                userShowBookingRepository.findForUpdate(
                        show.getId(),
                        userId
                ).orElseThrow(() ->
                        new IllegalStateException(
                                "User-show booking record not found"
                        )
                );

        /*
         * ---------------------------------------------------------
         * LOCK RESERVATION SEATS
         * ---------------------------------------------------------
         *
         * This uses the method we added to SeatRepository:
         *
         * findReservationSeatsForUpdate()
         */
        List<Seat> seats =
                seatRepository
                        .findReservationSeatsForUpdate(
                                reservationId
                        );

        /*
         * ---------------------------------------------------------
         * RELEASE SEATS
         * ---------------------------------------------------------
         */
        for (Seat seat : seats) {

            seat.setStatus(
                    SeatStatus.AVAILABLE
            );
        }

        /*
         * ---------------------------------------------------------
         * UPDATE USER ACTIVE SEAT COUNT
         * ---------------------------------------------------------
         */
        int currentActiveSeats =
                userShowBooking.getActiveSeatCount();

        int reservationSeatCount =
                seats.size();

        userShowBooking.setActiveSeatCount(
                Math.max(
                        0,
                        currentActiveSeats
                                - reservationSeatCount
                )
        );

        /*
         * ---------------------------------------------------------
         * CANCEL RESERVATION
         * ---------------------------------------------------------
         */
        reservation.setStatus(
                ReservationStatus.CANCELLED
        );

        /*
         * ---------------------------------------------------------
         * SAVE CHANGES
         * ---------------------------------------------------------
         */
        seatRepository.saveAll(seats);

        userShowBookingRepository.save(
                userShowBooking
        );

        reservationRepository.save(
                reservation
        );
    }

    /*
     * =============================================================
     * VALIDATION
     * =============================================================
     */

    private void validateReservationRequest(
            Long showId,
            String userId,
            List<String> seatNumbers,
            String idempotencyKey) {

        if (showId == null) {

            throw new InvalidReservationRequestException(
                    "Show ID is required"
            );
        }

        if (userId == null
                || userId.isBlank()) {

            throw new InvalidReservationRequestException(
                    "Authenticated user is required"
            );
        }

        if (seatNumbers == null
                || seatNumbers.isEmpty()) {

            throw new InvalidReservationRequestException(
                    "At least one seat is required"
            );
        }

        if (idempotencyKey == null
                || idempotencyKey.isBlank()) {

            throw new InvalidReservationRequestException(
                    "Idempotency key is required"
            );
        }

        if (seatNumbers.size() > 100) {

            throw new InvalidReservationRequestException(
                    "Too many seats requested"
            );
        }
    }

    private void validateCancellationRequest(
            String reservationId,
            String userId) {

        if (reservationId == null
                || reservationId.isBlank()) {

            throw new InvalidReservationRequestException(
                    "Reservation ID is required"
            );
        }

        if (userId == null
                || userId.isBlank()) {

            throw new InvalidReservationRequestException(
                    "Authenticated user is required"
            );
        }
    }

    /*
     * =============================================================
     * SEAT NORMALIZATION
     * =============================================================
     */

    private List<String> normalizeSeatNumbers(
            List<String> seatNumbers) {

        /*
         * Trim + sort.
         *
         * We intentionally do NOT silently remove duplicates.
         * A request containing duplicates is invalid.
         */
        List<String> normalized =
                seatNumbers.stream()
                        .map(String::trim)
                        .toList();

        /*
         * Blank seat number.
         */
        if (normalized.stream()
                .anyMatch(String::isBlank)) {

            throw new InvalidReservationRequestException(
                    "Seat number cannot be blank"
            );
        }

        /*
         * Duplicate seat number.
         */
        Set<String> uniqueSeats =
                new HashSet<>(normalized);

        if (uniqueSeats.size()
                != normalized.size()) {

            throw new InvalidReservationRequestException(
                    "Duplicate seat numbers are not allowed"
            );
        }

        /*
         * Deterministic lock order.
         */
        return normalized.stream()
                .sorted()
                .toList();
    }

    /*
     * =============================================================
     * IDEMPOTENCY REQUEST HASH
     * =============================================================
     */

    private String createRequestHash(
            Long showId,
            List<String> seatNumbers) {

        /*
         * The list is already normalized and sorted.
         *
         * Therefore:
         *
         * [A1, A2]
         *
         * and
         *
         * [A2, A1]
         *
         * produce the same request hash.
         */
        String canonicalRequest =
                showId
                        + "|"
                        + String.join(
                        ",",
                        seatNumbers
                );

        try {

            MessageDigest digest =
                    MessageDigest.getInstance(
                            "SHA-256"
                    );

            byte[] hash =
                    digest.digest(
                            canonicalRequest.getBytes(
                                    StandardCharsets.UTF_8
                            )
                    );

            StringBuilder result =
                    new StringBuilder();

            for (byte b : hash) {

                result.append(
                        String.format(
                                "%02x",
                                b
                        )
                );
            }

            return result.toString();

        } catch (NoSuchAlgorithmException ex) {

            /*
             * SHA-256 is guaranteed by standard Java
             * implementations, so this indicates a serious
             * runtime problem.
             */
            throw new IllegalStateException(
                    "SHA-256 algorithm is not available",
                    ex
            );
        }
    }
}
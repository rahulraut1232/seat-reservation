package com.seatreservation.seat_reservation_service.repository;

import com.seatreservation.seat_reservation_service.entity.Seat;
import com.seatreservation.seat_reservation_service.entity.SeatStatus;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface SeatRepository extends JpaRepository<Seat, Long> {

    Optional<Seat> findByShowIdAndSeatNumber(
            Long showId,
            String seatNumber
    );

    List<Seat> findByShowIdOrderBySeatNumberAsc(Long showId);

    List<Seat> findByShowIdAndSeatNumberInOrderBySeatNumberAsc(
            Long showId,
            Collection<String> seatNumbers
    );

    long countByShowIdAndStatus(
            Long showId,
            SeatStatus status
    );

    long countByStatus(SeatStatus status);

    /*
     * Pessimistic write lock.
     *
     * SELECT ... FOR UPDATE
     *
     * This prevents two concurrent transactions from
     * modifying the same seat at the same time.
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
        SELECT s
        FROM Seat s
        WHERE s.show.id = :showId
          AND s.seatNumber IN :seatNumbers
        ORDER BY s.seatNumber ASC
        """)
    List<Seat> findSeatsForUpdate(
            @Param("showId") Long showId,
            @Param("seatNumbers") Collection<String> seatNumbers
    );

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
    SELECT s
    FROM Seat s
    JOIN ReservationSeat rs
        ON rs.seat.id = s.id
    WHERE rs.reservation.id = :reservationId
    ORDER BY s.seatNumber ASC
    """)
    List<Seat> findReservationSeatsForUpdate(
            @Param("reservationId") String reservationId
    );
}
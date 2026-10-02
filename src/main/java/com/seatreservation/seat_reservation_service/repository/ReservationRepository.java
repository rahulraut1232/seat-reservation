package com.seatreservation.seat_reservation_service.repository;

import com.seatreservation.seat_reservation_service.entity.Reservation;
import com.seatreservation.seat_reservation_service.entity.ReservationStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface ReservationRepository
        extends JpaRepository<Reservation, String> {

    /*
     * Used for enforcing the per-user booking limit.
     *
     * HELD and CONFIRMED seats both count towards the limit.
     */
    @Query("""
        SELECT COUNT(rs)
        FROM ReservationSeat rs
        JOIN rs.reservation r
        WHERE r.show.id = :showId
          AND r.userId = :userId
          AND r.status IN :statuses
        """)
    long countActiveSeatsForUser(
            @Param("showId") Long showId,
            @Param("userId") String userId,
            @Param("statuses") List<ReservationStatus> statuses
    );

    List<Reservation> findByShowIdAndUserId(
            Long showId,
            String userId
    );

    List<Reservation> findByShowIdAndStatus(
            Long showId,
            ReservationStatus status
    );
}
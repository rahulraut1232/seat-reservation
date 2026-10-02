package com.seatreservation.seat_reservation_service.repository;

import com.seatreservation.seat_reservation_service.entity.UserShowBooking;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface UserShowBookingRepository
        extends JpaRepository<UserShowBooking, Long> {

    /*
     * Lock the user's row for this show.
     *
     * Equivalent to:
     *
     * SELECT ...
     * FROM user_show_bookings
     * WHERE show_id = ?
     * AND user_id = ?
     * FOR UPDATE
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("""
        SELECT u
        FROM UserShowBooking u
        WHERE u.show.id = :showId
          AND u.userId = :userId
        """)
    Optional<UserShowBooking> findForUpdate(
            @Param("showId") Long showId,
            @Param("userId") String userId
    );

    Optional<UserShowBooking> findByShowIdAndUserId(
            Long showId,
            String userId
    );

    boolean existsByShowIdAndUserId(
            Long showId,
            String userId
    );

    /**
     * Creates the user-show booking row if it doesn't already exist.
     *
     * PostgreSQL-specific:
     * INSERT ... ON CONFLICT DO NOTHING
     */
    @Modifying
    @Query(value = """
        INSERT INTO user_show_bookings
            (show_id, user_id, active_seat_count)
        VALUES
            (:showId, :userId, 0)
        ON CONFLICT (show_id, user_id)
        DO NOTHING
        """, nativeQuery = true)
    int createIfAbsent(
            @Param("showId") Long showId,
            @Param("userId") String userId
    );

}
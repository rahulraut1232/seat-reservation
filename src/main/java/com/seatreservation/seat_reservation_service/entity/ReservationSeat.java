package com.seatreservation.seat_reservation_service.entity;

import jakarta.persistence.*;

@Entity
@Table(
        name = "reservation_seats",
        uniqueConstraints = {
                @UniqueConstraint(
                        name = "uk_reservation_seat",
                        columnNames = {"reservation_id", "seat_id"}
                )
        }
)
public class ReservationSeat {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "reservation_id", nullable = false)
    private Reservation reservation;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "seat_id", nullable = false)
    private Seat seat;

    public ReservationSeat() {
    }

    public ReservationSeat(Reservation reservation, Seat seat) {
        this.reservation = reservation;
        this.seat = seat;
    }

    public Long getId() {
        return id;
    }

    public Reservation getReservation() {
        return reservation;
    }

    public Seat getSeat() {
        return seat;
    }
}
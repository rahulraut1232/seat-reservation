package com.seatreservation.seat_reservation_service.entity;

import jakarta.persistence.*;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(
        name = "reservations",
        indexes = {
                @Index(
                        name = "idx_reservation_user_show",
                        columnList = "user_id, show_id"
                ),
                @Index(
                        name = "idx_reservation_show",
                        columnList = "show_id"
                )
        }
)
public class Reservation {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private String id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "show_id", nullable = false)
    private Show show;

    @Column(name = "user_id", nullable = false)
    private String userId;

    @Column(name = "amount_paise", nullable = false)
    private Long amountPaise;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private ReservationStatus status;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @Column(name = "expires_at")
    private LocalDateTime expiresAt;

    @OneToMany(
            mappedBy = "reservation",
            cascade = CascadeType.ALL,
            orphanRemoval = true
    )
    private List<ReservationSeat> reservationSeats = new ArrayList<>();


    public Reservation() {
    }

    public String getId() {
        return id;
    }

    public Show getShow() {
        return show;
    }

    public String getUserId() {
        return userId;
    }

    public Long getAmountPaise() {
        return amountPaise;
    }

    public ReservationStatus getStatus() {
        return status;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public LocalDateTime getExpiresAt() {
        return expiresAt;
    }

    public List<ReservationSeat> getReservationSeats() {
        return reservationSeats;
    }


    public void setId(String id) {
        this.id = id;
    }

    public void setShow(Show show) {
        this.show = show;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public void setAmountPaise(Long amountPaise) {
        this.amountPaise = amountPaise;
    }

    public void setStatus(ReservationStatus status) {
        this.status = status;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public void setExpiresAt(LocalDateTime expiresAt) {
        this.expiresAt = expiresAt;
    }

    public void setReservationSeats(
            List<ReservationSeat> reservationSeats) {
        this.reservationSeats = reservationSeats;
    }
}
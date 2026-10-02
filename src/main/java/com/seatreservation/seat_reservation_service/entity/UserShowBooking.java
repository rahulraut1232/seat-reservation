package com.seatreservation.seat_reservation_service.entity;

import jakarta.persistence.*;

@Entity
@Table(
        name = "user_show_bookings",
        uniqueConstraints = {
                @UniqueConstraint(
                        name = "uk_user_show",
                        columnNames = {"show_id", "user_id"}
                )
        }
)
public class UserShowBooking {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "show_id", nullable = false)
    private Show show;

    @Column(name = "user_id", nullable = false)
    private String userId;

    /*
     * Number of currently active seats for this user
     * on this particular show.
     *
     * HELD + CONFIRMED
     */
    @Column(name = "active_seat_count", nullable = false)
    private Integer activeSeatCount = 0;

    public UserShowBooking() {
    }

    public UserShowBooking(
            Show show,
            String userId) {

        this.show = show;
        this.userId = userId;
        this.activeSeatCount = 0;
    }

    public Long getId() {
        return id;
    }

    public Show getShow() {
        return show;
    }

    public String getUserId() {
        return userId;
    }

    public Integer getActiveSeatCount() {
        return activeSeatCount;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public void setShow(Show show) {
        this.show = show;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public void setActiveSeatCount(Integer activeSeatCount) {
        this.activeSeatCount = activeSeatCount;
    }
}
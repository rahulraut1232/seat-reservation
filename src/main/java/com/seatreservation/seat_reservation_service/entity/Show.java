package com.seatreservation.seat_reservation_service.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "shows")
public class Show {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String name;

    @Column(name = "price_paise", nullable = false)
    private Long pricePaise;

    @Column(name = "per_user_limit", nullable = false)
    private Integer perUserLimit = 4;

    public Show() {
    }

    public Show(String name, Long pricePaise, Integer perUserLimit) {
        this.name = name;
        this.pricePaise = pricePaise;
        this.perUserLimit = perUserLimit;
    }

    public Long getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public Long getPricePaise() {
        return pricePaise;
    }

    public Integer getPerUserLimit() {
        return perUserLimit;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public void setName(String name) {
        this.name = name;
    }

    public void setPricePaise(Long pricePaise) {
        this.pricePaise = pricePaise;
    }

    public void setPerUserLimit(Integer perUserLimit) {
        this.perUserLimit = perUserLimit;
    }
}
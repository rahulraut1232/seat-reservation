package com.seatreservation.seat_reservation_service.service;

import com.seatreservation.seat_reservation_service.entity.Show;

import java.util.List;

public interface ShowService {

    Show createShow(
            String name,
            List<String> seatNumbers,
            Long pricePaise,
            Integer perUserLimit
    );

    Show getShow(Long showId);
}
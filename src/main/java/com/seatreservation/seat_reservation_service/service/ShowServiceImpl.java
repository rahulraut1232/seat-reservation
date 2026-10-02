package com.seatreservation.seat_reservation_service.service;

import com.seatreservation.seat_reservation_service.entity.Seat;
import com.seatreservation.seat_reservation_service.entity.Show;
import com.seatreservation.seat_reservation_service.repository.SeatRepository;
import com.seatreservation.seat_reservation_service.repository.ShowRepository;
import jakarta.transaction.Transactional;
import org.springframework.stereotype.Service;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

@Service
public class ShowServiceImpl implements ShowService {

    private final ShowRepository showRepository;
    private final SeatRepository seatRepository;

    public ShowServiceImpl(
            ShowRepository showRepository,
            SeatRepository seatRepository) {

        this.showRepository = showRepository;
        this.seatRepository = seatRepository;
    }

    @Override
    @Transactional
    public Show createShow(
            String name,
            List<String> seatNumbers,
            Long pricePaise,
            Integer perUserLimit) {

        validateShow(name, seatNumbers, pricePaise, perUserLimit);

        if (showRepository.existsByName(name)) {
            throw new IllegalArgumentException(
                    "Show already exists: " + name
            );
        }

        Show show = new Show(
                name,
                pricePaise,
                perUserLimit
        );

        Show savedShow = showRepository.save(show);

        List<Seat> seats = seatNumbers.stream()
                .map(seatNumber ->
                        new Seat(savedShow, seatNumber))
                .toList();

        seatRepository.saveAll(seats);

        return savedShow;
    }

    @Override
    @Transactional
    public Show getShow(Long showId) {

        return showRepository.findById(showId)
                .orElseThrow(() ->
                        new IllegalArgumentException(
                                "Show not found: " + showId
                        ));
    }

    private void validateShow(
            String name,
            List<String> seatNumbers,
            Long pricePaise,
            Integer perUserLimit) {

        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException(
                    "Show name is required"
            );
        }

        if (seatNumbers == null || seatNumbers.isEmpty()) {
            throw new IllegalArgumentException(
                    "At least one seat is required"
            );
        }

        Set<String> uniqueSeats = new HashSet<>(seatNumbers);

        if (uniqueSeats.size() != seatNumbers.size()) {
            throw new IllegalArgumentException(
                    "Duplicate seat numbers are not allowed"
            );
        }

        if (pricePaise == null || pricePaise < 0) {
            throw new IllegalArgumentException(
                    "Price must be non-negative"
            );
        }

        if (perUserLimit == null || perUserLimit <= 0) {
            throw new IllegalArgumentException(
                    "Per-user limit must be greater than zero"
            );
        }
    }
}
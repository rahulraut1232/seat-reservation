package com.seatreservation.seat_reservation_service.metrics;

import com.seatreservation.seat_reservation_service.entity.SeatStatus;
import com.seatreservation.seat_reservation_service.repository.SeatRepository;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.stereotype.Component;

@Component
public class ReservationMetrics {

    private final SeatRepository seatRepository;

    public ReservationMetrics(
            SeatRepository seatRepository,
            MeterRegistry meterRegistry) {

        this.seatRepository = seatRepository;

        Gauge.builder(
                        "available_seats",
                        this,
                        ReservationMetrics::getAvailableSeats
                )
                .description("Current number of available seats across all shows")
                .register(meterRegistry);
    }

    private double getAvailableSeats() {
        return seatRepository.countByStatus(SeatStatus.AVAILABLE);
    }
}
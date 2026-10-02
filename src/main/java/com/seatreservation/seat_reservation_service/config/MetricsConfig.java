package com.seatreservation.seat_reservation_service.config;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class MetricsConfig {

    @Bean
    public Counter reservationsConfirmedCounter(MeterRegistry meterRegistry) {
        return Counter.builder("reservations_confirmed_total")
                .description("Number of successfully confirmed reservations")
                .register(meterRegistry);
    }

    @Bean
    public Counter seatTakenDeclinedCounter(MeterRegistry meterRegistry) {
        return Counter.builder("reservations_declined_total")
                .tag("reason", "seat_taken")
                .description("Number of reservations declined because a seat was already taken")
                .register(meterRegistry);
    }

    @Bean
    public Counter perUserLimitDeclinedCounter(MeterRegistry meterRegistry) {
        return Counter.builder("reservations_declined_total")
                .tag("reason", "per_user_limit")
                .description("Number of reservations declined because the per-user limit was exceeded")
                .register(meterRegistry);
    }

    @Bean
    public Counter idempotencyReplayCounter(MeterRegistry meterRegistry) {
        return Counter.builder("reservations_declined_total")
                .tag("reason", "idempotency_replay")
                .description("Number of idempotent reservation replays")
                .register(meterRegistry);
    }
}
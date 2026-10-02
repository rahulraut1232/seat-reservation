package com.seatreservation.seat_reservation_service.config;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class HealthController {

    private final JdbcTemplate jdbcTemplate;

    public HealthController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * Liveness probe.
     *
     * Indicates that the application process is running.
     * It intentionally does not check external dependencies.
     */
    @GetMapping("/health/live")
    public ResponseEntity<Map<String, String>> liveness() {

        return ResponseEntity.ok(
                Map.of(
                        "status", "UP",
                        "type", "liveness"
                )
        );
    }

    /**
     * Readiness probe.
     *
     * The application is ready to receive traffic only when
     * the database is reachable.
     */
    @GetMapping("/health/ready")
    public ResponseEntity<Map<String, String>> readiness() {

        try {
            jdbcTemplate.queryForObject(
                    "SELECT 1",
                    Integer.class
            );

            return ResponseEntity.ok(
                    Map.of(
                            "status", "UP",
                            "type", "readiness",
                            "database", "UP"
                    )
            );

        } catch (Exception ex) {

            return ResponseEntity
                    .status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(
                            Map.of(
                                    "status", "DOWN",
                                    "type", "readiness",
                                    "database", "DOWN"
                            )
                    );
        }
    }
}
package com.seatreservation.seat_reservation_service.controller;

import com.seatreservation.seat_reservation_service.dto.CreateShowRequest;
import com.seatreservation.seat_reservation_service.dto.ShowDetailsResponse;
import com.seatreservation.seat_reservation_service.dto.ShowResponse;
import com.seatreservation.seat_reservation_service.entity.Seat;
import com.seatreservation.seat_reservation_service.entity.Show;
import com.seatreservation.seat_reservation_service.repository.SeatRepository;
import com.seatreservation.seat_reservation_service.service.ShowService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/shows")
public class ShowController {

    private final ShowService showService;
    private final SeatRepository seatRepository;

    public ShowController(
            ShowService showService,
            SeatRepository seatRepository) {

        this.showService = showService;
        this.seatRepository = seatRepository;
    }

    /*
     * ---------------------------------------------------------
     * CREATE SHOW
     * ---------------------------------------------------------
     *
     * POST /shows
     *
     * Request:
     * {
     *   "name": "Mumbai Concert",
     *   "seats": ["A1", "A2", "A3"],
     *   "price_paise": 50000
     * }
     */
    @PostMapping
    public ResponseEntity<ShowResponse> createShow(
            @Valid @RequestBody CreateShowRequest request) {

        /*
         * Assignment default:
         * per-user limit = 4.
         */
        Show show = showService.createShow(
                request.name(),
                request.seats(),
                request.price_paise(),
                4
        );

        List<String> seats =
                seatRepository
                        .findByShowIdOrderBySeatNumberAsc(
                                show.getId()
                        )
                        .stream()
                        .map(Seat::getSeatNumber)
                        .toList();

        ShowResponse response =
                new ShowResponse(
                        show.getId(),
                        show.getName(),
                        seats,
                        show.getPricePaise(),
                        show.getPerUserLimit()
                );

        return ResponseEntity
                .status(HttpStatus.CREATED)
                .body(response);
    }

    /*
     * ---------------------------------------------------------
     * GET SHOW
     * ---------------------------------------------------------
     *
     * GET /shows/{id}
     *
     * Returns:
     * - total seats
     * - available seats
     * - held seats
     * - confirmed seats
     * - individual seat status
     */
    @GetMapping("/{showId}")
    public ResponseEntity<ShowDetailsResponse> getShow(
            @PathVariable Long showId) {

        Show show =
                showService.getShow(showId);

        List<Seat> seats =
                seatRepository
                        .findByShowIdOrderBySeatNumberAsc(
                                showId
                        );

        ShowDetailsResponse response =
                ShowDetailsResponse.from(
                        show,
                        seats
                );

        return ResponseEntity.ok(response);
    }
}
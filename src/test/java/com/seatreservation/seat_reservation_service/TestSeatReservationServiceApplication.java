package com.seatreservation.seat_reservation_service;

import org.springframework.boot.SpringApplication;

public class TestSeatReservationServiceApplication {

	public static void main(String[] args) {
		SpringApplication.from(SeatReservationServiceApplication::main).with(TestcontainersConfiguration.class).run(args);
	}

}

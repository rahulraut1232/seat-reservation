CREATE TABLE shows (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    price_paise BIGINT NOT NULL,
    per_user_limit INTEGER NOT NULL DEFAULT 4
);

CREATE TABLE seats (
    id BIGSERIAL PRIMARY KEY,
    show_id BIGINT NOT NULL,
    seat_number VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE',

    CONSTRAINT fk_seat_show
        FOREIGN KEY (show_id) REFERENCES shows(id),

    CONSTRAINT uk_seat_show_number
        UNIQUE (show_id, seat_number)
);

CREATE INDEX idx_seats_show_status
    ON seats(show_id, status);

CREATE TABLE reservations (
    id VARCHAR(36) PRIMARY KEY,
    show_id BIGINT NOT NULL,
    user_id VARCHAR(100) NOT NULL,
    amount_paise BIGINT NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE,

    CONSTRAINT fk_reservation_show
        FOREIGN KEY (show_id) REFERENCES shows(id)
);

CREATE INDEX idx_reservations_show_user
    ON reservations(show_id, user_id);

CREATE TABLE reservation_seats (
    id BIGSERIAL PRIMARY KEY,
    reservation_id VARCHAR(36) NOT NULL,
    seat_id BIGINT NOT NULL,

    CONSTRAINT fk_reservation_seat_reservation
        FOREIGN KEY (reservation_id) REFERENCES reservations(id),

    CONSTRAINT fk_reservation_seat_seat
        FOREIGN KEY (seat_id) REFERENCES seats(id),

    CONSTRAINT uk_reservation_seat
        UNIQUE (reservation_id, seat_id)
);

CREATE TABLE idempotency_records (
    id BIGSERIAL PRIMARY KEY,
    user_id VARCHAR(100) NOT NULL,
    idempotency_key VARCHAR(255) NOT NULL,
    request_hash VARCHAR(64) NOT NULL,
    reservation_id VARCHAR(36) NOT NULL UNIQUE,

    CONSTRAINT fk_idempotency_reservation
        FOREIGN KEY (reservation_id) REFERENCES reservations(id),

    CONSTRAINT uk_idempotency_user_key
        UNIQUE (user_id, idempotency_key)
);

CREATE TABLE user_show_bookings (
    id BIGSERIAL PRIMARY KEY,
    show_id BIGINT NOT NULL,
    user_id VARCHAR(100) NOT NULL,
    active_seat_count INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT fk_user_show_booking_show
        FOREIGN KEY (show_id) REFERENCES shows(id),

    CONSTRAINT uk_user_show_booking
        UNIQUE (show_id, user_id)
);

CREATE INDEX idx_user_show_booking_user
    ON user_show_bookings(show_id, user_id);
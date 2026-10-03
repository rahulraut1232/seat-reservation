# Seat Reservation at Scale

A production-oriented Spring Boot service for concurrent seat reservation with strong consistency, idempotency, per-user booking limits, authentication, observability, and Docker support.

The service is designed around correctness under high contention, particularly when many users attempt to reserve the same seat concurrently.

---

## 🚀 Live Deployment

**Live API:**
https://seat-reservation-service-gj8y.onrender.com

### Health Checks

* **Liveness:** `/health/live`
* **Readiness:** `/health/ready`
* **Prometheus Metrics:** `/actuator/prometheus`

Full URLs:

```text
https://seat-reservation-service-gj8y.onrender.com/health/live
https://seat-reservation-service-gj8y.onrender.com/health/ready
https://seat-reservation-service-gj8y.onrender.com/actuator/prometheus
```

> The service is deployed on Render. The free-tier instance may take some time to wake up after inactivity.

---

## ✅ Deployment Validation

The complete correctness and concurrency test suite was executed against the deployed service.

| Test                    | Result |
| ----------------------- | ------ |
| Authentication          | PASS   |
| Burst / No Double Sell  | PASS   |
| Per User Limit          | PASS   |
| Idempotency Concurrency | PASS   |
| Idempotency Conflict    | PASS   |
| Multi Seat Atomicity    | PASS   |
| Cancel Ownership        | PASS   |

**Final result: 7/7 tests passed against the live deployment.**

The test suite validates:

* No double-selling under concurrent requests
* Zero unexpected 5xx responses during contention
* Reconciliation invariant
* Idempotent retries
* Same-key/different-body conflicts
* Per-user booking limits under concurrency
* Token-derived identity
* Reservation ownership during cancellation
* Multi-seat atomicity

---

## 📋 Quick Start

### Prerequisites

* Java 21
* Maven 3.9+
* Docker Desktop
* PowerShell 5.1+

### Build

```powershell
mvn clean package
```

### Run with Docker Compose

```powershell
docker compose up --build -d
```

The application will be available at:

```text
http://localhost:8080
```

PostgreSQL will run on:

```text
localhost:5432
```

### Check application health

```powershell
curl.exe http://localhost:8080/health/live
curl.exe http://localhost:8080/health/ready
```

---

## 🏗️ Architecture

```text
                    ┌─────────────────────┐
                    │      Client         │
                    └──────────┬──────────┘
                               │
                         HTTP / JSON
                               │
                               ▼
                    ┌─────────────────────┐
                    │ Spring Boot API     │
                    │                     │
                    │ Authentication      │
                    │ Controllers         │
                    │ Validation           │
                    │ Reservation Service │
                    └──────────┬──────────┘
                               │
                               │ Transaction
                               ▼
                    ┌─────────────────────┐
                    │    PostgreSQL       │
                    │                     │
                    │ Shows               │
                    │ Seats               │
                    │ Reservations        │
                    │ Reservation Seats   │
                    │ Idempotency         │
                    │ User/Show Booking   │
                    └─────────────────────┘
```

The database is the system of record for reservation state.

Concurrency control is implemented using PostgreSQL transactions and pessimistic row-level locking.

---

## ✨ Features

* Concurrent seat reservation
* No double-selling
* Multi-seat atomic reservation
* Per-user seat booking limit
* Idempotency support
* Same-key/different-request detection
* Token-derived user identity
* Reservation cancellation with ownership validation
* PostgreSQL persistence
* Flyway database migrations
* Integer paise-based money representation
* Liveness and readiness health checks
* Prometheus metrics
* Correlation/request IDs
* Structured application logging
* Docker support
* PowerShell concurrency test suite

---

# 🔌 API

## 1. Create Show

### Request

```http
POST /shows
Authorization: Bearer <admin-user>
Content-Type: application/json
```

```json
{
  "name": "friday-night",
  "seats": [
    "A1",
    "A2",
    "A3",
    "A4"
  ],
  "price_paise": 25000
}
```

### Response

```json
{
  "id": 1,
  "name": "friday-night",
  "seats": [
    "A1",
    "A2",
    "A3",
    "A4"
  ],
  "price_paise": 25000,
  "per_user_limit": 4
}
```

---

## 2. Reserve Seats

### Request

```http
POST /shows/{id}/reserve
Authorization: Bearer <user-id>
Content-Type: application/json
```

```json
{
  "seats": [
    "A1"
  ],
  "idempotency_key": "reservation-123"
}
```

The user identity is derived from the authentication token.

The request body does **not** contain a `user_id`.

### Successful Response

```json
{
  "reservation_id": "e30e1695-4087-4915-8b22-4e877d635107",
  "show_id": 1,
  "user_id": "user-123",
  "seats": [
    "A1"
  ],
  "amount_paise": 25000,
  "status": "CONFIRMED"
}
```

---

## 3. Cancel Reservation

### Request

```http
POST /reservations/{reservationId}/cancel
Authorization: Bearer <user-id>
```

Only the owner of the reservation can cancel it.

A repeated cancellation by the owner is safe and returns the already-cancelled reservation.

An attempt by another user returns:

```http
403 Forbidden
```

---

## 4. Get Show State

### Request

```http
GET /shows/{id}
```

### Response

```json
{
  "id": 1,
  "name": "friday-night",
  "price_paise": 25000,
  "per_user_limit": 4,
  "total_seats": 4,
  "available_seats": 3,
  "held_seats": 0,
  "confirmed_seats": 1,
  "seats": [
    {
      "seat": "A1",
      "status": "CONFIRMED"
    },
    {
      "seat": "A2",
      "status": "AVAILABLE"
    },
    {
      "seat": "A3",
      "status": "AVAILABLE"
    },
    {
      "seat": "A4",
      "status": "AVAILABLE"
    }
  ]
}
```

### Reconciliation Invariant

At all times:

```text
available_seats + held_seats + confirmed_seats = total_seats
```

---

# 💥 Concurrency / Burst Testing

The repository contains PowerShell scripts covering the major correctness requirements.

The scripts are environment-independent and accept the target service through the `BaseUrl` parameter.

## Run the complete suite against the live deployment

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\scripts\run-all-tests.ps1 `
    -BaseUrl "https://seat-reservation-service-gj8y.onrender.com"
```

## Run against a local deployment

```powershell
.\scripts\run-all-tests.ps1 `
    -BaseUrl "http://localhost:8080"
```

### Individual tests

```powershell
.\scripts\authentication-test.ps1 -BaseUrl "https://seat-reservation-service-gj8y.onrender.com"

.\scripts\burst-test.ps1 -BaseUrl "https://seat-reservation-service-gj8y.onrender.com"

.\scripts\per-user-limit-test.ps1 -BaseUrl "https://seat-reservation-service-gj8y.onrender.com"

.\scripts\idempotency-concurrency-test.ps1 -BaseUrl "https://seat-reservation-service-gj8y.onrender.com"

.\scripts\idempotency-conflict-test.ps1 -BaseUrl "https://seat-reservation-service-gj8y.onrender.com"

.\scripts\multi-seat-atomicity-test.ps1 -BaseUrl "https://seat-reservation-service-gj8y.onrender.com"

.\scripts\cancel-ownership-test.ps1 -BaseUrl "https://seat-reservation-service-gj8y.onrender.com"
```

---

## Test Scenarios

### Authentication

Verifies:

* Unauthenticated reservation requests return `401`
* Authenticated requests succeed
* Public show GET remains accessible

### Burst / No Double Sell

Multiple users concurrently target the same seat.

Expected:

```text
Exactly one 201
Remaining requests: 409
5xx responses: 0
```

### Per User Limit

Multiple concurrent requests from the same user are sent against a show with a limit of 4.

The final number of confirmed seats for that user must not exceed 4.

### Idempotency Concurrency

Multiple concurrent requests use the same:

```text
user + show + idempotency_key
```

Only one reservation is created. Retries return the same reservation.

### Idempotency Conflict

The same idempotency key is reused with a different seat selection.

Expected:

```http
409 Conflict
```

with an idempotency conflict error.

### Multi Seat Atomicity

A request attempts to reserve multiple seats simultaneously.

The service uses an all-or-nothing model:

* If all requested seats are available → reservation succeeds.
* If any requested seat is unavailable → entire request is rejected.
* No partial reservation is created.

### Cancel Ownership

Verifies that:

* The owner can cancel the reservation.
* Another user receives `403`.
* The reservation remains confirmed after an unauthorized cancellation attempt.
* The owner can safely repeat the cancellation.
* Cancelled seats become available again.

---

# 🔒 Concurrency Design

The reservation decision is protected by a database transaction.

The service:

1. Validates the request.
2. Locks the per-user/show booking row.
3. Checks the user's active seat count.
4. Locks all requested seat rows using a pessimistic write lock.
5. Locks seats in deterministic seat-number order.
6. Verifies that every requested seat is `AVAILABLE`.
7. Creates the reservation and reservation-seat records.
8. Marks the seats as `CONFIRMED`.
9. Updates the user's active seat count.
10. Stores the idempotency record.
11. Commits the transaction.

This prevents two concurrent transactions from successfully confirming the same seat.

---

# 🔐 Deterministic Lock Ordering

Multi-seat reservations can involve multiple seat rows.

To reduce deadlock risk, requested seat numbers are:

1. Normalized
2. Deduplicated
3. Sorted
4. Locked in ascending order

For example:

```text
[A5, A2, A8]
```

becomes:

```text
[A2, A5, A8]
```

All transactions therefore attempt to acquire seat locks in the same order.

---

# ♻️ Idempotency

Idempotency is enforced using a database table keyed by:

```text
(user_id, idempotency_key)
```

The stored request hash is calculated from the reservation request.

For example:

```text
show_id | sorted seats
```

### Same key + same request

The original reservation is returned.

No additional reservation or charge is created.

### Same key + different request

The request is rejected with:

```http
409 Conflict
```

This prevents accidental reuse of an idempotency key for a different reservation.

---

# 👤 Authentication

The reservation user is derived from the Bearer authentication token.

Example:

```http
Authorization: Bearer user-123
```

The controller obtains:

```java
authentication.getName()
```

and passes that identity to the reservation service.

There is no `user_id` field accepted in the reservation request.

For this take-home implementation, the bearer token itself represents the user identity.

### Production implementation

A production deployment would replace this simplified authentication mechanism with JWT/OIDC validation, including:

* Signature verification
* Issuer validation
* Audience validation
* Expiration validation
* Subject extraction

---

# 💰 Money Representation

All monetary values are represented as integer paise.

Example:

```text
₹250.00 = 25000 paise
```

No floating-point representation is used for monetary calculations.

The service also uses checked multiplication when calculating reservation totals to avoid integer overflow.

---

# 🗄️ Database

PostgreSQL is used as the system of record.

### Main tables

```text
shows
seats
reservations
reservation_seats
idempotency_records
user_show_bookings
```

### Important constraints

* Unique show name
* Unique `(show_id, seat_number)`
* Unique `(reservation_id, seat_id)`
* Unique `(user_id, idempotency_key)`
* Unique `(show_id, user_id)`

These constraints provide additional protection at the database layer.

---

# 🛠️ Database Migrations

Flyway manages database schema migrations.

Migration files are located under:

```text
src/main/resources/db/migration/
```

The application uses:

```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: validate
```

Hibernate validates the schema rather than modifying it automatically.

---

# ❤️ Health Checks

## Liveness

```http
GET /health/live
```

Indicates that the application process is running.

Example:

```json
{
  "status": "UP",
  "type": "liveness"
}
```

## Readiness

```http
GET /health/ready
```

The readiness check executes a database query.

If PostgreSQL is unavailable, readiness returns:

```http
503 Service Unavailable
```

This allows a deployment platform to distinguish between:

* Application process is alive
* Application is actually ready to serve traffic

---

# 📊 Observability

## Prometheus

Metrics are exposed through:

```text
/actuator/prometheus
```

The application exposes metrics including:

* Confirmed reservations
* Reservation declines
* Seat-taken declines
* Per-user-limit declines
* Idempotency replay
* Available seats

Example metric:

```text
available_seats
```

The available-seat gauge is derived from the current database state.

---

# 🧾 Correlation IDs

Every request receives an `X-Request-ID`.

Clients may provide their own:

```http
X-Request-ID: abc-123
```

Otherwise the service generates a UUID.

The ID is:

* Returned in the HTTP response
* Added to the logging MDC
* Included in application logs

This makes it possible to trace a request across application logs.

---

# 📝 Error Handling

Domain failures return appropriate 4xx responses rather than 5xx errors.

Examples:

| Scenario                | HTTP Status |
| ----------------------- | ----------: |
| Invalid request         |         400 |
| Show not found          |         404 |
| Reservation not found   |         404 |
| Seat already taken      |         409 |
| Per-user limit exceeded |         409 |
| Idempotency conflict    |         409 |
| Reservation not owned   |         403 |
| Authentication required |         401 |

Unexpected application failures are handled by the global exception handler.

---

# 🐳 Docker

The application includes a multi-stage Dockerfile.

The first stage builds the application using Maven and Java 21.

The second stage runs the generated JAR using a lightweight Java 21 runtime.

Build:

```powershell
docker build -t seat-reservation-service .
```

Run with Docker Compose:

```powershell
docker compose up --build -d
```

Stop:

```powershell
docker compose down
```

Stop and remove database volume:

```powershell
docker compose down -v
```

---

# ⚙️ Configuration

The application supports environment-based database configuration.

```text
SPRING_DATASOURCE_URL
SPRING_DATASOURCE_USERNAME
SPRING_DATASOURCE_PASSWORD
PORT
```

Local defaults point to PostgreSQL running on:

```text
localhost:5432
```

Docker Compose overrides the database hostname to:

```text
postgres
```

The application uses UTC to avoid timezone compatibility issues across environments.

---

# 📁 Project Structure

```text
seat-reservation-service/
│
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/seatreservation/seat_reservation_service/
│   │   │       ├── config/
│   │   │       ├── controller/
│   │   │       ├── dto/
│   │   │       ├── entity/
│   │   │       ├── exception/
│   │   │       ├── repository/
│   │   │       ├── service/
│   │   │       └── metrics/
│   │   │
│   │   └── resources/
│   │       ├── db/migration/
│   │       └── application.yml
│   │
│   └── test/
│
├── scripts/
│   ├── run-all-tests.ps1
│   ├── authentication-test.ps1
│   ├── burst-test.ps1
│   ├── per-user-limit-test.ps1
│   ├── idempotency-concurrency-test.ps1
│   ├── idempotency-conflict-test.ps1
│   ├── multi-seat-atomicity-test.ps1
│   └── cancel-ownership-test.ps1
│
├── Dockerfile
├── docker-compose.yml
├── pom.xml
├── README.md
└── WRITEUP.md
```

---

# 🧪 Clean Checkout

A clean checkout should be able to build and run using:

```powershell
mvn clean package
```

or:

```powershell
docker compose up --build -d
```

The repository contains the required database migrations, Docker configuration, and test scripts.

---

# ⚖️ Design Trade-offs

## PostgreSQL Row Locks vs Redis

PostgreSQL was selected as the source of truth because the reservation state, idempotency state, and user booking limits can be updated transactionally.

Using Redis for distributed locking could reduce database contention in some architectures, but would introduce additional consistency and failure-mode considerations.

For this assignment, a single strongly consistent database provides a simpler correctness model.

## Consistency vs Availability

The service prioritizes correctness and consistency for reservations.

If the database is unavailable, the service should not attempt to make reservation decisions from stale or locally cached seat state.

This means reservation availability may temporarily decrease during a database outage, but the system avoids risking duplicate reservations.

---

# ⏳ Holds and Expiry

The implementation uses an explicit cancellation model.

Reservations are confirmed immediately rather than using a temporary hold followed by payment confirmation.

Cancellation releases the associated seats back to `AVAILABLE`.

A future production implementation could introduce time-boxed holds with:

* Hold expiration timestamps
* Background expiry processing
* Atomic expiration checks
* Payment confirmation
* Recovery handling

---

# 🤖 AI-Assisted Development

AI tools were used during development as an engineering productivity aid.

They were used for tasks such as:

* Exploring implementation approaches
* Reviewing Spring Boot structure
* Generating initial boilerplate
* Debugging build/runtime issues
* Reviewing concurrency scenarios
* Designing test scripts
* Improving documentation
* Reviewing edge cases

The final implementation decisions were reviewed and validated manually.

In particular, the concurrency model, database locking strategy, idempotency behavior, ownership checks, and test results were verified against the running service.

The deployed service was then tested using the included concurrency test suite.

---

# 🔮 Future Improvements

For a production-scale implementation, possible improvements include:

* JWT/OIDC authentication
* Time-boxed seat holds
* Payment integration
* Outbox/event-driven architecture
* Distributed tracing
* Grafana dashboards and alerting
* Database connection pool tuning
* Read replicas for read-heavy show queries
* Partitioning/sharding for very large workloads
* Rate limiting
* Load testing with significantly larger concurrency
* Kubernetes deployment
* Automated CI/CD
* Automated integration tests using Testcontainers

These are intentionally outside the scope of the current take-home implementation.

---

# 📌 Final Validation

The deployed service was tested using the complete test suite against:

```text
https://seat-reservation-service-gj8y.onrender.com
```

Final result:

```text
=============================================
 TEST SUITE SUMMARY
=============================================

Test                    Result
----                    ------
Authentication          PASS
Burst / No Double Sell  PASS
Per User Limit          PASS
Idempotency Concurrency PASS
Idempotency Conflict    PASS
Multi Seat Atomicity    PASS
Cancel Ownership        PASS

Passed: 7
Failed: 0
Total : 7

=============================================
 ALL TESTS PASSED
=============================================
```

---

# 📄 Additional Documentation

See [`WRITEUP.md`](WRITEUP.md) for detailed explanations of:

* Atomic reservation decisions
* Race-freedom
* Deterministic lock ordering
* Multi-seat atomicity
* Idempotency
* Authentication
* Cancellation
* Consistency and partition behavior
* Observability
* AI-assisted development
* Production considerations

---

## 👨‍💻 Submission

**Live Service:**
https://seat-reservation-service-gj8y.onrender.com

**Test Suite:**

```powershell
.\scripts\run-all-tests.ps1 `
    -BaseUrl "https://seat-reservation-service-gj8y.onrender.com"
```

**Validation:** 7/7 tests passed against the deployed service.

# Seat Reservation Service

A concurrency-safe seat reservation backend built with **Java 21, Spring Boot, PostgreSQL, Flyway, Spring Security, Docker, and Micrometer/Prometheus**.

The service is designed for high-contention on-sale scenarios where multiple users may attempt to reserve the same seat concurrently.

## Features

* Create shows with a configurable seat layout and price.
* Reserve one or multiple seats atomically.
* Prevent double-selling under concurrent requests.
* Enforce a per-user active-seat limit.
* Idempotent reservation requests.
* Detect same idempotency key used with a different request.
* Bearer-token authentication with user identity derived from the token.
* Reservation ownership validation during cancellation.
* PostgreSQL pessimistic row locking for concurrency control.
* Deterministic seat-lock ordering to reduce deadlock risk.
* Flyway database migrations.
* Liveness and database-backed readiness endpoints.
* Prometheus metrics.
* Correlation/request IDs in HTTP responses and logs.
* Docker and Docker Compose support.
* PowerShell concurrency and correctness test suite.

---

# Technology Stack

| Component           | Technology                  |
| ------------------- | --------------------------- |
| Language            | Java 21                     |
| Framework           | Spring Boot 4.1.1           |
| Database            | PostgreSQL 17               |
| Persistence         | Spring Data JPA / Hibernate |
| Database Migration  | Flyway                      |
| Security            | Spring Security             |
| Metrics             | Micrometer + Prometheus     |
| Build               | Maven                       |
| Containerization    | Docker                      |
| Local orchestration | Docker Compose              |

---

# Architecture

The service uses a layered architecture:

```text
HTTP Request
     |
     v
Controller
     |
     v
Reservation Service
     |
     +--------------------+
     |                    |
     v                    v
Repositories          Metrics
     |
     v
PostgreSQL
```

The reservation path uses database-level locking rather than JVM-only synchronization so correctness does not depend on a single application process.

For a reservation request:

```text
Client
  |
  | POST /shows/{id}/reserve
  | Authorization: Bearer <user-id>
  v
Authentication
  |
  v
ReservationService
  |
  +--> Lock user/show coordination row
  |
  +--> Check idempotency record
  |
  +--> Lock requested seats in sorted order
  |
  +--> Verify all seats are AVAILABLE
  |
  +--> Verify per-user limit
  |
  +--> Create reservation
  |
  +--> Mark seats CONFIRMED
  |
  +--> Update user's active seat count
  |
  +--> Store idempotency record
  |
  v
COMMIT
```

All reservation state changes occur within a database transaction.

---

# Running Locally

## Prerequisites

Install:

* Java 21
* Maven
* Docker Desktop
* PowerShell 5.1+ available

Verify:

```powershell
java -version
mvn -version
docker --version
docker compose version
```

---

# Option 1: Run with Docker Compose

Build the application:

```powershell
$env:JAVA_TOOL_OPTIONS="-Duser.timezone=UTC"
mvn clean package -DskipTests
```

Start the complete stack:

```powershell
docker compose up --build -d
```

Check containers:

```powershell
docker ps
```

The following containers should be running:

```text
seat-reservation-api
seat-reservation-postgres
```

The API is available at:

```text
http://localhost:8080
```

Stop the stack:

```powershell
docker compose down
```

---

# Option 2: Run the Application Locally

Start PostgreSQL:

```powershell
docker compose up -d postgres
```

Then start Spring Boot:

```powershell
mvn spring-boot:run
```

If your local environment has timezone configuration issues, use:

```powershell
$env:JAVA_TOOL_OPTIONS="-Duser.timezone=UTC"
mvn spring-boot:run
```

---

# Database

The application uses PostgreSQL.

Default local configuration:

```text
Database: seat_reservation
Username: postgres
Password: postgres
Host: localhost
Port: 5432
```

The application uses Flyway migrations and Hibernate validation.

Hibernate is configured with:

```text
ddl-auto: validate
```

Therefore, application startup does not automatically create or modify the database schema.

Flyway owns schema creation and migration.

---

# API

## Authentication

Protected endpoints require:

```http
Authorization: Bearer <user-id>
```

For this take-home implementation, the bearer token itself represents the user identity.

Example:

```http
Authorization: Bearer user-123
```

The reservation service obtains the user ID from the authenticated Spring Security principal.

The user ID is **not accepted from the reservation request body**.

> Production deployment should replace this simplified token mechanism with JWT/OIDC validation and signature verification.

---

# Create a Show

### Request

```http
POST /shows
Authorization: Bearer admin-user
Content-Type: application/json
```

Example:

```json
{
  "name": "Rock Concert",
  "seats": [
    "A1",
    "A2",
    "A3",
    "A4"
  ],
  "price_paise": 10000
}
```

### Response

```json
{
  "id": 1,
  "name": "Rock Concert",
  "price_paise": 10000,
  "per_user_limit": 4,
  "seats": [
    "A1",
    "A2",
    "A3",
    "A4"
  ]
}
```

Prices are represented as integer **paise** rather than floating-point values.

For example:

```text
₹100.00 = 10000 paise
```

---

# Get Show Details

### Request

```http
GET /shows/{showId}
```

Example:

```powershell
curl.exe http://localhost:8080/shows/1
```

### Response

```json
{
  "id": 1,
  "name": "Rock Concert",
  "price_paise": 10000,
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

This endpoint exposes both individual seat state and aggregate counts.

---

# Reserve Seats

### Request

```http
POST /shows/{showId}/reserve
Authorization: Bearer user-123
Content-Type: application/json
```

Example:

```json
{
  "seats": [
    "A1",
    "A2"
  ],
  "idempotency_key": "checkout-12345"
}
```

### Success

HTTP `201 Created`

```json
{
  "reservation_id": "6b7b7f3b-8e8f-4b4a-bf6f-8f9a4f0d9c20",
  "show_id": 1,
  "user_id": "user-123",
  "seats": [
    "A1",
    "A2"
  ],
  "amount_paise": 20000,
  "status": "confirmed"
}
```

---

# Cancellation

A reservation can be cancelled only by its owner.

### Request

```http
POST /reservations/{reservationId}/cancel
Authorization: Bearer user-123
```

Successful cancellation returns HTTP `200`.

An authenticated user attempting to cancel another user's reservation receives:

```text
403 Forbidden
```

Cancelling an already cancelled reservation is treated as an idempotent operation and returns the existing cancelled reservation.

---

# Reservation Semantics

## Multi-seat reservations

Multi-seat reservations use **all-or-nothing semantics**.

For example, if a request contains:

```json
{
  "seats": ["A1", "A2"]
}
```

and `A1` is unavailable, neither seat is reserved.

The service does not partially reserve `A2`.

---

# Concurrency Control

The service uses PostgreSQL pessimistic row locking.

Requested seats are normalized and sorted before acquiring locks.

For example:

```text
Request:
A3, A1, A2

Normalized:
A1, A2, A3
```

Database locks are acquired in ascending seat order.

This provides deterministic lock acquisition for multi-seat reservations and reduces deadlock risk.

The reservation transaction:

1. Creates the user/show coordination row if necessary.
2. Locks the user/show coordination row.
3. Checks the idempotency record.
4. Locks all requested seats.
5. Verifies that every requested seat exists.
6. Verifies that every requested seat is available.
7. Verifies the per-user limit.
8. Creates the reservation.
9. Marks seats as `CONFIRMED`.
10. Updates the user's active-seat count.
11. Stores the idempotency record.
12. Commits atomically.

Because the availability check occurs while the seat rows are locked, concurrent requests cannot both successfully reserve the same seat.

---

# Per-User Reservation Limit

Each show has a configurable per-user limit.

The default is:

```text
4 seats
```

The service maintains a `(show_id, user_id)` coordination record containing the user's active seat count.

The row is pessimistically locked before checking and updating the count.

This prevents concurrent requests from bypassing the limit through race conditions.

Example:

```text
10 concurrent requests
       |
       v
same user + same show
       |
       v
serialized user/show lock
       |
       v
maximum 4 confirmed seats
```

---

# Idempotency

Idempotency records are uniquely scoped by:

```text
(user_id, idempotency_key)
```

The request hash contains the relevant request identity, including:

```text
show_id
seat numbers
```

### Same request

If the same user retries the same request with the same idempotency key, the original reservation is returned.

### Different request

If the same user reuses an idempotency key with a different request, the service returns:

```text
409 IDEMPOTENCY_CONFLICT
```

This prevents an accidental or malicious key reuse from mapping two different requests to the same operation.

---

# Correctness Invariant

For every show:

```text
available + held + confirmed = total seats
```

Example:

```text
available = 3
held      = 0
confirmed = 1
total     = 4

3 + 0 + 1 = 4
```

The test suite verifies this invariant after concurrent operations.

---

# Health Endpoints

## Liveness

```http
GET /health/live
```

Returns HTTP `200` when the application process is alive.

Example:

```json
{
  "status": "UP",
  "type": "liveness"
}
```

Liveness does not depend on the database.

---

## Readiness

```http
GET /health/ready
```

The readiness endpoint executes a database connectivity check.

Healthy response:

```text
HTTP 200
```

Example:

```json
{
  "database": "UP",
  "status": "UP",
  "type": "readiness"
}
```

If PostgreSQL becomes unavailable, readiness returns:

```text
HTTP 503
```

This allows an orchestrator such as Kubernetes to stop routing traffic to an instance whose database dependency is unavailable.

---

# Prometheus Metrics

Prometheus metrics are exposed through:

```http
GET /actuator/prometheus
```

The service exposes metrics for:

* confirmed reservations
* declined requests due to seat contention
* declined requests due to per-user limit
* idempotency replay
* available seats

Example:

```text
available_seats{application="seat-reservation"} 72.0
```

The available-seat gauge represents the current number of available seats across shows.

---

# Correlation / Request ID

Every HTTP request receives an `X-Request-ID`.

If the client provides one:

```http
X-Request-ID: checkout-request-123
```

the service propagates the same value into the response.

If none is supplied, the application generates a UUID.

Example:

```http
X-Request-ID: 550e8400-e29b-41d4-a716-446655440000
```

The request ID is also included in the application logging context to make concurrent request troubleshooting easier.

---

# Automated Test Suite

The project contains PowerShell-based correctness and concurrency tests under:

```text
scripts/
```

Available tests:

```text
authentication-test.ps1
burst-test.ps1
per-user-limit-test.ps1
idempotency-concurrency-test.ps1
idempotency-conflict-test.ps1
multi-seat-atomicity-test.ps1
cancel-ownership-test.ps1
run-all-tests.ps1
```

## Run the complete suite

From PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\scripts\run-all-tests.ps1
```

The complete suite currently covers:

```text
Authentication
Burst / No Double Sell
Per User Limit
Idempotency Concurrency
Idempotency Conflict
Multi Seat Atomicity
Cancel Ownership
```

Expected result:

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

The tests are designed to run with **Windows PowerShell 5.1**, so they do not depend on `ForEach-Object -Parallel`.

---

# Test Scenarios

## No Double Sell

Multiple concurrent users attempt to reserve the same hot seat.

Expected:

```text
1 × 201 Created
N × 409 Conflict
0 × 5xx
```

The final seat state must be:

```text
CONFIRMED
```

exactly once.

---

## Per-User Limit

Multiple concurrent requests from the same user attempt to reserve seats.

With a default limit of 4:

```text
10 concurrent requests
        |
        v
4 successful reservations
6 declined requests
```

The final confirmed seat count for that user must not exceed 4.

---

## Idempotency Concurrency

Multiple concurrent requests use the same:

```text
user
show
seat set
idempotency key
```

All successful responses must refer to the same reservation.

No duplicate reservations are created.

---

## Idempotency Conflict

The same user sends:

```text
idempotency_key = X
seats = A1
```

followed by:

```text
idempotency_key = X
seats = A2
```

The second request returns:

```text
409 IDEMPOTENCY_CONFLICT
```

---

## Multi-seat Atomicity

Multiple users concurrently attempt to reserve the same pair of seats.

Only one request can reserve both seats.

The other requests receive a domain-level `409` response.

No partial reservation is created.

---

## Cancellation Ownership

The test verifies that:

1. The owner can cancel the reservation.
2. Another authenticated user cannot cancel it.
3. The cancelled seats become available again.
4. Repeating cancellation is safe.
5. The seat-count invariant remains valid.

---

# Error Handling

Domain failures are represented as HTTP `4xx` responses rather than server errors.

Examples:

| Condition                         | HTTP |
| --------------------------------- | ---: |
| Invalid request                   |  400 |
| Show not found                    |  404 |
| Reservation not found             |  404 |
| Seat already taken                |  409 |
| Per-user limit exceeded           |  409 |
| Idempotency conflict              |  409 |
| Reservation owned by another user |  403 |
| Authentication required           |  401 |

Unexpected application errors are returned as HTTP `500`.

The concurrency test suite specifically verifies that expected contention does not result in `5xx` responses.

---

# Project Structure

```text
seat-reservation-service/
│
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/seatreservation/
│   │   │       └── seat_reservation_service/
│   │   │           ├── config/
│   │   │           ├── controller/
│   │   │           ├── dto/
│   │   │           ├── entity/
│   │   │           ├── exception/
│   │   │           ├── repository/
│   │   │           └── service/
│   │   │
│   │   └── resources/
│   │       ├── db/migration/
│   │       └── application.yml
│   │
│   └── test/
│
├── scripts/
│   ├── authentication-test.ps1
│   ├── burst-test.ps1
│   ├── per-user-limit-test.ps1
│   ├── idempotency-concurrency-test.ps1
│   ├── idempotency-conflict-test.ps1
│   ├── multi-seat-atomicity-test.ps1
│   ├── cancel-ownership-test.ps1
│   └── run-all-tests.ps1
│
├── Dockerfile
├── docker-compose.yml
├── pom.xml
├── README.md
└── WRITEUP.md
```

---

# Docker Configuration

The Docker Compose stack contains:

```text
PostgreSQL
    |
    v
seat-reservation-api
    |
    v
port 8080
```

PostgreSQL uses a persistent Docker volume:

```text
postgres_data
```

The API waits for PostgreSQL's health check before starting.

---

# Configuration

The following environment variables can be overridden:

```text
SPRING_DATASOURCE_URL
SPRING_DATASOURCE_USERNAME
SPRING_DATASOURCE_PASSWORD
```

Example:

```powershell
$env:SPRING_DATASOURCE_URL="jdbc:postgresql://localhost:5432/seat_reservation"
$env:SPRING_DATASOURCE_USERNAME="postgres"
$env:SPRING_DATASOURCE_PASSWORD="postgres"
```

---

# Design Decisions

### Database-level concurrency

The service uses PostgreSQL row locks instead of JVM synchronization. This makes the correctness model suitable for multiple application instances.

### Deterministic lock ordering

Seat numbers are sorted before acquiring locks. This provides consistent lock ordering for multi-seat requests.

### Integer money

All monetary values are represented in paise using integer types. Floating-point money calculations are avoided.

### Explicit cancellation

The current implementation uses explicit cancellation rather than automatic expiry. The reservation model contains status and expiry fields so an expiry workflow can be added later.

### All-or-nothing multi-seat reservations

A request containing multiple seats either reserves all requested seats or none of them.

---

# Known Production Considerations

The take-home implementation intentionally keeps some production concerns simplified.

## Authentication

The current bearer-token implementation treats the token value as the user ID.

A production system should use:

* signed JWTs
* OIDC
* an API gateway or identity provider
* signature and issuer validation
* expiration validation

## Distributed deployment

The reservation correctness model relies on PostgreSQL as the source of truth. Application instances do not use local JVM locks for reservation correctness.

This allows multiple API instances to coordinate through database transactions and row locks.

## Expiry

Automatic hold expiration can be added using a scheduled worker or queue-based expiry process.

The expiry operation would need to acquire the same relevant database locks used by reservation/cancellation operations.

## Scalability

For very high traffic, additional components could be introduced:

* connection-pool tuning
* Redis for read-heavy caching
* Kafka for asynchronous events
* rate limiting
* partitioning/sharding strategies
* dedicated reservation workers
* database read replicas for non-authoritative reads

The authoritative seat state should continue to have a strongly consistent write path.

---

# AI-Assisted Development

AI tools were used during development to assist with:

* project scaffolding
* Spring Boot implementation
* concurrency design discussions
* debugging
* test-script development
* Docker configuration
* documentation

All generated code was reviewed, integrated, executed locally, and validated using the project's automated concurrency and correctness tests.

The final implementation was validated against the required reservation invariants and concurrent request scenarios.

---

# Current Validation

The complete correctness suite passes:

```text
7 / 7 tests passed
0 failed
0 unexpected 5xx responses in the tested concurrency scenarios
```

Validated scenarios include:

```text
Authentication
No double-sell
Per-user concurrency limit
Idempotency replay under concurrency
Idempotency key conflict
Multi-seat atomicity
Cancellation ownership
```

---

# Future Improvements

Potential next steps for a production deployment:

1. Replace simplified bearer authentication with JWT/OIDC validation.
2. Add automatic hold expiration.
3. Add distributed rate limiting.
4. Add OpenTelemetry tracing.
5. Add Grafana dashboards for reservation and contention metrics.
6. Add load testing with configurable concurrency and request rates.
7. Add deployment manifests for Kubernetes/EKS.
8. Add graceful shutdown and connection-draining configuration.
9. Tune PostgreSQL indexes and connection pools based on production load.
10. Add integration tests using Testcontainers PostgreSQL.

---

# License

This project was created as a backend engineering take-home exercise.

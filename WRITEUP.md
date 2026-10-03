# Seat Reservation at Scale — Engineering Write-up

## 1. Overview

This project implements a concurrency-safe seat reservation service for high-contention on-sale scenarios.

The primary goal was not only to provide the required REST APIs, but to ensure correctness when many users attempt to reserve the same seats concurrently.

The implementation focuses on:

* No double-selling of seats.
* Atomic multi-seat reservations.
* Per-user reservation limits under concurrency.
* Idempotent reservation requests.
* Correct ownership enforcement during cancellation.
* Database-backed health/readiness checks.
* Prometheus metrics and request correlation.
* Dockerized deployment.
* Automated concurrency and correctness validation.

The authoritative state is maintained in PostgreSQL.

---

# 2. Technology Choices

The service is implemented using:

* Java 21
* Spring Boot 4.1.1
* Spring Data JPA / Hibernate
* PostgreSQL 17
* Flyway
* Spring Security
* Micrometer + Prometheus
* Maven
* Docker / Docker Compose

PostgreSQL is used as the source of truth for reservation state because the correctness requirements depend on transactional consistency and row-level locking.

---

# 3. Reservation State Model

A seat can be in one of three states:

```text
AVAILABLE
HELD
CONFIRMED
```

Reservations have the following lifecycle states:

```text
HELD
CONFIRMED
CANCELLED
EXPIRED
```

The current implementation uses explicit cancellation and confirms reservations directly. The `HELD` and `EXPIRED` states are retained in the model to support a future payment/temporary-hold workflow.

The fundamental invariant is:

```text
available + held + confirmed = total seats
```

This invariant must remain true after every committed reservation or cancellation operation.

---

# 4. Atomic Reservation Decision

The most important correctness requirement is preventing two concurrent requests from reserving the same seat.

The reservation operation is executed inside a single database transaction.

The simplified flow is:

```text
BEGIN TRANSACTION

1. Validate request
2. Normalize and sort requested seats
3. Lock user/show coordination row
4. Check idempotency record
5. Check per-user limit
6. Lock requested seat rows
7. Verify all seats are AVAILABLE
8. Calculate reservation amount
9. Create reservation
10. Create reservation-seat records
11. Mark seats CONFIRMED
12. Increment user's active seat count
13. Store idempotency record

COMMIT
```

If any domain validation fails, the transaction is rolled back.

---

# 5. Race-Freedom / No Double-Sell

The application uses PostgreSQL pessimistic row locks.

Requested seats are locked using a query equivalent to:

```text
SELECT ...
FROM seats
WHERE show_id = ?
  AND seat_number IN (...)
ORDER BY seat_number ASC
FOR UPDATE
```

The important property is that the availability check happens **after the seat rows have been locked**.

Consider two users concurrently requesting `A1`:

```text
User A                     User B
------                     ------
Lock A1
Check A1 = AVAILABLE
Reserve A1
Mark A1 CONFIRMED
Commit
                           Wait for A1 lock
                           Acquire A1 lock
                           Check A1 = CONFIRMED
                           Return 409
```

Therefore both requests cannot observe `A1` as available and successfully reserve it.

This provides database-level correctness rather than relying on an in-memory Java lock.

That distinction is important because JVM synchronization would not provide the same correctness guarantee when multiple application instances are deployed.

---

# 6. Deterministic Lock Ordering

Multi-seat reservations introduce another concurrency concern: deadlocks.

For example:

```text
Request A: A1, A2
Request B: A2, A1
```

If locks were acquired in request order, the requests could potentially acquire:

```text
Request A -> A1
Request B -> A2
```

and then wait for each other's lock.

To reduce this risk, requested seat numbers are normalized and sorted before locking.

Example:

```text
Input:
A3, A1, A2

Normalized:
A1, A2, A3
```

The repository query also explicitly orders the rows by seat number.

Therefore concurrent multi-seat requests follow the same lock acquisition order.

---

# 7. Multi-seat Atomicity

Multi-seat reservations use an all-or-nothing model.

For a request:

```json
{
  "seats": ["A1", "A2"]
}
```

both seats must be available.

If either seat is unavailable:

```text
No reservation is created
No seat is confirmed
409 Conflict is returned
```

The application does not partially reserve the available subset.

This behavior is intentional and documented as part of the API semantics.

The complete operation occurs within one database transaction, so a failed request does not leave partially committed reservation state.

---

# 8. Per-user Limit Under Concurrency

Each show has a configurable per-user limit.

The default is:

```text
4 seats
```

A separate coordination table maintains:

```text
show_id
user_id
active_seat_count
```

There is a unique constraint on:

```text
(show_id, user_id)
```

Before checking or updating the user's active seat count, the service locks this coordination row.

Conceptually:

```text
User A request 1
       |
       v
Lock (Show X, User A)
       |
       v
Check active count
       |
       v
Reserve seats
       |
       v
Update count
       |
       v
Commit
       |
       v
Unlock
```

A concurrent request for the same user/show must wait for the lock.

This prevents the following race:

```text
Current count = 3
Limit = 4

Request A sees 3 -> allows 1
Request B sees 3 -> allows 1

Result would incorrectly become 5
```

With the coordination lock:

```text
Request A sees 3 -> reserves 1 -> count = 4
Request B sees 4 -> rejects
```

Thus the per-user limit remains enforced under concurrent traffic.

---

# 9. Idempotency

Reservation requests contain:

```text
idempotency_key
```

Idempotency records are uniquely scoped by:

```text
(user_id, idempotency_key)
```

The stored record contains a request hash and the resulting reservation.

The request hash includes the relevant request identity, including:

```text
show_id
seat numbers
```

## Same request

If the client retries:

```text
user = user-123
key  = checkout-001
seats = A1
```

the existing idempotency record is returned instead of creating another reservation.

This protects against clients retrying requests because of network timeouts or lost responses.

## Same key, different request

If the client first sends:

```text
key   = checkout-001
seats = A1
```

and later sends:

```text
key   = checkout-001
seats = A2
```

the request hash does not match.

The service returns:

```text
409 IDEMPOTENCY_CONFLICT
```

This prevents accidental reuse of an idempotency key for a different business operation.

---

# 10. Idempotency and Concurrency

Idempotency is tested concurrently.

Multiple requests use the same:

```text
user
show
seat set
idempotency key
```

The expected result is one logical reservation.

The test verifies that concurrent responses refer to the same reservation rather than creating multiple reservations.

This is important because checking idempotency only in application memory would not be safe across multiple application instances.

The database uniqueness constraint provides an additional persistence-level safeguard.

---

# 11. Identity and Authorization

The reservation endpoint does not accept `user_id` from the request body.

Instead:

```text
Authorization: Bearer <token>
```

is processed by Spring Security.

The authenticated principal is used by the controller:

```text
authentication.getName()
```

and passed to the reservation service.

Therefore a client cannot simply send:

```json
{
  "user_id": "another-user"
}
```

to reserve or cancel on behalf of another user.

The cancellation flow also verifies that the authenticated user owns the reservation.

An ownership violation returns:

```text
403 Forbidden
```

The take-home implementation uses the bearer token value as the user identity for simplicity.

For production, this should be replaced with proper JWT/OIDC validation, including signature, issuer, audience, and expiry validation.

---

# 12. Cancellation

Cancellation is transactional.

The service:

1. Loads the reservation.
2. Verifies the authenticated user owns it.
3. Locks the associated reservation-seat rows.
4. Changes the seats back to `AVAILABLE`.
5. Decrements the user's active-seat count.
6. Changes the reservation status to `CANCELLED`.
7. Commits the transaction.

This preserves the seat-count invariant.

Cancellation of an already cancelled reservation is treated as idempotent.

---

# 13. Money Representation

Prices are represented using integer paise.

For example:

```text
₹100.00 = 10000 paise
```

The service does not use floating-point arithmetic for monetary calculations.

The reservation amount is calculated using integer arithmetic.

`Math.multiplyExact` is used so that an integer overflow results in a controlled validation failure rather than silently producing an incorrect monetary value.

---

# 14. Database Schema and Migrations

Flyway manages database schema creation and migrations.

The main entities are:

```text
shows
seats
reservations
reservation_seats
idempotency_records
user_show_bookings
```

Important database constraints include:

```text
shows.name
    UNIQUE

seats(show_id, seat_number)
    UNIQUE

reservation_seats(reservation_id, seat_id)
    UNIQUE

idempotency_records(user_id, idempotency_key)
    UNIQUE

user_show_bookings(show_id, user_id)
    UNIQUE
```

These constraints provide database-level protection against duplicate logical records.

Hibernate is configured with:

```text
ddl-auto: validate
```

so Hibernate validates the schema rather than managing schema creation.

---

# 15. Health and Readiness

Two explicit health endpoints are provided.

## Liveness

```text
GET /health/live
```

Liveness indicates that the application process is running.

It does not depend on PostgreSQL.

## Readiness

```text
GET /health/ready
```

Readiness executes a database connectivity check.

When PostgreSQL is available:

```text
HTTP 200
```

When PostgreSQL is unavailable:

```text
HTTP 503
```

This distinction is important in a containerized or Kubernetes environment.

An application process can be alive while being unable to serve reservation traffic because its database dependency is unavailable.

Failing readiness in that situation allows the orchestrator/load balancer to stop routing traffic to the unhealthy instance.

---

# 16. Observability

The service exposes Prometheus metrics through:

```text
GET /actuator/prometheus
```

Metrics include:

```text
available_seats
reservations_confirmed_total
```

and reservation-decline outcome metrics/tags for:

```text
seat_taken
per_user_limit
idempotency_replay
```

The available-seat gauge is backed by the current database state.

These metrics provide visibility into:

* successful reservation volume
* contention
* user-limit rejections
* idempotent retries
* remaining inventory

---

# 17. Correlation IDs

Every request receives an `X-Request-ID`.

If a client supplies:

```text
X-Request-ID: checkout-123
```

the same ID is returned in the response.

If the client does not provide one, the service generates a UUID.

The ID is stored in the logging MDC and included in the console logging pattern.

This makes it possible to trace a particular request through application logs, which is especially useful during concurrent on-sale traffic.

---

# 18. Error Handling

Expected domain failures are represented as 4xx responses.

Examples:

```text
401 Unauthorized
    Authentication required

403 Forbidden
    Reservation belongs to another user

404 Not Found
    Show or reservation does not exist

409 Conflict
    Seat already taken

409 Conflict
    Per-user limit exceeded

409 Conflict
    Idempotency conflict

400 Bad Request
    Invalid request
```

Expected business contention does not result in a `500 Internal Server Error`.

A generic exception handler is also present for unexpected failures.

---

# 19. Concurrency Test Strategy

The project includes a PowerShell test suite designed to exercise the correctness properties directly.

The tests include:

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

The complete suite is executed sequentially by:

```powershell
.\scripts\run-all-tests.ps1
```

The scripts were implemented to remain compatible with Windows PowerShell 5.1.

---

# 20. Validation Results

The complete correctness suite currently passes:

```text
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
```

## No Double-Sell Test

The test sends concurrent requests for the same seat.

The expected behavior is:

```text
1 × HTTP 201
remaining requests × HTTP 409
0 × HTTP 5xx
```

The final state confirms that exactly one reservation owns the seat.

## Per-user Limit Test

Ten concurrent requests are generated for the same user.

With a limit of four seats:

```text
4 × HTTP 201
6 × HTTP 409
0 × HTTP 5xx
```

The final confirmed seat count remains four or below.

## Idempotency Concurrency Test

Twenty concurrent requests use the same idempotency key and request.

The requests resolve to one reservation.

## Multi-seat Atomicity Test

Ten concurrent users attempt to reserve the same pair of seats.

Exactly one request succeeds, and the two seats are confirmed together.

## Cancellation Ownership Test

The test verifies that:

```text
owner     -> can cancel
attacker  -> receives 403
owner     -> repeated cancellation remains safe
```

The final seat inventory is restored correctly.

---

# 21. Docker Deployment

The application is packaged as a Docker image.

The Docker Compose environment contains:

```text
+-------------------------+
| seat-reservation-api    |
| Spring Boot             |
| Port 8080               |
+------------+------------+
             |
             |
+------------v------------+
| PostgreSQL 17           |
| seat_reservation DB     |
| Port 5432               |
+-------------------------+
```

The API waits for PostgreSQL to pass its Docker health check before starting.

Database credentials and connection details are provided through environment variables in the Compose configuration.

The PostgreSQL data directory is backed by a named Docker volume for local persistence.

---

# 22. Partition / Consistency Trade-off

The authoritative reservation state is maintained in PostgreSQL.

The design intentionally prioritizes correctness of seat ownership over availability when the database is unavailable.

If PostgreSQL cannot be reached, the application should not attempt to make an independent reservation decision from stale or local state.

This avoids a dangerous scenario where two application instances independently believe the same seat is available.

The trade-off is:

```text
Database unavailable
        |
        v
Reservation writes unavailable
        |
        v
No unsafe seat allocation
```

For a seat-selling system, preserving authoritative inventory correctness is more important than accepting writes that cannot be durably coordinated.

---

# 23. Why Database Locks Instead of Redis Locks?

A distributed lock service such as Redis could be used for coordination, but PostgreSQL already owns the authoritative seat state.

Using database row locks means:

* lock and seat state are part of the same transactional system
* no separate lock-state consistency problem is introduced
* reservation commit and seat state update happen atomically
* correctness works across multiple API instances

Redis could still be useful for caching, rate limiting, or other non-authoritative workloads, but the database remains the source of truth for seat ownership.

---

# 24. Scaling Considerations

The implementation is designed so reservation correctness does not depend on a single JVM instance.

Multiple API instances can coordinate through PostgreSQL.

A production deployment would additionally require:

* database connection-pool tuning
* rate limiting
* request timeouts
* load balancing
* autoscaling
* PostgreSQL capacity planning
* monitoring and alerting
* distributed tracing
* graceful shutdown
* proper authentication infrastructure

For very large workloads, the read path could be separated from the strongly consistent reservation write path.

Caching could be introduced for read-heavy show/seat queries, but cached availability should never become the authoritative source for reservation decisions.

---

# 25. Hold and Expiry Model

The current implementation performs direct confirmation and supports explicit cancellation.

The data model includes:

```text
HELD
EXPIRED
expires_at
```

to make a temporary hold workflow possible.

A production checkout flow could be:

```text
AVAILABLE
    |
    | reserve
    v
HELD
    |
    +------ payment success ------> CONFIRMED
    |
    +------ timeout -------------> EXPIRED
```

An expiry worker would need to use the same locking strategy as reservation and cancellation so that an expiring hold cannot race incorrectly with another state transition.

---

# 26. AI-Assisted Development

AI tools were used during development for:

* Spring Boot project scaffolding
* implementation assistance
* concurrency design discussions
* debugging
* PowerShell test-script development
* Docker configuration
* README and engineering documentation

AI-generated suggestions were reviewed and integrated into the codebase rather than being treated as unverified output.

The resulting implementation was validated through actual local execution and concurrency tests.

The most important correctness properties were verified through automated tests rather than relying only on static reasoning.

---

# 27. Known Simplifications

This implementation intentionally simplifies several production concerns because the exercise focuses on reservation correctness and deployability.

### Authentication

The bearer token is treated as the user identity.

Production should use a real identity provider and JWT/OIDC validation.

### Payment

No external payment gateway is integrated.

The current reservation is confirmed directly.

### Expiry

Automatic hold expiry is not currently enabled.

The data model supports adding it.

### Distributed caching

Redis is not required for correctness and is therefore not part of the current critical reservation path.

### Kubernetes

The service is Dockerized and can be adapted to Kubernetes/EKS, but the current local deployment uses Docker Compose.

---

# 28. Future Improvements

Potential production improvements include:

1. JWT/OIDC authentication.
2. Automatic reservation expiry.
3. Payment integration with idempotent payment operations.
4. Distributed rate limiting.
5. OpenTelemetry tracing.
6. Grafana dashboards and alerts.
7. Kubernetes/EKS deployment manifests.
8. Horizontal pod autoscaling.
9. PostgreSQL performance tuning and connection-pool optimization.
10. Load testing at progressively higher concurrency.
11. Redis for selected read-heavy/cache workloads.
12. Kafka events for asynchronous downstream processing.
13. Graceful shutdown and connection draining.
14. More extensive failure-injection testing.

---

# 29. Final Engineering Summary

The central design decision is to make PostgreSQL the authoritative coordination point for reservation state.

The service combines:

```text
Database Transaction
        +
User/Show Pessimistic Lock
        +
Deterministic Seat Locking
        +
Availability Check Under Lock
        +
Per-user Counter
        +
Database-backed Idempotency
        +
Unique Constraints
```

This provides a clear correctness model for concurrent reservation requests.

The implementation was validated with concurrent test scenarios covering double-selling, per-user limits, idempotency, multi-seat atomicity, authentication, and cancellation ownership.

Current validation result:

```text
7 / 7 correctness tests passing
0 failed tests
```

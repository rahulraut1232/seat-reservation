package com.seatreservation.seat_reservation_service.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

@Configuration
public class SecurityConfig {

    private final BearerTokenAuthenticationFilter bearerTokenAuthenticationFilter;

    public SecurityConfig(
            BearerTokenAuthenticationFilter bearerTokenAuthenticationFilter) {
        this.bearerTokenAuthenticationFilter = bearerTokenAuthenticationFilter;
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http)
            throws Exception {

        http
                .csrf(csrf -> csrf.disable())

                .sessionManagement(session ->
                        session.sessionCreationPolicy(SessionCreationPolicy.STATELESS)
                )

                .authorizeHttpRequests(auth -> auth

                        // Health endpoints
                        .requestMatchers(
                                "/health/live",
                                "/health/ready",
                                "/actuator/health/**",
                                "/actuator/prometheus"
                        ).permitAll()

                        // Public show browsing
                        .requestMatchers(HttpMethod.GET, "/shows").permitAll()
                        .requestMatchers(HttpMethod.GET, "/shows/**").permitAll()

                        // Show creation requires authentication
                        .requestMatchers(HttpMethod.POST, "/shows").authenticated()

                        // Reservation and cancellation require authentication
                        .requestMatchers(
                                HttpMethod.POST,
                                "/shows/*/reserve",
                                "/reservations/*/cancel"
                        ).authenticated()

                        // Everything else requires authentication
                        .anyRequest().authenticated()
                )

                .httpBasic(basic -> basic.disable())
                .formLogin(form -> form.disable())

                .addFilterBefore(
                        bearerTokenAuthenticationFilter,
                        UsernamePasswordAuthenticationFilter.class
                );

        return http.build();
    }
}
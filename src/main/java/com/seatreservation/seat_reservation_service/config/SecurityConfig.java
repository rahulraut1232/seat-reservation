package com.seatreservation.seat_reservation_service.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import jakarta.servlet.http.HttpServletResponse;

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
                        session.sessionCreationPolicy(
                                SessionCreationPolicy.STATELESS
                        )
                )

                .exceptionHandling(exception ->
                        exception.authenticationEntryPoint(
                                (request, response, authException) -> {
                                    response.setStatus(
                                            HttpServletResponse.SC_UNAUTHORIZED
                                    );
                                    response.setContentType("application/json");
                                    response.getWriter().write(
                                            "{\"status\":401,\"error\":\"UNAUTHORIZED\",\"message\":\"Authentication required\"}"
                                    );
                                }
                        )
                )

                .authorizeHttpRequests(auth -> auth

                        .requestMatchers(
                                "/health/live",
                                "/health/ready",
                                "/actuator/health/**",
                                "/actuator/prometheus"
                        ).permitAll()

                        .requestMatchers(HttpMethod.GET, "/shows").permitAll()
                        .requestMatchers(HttpMethod.GET, "/shows/**").permitAll()

                        .requestMatchers(
                                HttpMethod.POST,
                                "/shows"
                        ).authenticated()

                        .requestMatchers(
                                HttpMethod.POST,
                                "/shows/*/reserve",
                                "/reservations/*/cancel"
                        ).authenticated()

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
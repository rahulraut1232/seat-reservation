package com.seatreservation.seat_reservation_service.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

@Configuration
public class SecurityConfig {

    private final BearerTokenAuthenticationFilter bearerTokenFilter;

    public SecurityConfig(
            BearerTokenAuthenticationFilter bearerTokenFilter) {
        this.bearerTokenFilter = bearerTokenFilter;
    }

    @Bean
    public SecurityFilterChain securityFilterChain(
            HttpSecurity http) throws Exception {

        http
                .csrf(csrf -> csrf.disable())

                .sessionManagement(session ->
                        session.sessionCreationPolicy(
                                SessionCreationPolicy.STATELESS))

                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(
                                        "/health/live",
                                        "/health/ready",
                                        "/actuator/health/**",
                                        "/actuator/prometheus")
                        .permitAll()

                        .requestMatchers(
                                "/shows",
                                "/shows/**"
                        ).permitAll()

                        .anyRequest().authenticated()
                )

                .addFilterBefore(
                        bearerTokenFilter,
                        UsernamePasswordAuthenticationFilter.class
                )

                .httpBasic(httpBasic -> httpBasic.disable())

                .formLogin(form -> form.disable());

        return http.build();
    }
}

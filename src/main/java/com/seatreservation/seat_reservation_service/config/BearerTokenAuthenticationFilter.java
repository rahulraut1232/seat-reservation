package com.seatreservation.seat_reservation_service.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

@Component
public class BearerTokenAuthenticationFilter extends OncePerRequestFilter {

    private static final String BEARER_PREFIX = "Bearer ";

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain)
            throws ServletException, IOException {

        String authorization =
                request.getHeader("Authorization");

        if (authorization != null
                && authorization.startsWith(BEARER_PREFIX)) {

            String token =
                    authorization.substring(BEARER_PREFIX.length()).trim();

            if (!token.isBlank()) {

                String userId = validateAndExtractUserId(token);

                if (userId != null) {

                    UsernamePasswordAuthenticationToken authentication =
                            new UsernamePasswordAuthenticationToken(
                                    userId,
                                    null,
                                    List.of(
                                            new SimpleGrantedAuthority(
                                                    "ROLE_USER"
                                            )
                                    )
                            );

                    SecurityContextHolder
                            .getContext()
                            .setAuthentication(authentication);
                }
            }
        }

        filterChain.doFilter(request, response);
    }

    private String validateAndExtractUserId(String token) {

        /*
         * Take-home authentication model:
         *
         * Bearer user-123
         *
         * In production this method would validate a JWT
         * signature and extract the subject ("sub").
         */

        if (token.length() > 100) {
            return null;
        }

        if (!token.matches("[a-zA-Z0-9_-]+")) {
            return null;
        }

        return token;
    }
}

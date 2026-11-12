package br.edu.turismo;

import java.time.LocalDate;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

/** Dados recebidos para criar uma reserva (validados antes de chegar ao banco). */
public record ReservaRequest(
        @NotBlank @Size(max = 15) String idTurista,
        @NotNull @Positive Integer idHospedagem,
        @NotBlank @Size(max = 10) String numeroQuarto,
        @NotNull LocalDate dataCheckin,
        @NotNull LocalDate dataCheckout) {
}

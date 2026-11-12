package br.edu.turismo;

import java.sql.Connection;
import java.sql.Date;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.Map;
import java.util.regex.Pattern;

import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import jakarta.validation.Valid;

/**
 * Escrita: a aplicacao NAO faz INSERT/UPDATE direto nas tabelas.
 * Ela so chama as procedures (transacao + regras no banco), que sao o unico
 * privilegio de escrita da conta app_operador.
 */
@RestController
@RequestMapping("/api/reservas")
public class ReservaController {

    private static final Pattern FORMATO_ID = Pattern.compile("^[A-Z]{3}-[0-9]{4}-[0-9]{6}$");

    private final JdbcTemplate jdbc;

    public ReservaController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Map<String, String> criar(@Valid @RequestBody ReservaRequest req) {
        if (!req.dataCheckout().isAfter(req.dataCheckin())) {
            throw new RequisicaoInvalidaException("O check-out deve ser depois do check-in.");
        }

        // Mesma conexao para o CALL e para ler o parametro OUT (@id_novo).
        String idReserva = jdbc.execute((Connection con) -> {
            try (PreparedStatement ps = con.prepareStatement(
                    "CALL sp_criar_reserva(?, ?, ?, ?, ?, @id_novo)")) {
                ps.setString(1, req.idTurista());
                ps.setInt(2, req.idHospedagem());
                ps.setString(3, req.numeroQuarto());
                ps.setDate(4, Date.valueOf(req.dataCheckin()));
                ps.setDate(5, Date.valueOf(req.dataCheckout()));
                ps.executeUpdate();
            }
            try (Statement st = con.createStatement();
                 ResultSet rs = st.executeQuery("SELECT @id_novo")) {
                rs.next();
                return rs.getString(1);
            }
        });

        return Map.of("idReserva", idReserva);
    }

    @PostMapping("/{id}/cancelar")
    public Map<String, String> cancelar(@PathVariable String id) {
        if (!FORMATO_ID.matcher(id).matches()) {
            throw new RequisicaoInvalidaException("Codigo de reserva invalido.");
        }
        jdbc.update("CALL sp_cancelar_reserva(?)", id);
        return Map.of("idReserva", id, "status", "CANCELADA");
    }
}

package br.edu.turismo;

import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Consultas (somente leitura).
 * Todas usam SQL fixo (sem concatenar entrada do usuario), executado pela
 * conta app_operador, que so enxerga as views e tabelas autorizadas.
 */
@RestController
@RequestMapping("/api")
public class ConsultaController {

    private final JdbcTemplate jdbc;

    public ConsultaController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** Evidencia para a apresentacao: com qual conta o banco enxerga a aplicacao. */
    @GetMapping("/conexao")
    public Map<String, Object> conexao() {
        return jdbc.queryForMap(
            "SELECT CURRENT_USER() AS conta_efetiva, DATABASE() AS banco");
    }

    /** VIEW: reservas ja com turista, hospedagem e quarto. */
    @GetMapping("/reservas")
    public List<Map<String, Object>> reservas() {
        return jdbc.queryForList(
            "SELECT id_reserva, turista, hospedagem, numero_quarto, tipo_quarto, "
          + "data_checkin, data_checkout, noites, valor_total, status_reserva "
          + "FROM vw_reservas_detalhadas ORDER BY data_checkin DESC");
    }

    /** VIEW: relatorio de faturamento por hospedagem. */
    @GetMapping("/faturamento")
    public List<Map<String, Object>> faturamento() {
        return jdbc.queryForList(
            "SELECT nome_fantasia, total_reservas, faturamento "
          + "FROM vw_faturamento_hospedagem ORDER BY nome_fantasia");
    }

    /** ENTIDADE (tabela): hospedagens. */
    @GetMapping("/hospedagens")
    public List<Map<String, Object>> hospedagens() {
        return jdbc.queryForList(
            "SELECT id_hospedagem, nome_fantasia, estrelas "
          + "FROM hospedagens ORDER BY nome_fantasia");
    }

    /** Quartos disponiveis para escolha no formulario de reserva. */
    @GetMapping("/quartos")
    public List<Map<String, Object>> quartos() {
        return jdbc.queryForList(
            "SELECT q.id_hospedagem, h.nome_fantasia, q.numero_quarto, "
          + "q.tipo_quarto, q.diaria_base "
          + "FROM quartos q JOIN hospedagens h ON h.id_hospedagem = q.id_hospedagem "
          + "ORDER BY h.nome_fantasia, q.numero_quarto");
    }

    /** Turistas (via view: a aplicacao nunca le a tabela usuarios nem senha_hash). */
    @GetMapping("/turistas")
    public List<Map<String, Object>> turistas() {
        return jdbc.queryForList(
            "SELECT id_usuario, nome, email FROM vw_usuarios_resumo "
          + "WHERE tipo_usuario = 'TURISTA' AND ativo = 1 ORDER BY nome");
    }
}

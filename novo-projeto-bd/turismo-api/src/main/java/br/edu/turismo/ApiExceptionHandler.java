package br.edu.turismo;

import java.sql.SQLException;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Traduz erros em respostas JSON simples.
 * - Regras do banco (SIGNAL 45000 das triggers/procedures): mensagem propria, controlada por nos.
 * - Qualquer outro erro: mensagem generica (detalhes so no log do servidor).
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    private static final Logger LOG = LoggerFactory.getLogger(ApiExceptionHandler.class);

    private ResponseEntity<Map<String, String>> resposta(HttpStatus status, String mensagem) {
        return ResponseEntity.status(status).body(Map.of("mensagem", mensagem));
    }

    @ExceptionHandler(RequisicaoInvalidaException.class)
    public ResponseEntity<Map<String, String>> requisicaoInvalida(RequisicaoInvalidaException ex) {
        return resposta(HttpStatus.BAD_REQUEST, ex.getMessage());
    }

    @ExceptionHandler({MethodArgumentNotValidException.class, HttpMessageNotReadableException.class})
    public ResponseEntity<Map<String, String>> entradaInvalida(Exception ex) {
        return resposta(HttpStatus.BAD_REQUEST, "Dados invalidos. Confira todos os campos.");
    }

    @ExceptionHandler(DataAccessException.class)
    public ResponseEntity<Map<String, String>> erroDeBanco(DataAccessException ex) {
        SQLException sql = procurarSql(ex);
        if (sql != null && "45000".equals(sql.getSQLState())) {
            // Regra de negocio do banco (ex.: quarto indisponivel, reserva ja cancelada)
            return resposta(HttpStatus.CONFLICT, sql.getMessage());
        }
        if (ex instanceof DataIntegrityViolationException) {
            return resposta(HttpStatus.BAD_REQUEST, "Turista ou quarto inexistente.");
        }
        LOG.error("Erro inesperado de banco de dados", ex);
        return resposta(HttpStatus.INTERNAL_SERVER_ERROR, "Erro interno ao processar a operacao.");
    }

    private SQLException procurarSql(Throwable erro) {
        for (Throwable t = erro; t != null; t = t.getCause()) {
            if (t instanceof SQLException s) {
                return s;
            }
        }
        return null;
    }
}

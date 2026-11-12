package br.edu.turismo;

/** Erro de entrada detectado pela aplicacao (resposta 400 com mensagem controlada). */
public class RequisicaoInvalidaException extends RuntimeException {
    public RequisicaoInvalidaException(String mensagem) {
        super(mensagem);
    }
}

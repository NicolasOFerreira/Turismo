-- =====================================================================
-- DEMONSTRAÇÃO (cole UM BLOCO por vez; não use "source")
-- Conecte-se como app_admin, nunca root:   mysql -u app_admin -p db_turismo
-- Linhas "ERRO ESPERADO" falham de propósito.
-- =====================================================================

SET @turista = (SELECT id_usuario FROM usuarios WHERE email = 'lucas@gmail.com');
SET @guia    = (SELECT id_usuario FROM usuarios WHERE email = 'camila.guia@gmail.com');
SELECT USER() AS conectado_como, CURRENT_USER() AS conta_efetiva;


-- 1. TRANSAÇÕES (COMMIT / ROLLBACK) ----------------------------------

-- 1.1 COMMIT: reserva criada com sucesso (3 noites x 280 = 840.00)
CALL sp_criar_reserva(@turista, 1, '101', '2026-12-20', '2026-12-23', @id_reserva);
SELECT @id_reserva AS id_gerado;
SELECT id_reserva, hospedagem, noites, valor_total, status_reserva
  FROM vw_reservas_detalhadas WHERE id_reserva = @id_reserva;
SELECT * FROM sequencias WHERE prefixo = 'RES';              -- ultimo_valor = 3

-- 1.2 ROLLBACK automático: mesmo quarto, período sobreposto
CALL sp_criar_reserva(@turista, 1, '101', '2026-12-21', '2026-12-22', @id_falha);
-- ERRO ESPERADO: Quarto indisponivel no periodo informado.
SELECT * FROM sequencias WHERE prefixo = 'RES';              -- continua 3 (ID desfeito)

-- 1.3 ROLLBACK manual
START TRANSACTION;
UPDATE reservas_hospedagem SET status_reserva = 'CANCELADA' WHERE id_reserva = @id_reserva;
SELECT id_reserva, status_reserva FROM reservas_hospedagem WHERE id_reserva = @id_reserva;  -- CANCELADA
ROLLBACK;
SELECT id_reserva, status_reserva FROM reservas_hospedagem WHERE id_reserva = @id_reserva;  -- CONFIRMADA


-- 2. TRIGGERS --------------------------------------------------------

-- 2.1 Conflito de datas barrado no banco, mesmo sem usar a procedure
INSERT INTO reservas_hospedagem
    (id_reserva, id_turista, id_hospedagem, numero_quarto, data_checkin, data_checkout, status_reserva)
VALUES ('TESTE-0000-0001', @turista, 2, '05', '2026-12-03', '2026-12-06', 'CONFIRMADA');
-- ERRO ESPERADO: Quarto indisponivel no periodo informado.

-- 2.2 Guia não pode ter dois passeios no mesmo horário
INSERT INTO passeios_guiados (id_passeio, id_turista, id_guia, id_ponto, data_hora, valor_contratado)
VALUES ('TESTE-0000-0003', @turista, @guia, 2, '2026-12-02 14:00:00', 100.00);
-- ERRO ESPERADO: O guia ja possui passeio agendado neste horario.

-- 2.3 Auditoria: cancelamento registrado com a conta do banco
CALL sp_cancelar_reserva(@id_reserva);
SELECT id_reserva, status_anterior, status_novo, usuario_db, data_hora
  FROM log_reservas ORDER BY id_log DESC LIMIT 3;


-- 3. FUNCTIONS -------------------------------------------------------
SELECT fn_valor_estadia(1, '201', '2026-12-10', '2026-12-13') AS valor_3_noites;   -- 1350.00
SELECT fn_proximo_id('PAS') AS exemplo_de_id;   -- consome um número; só para mostrar o formato


-- 4. VIEWS -----------------------------------------------------------
SELECT * FROM vw_reservas_detalhadas;
SELECT * FROM vw_faturamento_hospedagem;
SELECT * FROM vw_usuarios_resumo;    -- sem a coluna senha_hash


-- 5. ÍNDICES (30 mil reservas de teste; pode levar alguns segundos) ----
SET SESSION cte_max_recursion_depth = 30000;
INSERT INTO reservas_hospedagem
    (id_reserva, id_turista, id_hospedagem, numero_quarto, data_checkin, data_checkout, status_reserva)
WITH RECURSIVE n (i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 30000)
SELECT CONCAT('TST-0000-', LPAD(i, 6, '0')), @turista, 1, '101',
       DATE_ADD('2024-01-01', INTERVAL (i MOD 900) DAY),
       DATE_ADD('2024-01-01', INTERVAL (i MOD 900) + 3 DAY),
       'CONCLUIDA'
  FROM n;
ANALYZE TABLE reservas_hospedagem;
SELECT COUNT(*) AS total_reservas FROM reservas_hospedagem;

-- 5.1 COM índice
EXPLAIN SELECT id_reserva, data_checkin, valor_total FROM reservas_hospedagem
 WHERE status_reserva = 'CONFIRMADA' AND data_checkin BETWEEN '2026-12-01' AND '2026-12-31'\G
-- OBSERVAR: type = range | key = idx_reservas_status_checkin | rows pequeno

-- 5.2 SEM o índice (invisível = o otimizador o ignora, sem apagar)
ALTER TABLE reservas_hospedagem ALTER INDEX idx_reservas_status_checkin INVISIBLE;
EXPLAIN SELECT id_reserva, data_checkin, valor_total FROM reservas_hospedagem
 WHERE status_reserva = 'CONFIRMADA' AND data_checkin BETWEEN '2026-12-01' AND '2026-12-31'\G
-- OBSERVAR: type = ALL | key = NULL | rows ~ 30 mil (lê a tabela inteira)
ALTER TABLE reservas_hospedagem ALTER INDEX idx_reservas_status_checkin VISIBLE;   -- não esqueça!


-- 6. CONTROLE DE ACESSO (abra OUTRO terminal: mysql -u app_operador -p db_turismo)
-- SELECT USER(), CURRENT_USER();                    -- app_operador@localhost (não é root)
-- SHOW GRANTS;
-- SELECT * FROM vw_reservas_detalhadas LIMIT 3;     -- OK
-- SELECT * FROM usuarios;                           -- ERRO 1142: SELECT command denied
-- DELETE FROM reservas_hospedagem;                  -- ERRO 1142: DELETE command denied
-- DROP TABLE hospedagens;                           -- ERRO 1142: DROP command denied
-- SET @t = (SELECT id_usuario FROM vw_usuarios_resumo WHERE email = 'lucas@gmail.com');
-- CALL sp_criar_reserva(@t, 2, '05', '2027-03-01', '2027-03-03', @x);   -- OK: escrita só via procedure
-- Conta de relatórios: mysql -u app_leitura -p db_turismo
-- SELECT * FROM vw_faturamento_hospedagem;          -- OK
-- CALL sp_criar_reserva(@t, 2, '05', '2027-04-01', '2027-04-03', @x);   -- ERRO 1370: EXECUTE denied


-- 7. LIMPEZA (rode antes de abrir a aplicação) -----------------------
DELETE FROM reservas_hospedagem WHERE id_reserva LIKE 'TST-%';
DELETE FROM reservas_hospedagem WHERE id_reserva = @id_reserva;
DELETE FROM reservas_hospedagem WHERE data_checkin = '2027-03-01';   -- reserva criada pelo app_operador
SELECT COUNT(*) AS reservas_restantes FROM reservas_hospedagem;      -- 2

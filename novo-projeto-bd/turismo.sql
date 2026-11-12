-- =====================================================================
-- SISTEMA DE TURISMO (N2) - SCRIPT ÚNICO - MySQL 8.0
-- Recria o banco db_turismo do zero (apaga o anterior).
--
-- COMO RODAR (uma única vez, como root; depois disso só contas app_*):
--   mysql> source C:/Users/Nicolas/Desktop/novo-projeto-bd/turismo.sql
-- =====================================================================

-- Necessário para criar functions com o log binário ativo (erro 1418)
SET GLOBAL log_bin_trust_function_creators = 1;

DROP DATABASE IF EXISTS db_turismo;
CREATE DATABASE db_turismo CHARACTER SET utf8mb4;
USE db_turismo;


-- =====================================================================
-- 1. TABELAS
-- =====================================================================

-- Grupos de usuários (base das permissões). AUTO_INCREMENT: tabela de
-- domínio pequena, sem criticidade de negócio.
CREATE TABLE grupos_usuarios (
    id_grupo  INT AUTO_INCREMENT PRIMARY KEY,
    nome      VARCHAR(30)  NOT NULL UNIQUE,
    descricao VARCHAR(150) NOT NULL
) ENGINE=InnoDB;

-- Usuários. O ID NÃO é AUTO_INCREMENT: vem de fn_proximo_id('USR').
CREATE TABLE usuarios (
    id_usuario    CHAR(15)     PRIMARY KEY,
    id_grupo      INT          NOT NULL,
    nome          VARCHAR(100) NOT NULL,
    email         VARCHAR(100) NOT NULL UNIQUE,
    senha_hash    VARCHAR(100) NULL,
    tipo_usuario  ENUM('TURISTA', 'GUIA', 'FUNCIONARIO') NOT NULL,
    ativo         TINYINT(1)   NOT NULL DEFAULT 1,
    data_cadastro DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (id_grupo) REFERENCES grupos_usuarios(id_grupo)
) ENGINE=InnoDB;

-- Especializações de usuarios
CREATE TABLE turistas (
    id_usuario CHAR(15) PRIMARY KEY,
    cpf        CHAR(11) UNIQUE,
    FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
) ENGINE=InnoDB;

CREATE TABLE guias (
    id_usuario CHAR(15)    PRIMARY KEY,
    cadastur   VARCHAR(20) NOT NULL UNIQUE,
    FOREIGN KEY (id_usuario) REFERENCES usuarios(id_usuario)
) ENGINE=InnoDB;

-- Dados de referência (AUTO_INCREMENT justificado: cadastro de baixo volume)
CREATE TABLE hospedagens (
    id_hospedagem INT AUTO_INCREMENT PRIMARY KEY,
    nome_fantasia VARCHAR(100) NOT NULL,
    cnpj          CHAR(14)     NOT NULL UNIQUE,
    estrelas      INT          NOT NULL DEFAULT 3,
    CHECK (estrelas BETWEEN 1 AND 5)
) ENGINE=InnoDB;

-- Chave composta: o número do quarto só é único dentro da hospedagem
CREATE TABLE quartos (
    id_hospedagem INT           NOT NULL,
    numero_quarto VARCHAR(10)   NOT NULL,
    tipo_quarto   VARCHAR(40)   NOT NULL,
    diaria_base   DECIMAL(10,2) NOT NULL CHECK (diaria_base > 0),
    PRIMARY KEY (id_hospedagem, numero_quarto),
    FOREIGN KEY (id_hospedagem) REFERENCES hospedagens(id_hospedagem)
) ENGINE=InnoDB;

-- Dado crítico: ID gerado por fn_proximo_id('RES'). valor_total é
-- calculado pelo trigger trg_reservas_bi.
CREATE TABLE reservas_hospedagem (
    id_reserva     CHAR(15)      PRIMARY KEY,
    id_turista     CHAR(15)      NOT NULL,
    id_hospedagem  INT           NOT NULL,
    numero_quarto  VARCHAR(10)   NOT NULL,
    data_checkin   DATE          NOT NULL,
    data_checkout  DATE          NOT NULL,
    valor_total    DECIMAL(10,2) NOT NULL DEFAULT 0,
    status_reserva ENUM('PENDENTE', 'CONFIRMADA', 'CANCELADA', 'CONCLUIDA')
                   NOT NULL DEFAULT 'PENDENTE',
    FOREIGN KEY (id_turista) REFERENCES turistas(id_usuario),
    FOREIGN KEY (id_hospedagem, numero_quarto)
        REFERENCES quartos(id_hospedagem, numero_quarto),
    CHECK (data_checkout > data_checkin)
) ENGINE=InnoDB;

CREATE TABLE pontos_turisticos (
    id_ponto INT AUTO_INCREMENT PRIMARY KEY,
    nome     VARCHAR(100) NOT NULL,
    cidade   VARCHAR(60)  NOT NULL
) ENGINE=InnoDB;

-- Dado crítico: ID gerado por fn_proximo_id('PAS')
CREATE TABLE passeios_guiados (
    id_passeio       CHAR(15)      PRIMARY KEY,
    id_turista       CHAR(15)      NOT NULL,
    id_guia          CHAR(15)      NOT NULL,
    id_ponto         INT           NOT NULL,
    data_hora        DATETIME      NOT NULL,
    valor_contratado DECIMAL(10,2) NOT NULL CHECK (valor_contratado >= 0),
    status_passeio   ENUM('AGENDADO', 'REALIZADO', 'CANCELADO')
                     NOT NULL DEFAULT 'AGENDADO',
    FOREIGN KEY (id_turista) REFERENCES turistas(id_usuario),
    FOREIGN KEY (id_guia)    REFERENCES guias(id_usuario),
    FOREIGN KEY (id_ponto)   REFERENCES pontos_turisticos(id_ponto)
) ENGINE=InnoDB;

-- Base da geração de IDs: guarda o último número usado por prefixo/ano
CREATE TABLE sequencias (
    prefixo      CHAR(3)           NOT NULL,
    ano          SMALLINT UNSIGNED NOT NULL,
    ultimo_valor INT UNSIGNED      NOT NULL,
    PRIMARY KEY (prefixo, ano)
) ENGINE=InnoDB;

-- Auditoria de mudanças de status. AUTO_INCREMENT justificado: tabela de
-- log, o ID só ordena os eventos.
CREATE TABLE log_reservas (
    id_log          INT AUTO_INCREMENT PRIMARY KEY,
    id_reserva      CHAR(15)     NOT NULL,
    status_anterior VARCHAR(20)  NOT NULL,
    status_novo     VARCHAR(20)  NOT NULL,
    usuario_db      VARCHAR(100) NOT NULL,
    data_hora       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;


-- =====================================================================
-- 2. ÍNDICES (FKs, PKs e UNIQUEs já têm índice automático)
-- =====================================================================

-- Busca de conflito de datas no mesmo quarto (usada pelo trigger de reserva)
CREATE INDEX idx_reservas_quarto_periodo
    ON reservas_hospedagem (id_hospedagem, numero_quarto, data_checkin, data_checkout);

-- Listagens e relatórios por status e período
CREATE INDEX idx_reservas_status_checkin
    ON reservas_hospedagem (status_reserva, data_checkin);

-- Agenda do guia e conflito de horário (trigger de passeio)
CREATE INDEX idx_passeios_guia_data
    ON passeios_guiados (id_guia, data_hora);


DELIMITER $$

-- =====================================================================
-- 3. FUNCTIONS
-- =====================================================================

-- Gera IDs no formato PREFIXO-ANO-SEQUENCIAL (ex.: RES-2026-000001).
-- A instrução INSERT ... ON DUPLICATE KEY é atômica e trava a linha da
-- sequência até o fim da transação: dois acessos nunca recebem o mesmo ID.
CREATE FUNCTION fn_proximo_id(p_prefixo CHAR(3))
RETURNS CHAR(15)
MODIFIES SQL DATA
BEGIN
    DECLARE v_prefixo CHAR(3) DEFAULT UPPER(p_prefixo);
    DECLARE v_ano SMALLINT UNSIGNED DEFAULT YEAR(CURDATE());

    IF v_prefixo NOT IN ('USR', 'RES', 'PAS') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prefixo de ID invalido.';
    END IF;

    INSERT INTO sequencias (prefixo, ano, ultimo_valor)
    VALUES (v_prefixo, v_ano, LAST_INSERT_ID(1))
    ON DUPLICATE KEY UPDATE ultimo_valor = LAST_INSERT_ID(ultimo_valor + 1);

    RETURN CONCAT(v_prefixo, '-', v_ano, '-', LPAD(LAST_INSERT_ID(), 6, '0'));
END$$

-- Valor da estadia = diária do quarto x número de noites
CREATE FUNCTION fn_valor_estadia(
    p_id_hospedagem INT, p_numero_quarto VARCHAR(10),
    p_checkin DATE, p_checkout DATE)
RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_diaria DECIMAL(10,2);

    SELECT diaria_base INTO v_diaria FROM quartos
     WHERE id_hospedagem = p_id_hospedagem AND numero_quarto = p_numero_quarto;

    IF v_diaria IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quarto nao encontrado.';
    END IF;

    RETURN v_diaria * DATEDIFF(p_checkout, p_checkin);
END$$


-- =====================================================================
-- 4. TRIGGERS
-- =====================================================================

-- Nova reserva: bloqueia sobreposição de datas e calcula o valor total.
-- A regra fica no banco, então vale para qualquer sistema que insira.
CREATE TRIGGER trg_reservas_bi
BEFORE INSERT ON reservas_hospedagem
FOR EACH ROW
BEGIN
    IF NEW.status_reserva IN ('PENDENTE', 'CONFIRMADA') AND EXISTS (
        SELECT 1 FROM reservas_hospedagem
         WHERE id_hospedagem = NEW.id_hospedagem
           AND numero_quarto = NEW.numero_quarto
           AND status_reserva IN ('PENDENTE', 'CONFIRMADA')
           AND data_checkin  < NEW.data_checkout
           AND data_checkout > NEW.data_checkin) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Quarto indisponivel no periodo informado.';
    END IF;

    SET NEW.valor_total = fn_valor_estadia(NEW.id_hospedagem, NEW.numero_quarto,
                                           NEW.data_checkin, NEW.data_checkout);
END$$

-- Auditoria: registra mudança de status com a conta do banco que a fez
CREATE TRIGGER trg_reservas_au
AFTER UPDATE ON reservas_hospedagem
FOR EACH ROW
BEGIN
    IF NEW.status_reserva <> OLD.status_reserva THEN
        INSERT INTO log_reservas (id_reserva, status_anterior, status_novo, usuario_db)
        VALUES (NEW.id_reserva, OLD.status_reserva, NEW.status_reserva, USER());
    END IF;
END$$

-- Um guia não pode ter dois passeios agendados no mesmo horário
CREATE TRIGGER trg_passeios_bi
BEFORE INSERT ON passeios_guiados
FOR EACH ROW
BEGIN
    IF NEW.status_passeio = 'AGENDADO' AND EXISTS (
        SELECT 1 FROM passeios_guiados
         WHERE id_guia = NEW.id_guia
           AND status_passeio = 'AGENDADO'
           AND data_hora = NEW.data_hora) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'O guia ja possui passeio agendado neste horario.';
    END IF;
END$$


-- =====================================================================
-- 5. PROCEDURES (transação: COMMIT se der certo, ROLLBACK se falhar)
-- =====================================================================

-- Cria uma reserva. FOR UPDATE trava a linha do quarto: duas pessoas
-- reservando ao mesmo tempo não conseguem furar o trigger de conflito.
CREATE PROCEDURE sp_criar_reserva(
    IN  p_id_turista    CHAR(15),
    IN  p_id_hospedagem INT,
    IN  p_numero_quarto VARCHAR(10),
    IN  p_checkin       DATE,
    IN  p_checkout      DATE,
    OUT p_id_reserva    CHAR(15))
BEGIN
    DECLARE v_quarto TINYINT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT 1 INTO v_quarto FROM quartos
     WHERE id_hospedagem = p_id_hospedagem AND numero_quarto = p_numero_quarto
       FOR UPDATE;

    SET p_id_reserva = fn_proximo_id('RES');

    INSERT INTO reservas_hospedagem
        (id_reserva, id_turista, id_hospedagem, numero_quarto,
         data_checkin, data_checkout, status_reserva)
    VALUES
        (p_id_reserva, p_id_turista, p_id_hospedagem, p_numero_quarto,
         p_checkin, p_checkout, 'CONFIRMADA');

    COMMIT;
END$$

-- Cancela uma reserva ativa
CREATE PROCEDURE sp_cancelar_reserva(IN p_id_reserva CHAR(15))
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT status_reserva INTO v_status FROM reservas_hospedagem
     WHERE id_reserva = p_id_reserva FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reserva nao encontrada.';
    END IF;
    IF v_status IN ('CANCELADA', 'CONCLUIDA') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Esta reserva nao pode mais ser cancelada.';
    END IF;

    UPDATE reservas_hospedagem SET status_reserva = 'CANCELADA'
     WHERE id_reserva = p_id_reserva;

    COMMIT;
END$$

DELIMITER ;


-- =====================================================================
-- 6. VIEWS
-- =====================================================================

-- Reservas já com turista, hospedagem e quarto (a aplicação não repete JOINs)
CREATE VIEW vw_reservas_detalhadas AS
SELECT r.id_reserva, u.nome AS turista, h.nome_fantasia AS hospedagem,
       r.numero_quarto, q.tipo_quarto, r.data_checkin, r.data_checkout,
       DATEDIFF(r.data_checkout, r.data_checkin) AS noites,
       r.valor_total, r.status_reserva
  FROM reservas_hospedagem r
  JOIN usuarios    u ON u.id_usuario = r.id_turista
  JOIN quartos     q ON q.id_hospedagem = r.id_hospedagem
                    AND q.numero_quarto = r.numero_quarto
  JOIN hospedagens h ON h.id_hospedagem = r.id_hospedagem;

-- Relatório gerencial: reservas e faturamento por hospedagem
CREATE VIEW vw_faturamento_hospedagem AS
SELECT h.id_hospedagem, h.nome_fantasia,
       COUNT(r.id_reserva) AS total_reservas,
       COALESCE(SUM(CASE WHEN r.status_reserva IN ('CONFIRMADA', 'CONCLUIDA')
                         THEN r.valor_total END), 0) AS faturamento
  FROM hospedagens h
  LEFT JOIN reservas_hospedagem r ON r.id_hospedagem = h.id_hospedagem
 GROUP BY h.id_hospedagem, h.nome_fantasia;

-- Usuários SEM senha_hash: única forma de a aplicação consultá-los
CREATE VIEW vw_usuarios_resumo AS
SELECT u.id_usuario, u.nome, u.email, u.tipo_usuario, g.nome AS grupo, u.ativo
  FROM usuarios u
  JOIN grupos_usuarios g ON g.id_grupo = u.id_grupo;


-- =====================================================================
-- 7. DADOS INICIAIS
-- =====================================================================

INSERT INTO grupos_usuarios (nome, descricao) VALUES
('ADMIN',    'Administração total do sistema'),
('RECEPCAO', 'Funcionários que gerenciam reservas'),
('GUIA',     'Guias de turismo credenciados'),
('TURISTA',  'Clientes que reservam hospedagens e passeios');

SET @u_lucas   = fn_proximo_id('USR');
SET @u_beatriz = fn_proximo_id('USR');
SET @u_camila  = fn_proximo_id('USR');
SET @u_admin   = fn_proximo_id('USR');
SET @u_recep   = fn_proximo_id('USR');

INSERT INTO usuarios (id_usuario, id_grupo, nome, email, tipo_usuario) VALUES
(@u_lucas,   4, 'Lucas Silva',    'lucas@gmail.com',       'TURISTA'),
(@u_beatriz, 4, 'Beatriz Souza',  'beatriz@gmail.com',     'TURISTA'),
(@u_camila,  3, 'Camila Rocha',   'camila.guia@gmail.com', 'GUIA'),
(@u_admin,   1, 'Administrador',  'admin@turismo.com',     'FUNCIONARIO'),
(@u_recep,   2, 'Marcos Recepção','recepcao@turismo.com',  'FUNCIONARIO');

INSERT INTO turistas (id_usuario, cpf) VALUES
(@u_lucas, '12345678901'), (@u_beatriz, '98765432100');

INSERT INTO guias (id_usuario, cadastur) VALUES (@u_camila, 'CAD-55.666777.88-9');

INSERT INTO hospedagens (nome_fantasia, cnpj, estrelas) VALUES
('Grand Hotel Bahiamar', '11222333000199', 4),
('Pousada Beira Mar',    '44555666000188', 3);

INSERT INTO quartos (id_hospedagem, numero_quarto, tipo_quarto, diaria_base) VALUES
(1, '101', 'Standard Casal',  280.00),
(1, '201', 'Suíte Luxo',      450.00),
(2, '05',  'Chalé Vista Mar', 320.00);

INSERT INTO pontos_turisticos (nome, cidade) VALUES
('Pelourinho', 'Salvador'),
('Centro Histórico de Florianópolis', 'Florianópolis');

SET @r1 = fn_proximo_id('RES');
SET @r2 = fn_proximo_id('RES');
INSERT INTO reservas_hospedagem
    (id_reserva, id_turista, id_hospedagem, numero_quarto, data_checkin, data_checkout, status_reserva)
VALUES
(@r1, @u_lucas,   1, '201', '2026-10-20', '2026-10-24', 'CONCLUIDA'),
(@r2, @u_beatriz, 2, '05',  '2026-12-01', '2026-12-05', 'CONFIRMADA');

SET @p1 = fn_proximo_id('PAS');
SET @p2 = fn_proximo_id('PAS');
INSERT INTO passeios_guiados
    (id_passeio, id_turista, id_guia, id_ponto, data_hora, valor_contratado, status_passeio)
VALUES
(@p1, @u_lucas,   @u_camila, 1, '2026-10-22 09:00:00', 150.00, 'REALIZADO'),
(@p2, @u_beatriz, @u_camila, 2, '2026-12-02 14:00:00', 200.00, 'AGENDADO');


-- =====================================================================
-- 8. USUÁRIOS MYSQL E PERMISSÕES (troque as senhas antes de entregar)
-- =====================================================================
-- Mapeamento: ADMIN -> app_admin | RECEPCAO/aplicação -> app_operador |
-- gerência (relatórios) -> app_leitura. Nenhuma conta é root.
CREATE USER IF NOT EXISTS 'app_admin'@'localhost'    IDENTIFIED BY 'Admin#Turismo2026';
CREATE USER IF NOT EXISTS 'app_operador'@'localhost' IDENTIFIED BY 'Oper#Turismo2026';
CREATE USER IF NOT EXISTS 'app_leitura'@'localhost'  IDENTIFIED BY 'Leit#Turismo2026';

-- Administrador: tudo, mas somente dentro de db_turismo
GRANT ALL PRIVILEGES ON db_turismo.* TO 'app_admin'@'localhost';

-- Operador (usado pelo backend): sem INSERT/UPDATE/DELETE em tabelas.
-- Lê views e cadastros; escreve só executando procedures. Sem acesso à
-- tabela usuarios (tem senha_hash).
GRANT SELECT ON db_turismo.vw_reservas_detalhadas    TO 'app_operador'@'localhost';
GRANT SELECT ON db_turismo.vw_faturamento_hospedagem TO 'app_operador'@'localhost';
GRANT SELECT ON db_turismo.vw_usuarios_resumo        TO 'app_operador'@'localhost';
GRANT SELECT ON db_turismo.hospedagens               TO 'app_operador'@'localhost';
GRANT SELECT ON db_turismo.quartos                   TO 'app_operador'@'localhost';
GRANT EXECUTE ON PROCEDURE db_turismo.sp_criar_reserva    TO 'app_operador'@'localhost';
GRANT EXECUTE ON PROCEDURE db_turismo.sp_cancelar_reserva TO 'app_operador'@'localhost';

-- Leitura: só relatórios
GRANT SELECT ON db_turismo.vw_reservas_detalhadas    TO 'app_leitura'@'localhost';
GRANT SELECT ON db_turismo.vw_faturamento_hospedagem TO 'app_leitura'@'localhost';


-- =====================================================================
-- 9. VERIFICAÇÃO RÁPIDA
-- =====================================================================
SELECT * FROM sequencias;   -- esperado: PAS=2, RES=2, USR=5 (ano 2026)
SELECT fn_valor_estadia(1, '201', '2026-12-10', '2026-12-13') AS esperado_1350;
SELECT * FROM vw_reservas_detalhadas;

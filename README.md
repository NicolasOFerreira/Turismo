# Sistema de Turismo

Projeto N2 da disciplina de Banco de Dados. Aplicação de reservas de hospedagem e passeios guiados com **MySQL 8.0** no banco e **Java + Spring Boot** no backend, com um front simples em HTML e JavaScript.

O foco do projeto é o banco de dados: as regras de negócio (conflito de datas, cálculo de valores, geração de IDs, auditoria) ficam no próprio banco, e a aplicação acessa tudo por uma conta de privilégio mínimo, **nunca pelo root**.

> **Autores:** _(preencher)_

---

## Estrutura do repositório

```
novo-projeto-bd/
├── turismo.sql        # cria o banco, objetos, dados iniciais e contas (rodar uma vez)
├── demo.sql           # roteiro de demonstração (TCL, triggers, índices, acesso)
├── der.png            # Diagrama Entidade-Relacionamento (adicionar)
└── turismo-api/       # backend Spring Boot + front estático
    ├── pom.xml
    └── src/main/
        ├── java/br/edu/turismo/
        └── resources/
            ├── application.properties
            └── static/index.html
```

## Tecnologias

| Camada | Tecnologia | Motivo |
|---|---|---|
| Banco | MySQL 8.0 (InnoDB) | SGBD exigido; transações, triggers, views, procedures e índices invisíveis |
| Backend | Java 17 + Spring Boot 3.3 (`JdbcTemplate`) | API REST simples; SQL explícito e parametrizado, sem ORM escondendo o que roda no banco |
| Frontend | HTML, CSS e JavaScript puro | Escopo pequeno; não precisa de framework |

## Pré-requisitos

- MySQL 8.0 em `localhost:3306`
- Java 17 ou superior
- Maven 3.8 ou superior
- Uma conta administrativa do MySQL, usada **uma única vez** para provisionar o banco e as contas da aplicação

## Como executar

**1. Criar o banco (uma vez).** No prompt do MySQL, com a conta administrativa:

```
mysql> source caminho/para/novo-projeto-bd/turismo.sql
```

O script recria o `db_turismo` do zero (apaga o anterior), cria tabelas, índices, functions, triggers, procedures, views, dados iniciais e as três contas `app_*`.

**2. Subir a aplicação.** No `cmd` do Windows:

```
cd turismo-api
set DB_PASSWORD=<senha da conta app_operador>
mvn spring-boot:run
```

No PowerShell use `$env:DB_PASSWORD="..."`. No Linux/macOS use `export DB_PASSWORD=...`.

**3. Abrir** <http://localhost:8080>

> A senha do banco **não está no código Java**: vem da variável de ambiente `DB_PASSWORD`.

## Funcionalidades

- Listar reservas de hospedagem (a partir de uma **view**)
- Criar reserva (via **procedure** com transação)
- Cancelar reserva (via **procedure**)
- Relatório de faturamento por hospedagem (a partir de uma **view**)
- Listar hospedagens (a partir de uma **tabela**)
- Cabeçalho que mostra, consultando o próprio banco, com qual conta MySQL a aplicação está conectada

### API

| Método | Rota | Origem dos dados |
|---|---|---|
| GET | `/api/conexao` | `CURRENT_USER()` e `DATABASE()` |
| GET | `/api/reservas` | view `vw_reservas_detalhadas` |
| GET | `/api/faturamento` | view `vw_faturamento_hospedagem` |
| GET | `/api/hospedagens` | tabela `hospedagens` |
| GET | `/api/quartos` | tabelas `quartos` e `hospedagens` |
| GET | `/api/turistas` | view `vw_usuarios_resumo` |
| POST | `/api/reservas` | `CALL sp_criar_reserva(...)` |
| POST | `/api/reservas/{id}/cancelar` | `CALL sp_cancelar_reserva(...)` |

## Banco de dados

### Modelagem

![DER](der.png)

São 11 tabelas:

| Tabela | Função |
|---|---|
| `grupos_usuarios` | Grupos de usuários (ADMIN, RECEPCAO, GUIA, TURISTA) |
| `usuarios` | Dados básicos de todos os usuários |
| `turistas`, `guias` | Especializações de `usuarios` |
| `hospedagens`, `quartos` | Hospedagens e seus quartos (chave composta: o número do quarto só é único dentro da hospedagem) |
| `reservas_hospedagem` | Reserva de um turista para um quarto em um período |
| `pontos_turisticos`, `passeios_guiados` | Passeios de um guia para um turista |
| `sequencias` | Último número usado por prefixo e ano (base da geração de IDs) |
| `log_reservas` | Auditoria das mudanças de status de reserva |

### Geração de IDs

Dados críticos (`usuarios`, `reservas_hospedagem`, `passeios_guiados`) **não usam `AUTO_INCREMENT`**. O ID vem da função `fn_proximo_id`, no formato `PREFIXO-ANO-SEQUENCIAL`, por exemplo `RES-2026-000001`. A função usa `INSERT ... ON DUPLICATE KEY UPDATE` sobre `sequencias`, que trava a linha até o fim da transação e evita IDs repetidos.

`AUTO_INCREMENT` aparece apenas em tabelas de apoio: `grupos_usuarios`, `hospedagens`, `pontos_turisticos` (cadastros pequenos, sem criticidade de negócio) e `log_reservas` (o ID só ordena os eventos).

### Índices

| Índice | Tabela | Para quê |
|---|---|---|
| `idx_reservas_quarto_periodo` | `reservas_hospedagem` (hospedagem, quarto, check-in, check-out) | Checagem de conflito de datas usada pelo trigger de reserva |
| `idx_reservas_status_checkin` | `reservas_hospedagem` (status, check-in) | Listagens e relatórios por status e período (igualdade primeiro, intervalo depois) |
| `idx_passeios_guia_data` | `passeios_guiados` (guia, data/hora) | Agenda do guia e conflito de horário |

O impacto é medido no `demo.sql` com `EXPLAIN`, com 30 mil reservas de teste e o índice visível e invisível.

### Triggers

| Trigger | Função |
|---|---|
| `trg_reservas_bi` | Antes de inserir reserva: bloqueia sobreposição de datas no mesmo quarto e calcula `valor_total` |
| `trg_reservas_au` | Depois de atualizar reserva: grava em `log_reservas` toda mudança de status, com a conta do banco que a fez |
| `trg_passeios_bi` | Impede dois passeios agendados no mesmo horário para o mesmo guia |

A regra de conflito está em trigger, e não só na aplicação, para valer para qualquer cliente que escreva no banco.

### Views

| View | Finalidade |
|---|---|
| `vw_reservas_detalhadas` | Reservas já com turista, hospedagem e quarto; a aplicação não repete JOINs |
| `vw_faturamento_hospedagem` | Total de reservas e faturamento por hospedagem |
| `vw_usuarios_resumo` | Usuários sem a coluna `senha_hash`; é a única forma de a aplicação consultá-los |

### Procedures e functions

| Objeto | Função |
|---|---|
| `sp_criar_reserva` | Transação: trava o quarto com `FOR UPDATE`, gera o ID e insere a reserva. `COMMIT` se der certo; handler com `ROLLBACK` se falhar, inclusive do número de ID consumido |
| `sp_cancelar_reserva` | Transação: valida o status atual e cancela a reserva |
| `fn_proximo_id` | Gera IDs no formato `PREFIXO-ANO-SEQUENCIAL` |
| `fn_valor_estadia` | Calcula diária × número de noites |

## Controle de acesso

Nenhuma conta usada pelo sistema é `root`. O root só é usado uma vez, para rodar `turismo.sql` e criar as contas abaixo.

| Conta | Grupo correspondente | Permissões |
|---|---|---|
| `app_admin` | ADMIN | Todos os privilégios, somente em `db_turismo` |
| `app_operador` | RECEPCAO / aplicação | `SELECT` nas views e em `hospedagens` e `quartos`; `EXECUTE` nas duas procedures. Sem `INSERT`, `UPDATE` ou `DELETE` direto e sem acesso à tabela `usuarios` |
| `app_leitura` | Gerência (relatórios) | `SELECT` apenas em `vw_reservas_detalhadas` e `vw_faturamento_hospedagem` |

Princípio do menor privilégio: se a aplicação fosse comprometida, o estrago possível ficaria limitado a leituras e às duas procedures.

**Senhas de demonstração** (apenas para ambiente local, definidas no `turismo.sql`):

| Conta | Senha |
|---|---|
| `app_admin` | `Admin#Turismo2026` |
| `app_operador` | `Oper#Turismo2026` |
| `app_leitura` | `Leit#Turismo2026` |

## Segurança da aplicação

- Todas as consultas usam SQL fixo e parâmetros (`PreparedStatement`), sem concatenar entrada do usuário (proteção contra SQL Injection)
- Entrada validada na API (Bean Validation) antes de chegar ao banco
- Mensagens de erro controladas: só as regras do banco (`SQLSTATE 45000`) chegam ao usuário; erros inesperados retornam mensagem genérica e ficam no log
- O front usa `textContent`, e não `innerHTML`, para não interpretar dados como HTML
- A aplicação nunca lê a tabela `usuarios` nem a coluna `senha_hash`

### Limitações conhecidas

- A API não tem autenticação: o projeto foca no controle de acesso no nível do banco
- `/api/reservas` não é paginado
- As configurações `useSSL=false` e `allowPublicKeyRetrieval=true` são adequadas só para execução local

## Demonstração

O arquivo `demo.sql` reúne os comandos usados na apresentação, em blocos para colar um de cada vez:

1. Transações: `COMMIT`, `ROLLBACK` automático (na procedure) e manual
2. Triggers: conflito de datas, conflito de guia e auditoria
3. Functions
4. Views
5. Índices: `EXPLAIN` com e sem índice, em 30 mil reservas de teste
6. Controle de acesso: o que cada conta pode e não pode fazer
7. Limpeza

Para repetir a demonstração, rode `turismo.sql` de novo e recrie o banco do zero.

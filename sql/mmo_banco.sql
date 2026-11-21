-- =====================================================================
--  AV3 - Técnicas de Implementação de Banco de Dados (UNIFAMETRO)
--  Projeto: Banco de dados de um MMO inspirado em RuneScape
--  SGBD: PostgreSQL 16
--  Equipe: Lucas Amaro Oliveira, Antônio Geovane Porto Camelo,
--          Joel Caleb Coelho dos Santos, Esli Pompeu de Paulo Rufino Filho
--
--  Estrutura do script:
--    PARTE 1 - DDL  (criação das tabelas e restrições)
--    PARTE 2 - VIEWS e FUNÇÃO de compra no mercado
--    PARTE 3 - DML  (dados de exemplo e operações do jogo)
--    PARTE 4 - DCL  (perfis de acesso: GRANT / REVOKE)
--    PARTE 5 - CONSULTAS (operações reais do sistema)
--    PARTE 6 - TRANSAÇÃO (compra no mercado com isolamento SERIALIZABLE)
--    PARTE 7 - DEMONSTRAÇÃO de bloqueios (comentada)
--
--  Os testes automatizados estão em testes.sql (rodar depois deste arquivo).
-- =====================================================================

DROP SCHEMA IF EXISTS mmo CASCADE;
CREATE SCHEMA mmo;
SET search_path TO mmo;


-- =====================================================================
--  PARTE 1 - DDL: TABELAS E RESTRIÇÕES
-- =====================================================================

-- 1. CONTAS: dados de login do jogador (cada conta tem 1 personagem)
CREATE TABLE contas (
    id_conta     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email        VARCHAR(120) NOT NULL UNIQUE,
    senha_hash   VARCHAR(255) NOT NULL,
    tipo_conta   VARCHAR(3)   NOT NULL DEFAULT 'F2P'
                 CHECK (tipo_conta IN ('F2P', 'P2P')),        -- gratuita ou assinante
    regiao       VARCHAR(2)   NOT NULL
                 CHECK (regiao IN ('BR', 'EU', 'US')),        -- usada no particionamento
    status       VARCHAR(10)  NOT NULL DEFAULT 'ativa'
                 CHECK (status IN ('ativa', 'suspensa', 'banida')),
    criada_em    TIMESTAMPTZ    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. CLÃS: grupos de jogadores (equivalente às guildas)
CREATE TABLE clas (
    id_cla     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome       VARCHAR(40) NOT NULL UNIQUE,
    descricao  VARCHAR(200),
    criado_em  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 3. PERSONAGENS: o avatar do jogador dentro do jogo
CREATE TABLE personagens (
    id_personagem  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_conta       BIGINT      NOT NULL UNIQUE           -- UNIQUE garante 1 personagem por conta
                   REFERENCES contas(id_conta) ON DELETE CASCADE,
    nome           VARCHAR(12) NOT NULL UNIQUE,          -- nome visível no jogo, não pode repetir
    moedas         BIGINT      NOT NULL DEFAULT 0
                   CHECK (moedas >= 0),                  -- saldo nunca fica negativo
    id_cla         BIGINT      REFERENCES clas(id_cla) ON DELETE RESTRICT,  -- clã com membros não pode ser apagado
    cargo_cla      VARCHAR(10)
                   CHECK (cargo_cla IN ('lider', 'oficial', 'membro')),
    criado_em      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- se está em um clã, precisa ter cargo; se não está, não pode ter cargo
    CONSTRAINT ck_cargo_cla CHECK ((id_cla IS NULL) = (cargo_cla IS NULL))
);

-- 4. SKILLS: catálogo de habilidades do jogo (Attack, Mining, ...)
CREATE TABLE skills (
    id_skill  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome      VARCHAR(20) NOT NULL UNIQUE,
    tipo      VARCHAR(10) NOT NULL
              CHECK (tipo IN ('combate', 'coleta', 'producao'))
);

-- 5. PERSONAGEM_SKILLS: nível e XP de cada personagem em cada skill (N:N)
CREATE TABLE personagem_skills (
    id_personagem  BIGINT   NOT NULL REFERENCES personagens(id_personagem) ON DELETE CASCADE,
    id_skill       BIGINT   NOT NULL REFERENCES skills(id_skill),
    xp             INT      NOT NULL DEFAULT 0 CHECK (xp >= 0),
    nivel          SMALLINT NOT NULL DEFAULT 1 CHECK (nivel BETWEEN 1 AND 99),
    PRIMARY KEY (id_personagem, id_skill)               -- chave primária composta
);

-- 6. ITENS: catálogo de todos os itens que existem no jogo
CREATE TABLE itens (
    id_item         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome            VARCHAR(40) NOT NULL UNIQUE,
    tipo            VARCHAR(12) NOT NULL
                    CHECK (tipo IN ('arma', 'armadura', 'recurso', 'consumivel', 'missao')),
    apenas_membros  BOOLEAN     NOT NULL DEFAULT FALSE,  -- só contas P2P podem usar
    empilhavel      BOOLEAN     NOT NULL DEFAULT FALSE,  -- ex.: minérios empilham, espadas não
    valor_base      INT         NOT NULL CHECK (valor_base >= 0)
);

-- 7. INVENTARIO: onde está cada item do personagem
--    local = 'mochila' (28 espaços), 'banco' (guardado) ou 'equipado' (em uso)
CREATE TABLE inventario (
    id_inventario  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_personagem  BIGINT      NOT NULL REFERENCES personagens(id_personagem) ON DELETE CASCADE,
    id_item        BIGINT      NOT NULL REFERENCES itens(id_item),
    local          VARCHAR(8)  NOT NULL
                   CHECK (local IN ('mochila', 'banco', 'equipado')),
    slot           SMALLINT,
    quantidade     INT         NOT NULL DEFAULT 1 CHECK (quantidade > 0),
    -- a mochila tem exatamente 28 espaços (0 a 27), como no RuneScape;
    -- no banco e no equipamento o espaço não é numerado (slot fica vazio)
    CONSTRAINT ck_slot_mochila CHECK (
        (local = 'mochila' AND slot IS NOT NULL AND slot BETWEEN 0 AND 27) OR
        (local <> 'mochila' AND slot IS NULL))
);

-- Índices únicos parciais (valem só para as linhas que atendem ao WHERE):
-- dois itens não ocupam o mesmo espaço da mochila
CREATE UNIQUE INDEX uq_mochila_slot    ON inventario (id_personagem, slot)    WHERE local = 'mochila';
-- no banco, itens iguais ficam agrupados em uma linha só (a quantidade soma)
CREATE UNIQUE INDEX uq_banco_item      ON inventario (id_personagem, id_item) WHERE local = 'banco';
-- o mesmo item não é equipado duas vezes
CREATE UNIQUE INDEX uq_equipado_item   ON inventario (id_personagem, id_item) WHERE local = 'equipado';

-- 8. QUESTS: missões do jogo, com requisito de nível em uma skill
CREATE TABLE quests (
    id_quest            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nome                VARCHAR(60) NOT NULL UNIQUE,
    dificuldade         VARCHAR(8)  NOT NULL
                        CHECK (dificuldade IN ('facil', 'media', 'dificil')),
    id_skill_requisito  BIGINT      REFERENCES skills(id_skill),
    nivel_minimo        SMALLINT    NOT NULL DEFAULT 1 CHECK (nivel_minimo BETWEEN 1 AND 99),
    recompensa_moedas   INT         NOT NULL DEFAULT 0 CHECK (recompensa_moedas >= 0),
    apenas_membros      BOOLEAN     NOT NULL DEFAULT FALSE
);

-- 9. PERSONAGEM_QUESTS: progresso de cada personagem nas quests (N:N)
CREATE TABLE personagem_quests (
    id_personagem  BIGINT      NOT NULL REFERENCES personagens(id_personagem) ON DELETE CASCADE,
    id_quest       BIGINT      NOT NULL REFERENCES quests(id_quest),
    status         VARCHAR(12) NOT NULL DEFAULT 'em_andamento'
                   CHECK (status IN ('em_andamento', 'concluida')),
    concluida_em   TIMESTAMPTZ,
    PRIMARY KEY (id_personagem, id_quest),
    -- quest concluída precisa ter data de conclusão
    CONSTRAINT ck_conclusao CHECK ((status = 'concluida') = (concluida_em IS NOT NULL))
);

-- 10. GE_OFERTAS: mercado entre jogadores (Grand Exchange)
CREATE TABLE ge_ofertas (
    id_oferta             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_personagem         BIGINT      NOT NULL REFERENCES personagens(id_personagem) ON DELETE CASCADE,
    id_item               BIGINT      NOT NULL REFERENCES itens(id_item),
    tipo                  VARCHAR(6)  NOT NULL CHECK (tipo IN ('compra', 'venda')),
    quantidade            INT         NOT NULL CHECK (quantidade > 0),
    quantidade_executada  INT         NOT NULL DEFAULT 0,
    preco_unitario        INT         NOT NULL CHECK (preco_unitario > 0),
    status                VARCHAR(10) NOT NULL DEFAULT 'aberta'
                          CHECK (status IN ('aberta', 'concluida', 'cancelada')),
    criada_em             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_executada CHECK (quantidade_executada BETWEEN 0 AND quantidade)
);

-- 11. PENALIDADES: punições aplicadas por moderadores
CREATE TABLE penalidades (
    id_penalidade  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_conta       BIGINT      NOT NULL REFERENCES contas(id_conta) ON DELETE CASCADE,
    tipo           VARCHAR(10) NOT NULL
                   CHECK (tipo IN ('aviso', 'mute', 'suspensao', 'banimento')),
    motivo         VARCHAR(200) NOT NULL,
    aplicada_por   VARCHAR(40) NOT NULL DEFAULT CURRENT_USER,  -- registra quem aplicou
    inicio         TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fim            TIMESTAMPTZ,                                   -- NULL = permanente
    CONSTRAINT ck_periodo CHECK (fim IS NULL OR fim > inicio)
);

-- 12. LOGS_ATIVIDADE: histórico de ações (usado pelo suporte / Game Master)
CREATE TABLE logs_atividade (
    id_log         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_personagem  BIGINT      REFERENCES personagens(id_personagem) ON DELETE SET NULL,
    tipo_evento    VARCHAR(20) NOT NULL,     -- ex.: 'login', 'compra_ge', 'quest', 'item_perdido'
    descricao      VARCHAR(255),
    criado_em      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Índices: o PostgreSQL NÃO cria índice em chave estrangeira sozinho.
-- Sem eles, JOINs e exclusões em cascata percorrem a tabela inteira.
CREATE INDEX idx_personagens_cla          ON personagens(id_cla);
CREATE INDEX idx_personagem_skills_skill  ON personagem_skills(id_skill);
CREATE INDEX idx_inventario_personagem    ON inventario(id_personagem);
CREATE INDEX idx_inventario_item          ON inventario(id_item);
CREATE INDEX idx_quests_skill             ON quests(id_skill_requisito);
CREATE INDEX idx_personagem_quests_quest  ON personagem_quests(id_quest);
CREATE INDEX idx_ge_personagem            ON ge_ofertas(id_personagem);
CREATE INDEX idx_ge_item_status           ON ge_ofertas(id_item, status);
CREATE INDEX idx_penalidades_conta        ON penalidades(id_conta);
CREATE INDEX idx_logs_personagem_data     ON logs_atividade(id_personagem, criado_em);


-- =====================================================================
--  PARTE 2 - VIEWS
-- =====================================================================

-- VIEW 1: Ranking geral (Hiscores) - soma dos níveis e do XP de todas as skills
CREATE VIEW vw_ranking AS
SELECT RANK() OVER (ORDER BY SUM(ps.nivel) DESC, SUM(ps.xp) DESC) AS posicao,
       p.nome            AS personagem,
       SUM(ps.nivel)     AS nivel_total,
       SUM(ps.xp)        AS xp_total
FROM personagens p
JOIN personagem_skills ps ON ps.id_personagem = p.id_personagem
GROUP BY p.id_personagem, p.nome;

-- VIEW 2: Perfil público do jogador - esconde email e senha (segurança)
--         É o que moderadores e outros perfis consultam
CREATE VIEW vw_jogador_publico AS
SELECT p.id_personagem,
       p.nome        AS personagem,
       c.id_conta,
       c.tipo_conta,
       c.regiao,
       c.status,
       cl.nome       AS cla,
       p.cargo_cla
FROM personagens p
JOIN contas c     ON c.id_conta = p.id_conta
LEFT JOIN clas cl ON cl.id_cla  = p.id_cla;

-- VIEW 3: Preço médio de cada item no mercado (ofertas de venda concluídas)
CREATE VIEW vw_preco_medio_mercado AS
SELECT i.nome                         AS item,
       COUNT(*)                       AS negociacoes,
       SUM(o.quantidade_executada)    AS unidades_vendidas,
       ROUND(AVG(o.preco_unitario))   AS preco_medio,
       MIN(o.preco_unitario)          AS menor_preco,
       MAX(o.preco_unitario)          AS maior_preco
FROM ge_ofertas o
JOIN itens i ON i.id_item = o.id_item
WHERE o.tipo = 'venda' AND o.status = 'concluida'
GROUP BY i.nome;


-- =====================================================================
--  PARTE 2B - FUNÇÃO: compra no mercado (Grand Exchange)
-- =====================================================================
-- Toda compra passa por esta função. Ela confere as regras ANTES de mexer
-- em moedas e itens; se alguma falhar, gera um erro e nada é alterado.
-- Premissa: ao anunciar uma venda, o item sai do inventário do vendedor e
-- fica reservado na oferta (como no Grand Exchange).
--
-- Códigos de erro (usados também nos testes):
--   MMO01 oferta não está aberta para venda (inexistente, concluída ou de compra)
--   MMO02 quantidade inválida ou maior que a disponível
--   MMO03 comprador sem moedas suficientes
--   MMO04 conta gratuita (F2P) tentando comprar item de membros
--   MMO05 jogador comprando a própria oferta
--   MMO06 chamada fora de uma transação SERIALIZABLE
CREATE FUNCTION comprar_oferta(p_comprador BIGINT, p_oferta BIGINT, p_quantidade INT)
RETURNS VOID LANGUAGE plpgsql
SET search_path = mmo   -- fixa o schema: a função não depende de quem a chama
AS $$
DECLARE
    v_oferta      ge_ofertas%ROWTYPE;
    v_moedas      BIGINT;
    v_tipo_conta  VARCHAR(3);
    v_so_membros  BOOLEAN;
    v_total       BIGINT;
BEGIN
    -- 0) A compra mexe com a economia do jogo: exige o isolamento mais alto
    IF current_setting('transaction_isolation') <> 'serializable' THEN
        RAISE EXCEPTION 'A compra precisa rodar em uma transação SERIALIZABLE' USING ERRCODE = 'MMO06';
    END IF;

    -- 1) Trava a oferta (FOR UPDATE) e confere se ela ainda está à venda
    SELECT * INTO v_oferta FROM ge_ofertas WHERE id_oferta = p_oferta FOR UPDATE;
    IF NOT FOUND OR v_oferta.tipo <> 'venda' OR v_oferta.status <> 'aberta' THEN
        RAISE EXCEPTION 'A oferta % não está aberta para venda', p_oferta USING ERRCODE = 'MMO01';
    END IF;

    IF p_quantidade IS NULL OR p_quantidade <= 0
       OR p_quantidade > v_oferta.quantidade - v_oferta.quantidade_executada THEN
        RAISE EXCEPTION 'Quantidade % indisponível na oferta %', p_quantidade, p_oferta USING ERRCODE = 'MMO02';
    END IF;

    IF v_oferta.id_personagem = p_comprador THEN
        RAISE EXCEPTION 'O jogador não pode comprar a própria oferta' USING ERRCODE = 'MMO05';
    END IF;

    -- 2) Trava comprador e vendedor sempre na mesma ordem (por id) para evitar deadlock
    PERFORM 1 FROM personagens
    WHERE id_personagem IN (p_comprador, v_oferta.id_personagem)
    ORDER BY id_personagem FOR UPDATE;

    SELECT p.moedas, c.tipo_conta INTO v_moedas, v_tipo_conta
    FROM personagens p JOIN contas c ON c.id_conta = p.id_conta
    WHERE p.id_personagem = p_comprador;

    SELECT apenas_membros INTO v_so_membros FROM itens WHERE id_item = v_oferta.id_item;
    IF v_so_membros AND v_tipo_conta = 'F2P' THEN
        RAISE EXCEPTION 'Conta gratuita não pode comprar item de membros' USING ERRCODE = 'MMO04';
    END IF;

    v_total := p_quantidade::BIGINT * v_oferta.preco_unitario;
    IF v_moedas IS NULL OR v_moedas < v_total THEN
        RAISE EXCEPTION 'Moedas insuficientes: precisa de %, tem %', v_total, COALESCE(v_moedas, 0) USING ERRCODE = 'MMO03';
    END IF;

    -- 3) Tudo certo: move as moedas
    UPDATE personagens SET moedas = moedas - v_total WHERE id_personagem = p_comprador;
    UPDATE personagens SET moedas = moedas + v_total WHERE id_personagem = v_oferta.id_personagem;

    -- 4) Entrega os itens no banco do comprador (soma se ele já tiver o item lá)
    INSERT INTO inventario (id_personagem, id_item, local, slot, quantidade)
    VALUES (p_comprador, v_oferta.id_item, 'banco', NULL, p_quantidade)
    ON CONFLICT (id_personagem, id_item) WHERE local = 'banco'
    DO UPDATE SET quantidade = inventario.quantidade + EXCLUDED.quantidade;

    -- 5) Atualiza a oferta: fecha quando tudo foi vendido
    UPDATE ge_ofertas
    SET quantidade_executada = quantidade_executada + p_quantidade,
        status = CASE WHEN quantidade_executada + p_quantidade = quantidade
                      THEN 'concluida' ELSE 'aberta' END
    WHERE id_oferta = p_oferta;

    -- 6) Registra no log para auditoria
    INSERT INTO logs_atividade (id_personagem, tipo_evento, descricao)
    VALUES (p_comprador, 'compra_ge',
            format('Comprou %s unidade(s) do item %s na oferta %s por %s cada',
                   p_quantidade, v_oferta.id_item, p_oferta, v_oferta.preco_unitario));
END $$;


-- =====================================================================
--  PARTE 3 - DML: DADOS DE EXEMPLO
-- =====================================================================

INSERT INTO contas (email, senha_hash, tipo_conta, regiao, status) VALUES
('lucas@email.com',   'hash_1', 'P2P', 'BR', 'ativa'),
('geovane@email.com', 'hash_2', 'P2P', 'BR', 'ativa'),
('joel@email.com',    'hash_3', 'F2P', 'BR', 'ativa'),
('esli@email.com',    'hash_4', 'P2P', 'US', 'ativa'),
('anna@email.com',    'hash_5', 'P2P', 'EU', 'ativa'),
('mark@email.com',    'hash_6', 'P2P', 'US', 'ativa'),
('sofia@email.com',   'hash_7', 'F2P', 'EU', 'ativa'),
('trader@email.com',  'hash_8', 'F2P', 'US', 'ativa');

INSERT INTO clas (nome, descricao) VALUES
('Guardioes do Norte', 'Clã focado em combate e chefes'),
('Mineradores BR',     'Clã brasileiro de skills de coleta'),
('Mercadores',         'Clã focado em comércio no Grand Exchange');

INSERT INTO personagens (id_conta, nome, moedas, id_cla, cargo_cla) VALUES
(1, 'Zezinho',     150000, 1, 'lider'),
(2, 'Camelo',      980000, 2, 'lider'),
(3, 'JoelKnight',   25000, 1, 'membro'),
(4, 'EsliMage',    420000, 3, 'lider'),
(5, 'AnnaFish',     60000, 2, 'oficial'),
(6, 'MarkPure',    300000, 1, 'oficial'),
(7, 'SofiaCook',     8000, NULL, NULL),
(8, 'RuneTrader', 1200000, NULL, NULL);

INSERT INTO skills (nome, tipo) VALUES
('Attack', 'combate'), ('Strength', 'combate'), ('Defence', 'combate'), ('Magic', 'combate'),
('Mining', 'coleta'),  ('Fishing', 'coleta'),   ('Woodcutting', 'coleta'),
('Cooking', 'producao'), ('Smithing', 'producao');

-- Cada personagem recebe todas as skills; os níveis variam por personagem
-- (XP calculado de forma simplificada a partir do nível)
INSERT INTO personagem_skills (id_personagem, id_skill, nivel, xp)
SELECT p.id_personagem,
       s.id_skill,
       n.nivel,
       (n.nivel * n.nivel * 100)                       -- fórmula simplificada de XP
FROM personagens p
CROSS JOIN skills s
CROSS JOIN LATERAL (SELECT (1 + (p.id_personagem * 17 + s.id_skill * 29) % 99)::SMALLINT AS nivel) n;

INSERT INTO itens (nome, tipo, apenas_membros, empilhavel, valor_base) VALUES
('Bronze sword',     'arma',       FALSE, FALSE,     30),
('Rune scimitar',    'arma',       FALSE, FALSE,  25000),
('Abyssal whip',     'arma',       TRUE,  FALSE, 1500000),
('Dragon platebody', 'armadura',   TRUE,  FALSE, 8000000),
('Iron ore',         'recurso',    FALSE, TRUE,      90),
('Coal',             'recurso',    FALSE, TRUE,     150),
('Raw lobster',      'recurso',    FALSE, TRUE,     200),
('Lobster',          'consumivel', FALSE, TRUE,     250),
('Yew logs',         'recurso',    FALSE, TRUE,     300),
('Quest scroll',     'missao',     FALSE, FALSE,      0);

INSERT INTO inventario (id_personagem, id_item, local, slot, quantidade) VALUES
(1, 3, 'equipado', NULL, 1),   -- Zezinho usa Abyssal whip
(1, 8, 'mochila',  0,   20),   -- 20 lobsters na mochila
(1, 4, 'banco',    NULL, 1),
(2, 2, 'equipado', NULL, 1),
(2, 5, 'mochila',  0,  300),
(2, 6, 'mochila',  1,  500),
(2, 5, 'banco',    NULL, 2000),
(3, 1, 'equipado', NULL, 1),
(4, 9, 'banco',    NULL, 800),
(5, 7, 'mochila',  0,   26),
(6, 2, 'equipado', NULL, 1),
(7, 8, 'mochila',  0,    5),
(8, 9, 'banco',    NULL, 15000);

INSERT INTO quests (nome, dificuldade, id_skill_requisito, nivel_minimo, recompensa_moedas, apenas_membros) VALUES
('Cook''s Assistant',     'facil',   8,  1,   500,  FALSE),
('Doric''s Quest',        'facil',   5, 15,  1800,  FALSE),
('Dragon Slayer',         'dificil', 1, 40, 50000,  FALSE),
('Fishing Contest',       'media',   6, 10,  5000,  TRUE),
('The Knight''s Sword',   'media',   9, 10, 12000,  FALSE);

INSERT INTO personagem_quests (id_personagem, id_quest, status, concluida_em) VALUES
(1, 1, 'concluida',    '2026-10-01 10:00'),
(1, 3, 'concluida',    '2026-10-15 21:30'),
(2, 2, 'concluida',    '2026-10-03 18:00'),
(2, 5, 'em_andamento', NULL),
(3, 1, 'em_andamento', NULL),
(5, 4, 'concluida',    '2026-10-20 14:10'),
(6, 2, 'em_andamento', NULL);

INSERT INTO ge_ofertas (id_personagem, id_item, tipo, quantidade, quantidade_executada, preco_unitario, status) VALUES
(2, 5, 'venda',  1000, 1000,   95, 'concluida'),
(2, 6, 'venda',   500,  500,  160, 'concluida'),
(4, 9, 'venda',   300,  300,  310, 'concluida'),
(8, 9, 'venda',  5000, 5000,  280, 'concluida'),
(5, 7, 'venda',   200,  200,  210, 'concluida'),
(1, 2, 'venda',     1,    1, 26000, 'concluida'),
(6, 5, 'compra',  400,    0,   92, 'aberta'),
(3, 8, 'compra',   50,    0,  240, 'aberta'),
(2, 8, 'venda',    10,    0,  260, 'aberta'),     -- usada na transação da PARTE 6
(7, 7, 'venda',    20,    0,  500, 'cancelada');

INSERT INTO logs_atividade (id_personagem, tipo_evento, descricao) VALUES
(1, 'login',        'Login no mundo 301'),
(2, 'compra_ge',    'Vendeu 1000 Iron ore'),
(8, 'login',        'Login no mundo 302'),
(8, 'compra_ge',    'Vendeu 5000 Yew logs'),
(3, 'item_perdido', 'Morreu no Wilderness e perdeu Rune scimitar'),
(1, 'quest',        'Concluiu Dragon Slayer');

-- --- Operações do dia a dia (UPDATE / DELETE) ---

-- Personagem ganha XP em Mining após minerar
UPDATE personagem_skills
SET xp = xp + 350
WHERE id_personagem = 2 AND id_skill = 5;

-- Conta comprou assinatura: passa de F2P para P2P
UPDATE contas SET tipo_conta = 'P2P' WHERE id_conta = 3;

-- Remover ofertas canceladas do mercado
DELETE FROM ge_ofertas WHERE status = 'cancelada';


-- =====================================================================
--  PARTE 4 - DCL: PERFIS DE ACESSO (GRANT / REVOKE)
-- =====================================================================
-- Os perfis são criados como "grupos" (NOLOGIN). Cada pessoa real recebe
-- um usuário com LOGIN que herda as permissões do grupo.
-- Jogadores NÃO têm usuário no banco: acessam só pela aplicação (app_server).

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_jogo')  THEN CREATE ROLE admin_jogo  NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'moderador')   THEN CREATE ROLE moderador   NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'game_master') THEN CREATE ROLE game_master NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_server')  THEN CREATE ROLE app_server  NOLOGIN; END IF;
END $$;

-- Ninguém tem acesso por padrão
REVOKE ALL ON ALL TABLES IN SCHEMA mmo FROM PUBLIC;
GRANT USAGE ON SCHEMA mmo TO admin_jogo, moderador, game_master, app_server;

-- ADMINISTRADOR: acesso total
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA mmo TO admin_jogo;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA mmo TO admin_jogo;

-- MODERADOR: consulta jogadores (sem email/senha) e aplica penalidades
GRANT SELECT ON vw_jogador_publico, vw_ranking TO moderador;
GRANT SELECT, INSERT ON penalidades TO moderador;
GRANT USAGE ON SEQUENCE penalidades_id_penalidade_seq TO moderador;
-- permissão por COLUNA: vê e altera só o status da conta, nunca o email ou a senha
GRANT SELECT (id_conta, status) ON contas TO moderador;
GRANT UPDATE (status)           ON contas TO moderador;

-- GAME MASTER (suporte): vê histórico, mercado e inventário; restaura itens perdidos
GRANT SELECT ON logs_atividade, ge_ofertas, inventario, itens, vw_jogador_publico TO game_master;
GRANT INSERT ON inventario TO game_master;
GRANT USAGE ON SEQUENCE inventario_id_inventario_seq TO game_master;

-- SERVIDOR DA APLICAÇÃO: operações do jogo (inventário, skills, quests, mercado)
GRANT SELECT ON contas, clas, skills, itens, quests TO app_server;
GRANT SELECT, INSERT, UPDATE         ON personagens, personagem_skills, personagem_quests, ge_ofertas TO app_server;
GRANT SELECT, INSERT, UPDATE, DELETE ON inventario TO app_server;
GRANT INSERT ON logs_atividade TO app_server;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA mmo TO app_server;

-- REVOKE: o servidor não pode alterar nem apagar logs (preserva a auditoria)
REVOKE UPDATE, DELETE ON logs_atividade FROM app_server;

-- Funções nascem executáveis por todos (PUBLIC) no PostgreSQL: retira e libera só a quem compra
REVOKE EXECUTE ON FUNCTION comprar_oferta(BIGINT, BIGINT, INT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION comprar_oferta(BIGINT, BIGINT, INT) TO app_server, admin_jogo;

-- Usuários reais (exemplo)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mod_ana') THEN
        CREATE USER mod_ana WITH PASSWORD 'troque_esta_senha' IN ROLE moderador;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gm_carlos') THEN
        CREATE USER gm_carlos WITH PASSWORD 'troque_esta_senha' IN ROLE game_master;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'servidor_br') THEN
        CREATE USER servidor_br WITH PASSWORD 'troque_esta_senha' IN ROLE app_server;
    END IF;
END $$;


-- =====================================================================
--  PARTE 5 - CONSULTAS (operações reais do sistema)
-- =====================================================================

-- C1. Top 5 do ranking geral (usa a VIEW)
SELECT * FROM vw_ranking WHERE posicao <= 5;

-- C2. Inventário completo de um personagem (JOIN)
SELECT p.nome AS personagem, i.nome AS item, inv.local, inv.slot, inv.quantidade
FROM inventario inv
JOIN personagens p ON p.id_personagem = inv.id_personagem
JOIN itens i       ON i.id_item       = inv.id_item
WHERE p.nome = 'Camelo'
ORDER BY inv.local, inv.slot;

-- C3. Quantidade de membros por clã (GROUP BY + COUNT + HAVING)
SELECT cl.nome AS cla, COUNT(p.id_personagem) AS membros
FROM clas cl
JOIN personagens p ON p.id_cla = cl.id_cla
GROUP BY cl.nome
HAVING COUNT(p.id_personagem) >= 2
ORDER BY membros DESC;

-- C4. Itens mais negociados no mercado (usa a VIEW de preço médio)
SELECT * FROM vw_preco_medio_mercado ORDER BY unidades_vendidas DESC;

-- C5. Média de nível total dos jogadores por região (AVG + GROUP BY)
SELECT c.regiao, COUNT(*) AS jogadores, ROUND(AVG(r.nivel_total), 1) AS media_nivel_total
FROM vw_ranking r
JOIN personagens p ON p.nome = r.personagem
JOIN contas c      ON c.id_conta = p.id_conta
GROUP BY c.regiao
ORDER BY media_nivel_total DESC;

-- C6. Situação de cada quest para um personagem (JOIN + LEFT JOIN + CASE)
--     Mostra se a quest já foi concluída, se está disponível ou por que está bloqueada
SELECT q.nome          AS quest,
       s.nome          AS skill_exigida,
       q.nivel_minimo,
       ps.nivel        AS nivel_atual,
       CASE
           WHEN pq.status = 'concluida'                       THEN 'Concluida'
           WHEN q.apenas_membros AND c.tipo_conta = 'F2P'     THEN 'Bloqueada: so membros'
           WHEN ps.nivel < q.nivel_minimo                     THEN 'Bloqueada: nivel baixo'
           ELSE 'Disponivel'
       END             AS situacao
FROM quests q
JOIN skills s             ON s.id_skill = q.id_skill_requisito
JOIN personagens p        ON p.nome = 'AnnaFish'
JOIN contas c             ON c.id_conta = p.id_conta
JOIN personagem_skills ps ON ps.id_personagem = p.id_personagem AND ps.id_skill = q.id_skill_requisito
LEFT JOIN personagem_quests pq ON pq.id_personagem = p.id_personagem AND pq.id_quest = q.id_quest
ORDER BY q.nivel_minimo, q.nome;

-- Moderador aplica uma penalidade (ex.: ofensas no chat)
INSERT INTO penalidades (id_conta, tipo, motivo, fim)
VALUES (8, 'suspensao', 'Ofensas repetidas no chat', CURRENT_TIMESTAMP + INTERVAL '3 days');
UPDATE contas SET status = 'suspensa' WHERE id_conta = 8;

-- C7. Contas com penalidade ativa
SELECT c.id_conta, p.nome, pe.tipo, pe.motivo, pe.fim
FROM penalidades pe
JOIN contas c      ON c.id_conta = pe.id_conta
JOIN personagens p ON p.id_conta = c.id_conta
WHERE pe.fim IS NULL OR pe.fim > CURRENT_TIMESTAMP;


-- =====================================================================
--  PARTE 6 - TRANSAÇÃO: compra no mercado (Grand Exchange)
-- =====================================================================
-- JoelKnight (id 3) compra 10 Lobsters do Camelo (id 2), oferta nº 9, por 260 cada.
-- SERIALIZABLE + FOR UPDATE: se duas compras disputarem a mesma oferta ao mesmo
-- tempo, o PostgreSQL deixa só uma terminar e cancela a outra (erro 40001).
-- Se qualquer regra falhar, a função gera erro e a transação inteira é desfeita.

BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    SELECT comprar_oferta(3, 9, 10);
COMMIT;

-- Repetir a mesma compra agora é recusado (a oferta já está concluída):
--   ERROR: A oferta 9 não está aberta para venda   (código MMO01)

-- Consultas de visualização (ranking, perfis) não precisam de tanto rigor:
-- usam o padrão READ COMMITTED, que é mais leve.
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
    SELECT * FROM vw_ranking;
COMMIT;


-- =====================================================================
--  PARTE 7 - DEMONSTRAÇÃO: o banco BLOQUEANDO operações indevidas
--  (comentado porque cada linha gera um ERRO de propósito;
--   descomente uma por vez para mostrar na apresentação)
-- =====================================================================

-- Moderador tentando ver o email dos jogadores  -> ERROR: permission denied for table contas
-- SET ROLE mod_ana;  SELECT email FROM contas;  RESET ROLE;

-- Servidor do jogo tentando apagar os logs     -> ERROR: permission denied for table logs_atividade
-- SET ROLE servidor_br;  DELETE FROM logs_atividade;  RESET ROLE;

-- Item no espaço 28 da mochila (só existe 0-27) -> viola ck_slot_mochila
-- INSERT INTO inventario (id_personagem, id_item, local, slot, quantidade) VALUES (1, 5, 'mochila', 28, 1);

-- Skill com nível 0 (permitido: 1 a 99)          -> viola personagem_skills_nivel_check
-- INSERT INTO personagem_skills VALUES (1, 1, 0, 120);

-- Saldo de moedas negativo                       -> viola personagens_moedas_check
-- UPDATE personagens SET moedas = moedas - 99999999 WHERE id_personagem = 7;

-- Segundo personagem na mesma conta              -> viola UNIQUE (id_conta)
-- INSERT INTO personagens (id_conta, nome) VALUES (1, 'Outro');

-- Equipar o mesmo item duas vezes               -> viola uq_equipado_item
-- INSERT INTO inventario (id_personagem, id_item, local, slot, quantidade) VALUES (1, 3, 'equipado', NULL, 1);

-- Apagar um clã que ainda tem membros            -> viola a chave estrangeira (RESTRICT)
-- DELETE FROM clas WHERE id_cla = 1;

-- Repetir uma compra já concluída                -> MMO01: a oferta não está aberta
-- BEGIN ISOLATION LEVEL SERIALIZABLE; SELECT comprar_oferta(3, 9, 10); COMMIT;

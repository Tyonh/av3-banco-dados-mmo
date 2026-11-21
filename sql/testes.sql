-- =====================================================================
--  AV3 - Banco de Dados de um MMO
--  TESTES AUTOMATIZADOS (PostgreSQL 16)
--
--  Como usar: rode primeiro mmo_banco.sql e depois este arquivo.
--  Cada teste executa um comando e compara o resultado com o esperado:
--    - "ok"              -> o comando deve funcionar
--    - um código de erro -> o banco deve recusar o comando com esse erro
--  Todo teste é desfeito no final (ROLLBACK), então os dados não mudam.
--
--  Códigos de erro usados:
--    23505 = violação de UNIQUE        23514 = violação de CHECK
--    23503 = violação de chave estrangeira
--    42501 = sem permissão (GRANT/REVOKE)
--    MMO01..MMO06 = regras da compra no mercado (função comprar_oferta)
-- =====================================================================

DROP SCHEMA IF EXISTS testes CASCADE;
CREATE SCHEMA testes;

CREATE TABLE testes.resultado (
    n         INT GENERATED ALWAYS AS IDENTITY,
    grupo     TEXT,
    teste     TEXT,
    esperado  TEXT,
    obtido    TEXT,
    passou    BOOLEAN,
    mensagem  TEXT
);

-- Os perfis testados (moderador, game master, servidor) precisam enxergar as funções de teste
GRANT USAGE ON SCHEMA testes TO PUBLIC;

-- Afirma que uma condição é verdadeira; se não for, gera o erro TT001
CREATE FUNCTION testes.afirma(condicao BOOLEAN, descricao TEXT) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    IF condicao IS NOT TRUE THEN
        RAISE EXCEPTION 'Afirmação falhou: %', descricao USING ERRCODE = 'TT001';
    END IF;
END $$;

-- Executa o comando, registra o resultado e desfaz tudo o que ele fez
CREATE FUNCTION testes.caso(p_grupo TEXT, p_teste TEXT, p_comando TEXT, p_esperado TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_estado TEXT;
    v_msg    TEXT;
BEGIN
    BEGIN
        EXECUTE p_comando;
        -- chegou aqui = funcionou; força um erro "sentinela" para desfazer o teste
        RAISE EXCEPTION 'sentinela' USING ERRCODE = 'TT000';
    EXCEPTION WHEN OTHERS THEN
        v_estado := SQLSTATE;
        v_msg    := SQLERRM;
    END;

    INSERT INTO testes.resultado (grupo, teste, esperado, obtido, passou, mensagem)
    VALUES (p_grupo, p_teste,
            COALESCE(p_esperado, 'ok'),
            CASE WHEN v_estado = 'TT000' THEN 'ok' ELSE v_estado END,
            COALESCE((p_esperado IS NULL AND v_estado = 'TT000') OR v_estado = p_esperado, FALSE),
            CASE WHEN v_estado = 'TT000' THEN NULL ELSE v_msg END);
END $$;


-- =====================================================================
--  1. RESTRIÇÕES (constraints) - seção 2.4 do relatório
-- =====================================================================
SELECT testes.caso('1 Restrições', 'Uma conta só tem um personagem',
  $q$INSERT INTO mmo.personagens (id_conta, nome) VALUES (1, 'Outro')$q$, '23505');

SELECT testes.caso('1 Restrições', 'Nome de personagem não se repete',
  $q$INSERT INTO mmo.contas (email, senha_hash, regiao) VALUES ('novo@email.com', 'h', 'BR');
     INSERT INTO mmo.personagens (id_conta, nome)
     VALUES ((SELECT id_conta FROM mmo.contas WHERE email = 'novo@email.com'), 'Camelo')$q$, '23505');

SELECT testes.caso('1 Restrições', 'Email de conta não se repete',
  $q$INSERT INTO mmo.contas (email, senha_hash, regiao) VALUES ('lucas@email.com', 'h', 'BR')$q$, '23505');

SELECT testes.caso('1 Restrições', 'Saldo de moedas não fica negativo',
  $q$UPDATE mmo.personagens SET moedas = -1 WHERE id_personagem = 7$q$, '23514');

SELECT testes.caso('1 Restrições', 'Nível de skill não pode ser 0',
  $q$UPDATE mmo.personagem_skills SET nivel = 0 WHERE id_personagem = 1 AND id_skill = 1$q$, '23514');

SELECT testes.caso('1 Restrições', 'Nível de skill não pode passar de 99',
  $q$UPDATE mmo.personagem_skills SET nivel = 100 WHERE id_personagem = 1 AND id_skill = 1$q$, '23514');

SELECT testes.caso('1 Restrições', 'Nível 99 é aceito',
  $q$UPDATE mmo.personagem_skills SET nivel = 99 WHERE id_personagem = 1 AND id_skill = 1$q$);

SELECT testes.caso('1 Restrições', 'Mochila não tem espaço 28 (só 0 a 27)',
  $q$INSERT INTO mmo.inventario (id_personagem, id_item, local, slot, quantidade) VALUES (1, 5, 'mochila', 28, 1)$q$, '23514');

SELECT testes.caso('1 Restrições', 'Espaço 27 da mochila é aceito',
  $q$INSERT INTO mmo.inventario (id_personagem, id_item, local, slot, quantidade) VALUES (1, 5, 'mochila', 27, 1)$q$);

SELECT testes.caso('1 Restrições', 'Item na mochila precisa de espaço definido',
  $q$INSERT INTO mmo.inventario (id_personagem, id_item, local, slot, quantidade) VALUES (1, 5, 'mochila', NULL, 1)$q$, '23514');

SELECT testes.caso('1 Restrições', 'Dois itens não ocupam o mesmo espaço da mochila',
  $q$INSERT INTO mmo.inventario (id_personagem, id_item, local, slot, quantidade) VALUES (1, 5, 'mochila', 0, 1)$q$, '23505');

SELECT testes.caso('1 Restrições', 'Banco e equipamento não usam espaço numerado',
  $q$INSERT INTO mmo.inventario (id_personagem, id_item, local, slot, quantidade) VALUES (1, 5, 'banco', 3, 1)$q$, '23514');

SELECT testes.caso('1 Restrições', 'Mesmo item não é equipado duas vezes',
  $q$INSERT INTO mmo.inventario (id_personagem, id_item, local, slot, quantidade) VALUES (1, 3, 'equipado', NULL, 1)$q$, '23505');

SELECT testes.caso('1 Restrições', 'Banco agrupa itens iguais em uma linha só',
  $q$INSERT INTO mmo.inventario (id_personagem, id_item, local, slot, quantidade) VALUES (2, 5, 'banco', NULL, 10)$q$, '23505');

SELECT testes.caso('1 Restrições', 'Quantidade de item precisa ser maior que zero',
  $q$INSERT INTO mmo.inventario (id_personagem, id_item, local, slot, quantidade) VALUES (1, 6, 'banco', NULL, 0)$q$, '23514');

SELECT testes.caso('1 Restrições', 'Membro de clã precisa ter cargo',
  $q$UPDATE mmo.personagens SET id_cla = 1, cargo_cla = NULL WHERE id_personagem = 7$q$, '23514');

SELECT testes.caso('1 Restrições', 'Quem não está em clã não tem cargo',
  $q$UPDATE mmo.personagens SET id_cla = NULL, cargo_cla = 'membro' WHERE id_personagem = 7$q$, '23514');

SELECT testes.caso('1 Restrições', 'Clã com membros não pode ser apagado',
  $q$DELETE FROM mmo.clas WHERE id_cla = 1$q$, '23503');

SELECT testes.caso('1 Restrições', 'Clã sem membros pode ser apagado',
  $q$DELETE FROM mmo.clas WHERE id_cla = 3 AND NOT EXISTS (SELECT 1 FROM mmo.personagens WHERE id_cla = 3);
     UPDATE mmo.personagens SET id_cla = NULL, cargo_cla = NULL WHERE id_cla = 3;
     DELETE FROM mmo.clas WHERE id_cla = 3;
     SELECT testes.afirma(NOT EXISTS (SELECT 1 FROM mmo.clas WHERE id_cla = 3), 'clã 3 ainda existe')$q$);

SELECT testes.caso('1 Restrições', 'Oferta não executa mais do que anunciou',
  $q$UPDATE mmo.ge_ofertas SET quantidade_executada = quantidade + 1 WHERE id_oferta = 7$q$, '23514');

SELECT testes.caso('1 Restrições', 'Oferta não tem preço zero',
  $q$UPDATE mmo.ge_ofertas SET preco_unitario = 0 WHERE id_oferta = 7$q$, '23514');

SELECT testes.caso('1 Restrições', 'Quest concluída precisa de data de conclusão',
  $q$UPDATE mmo.personagem_quests SET status = 'concluida', concluida_em = NULL
     WHERE id_personagem = 2 AND id_quest = 5$q$, '23514');

SELECT testes.caso('1 Restrições', 'Fim da penalidade vem depois do início',
  $q$INSERT INTO mmo.penalidades (id_conta, tipo, motivo, fim)
     VALUES (1, 'mute', 'teste', CURRENT_TIMESTAMP - INTERVAL '1 day')$q$, '23514');

SELECT testes.caso('1 Restrições', 'Item inexistente não entra no inventário (FK)',
  $q$INSERT INTO mmo.inventario (id_personagem, id_item, local, slot, quantidade) VALUES (1, 9999, 'banco', NULL, 1)$q$, '23503');

SELECT testes.caso('1 Restrições', 'Apagar a conta apaga o personagem e seus dados (CASCADE)',
  $q$DELETE FROM mmo.contas WHERE id_conta = 7;
     SELECT testes.afirma(NOT EXISTS (SELECT 1 FROM mmo.personagens WHERE id_conta = 7), 'personagem não foi apagado');
     SELECT testes.afirma(NOT EXISTS (SELECT 1 FROM mmo.inventario WHERE id_personagem = 7), 'inventário não foi apagado');
     SELECT testes.afirma(NOT EXISTS (SELECT 1 FROM mmo.personagem_skills WHERE id_personagem = 7), 'skills não foram apagadas')$q$);

SELECT testes.caso('1 Restrições', 'Apagar personagem preserva os logs (SET NULL)',
  $q$SELECT testes.afirma(EXISTS (SELECT 1 FROM mmo.logs_atividade WHERE id_personagem = 3), 'sem log para testar');
     DELETE FROM mmo.contas WHERE id_conta = 3;
     SELECT testes.afirma(EXISTS (SELECT 1 FROM mmo.logs_atividade WHERE id_personagem IS NULL), 'log foi apagado junto')$q$);


-- =====================================================================
--  2. ESTRUTURA DO MODELO - checklist de modelagem
-- =====================================================================
SELECT testes.caso('2 Estrutura', 'Toda tabela tem chave primária',
  $q$SELECT testes.afirma(NOT EXISTS (
       SELECT 1 FROM pg_class t
       WHERE t.relnamespace = 'mmo'::regnamespace AND t.relkind = 'r'
         AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = t.oid AND c.contype = 'p')),
     'existe tabela sem PK')$q$);

SELECT testes.caso('2 Estrutura', 'Toda chave estrangeira tem índice',
  $q$SELECT testes.afirma(NOT EXISTS (
       SELECT 1 FROM pg_constraint c
       WHERE c.contype = 'f' AND c.connamespace = 'mmo'::regnamespace
         AND NOT EXISTS (SELECT 1 FROM pg_index i
                         WHERE i.indrelid = c.conrelid AND i.indkey[0] = c.conkey[1])),
     'existe FK sem índice')$q$);

SELECT testes.caso('2 Estrutura', 'Datas guardam fuso horário (multi-região)',
  $q$SELECT testes.afirma(NOT EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'mmo' AND data_type = 'timestamp without time zone'
         AND table_name NOT LIKE 'vw\_%'),
     'existe coluna TIMESTAMP sem fuso')$q$);


-- =====================================================================
--  3. CONSISTÊNCIA DOS DADOS DE EXEMPLO
-- =====================================================================
SELECT testes.caso('3 Dados', 'Conta gratuita (F2P) não tem item de membros',
  $q$SELECT testes.afirma(NOT EXISTS (
       SELECT 1 FROM mmo.inventario inv
       JOIN mmo.itens i ON i.id_item = inv.id_item
       JOIN mmo.personagens p ON p.id_personagem = inv.id_personagem
       JOIN mmo.contas c ON c.id_conta = p.id_conta
       WHERE i.apenas_membros AND c.tipo_conta = 'F2P'), 'F2P com item de membros')$q$);

SELECT testes.caso('3 Dados', 'Conta gratuita (F2P) não faz quest de membros',
  $q$SELECT testes.afirma(NOT EXISTS (
       SELECT 1 FROM mmo.personagem_quests pq
       JOIN mmo.quests q ON q.id_quest = pq.id_quest
       JOIN mmo.personagens p ON p.id_personagem = pq.id_personagem
       JOIN mmo.contas c ON c.id_conta = p.id_conta
       WHERE q.apenas_membros AND c.tipo_conta = 'F2P'), 'F2P em quest de membros')$q$);

SELECT testes.caso('3 Dados', 'Ninguém começou quest sem o nível exigido',
  $q$SELECT testes.afirma(NOT EXISTS (
       SELECT 1 FROM mmo.personagem_quests pq
       JOIN mmo.quests q ON q.id_quest = pq.id_quest
       JOIN mmo.personagem_skills ps ON ps.id_personagem = pq.id_personagem
                                    AND ps.id_skill = q.id_skill_requisito
       WHERE ps.nivel < q.nivel_minimo), 'quest iniciada abaixo do nível')$q$);


-- =====================================================================
--  4. VIEWS - seção 2.5
-- =====================================================================
SELECT testes.caso('4 Views', 'vw_jogador_publico não mostra email nem senha',
  $q$SELECT testes.afirma(NOT EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'mmo' AND table_name = 'vw_jogador_publico'
         AND column_name IN ('email', 'senha_hash')), 'view expõe dado sensível')$q$);

SELECT testes.caso('4 Views', 'vw_ranking lista todos os personagens',
  $q$SELECT testes.afirma((SELECT COUNT(*) FROM mmo.vw_ranking) = (SELECT COUNT(*) FROM mmo.personagens),
     'ranking com número diferente de personagens')$q$);


-- =====================================================================
--  5. PERMISSÕES (DCL) - seção 5.1
-- =====================================================================
SELECT testes.caso('5 Permissões', 'Moderador consulta jogadores pela view',
  $q$SET LOCAL ROLE mod_ana; SELECT COUNT(*) FROM mmo.vw_jogador_publico$q$);

SELECT testes.caso('5 Permissões', 'Moderador não lê email dos jogadores',
  $q$SET LOCAL ROLE mod_ana; SELECT email FROM mmo.contas$q$, '42501');

SELECT testes.caso('5 Permissões', 'Moderador não altera email',
  $q$SET LOCAL ROLE mod_ana; UPDATE mmo.contas SET email = 'x@x.com' WHERE id_conta = 1$q$, '42501');

SELECT testes.caso('5 Permissões', 'Moderador aplica penalidade e o banco registra quem foi',
  $q$SET LOCAL ROLE mod_ana;
     INSERT INTO mmo.penalidades (id_conta, tipo, motivo) VALUES (6, 'aviso', 'teste');
     UPDATE mmo.contas SET status = 'suspensa' WHERE id_conta = 6;
     SELECT testes.afirma((SELECT aplicada_por FROM mmo.penalidades ORDER BY id_penalidade DESC LIMIT 1) = 'mod_ana',
                          'aplicada_por diferente de mod_ana')$q$);

SELECT testes.caso('5 Permissões', 'Moderador não altera a estrutura do banco',
  $q$SET LOCAL ROLE mod_ana; ALTER TABLE mmo.personagens ADD COLUMN x INT$q$, '42501');

SELECT testes.caso('5 Permissões', 'Game Master consulta logs e mercado',
  $q$SET LOCAL ROLE gm_carlos; SELECT COUNT(*) FROM mmo.logs_atividade; SELECT COUNT(*) FROM mmo.ge_ofertas$q$);

SELECT testes.caso('5 Permissões', 'Game Master restaura item perdido',
  $q$SET LOCAL ROLE gm_carlos;
     INSERT INTO mmo.inventario (id_personagem, id_item, local, slot, quantidade) VALUES (3, 2, 'banco', NULL, 1)$q$);

SELECT testes.caso('5 Permissões', 'Game Master não altera contas',
  $q$SET LOCAL ROLE gm_carlos; UPDATE mmo.contas SET status = 'ativa'$q$, '42501');

SELECT testes.caso('5 Permissões', 'Game Master não apaga logs',
  $q$SET LOCAL ROLE gm_carlos; DELETE FROM mmo.logs_atividade$q$, '42501');

SELECT testes.caso('5 Permissões', 'Servidor do jogo atualiza inventário e skills',
  $q$SET LOCAL ROLE servidor_br;
     UPDATE mmo.inventario SET quantidade = quantidade + 1 WHERE id_personagem = 1 AND local = 'mochila' AND slot = 0;
     UPDATE mmo.personagem_skills SET xp = xp + 10 WHERE id_personagem = 1 AND id_skill = 5$q$);

SELECT testes.caso('5 Permissões', 'Servidor do jogo registra log',
  $q$SET LOCAL ROLE servidor_br;
     INSERT INTO mmo.logs_atividade (id_personagem, tipo_evento, descricao) VALUES (1, 'login', 'teste')$q$);

SELECT testes.caso('5 Permissões', 'Servidor do jogo não apaga logs',
  $q$SET LOCAL ROLE servidor_br; DELETE FROM mmo.logs_atividade$q$, '42501');

SELECT testes.caso('5 Permissões', 'Servidor do jogo não altera logs',
  $q$SET LOCAL ROLE servidor_br; UPDATE mmo.logs_atividade SET descricao = 'x'$q$, '42501');

SELECT testes.caso('5 Permissões', 'Servidor do jogo não aplica penalidade',
  $q$SET LOCAL ROLE servidor_br; INSERT INTO mmo.penalidades (id_conta, tipo, motivo) VALUES (1, 'aviso', 'x')$q$, '42501');

SELECT testes.caso('5 Permissões', 'Nenhuma tabela liberada para PUBLIC',
  $q$SELECT testes.afirma(NOT EXISTS (
       SELECT 1 FROM information_schema.role_table_grants
       WHERE grantee = 'PUBLIC' AND table_schema = 'mmo'), 'tabela acessível por PUBLIC')$q$);

SELECT testes.caso('5 Permissões', 'Game Master não executa compras',
  $q$SET LOCAL ROLE gm_carlos; SELECT mmo.comprar_oferta(3, 9, 1)$q$, '42501');


-- =====================================================================
--  6. COMPRA NO MERCADO E ISOLAMENTO - seção 5.3
--     Cada teste cria a própria oferta: o Camelo (id 2) anuncia
--     10 Lobsters (item 8) por 260 cada. Assim o teste não depende
--     do estado em que o script principal deixou as ofertas.
-- =====================================================================
CREATE FUNCTION testes.nova_oferta() RETURNS BIGINT LANGUAGE sql AS $f$
    INSERT INTO mmo.ge_ofertas (id_personagem, id_item, tipo, quantidade, preco_unitario)
    VALUES (2, 8, 'venda', 10, 260) RETURNING id_oferta;
$f$;
CREATE FUNCTION testes.ultima_oferta() RETURNS BIGINT LANGUAGE sql AS $f$
    SELECT MAX(id_oferta) FROM mmo.ge_ofertas;
$f$;
-- guarda moedas e itens antes da compra, para comparar depois
CREATE FUNCTION testes.foto() RETURNS VOID LANGUAGE sql AS $f$
    CREATE TEMP TABLE IF NOT EXISTS foto AS
    SELECT (SELECT moedas FROM mmo.personagens WHERE id_personagem = 3) AS moedas_comprador,
           (SELECT moedas FROM mmo.personagens WHERE id_personagem = 2) AS moedas_vendedor,
           COALESCE((SELECT quantidade FROM mmo.inventario
                     WHERE id_personagem = 3 AND id_item = 8 AND local = 'banco'), 0) AS lobsters;
$f$;

SELECT testes.caso('6 Compra', 'Compra fora de SERIALIZABLE é recusada',
  $q$SELECT testes.nova_oferta(); SELECT mmo.comprar_oferta(3, testes.ultima_oferta(), 10)$q$, 'MMO06');

BEGIN ISOLATION LEVEL SERIALIZABLE;

SELECT testes.caso('6 Compra', 'Compra válida move moedas, item, oferta e log',
  $q$SELECT testes.nova_oferta(); SELECT testes.foto();
     SELECT mmo.comprar_oferta(3, testes.ultima_oferta(), 10);
     SELECT testes.afirma((SELECT moedas FROM mmo.personagens WHERE id_personagem = 3) = (SELECT moedas_comprador FROM foto) - 2600, 'comprador não pagou 2600');
     SELECT testes.afirma((SELECT moedas FROM mmo.personagens WHERE id_personagem = 2) = (SELECT moedas_vendedor FROM foto) + 2600, 'vendedor não recebeu 2600');
     SELECT testes.afirma((SELECT quantidade FROM mmo.inventario WHERE id_personagem = 3 AND id_item = 8 AND local = 'banco') = (SELECT lobsters FROM foto) + 10, 'itens não entregues');
     SELECT testes.afirma((SELECT status FROM mmo.ge_ofertas WHERE id_oferta = testes.ultima_oferta()) = 'concluida', 'oferta não concluída');
     SELECT testes.afirma((SELECT descricao FROM mmo.logs_atividade ORDER BY id_log DESC LIMIT 1) LIKE 'Comprou 10 %', 'sem log')$q$);

SELECT testes.caso('6 Compra', 'Servidor do jogo consegue executar a compra',
  $q$SELECT testes.nova_oferta(); SET LOCAL ROLE servidor_br;
     SELECT mmo.comprar_oferta(3, testes.ultima_oferta(), 10)$q$);

SELECT testes.caso('6 Compra', 'Repetir a mesma compra é recusado (sem duplicar)',
  $q$SELECT testes.nova_oferta();
     SELECT mmo.comprar_oferta(3, testes.ultima_oferta(), 10);
     SELECT mmo.comprar_oferta(3, testes.ultima_oferta(), 10)$q$, 'MMO01');

SELECT testes.caso('6 Compra', 'Compra parcial deixa a oferta aberta',
  $q$SELECT testes.nova_oferta();
     SELECT mmo.comprar_oferta(3, testes.ultima_oferta(), 4);
     SELECT testes.afirma((SELECT quantidade_executada FROM mmo.ge_ofertas WHERE id_oferta = testes.ultima_oferta()) = 4, 'executada diferente de 4');
     SELECT testes.afirma((SELECT status FROM mmo.ge_ofertas WHERE id_oferta = testes.ultima_oferta()) = 'aberta', 'oferta fechou antes da hora')$q$);

SELECT testes.caso('6 Compra', 'Não compra mais do que a oferta tem',
  $q$SELECT testes.nova_oferta(); SELECT mmo.comprar_oferta(3, testes.ultima_oferta(), 11)$q$, 'MMO02');

SELECT testes.caso('6 Compra', 'Não compra sem moedas suficientes',
  $q$SELECT testes.nova_oferta();
     UPDATE mmo.personagens SET moedas = 100 WHERE id_personagem = 3;
     SELECT mmo.comprar_oferta(3, testes.ultima_oferta(), 10)$q$, 'MMO03');

SELECT testes.caso('6 Compra', 'Compra recusada não altera nada',
  $q$SELECT testes.nova_oferta(); SELECT testes.foto();
     UPDATE mmo.personagens SET moedas = 100 WHERE id_personagem = 3;
     DO $d$ BEGIN
         PERFORM mmo.comprar_oferta(3, testes.ultima_oferta(), 10);
     EXCEPTION WHEN SQLSTATE 'MMO03' THEN NULL;  -- erro esperado; confere o estado depois
     END $d$;
     SELECT testes.afirma((SELECT moedas FROM mmo.personagens WHERE id_personagem = 2) = (SELECT moedas_vendedor FROM foto), 'vendedor recebeu moedas');
     SELECT testes.afirma(COALESCE((SELECT quantidade FROM mmo.inventario WHERE id_personagem = 3 AND id_item = 8 AND local = 'banco'), 0) = (SELECT lobsters FROM foto), 'item entregue');
     SELECT testes.afirma((SELECT status FROM mmo.ge_ofertas WHERE id_oferta = testes.ultima_oferta()) = 'aberta', 'oferta mudou')$q$);

SELECT testes.caso('6 Compra', 'Conta gratuita não compra item de membros',
  $q$INSERT INTO mmo.ge_ofertas (id_personagem, id_item, tipo, quantidade, preco_unitario)
     VALUES (1, 3, 'venda', 1, 1500000);
     UPDATE mmo.personagens SET moedas = 9000000 WHERE id_personagem = 8;
     SELECT mmo.comprar_oferta(8, testes.ultima_oferta(), 1)$q$, 'MMO04');

SELECT testes.caso('6 Compra', 'Jogador não compra a própria oferta',
  $q$SELECT testes.nova_oferta(); SELECT mmo.comprar_oferta(2, testes.ultima_oferta(), 1)$q$, 'MMO05');

SELECT testes.caso('6 Compra', 'Oferta de compra não pode ser "comprada"',
  $q$INSERT INTO mmo.ge_ofertas (id_personagem, id_item, tipo, quantidade, preco_unitario)
     VALUES (6, 5, 'compra', 10, 90);
     SELECT mmo.comprar_oferta(1, testes.ultima_oferta(), 1)$q$, 'MMO01');

COMMIT;


-- =====================================================================
--  RESULTADO
-- =====================================================================
SELECT n, grupo, teste, esperado, obtido,
       CASE WHEN passou THEN 'PASSOU' ELSE 'FALHOU' END AS resultado
FROM testes.resultado ORDER BY n;

SELECT teste, esperado, obtido, mensagem AS motivo_da_falha
FROM testes.resultado WHERE NOT passou ORDER BY n;


-- Se algum teste falhou, termina com erro e o resumo abaixo não é exibido. Assim o psql (e a automação do
-- GitHub Actions) devolve código de saída diferente de zero.
DO $$
DECLARE v_falhas INT;
BEGIN
    SELECT COUNT(*) INTO v_falhas FROM testes.resultado WHERE NOT passou;
    IF v_falhas > 0 THEN
        RAISE EXCEPTION '% teste(s) falharam: veja a lista acima', v_falhas;
    END IF;
END $$;

-- Resumo final (última consulta: é o que o pgAdmin mostra ao executar o arquivo todo)
SELECT COUNT(*) FILTER (WHERE passou) || ' de ' || COUNT(*) || ' testes passaram' AS resumo
FROM testes.resultado;

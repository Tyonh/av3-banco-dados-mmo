-- =====================================================================
--  AV3 - TESTE DE CONCORRÊNCIA: duas compras da mesma oferta ao mesmo tempo
--
--  Precisa de DUAS conexões abertas (ex.: duas janelas de consulta no
--  pgAdmin), porque testa duas transações acontecendo em paralelo.
--  Rode depois de mmo_banco.sql.
-- =====================================================================

-- ---------- PREPARAÇÃO (rode uma vez, em qualquer janela) ----------
SET search_path TO mmo;
INSERT INTO ge_ofertas (id_personagem, id_item, tipo, quantidade, preco_unitario)
VALUES (2, 8, 'venda', 10, 260)
RETURNING id_oferta;   -- anote o número e troque :oferta por ele nas linhas abaixo


-- ---------- JANELA 1: JoelKnight (id 3) compra as 10 Lobsters ----------
-- Rode as duas linhas e NÃO rode o COMMIT ainda.
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT mmo.comprar_oferta(3, :oferta, 10);
-- (pare aqui e vá para a janela 2)


-- ---------- JANELA 2: MarkPure (id 6) tenta comprar a mesma oferta ----------
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT mmo.comprar_oferta(6, :oferta, 10);
-- A janela 2 fica ESPERANDO: a janela 1 travou a oferta (FOR UPDATE).


-- ---------- JANELA 1: confirma ----------
COMMIT;
-- Neste momento a janela 2 recebe o erro:
--   ERROR: could not serialize access due to concurrent update  (código 40001)
-- e a compra dela é cancelada.


-- ---------- JANELA 2: encerra a transação que falhou ----------
ROLLBACK;


-- ---------- CONFERÊNCIA ----------
-- Só o JoelKnight recebeu as Lobsters; a oferta foi vendida uma única vez.
SELECT p.nome, inv.quantidade
FROM mmo.inventario inv
JOIN mmo.personagens p ON p.id_personagem = inv.id_personagem
WHERE inv.id_item = 8 AND inv.local = 'banco' AND inv.id_personagem IN (3, 6);

SELECT id_oferta, quantidade_executada, status
FROM mmo.ge_ofertas WHERE id_oferta = :oferta;

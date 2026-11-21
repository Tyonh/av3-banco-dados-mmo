#!/usr/bin/env bash
# Versão automática de sql/teste_concorrencia.sql: abre duas conexões que tentam
# comprar a mesma oferta ao mesmo tempo e confere que só uma compra acontece.
# Usa as variáveis padrão do psql (PGHOST, PGUSER, PGDATABASE, PGPASSWORD...).
set -euo pipefail
PSQL="psql -X -v ON_ERROR_STOP=1 -q"

OFERTA=$($PSQL -At -c "INSERT INTO mmo.ge_ofertas (id_personagem, id_item, tipo, quantidade, preco_unitario)
                       VALUES (2, 8, 'venda', 10, 260) RETURNING id_oferta" | head -1)
antes() { $PSQL -At -c "SELECT COALESCE(SUM(quantidade),0) FROM mmo.inventario
                        WHERE id_personagem=$1 AND id_item=8 AND local='banco'"; }
J0=$(antes 3); M0=$(antes 6)
echo "Oferta $OFERTA criada (10 Lobsters). Antes: JoelKnight=$J0, MarkPure=$M0"

# Conexão 1: JoelKnight compra e segura a transação aberta por 3 segundos
$PSQL -c "BEGIN ISOLATION LEVEL SERIALIZABLE;
          SELECT mmo.comprar_oferta(3, $OFERTA, 10);
          SELECT pg_sleep(3);
          COMMIT;" > /tmp/conexao1.log 2>&1 &
sleep 1
# Conexão 2: MarkPure tenta comprar a mesma oferta enquanto a 1 está aberta
set +e
$PSQL -c "BEGIN ISOLATION LEVEL SERIALIZABLE;
          SELECT mmo.comprar_oferta(6, $OFERTA, 10);
          COMMIT;" > /tmp/conexao2.log 2>&1
R2=$?
set -e
wait

J1=$(antes 3); M1=$(antes 6)
STATUS=$($PSQL -At -c "SELECT status FROM mmo.ge_ofertas WHERE id_oferta=$OFERTA")
echo "Conexão 2 terminou com: $(grep -o 'ERROR:.*' /tmp/conexao2.log || echo 'sucesso')"
echo "Depois: JoelKnight=$J1, MarkPure=$M1, oferta=$STATUS"

if [ "$R2" -ne 0 ] && grep -q 'could not serialize' /tmp/conexao2.log \
   && [ $((J1 - J0)) -eq 10 ] && [ "$M1" -eq "$M0" ] && [ "$STATUS" = "concluida" ]; then
  echo "PASSOU: a oferta foi vendida uma única vez."
else
  echo "FALHOU: a compra concorrente não se comportou como esperado."; exit 1
fi

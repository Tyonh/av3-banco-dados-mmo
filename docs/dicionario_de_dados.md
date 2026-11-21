# Dicionário de dados

Gerado a partir do catálogo do PostgreSQL 16 depois de executar [`sql/mmo_banco.sql`](../sql/mmo_banco.sql). Restrições que envolvem mais de uma coluna (por exemplo, as regras da mochila e do cargo no clã) estão no [README](../README.md#regras-do-jogo-dentro-do-banco).

## 1. `contas`

Login do jogador, tipo de conta e região


| Atributo | Tipo | Obrigatório | Chave | Regra |
|---|---|---|---|---|
| id_conta | bigint | sim | PK | gerado automaticamente |
| email | varchar(120) | sim | UK |  |
| senha_hash | varchar(255) | sim |  |  |
| tipo_conta | varchar(3) | sim |  | padrão F2P; valores: F2P, P2P |
| regiao | varchar(2) | sim |  | valores: BR, EU, US |
| status | varchar(10) | sim |  | padrão ativa; valores: ativa, suspensa, banida |
| criada_em | timestamptz | sim |  | padrão data/hora atual |

## 2. `clas`

Grupos de jogadores (guildas)


| Atributo | Tipo | Obrigatório | Chave | Regra |
|---|---|---|---|---|
| id_cla | bigint | sim | PK | gerado automaticamente |
| nome | varchar(40) | sim | UK |  |
| descricao | varchar(200) | não |  |  |
| criado_em | timestamptz | sim |  | padrão data/hora atual |

## 3. `personagens`

Avatar do jogador no jogo (1 por conta)


| Atributo | Tipo | Obrigatório | Chave | Regra |
|---|---|---|---|---|
| id_personagem | bigint | sim | PK | gerado automaticamente |
| id_conta | bigint | sim | FK→contas, UK |  |
| nome | varchar(12) | sim | UK |  |
| moedas | bigint | sim |  | padrão 0; moedas >= 0 |
| id_cla | bigint | não | FK→clas |  |
| cargo_cla | varchar(10) | não |  | valores: lider, oficial, membro |
| criado_em | timestamptz | sim |  | padrão data/hora atual |

## 4. `skills`

Catálogo de habilidades


| Atributo | Tipo | Obrigatório | Chave | Regra |
|---|---|---|---|---|
| id_skill | bigint | sim | PK | gerado automaticamente |
| nome | varchar(20) | sim | UK |  |
| tipo | varchar(10) | sim |  | valores: combate, coleta, producao |

## 5. `personagem_skills`

Nível e XP de cada personagem em cada skill


| Atributo | Tipo | Obrigatório | Chave | Regra |
|---|---|---|---|---|
| id_personagem | bigint | sim | FK→personagens, PK |  |
| id_skill | bigint | sim | FK→skills, PK |  |
| xp | integer | sim |  | padrão 0; xp >= 0 |
| nivel | smallint | sim |  | padrão 1; nivel de 1 a 99 |

## 6. `itens`

Catálogo de itens do jogo


| Atributo | Tipo | Obrigatório | Chave | Regra |
|---|---|---|---|---|
| id_item | bigint | sim | PK | gerado automaticamente |
| nome | varchar(40) | sim | UK |  |
| tipo | varchar(12) | sim |  | valores: arma, armadura, recurso, consumivel, missao |
| apenas_membros | boolean | sim |  | padrão false |
| empilhavel | boolean | sim |  | padrão false |
| valor_base | integer | sim |  | valor_base >= 0 |

## 7. `inventario`

Onde está cada item: mochila, banco ou equipado


| Atributo | Tipo | Obrigatório | Chave | Regra |
|---|---|---|---|---|
| id_inventario | bigint | sim | PK | gerado automaticamente |
| id_personagem | bigint | sim | FK→personagens |  |
| id_item | bigint | sim | FK→itens |  |
| local | varchar(8) | sim |  | valores: mochila, banco, equipado |
| slot | smallint | não |  | 0 a 27 na mochila; vazio no banco e no equipamento |
| quantidade | integer | sim |  | padrão 1; quantidade > 0 |

## 8. `quests`

Missões e o nível exigido


| Atributo | Tipo | Obrigatório | Chave | Regra |
|---|---|---|---|---|
| id_quest | bigint | sim | PK | gerado automaticamente |
| nome | varchar(60) | sim | UK |  |
| dificuldade | varchar(8) | sim |  | valores: facil, media, dificil |
| id_skill_requisito | bigint | não | FK→skills |  |
| nivel_minimo | smallint | sim |  | padrão 1; nivel_minimo de 1 a 99 |
| recompensa_moedas | integer | sim |  | padrão 0; recompensa_moedas >= 0 |
| apenas_membros | boolean | sim |  | padrão false |

## 9. `personagem_quests`

Progresso de cada personagem nas quests


| Atributo | Tipo | Obrigatório | Chave | Regra |
|---|---|---|---|---|
| id_personagem | bigint | sim | FK→personagens, PK |  |
| id_quest | bigint | sim | FK→quests, PK |  |
| status | varchar(12) | sim |  | padrão em_andamento; valores: em_andamento, concluida |
| concluida_em | timestamptz | não |  |  |

## 10. `ge_ofertas`

Ofertas de compra e venda no mercado


| Atributo | Tipo | Obrigatório | Chave | Regra |
|---|---|---|---|---|
| id_oferta | bigint | sim | PK | gerado automaticamente |
| id_personagem | bigint | sim | FK→personagens |  |
| id_item | bigint | sim | FK→itens |  |
| tipo | varchar(6) | sim |  | valores: compra, venda |
| quantidade | integer | sim |  | quantidade > 0 |
| quantidade_executada | integer | sim |  | padrão 0 |
| preco_unitario | integer | sim |  | preco_unitario > 0 |
| status | varchar(10) | sim |  | padrão aberta; valores: aberta, concluida, cancelada |
| criada_em | timestamptz | sim |  | padrão data/hora atual |

## 11. `penalidades`

Punições aplicadas pela moderação


| Atributo | Tipo | Obrigatório | Chave | Regra |
|---|---|---|---|---|
| id_penalidade | bigint | sim | PK | gerado automaticamente |
| id_conta | bigint | sim | FK→contas |  |
| tipo | varchar(10) | sim |  | valores: aviso, mute, suspensao, banimento |
| motivo | varchar(200) | sim |  |  |
| aplicada_por | varchar(40) | sim |  | padrão CURRENT_USER |
| inicio | timestamptz | sim |  | padrão data/hora atual |
| fim | timestamptz | não |  |  |

## 12. `logs_atividade`

Histórico de ações (auditoria)


| Atributo | Tipo | Obrigatório | Chave | Regra |
|---|---|---|---|---|
| id_log | bigint | sim | PK | gerado automaticamente |
| id_personagem | bigint | não | FK→personagens |  |
| tipo_evento | varchar(20) | sim |  |  |
| descricao | varchar(255) | não |  |  |
| criado_em | timestamptz | sim |  | padrão data/hora atual |

\pset footer off

\echo
\echo 'Escalas e repetições'
SELECT escala, estrategia, count(*) AS repeticoes
FROM resultado.execucao
GROUP BY escala, estrategia
ORDER BY escala, estrategia;

\echo
\echo 'Escrita: latência por comando (pgbench), em ms'
WITH escalas AS (
    SELECT min(escala) AS primeira, max(escala) AS segunda FROM resultado.execucao
),
linha AS (
    SELECT
        execucao,
        latencia_ms,
        row_number() OVER (PARTITION BY execucao ORDER BY ordem) AS codigo
    FROM resultado.latencia
    WHERE
        fase = 'escrita' AND
        comando ~ '^(INSERT|UPDATE|DELETE) '
)
SELECT
    comando.nome AS comando,
    execucao.estrategia,
    round(avg(linha.latencia_ms) FILTER (WHERE execucao.escala = escalas.primeira), 3) AS escala1_ms,
    round(stddev_samp(linha.latencia_ms) FILTER (WHERE execucao.escala = escalas.primeira), 3) AS escala1_desvio,
    round(avg(linha.latencia_ms) FILTER (WHERE execucao.escala = escalas.segunda), 3) AS escala2_ms,
    round(stddev_samp(linha.latencia_ms) FILTER (WHERE execucao.escala = escalas.segunda), 3) AS escala2_desvio,
    round(
        avg(linha.latencia_ms) FILTER (WHERE execucao.escala = escalas.segunda) /
        nullif(avg(linha.latencia_ms) FILTER (WHERE execucao.escala = escalas.primeira), 0),
        2
    ) AS razao
FROM linha
JOIN resultado.execucao ON execucao.id = linha.execucao
JOIN ensaio.comando ON comando.codigo = linha.codigo
CROSS JOIN escalas
GROUP BY comando.codigo, comando.nome, execucao.estrategia
ORDER BY comando.codigo, execucao.estrategia;

\echo
\echo 'Leitura: latência por consulta (pgbench), em ms'
WITH escalas AS (
    SELECT min(escala) AS primeira, max(escala) AS segunda FROM resultado.execucao
),
linha AS (
    SELECT
        execucao,
        latencia_ms,
        row_number() OVER (PARTITION BY execucao ORDER BY ordem) AS codigo
    FROM resultado.latencia
    WHERE
        fase = 'leitura' AND
        comando ~ '^SELECT ' AND
        comando !~ '^SELECT id'
)
SELECT
    consulta.nome AS consulta,
    execucao.estrategia,
    round(avg(linha.latencia_ms) FILTER (WHERE execucao.escala = escalas.primeira), 3) AS escala1_ms,
    round(stddev_samp(linha.latencia_ms) FILTER (WHERE execucao.escala = escalas.primeira), 3) AS escala1_desvio,
    round(avg(linha.latencia_ms) FILTER (WHERE execucao.escala = escalas.segunda), 3) AS escala2_ms,
    round(stddev_samp(linha.latencia_ms) FILTER (WHERE execucao.escala = escalas.segunda), 3) AS escala2_desvio,
    round(
        avg(linha.latencia_ms) FILTER (WHERE execucao.escala = escalas.segunda) /
        nullif(avg(linha.latencia_ms) FILTER (WHERE execucao.escala = escalas.primeira), 0),
        2
    ) AS razao
FROM linha
JOIN resultado.execucao ON execucao.id = linha.execucao
JOIN ensaio.consulta ON consulta.codigo = linha.codigo
CROSS JOIN escalas
GROUP BY consulta.codigo, consulta.nome, execucao.estrategia
ORDER BY consulta.codigo, execucao.estrategia;

\echo
\echo 'Blocos lidos e WAL por execução de cada comando (pg_stat_statements)'
WITH escalas AS (
    SELECT min(escala) AS primeira, max(escala) AS segunda FROM resultado.execucao
),
linha AS (
    SELECT
        execucao,
        fase,
        comando,
        regexp_replace(
            regexp_replace(
                regexp_replace(rtrim(comando, ';'), '(?<!:):[a-z_]+', '?', 'g'),
                '''[^'']*''',
                '?',
                'g'
            ),
            '''[^'']*$',
            '?'
        ) AS normal,
        row_number() OVER (PARTITION BY execucao, fase ORDER BY ordem) AS codigo
    FROM resultado.latencia
    WHERE
        (fase = 'escrita' AND comando ~ '^(INSERT|UPDATE|DELETE) ') OR
        (fase = 'leitura' AND comando ~ '^SELECT ' AND comando !~ '^SELECT id')
),
medida AS (
    SELECT
        linha.execucao,
        linha.fase,
        linha.codigo,
        (estatistica.blocos_memoria + estatistica.blocos_lidos)::numeric / estatistica.chamadas AS blocos,
        estatistica.wal_bytes / estatistica.chamadas AS wal
    FROM linha
    JOIN resultado.estatistica ON
        estatistica.execucao = linha.execucao AND
        estatistica.fase = linha.fase AND
        starts_with(regexp_replace(estatistica.consulta, '\$[0-9]+', '?', 'g'), linha.normal)
)
SELECT
    medida.fase,
    coalesce(comando.nome, consulta.nome) AS operacao,
    execucao.estrategia,
    round(avg(medida.blocos) FILTER (WHERE execucao.escala = escalas.primeira), 1) AS escala1_blocos,
    round(avg(medida.blocos) FILTER (WHERE execucao.escala = escalas.segunda), 1) AS escala2_blocos,
    round(avg(medida.wal) FILTER (WHERE execucao.escala = escalas.primeira)) AS escala1_wal_bytes,
    round(avg(medida.wal) FILTER (WHERE execucao.escala = escalas.segunda)) AS escala2_wal_bytes
FROM medida
JOIN resultado.execucao ON execucao.id = medida.execucao
LEFT JOIN ensaio.comando ON
    medida.fase = 'escrita' AND
    comando.codigo = medida.codigo
LEFT JOIN ensaio.consulta ON
    medida.fase = 'leitura' AND
    consulta.codigo = medida.codigo
CROSS JOIN escalas
GROUP BY medida.fase, medida.codigo, coalesce(comando.nome, consulta.nome), execucao.estrategia
ORDER BY medida.fase DESC, medida.codigo, execucao.estrategia;

\echo
\echo 'Armazenamento depois da escrita, antes do VACUUM'
WITH medida AS (
    SELECT
        execucao.escala,
        execucao.estrategia,
        execucao.id,
        sum(tamanho_depois.total_bytes) AS total,
        sum(tamanho_depois.indices_bytes) AS indices,
        sum(tamanho_depois.total_bytes - tamanho_antes.total_bytes) AS acrescimo,
        sum(tamanho_depois.linhas - tamanho_antes.linhas) FILTER (
            WHERE tamanho_depois.tabela NOT LIKE 'vexterno.%' OR tamanho_depois.tabela LIKE 'vexterno.historia%'
        ) AS versoes
    FROM resultado.execucao
    JOIN resultado.tamanho tamanho_depois ON
        tamanho_depois.execucao = execucao.id AND
        tamanho_depois.momento = 'depois'
    JOIN resultado.tamanho tamanho_antes ON
        tamanho_antes.execucao = execucao.id AND
        tamanho_antes.momento = 'antes' AND
        tamanho_antes.tabela = tamanho_depois.tabela
    GROUP BY execucao.escala, execucao.estrategia, execucao.id
)
SELECT
    escala,
    estrategia,
    round(avg(total) / 1048576, 1) AS total_mb,
    round(stddev_samp(total) / 1048576, 2) AS desvio_mb,
    round(avg(indices) / 1048576, 1) AS indices_mb,
    round(avg(versoes)) AS versoes,
    round(avg(acrescimo / nullif(versoes, 0))) AS bytes_por_versao
FROM medida
GROUP BY escala, estrategia
ORDER BY escala, estrategia;

\echo
\echo 'Armazenamento por tabela, em MB'
SELECT
    execucao.escala,
    execucao.estrategia,
    tamanho.tabela,
    round(avg(tamanho.total_bytes) / 1048576, 1) AS total_mb,
    round(avg(tamanho.tabela_bytes) / 1048576, 1) AS tabela_mb,
    round(avg(tamanho.indices_bytes) / 1048576, 1) AS indices_mb,
    round(avg(tamanho.linhas)) AS linhas
FROM resultado.tamanho
JOIN resultado.execucao ON execucao.id = tamanho.execucao
WHERE tamanho.momento = 'depois'
GROUP BY execucao.escala, execucao.estrategia, tamanho.tabela
ORDER BY execucao.escala, execucao.estrategia, tamanho.tabela;

\echo
\echo 'WAL, duração e checkpoints por fase'
SELECT
    execucao.escala,
    execucao.estrategia,
    fase.fase,
    round(avg(pg_wal_lsn_diff(fase.lsn_depois, fase.lsn_antes)) / 1048576, 1) AS wal_mb,
    round(stddev_samp(pg_wal_lsn_diff(fase.lsn_depois, fase.lsn_antes)) / 1048576, 2) AS desvio_mb,
    round(avg(extract(epoch FROM fase.fim - fase.inicio)), 1) AS segundos,
    round(avg(fase.tps)) AS tps,
    sum(fase.falhas) AS falhas,
    count(*) FILTER (WHERE fase.checkpoint_depois <> fase.checkpoint_antes) AS com_checkpoint
FROM resultado.fase
JOIN resultado.execucao ON execucao.id = fase.execucao
GROUP BY execucao.escala, execucao.estrategia, fase.fase
ORDER BY execucao.escala, execucao.estrategia, fase.fase DESC;

\echo
\echo 'Escalabilidade: razão entre a maior e a menor escala'
WITH escalas AS (
    SELECT min(escala) AS primeira, max(escala) AS segunda FROM resultado.execucao
),
medida AS (
    SELECT
        execucao.escala,
        execucao.estrategia,
        avg(fase.latencia_media_ms) FILTER (WHERE fase.fase = 'escrita') AS escrita_ms,
        avg(fase.latencia_media_ms) FILTER (WHERE fase.fase = 'leitura') AS leitura_ms,
        avg(pg_wal_lsn_diff(fase.lsn_depois, fase.lsn_antes) / fase.transacoes) FILTER (WHERE fase.fase = 'escrita') AS wal_por_operacao,
        avg((
            SELECT sum(tamanho.total_bytes)
            FROM resultado.tamanho
            WHERE
                tamanho.execucao = execucao.id AND
                tamanho.momento = 'depois'
        )) AS tamanho
    FROM resultado.execucao
    JOIN resultado.fase ON fase.execucao = execucao.id
    GROUP BY execucao.escala, execucao.estrategia
)
SELECT
    medida.estrategia,
    round(
        max(medida.escrita_ms) FILTER (WHERE medida.escala = escalas.segunda) /
        nullif(max(medida.escrita_ms) FILTER (WHERE medida.escala = escalas.primeira), 0),
        2
    ) AS latencia_escrita,
    round(
        max(medida.leitura_ms) FILTER (WHERE medida.escala = escalas.segunda) /
        nullif(max(medida.leitura_ms) FILTER (WHERE medida.escala = escalas.primeira), 0),
        2
    ) AS latencia_leitura,
    round(
        max(medida.wal_por_operacao) FILTER (WHERE medida.escala = escalas.segunda) /
        nullif(max(medida.wal_por_operacao) FILTER (WHERE medida.escala = escalas.primeira), 0),
        2
    ) AS wal_por_operacao,
    round(
        max(medida.tamanho) FILTER (WHERE medida.escala = escalas.segunda) /
        nullif(max(medida.tamanho) FILTER (WHERE medida.escala = escalas.primeira), 0),
        2
    ) AS tamanho
FROM medida
CROSS JOIN escalas
GROUP BY medida.estrategia
ORDER BY medida.estrategia;

\echo
\echo 'Complexidade'
SELECT
    item,
    max(quantidade) FILTER (WHERE estrategia = 'base') AS base,
    max(quantidade) FILTER (WHERE estrategia = 'vinterno') AS vinterno,
    max(quantidade) FILTER (WHERE estrategia = 'vexterno') AS vexterno
FROM resultado.complexidade
GROUP BY item
ORDER BY item;

\echo
\echo 'Falhas de consistência e de verificação (tudo zero é o esperado)'
SELECT
    'consistencia' AS checagem,
    execucao.escala,
    execucao.estrategia,
    coalesce(sum(consistencia.falhas), 0) AS falhas
FROM resultado.execucao
JOIN resultado.consistencia ON consistencia.execucao = execucao.id
GROUP BY execucao.escala, execucao.estrategia
UNION ALL
SELECT
    'verificacao',
    escala,
    'todas',
    sum(atual_vinterno + atual_vexterno + historia_aberta + historico + lacunas_vinterno + lacunas_vexterno + id_vinterno)
FROM resultado.verificacao
GROUP BY escala
ORDER BY 1, 2, 3;

\echo
\echo 'Ambiente'
SELECT chave, valor FROM resultado.ambiente ORDER BY chave;

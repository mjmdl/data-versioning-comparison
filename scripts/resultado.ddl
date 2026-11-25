BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE SCHEMA resultado;

CREATE TABLE resultado.ambiente (
    chave text NOT NULL,
    valor text,

    CONSTRAINT ambiente_pk PRIMARY KEY (chave)
);

CREATE TABLE resultado.complexidade (
    estrategia text NOT NULL,
    item       text NOT NULL,
    quantidade bigint NOT NULL,

    CONSTRAINT complexidade_pk PRIMARY KEY (estrategia, item)
);

CREATE TABLE resultado.execucao (
    id         integer GENERATED ALWAYS AS IDENTITY,
    escala     integer NOT NULL,
    estrategia text NOT NULL,
    repeticao  integer NOT NULL,
    inicio     timestamptz NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT execucao_pk PRIMARY KEY (id),
    CONSTRAINT execucao_uq UNIQUE (escala, estrategia, repeticao)
);

CREATE TABLE resultado.fase (
    execucao          integer NOT NULL,
    fase              text NOT NULL,
    inicio            timestamptz NOT NULL,
    fim               timestamptz,
    lsn_antes         pg_lsn NOT NULL,
    lsn_depois        pg_lsn,
    checkpoint_antes  pg_lsn NOT NULL,
    checkpoint_depois pg_lsn,
    transacoes        bigint,
    falhas            bigint,
    tps               numeric,
    latencia_media_ms numeric,

    CONSTRAINT fase_pk         PRIMARY KEY (execucao, fase),
    CONSTRAINT fase_fk_execucao FOREIGN KEY (execucao) REFERENCES resultado.execucao (id) ON DELETE CASCADE
);

CREATE TABLE resultado.latencia (
    execucao    integer NOT NULL,
    fase        text NOT NULL,
    ordem       integer NOT NULL,
    latencia_ms numeric NOT NULL,
    falhas      bigint NOT NULL,
    comando     text NOT NULL,

    CONSTRAINT latencia_pk          PRIMARY KEY (execucao, fase, ordem),
    CONSTRAINT latencia_fk_execucao FOREIGN KEY (execucao) REFERENCES resultado.execucao (id) ON DELETE CASCADE
);

CREATE TABLE resultado.estatistica (
    execucao             integer NOT NULL,
    fase                 text NOT NULL,
    queryid              bigint,
    consulta             text NOT NULL,
    chamadas             bigint NOT NULL,
    tempo_total_ms       double precision NOT NULL,
    tempo_medio_ms       double precision NOT NULL,
    tempo_desvio_ms      double precision NOT NULL,
    linhas               bigint NOT NULL,
    blocos_memoria       bigint NOT NULL,
    blocos_lidos         bigint NOT NULL,
    blocos_sujos         bigint NOT NULL,
    blocos_escritos      bigint NOT NULL,
    wal_registros        bigint NOT NULL,
    wal_paginas_inteiras bigint NOT NULL,
    wal_bytes            numeric NOT NULL,

    CONSTRAINT estatistica_fk_execucao FOREIGN KEY (execucao) REFERENCES resultado.execucao (id) ON DELETE CASCADE
);
CREATE INDEX estatistica_ix_execucao ON resultado.estatistica (execucao, fase);

CREATE TABLE resultado.tamanho (
    execucao      integer NOT NULL,
    momento       text NOT NULL,
    tabela        text NOT NULL,
    total_bytes   bigint NOT NULL,
    tabela_bytes  bigint NOT NULL,
    indices_bytes bigint NOT NULL,
    linhas        bigint,

    CONSTRAINT tamanho_pk          PRIMARY KEY (execucao, momento, tabela),
    CONSTRAINT tamanho_fk_execucao FOREIGN KEY (execucao) REFERENCES resultado.execucao (id) ON DELETE CASCADE
);

CREATE TABLE resultado.consistencia (
    execucao integer NOT NULL,
    tabela   text NOT NULL,
    regra    text NOT NULL,
    falhas   bigint NOT NULL,

    CONSTRAINT consistencia_pk          PRIMARY KEY (execucao, tabela, regra),
    CONSTRAINT consistencia_fk_execucao FOREIGN KEY (execucao) REFERENCES resultado.execucao (id) ON DELETE CASCADE
);

CREATE TABLE resultado.verificacao (
    escala           integer NOT NULL,
    repeticao        integer NOT NULL,
    tabela           text NOT NULL,
    atual_vinterno   bigint NOT NULL,
    atual_vexterno   bigint NOT NULL,
    historia_aberta  bigint NOT NULL,
    historico        bigint NOT NULL,
    lacunas_vinterno bigint NOT NULL,
    lacunas_vexterno bigint NOT NULL,
    id_vinterno      bigint NOT NULL,

    CONSTRAINT verificacao_pk PRIMARY KEY (escala, repeticao, tabela)
);



CREATE OR REPLACE FUNCTION resultado.iniciar(_execucao integer, _fase text) RETURNS void LANGUAGE sql AS $$
    SELECT public.pg_stat_statements_reset();

    INSERT INTO resultado.fase (execucao, fase, inicio, lsn_antes, checkpoint_antes)
    VALUES (
        _execucao,
        _fase,
        clock_timestamp(),
        pg_current_wal_lsn(),
        (pg_control_checkpoint()).checkpoint_lsn
    );
$$;

CREATE OR REPLACE FUNCTION resultado.encerrar(
    _execucao   integer,
    _fase       text,
    _transacoes bigint,
    _falhas     bigint,
    _tps        numeric,
    _latencia   numeric
)
RETURNS void LANGUAGE sql AS $$
    UPDATE resultado.fase
    SET
        fim = clock_timestamp(),
        lsn_depois = pg_current_wal_lsn(),
        checkpoint_depois = (pg_control_checkpoint()).checkpoint_lsn,
        transacoes = _transacoes,
        falhas = _falhas,
        tps = _tps,
        latencia_media_ms = _latencia
    WHERE
        fase.execucao = _execucao AND
        fase.fase = _fase;

    INSERT INTO resultado.estatistica
    SELECT
        _execucao,
        _fase,
        queryid,
        query,
        calls,
        total_exec_time,
        mean_exec_time,
        stddev_exec_time,
        rows,
        shared_blks_hit,
        shared_blks_read,
        shared_blks_dirtied,
        shared_blks_written,
        wal_records,
        wal_fpi,
        wal_bytes
    FROM public.pg_stat_statements
    WHERE
        dbid = (SELECT oid FROM pg_database WHERE datname = current_database()) AND
        toplevel;
$$;

CREATE OR REPLACE FUNCTION resultado.medir(_execucao integer, _momento text, _estrategia text) RETURNS void LANGUAGE sql AS $$
    INSERT INTO resultado.tamanho (execucao, momento, tabela, total_bytes, tabela_bytes, indices_bytes)
    SELECT
        _execucao,
        _momento,
        pg_namespace.nspname || '.' || pg_class.relname,
        pg_total_relation_size(pg_class.oid),
        pg_relation_size(pg_class.oid),
        pg_indexes_size(pg_class.oid)
    FROM pg_class
    JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    WHERE
        pg_namespace.nspname = _estrategia AND
        pg_class.relkind = 'r';

    UPDATE resultado.tamanho
    SET linhas = contagem.linhas
    FROM (
        VALUES
            ('base.departamento', (SELECT count(*) FROM base.departamento)),
            ('base.horario', (SELECT count(*) FROM base.horario)),
            ('base.funcionario', (SELECT count(*) FROM base.funcionario)),
            ('base.ferias', (SELECT count(*) FROM base.ferias)),
            ('base.ponto', (SELECT count(*) FROM base.ponto)),
            ('vinterno.departamento', (SELECT count(*) FROM vinterno.departamento)),
            ('vinterno.horario', (SELECT count(*) FROM vinterno.horario)),
            ('vinterno.funcionario', (SELECT count(*) FROM vinterno.funcionario)),
            ('vinterno.ferias', (SELECT count(*) FROM vinterno.ferias)),
            ('vinterno.ponto', (SELECT count(*) FROM vinterno.ponto)),
            ('vexterno.departamento', (SELECT count(*) FROM vexterno.departamento)),
            ('vexterno.horario', (SELECT count(*) FROM vexterno.horario)),
            ('vexterno.funcionario', (SELECT count(*) FROM vexterno.funcionario)),
            ('vexterno.ferias', (SELECT count(*) FROM vexterno.ferias)),
            ('vexterno.ponto', (SELECT count(*) FROM vexterno.ponto)),
            ('vexterno.historia_departamento', (SELECT count(*) FROM vexterno.historia_departamento)),
            ('vexterno.historia_horario', (SELECT count(*) FROM vexterno.historia_horario)),
            ('vexterno.historia_funcionario', (SELECT count(*) FROM vexterno.historia_funcionario)),
            ('vexterno.historia_ferias', (SELECT count(*) FROM vexterno.historia_ferias)),
            ('vexterno.historia_ponto', (SELECT count(*) FROM vexterno.historia_ponto))
    ) contagem (tabela, linhas)
    WHERE
        tamanho.execucao = _execucao AND
        tamanho.momento = _momento AND
        tamanho.tabela = contagem.tabela;
$$;

COMMIT;

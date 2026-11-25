BEGIN;

CREATE TABLE ensaio.consulta (
    codigo smallint NOT NULL,
    nome   text NOT NULL,

    CONSTRAINT consulta_pk      PRIMARY KEY (codigo),
    CONSTRAINT consulta_uq_nome UNIQUE (nome)
);

INSERT INTO ensaio.consulta (codigo, nome) VALUES
    (1, 'departamento_atual'),
    (2, 'horario_atual'),
    (3, 'funcionario_atual'),
    (4, 'ferias_atual'),
    (5, 'ponto_atual'),
    (6, 'departamento_passado'),
    (7, 'horario_passado'),
    (8, 'funcionario_passado'),
    (9, 'ferias_passado'),
    (10, 'ponto_passado'),
    (11, 'departamento_historico'),
    (12, 'horario_historico'),
    (13, 'funcionario_historico'),
    (14, 'ferias_historico'),
    (15, 'ponto_historico');

CREATE TABLE ensaio.leitura (
    escala   integer NOT NULL,
    consulta smallint NOT NULL,
    k        integer NOT NULL,
    id       uuid NOT NULL,
    instante timestamptz,

    CONSTRAINT leitura_pk          PRIMARY KEY (escala, consulta, k),
    CONSTRAINT leitura_fk_consulta FOREIGN KEY (consulta) REFERENCES ensaio.consulta (codigo)
);

CREATE UNLOGGED TABLE ensaio.sim_vida (
    tabela  smallint NOT NULL,
    posicao integer NOT NULL,
    vigente integer,
    id      uuid NOT NULL,
    inicio  integer NOT NULL,
    fim     integer NOT NULL,

    CONSTRAINT sim_vida_pk PRIMARY KEY (tabela, posicao)
);
CREATE UNIQUE INDEX sim_vida_uq_vigente ON ensaio.sim_vida (tabela, vigente);

CREATE INDEX plano_ix_comando ON ensaio.plano (comando, id, n);



CREATE OR REPLACE PROCEDURE ensaio.gerar_leituras(
    _escala    integer,
    _execucoes integer DEFAULT 10000,
    _semente   double precision DEFAULT 0.5
)
LANGUAGE plpgsql AS $$
DECLARE
    _passo              constant bigint := 315360000;
    _codigo_consulta    integer;
    _tabela_consultada  integer;
    _execucao           integer;
    _total_entidades    integer;
    _entidades_vigentes integer;
    _posicao_sorteada   integer;
    _entidade_sorteada  uuid;
    _nasceu             integer;
    _acabou             integer;
    _duracao            bigint;
    _momento            timestamptz;
BEGIN
    PERFORM setseed(_semente);

    DELETE FROM ensaio.leitura WHERE leitura.escala = _escala;
    TRUNCATE ensaio.sim_vida;

    INSERT INTO ensaio.sim_vida (tabela, posicao, vigente, id, inicio, fim)
    SELECT
        vidas.tabela,
        row_number() OVER (PARTITION BY vidas.tabela ORDER BY vidas.inicio),
        CASE
            WHEN vidas.fim > _escala THEN row_number() OVER (PARTITION BY vidas.tabela, vidas.fim > _escala ORDER BY vidas.inicio)
        END,
        vidas.id,
        vidas.inicio,
        vidas.fim
    FROM (
    SELECT
        1 AS tabela,
        plano_criacao.id,
        plano_criacao.n AS inicio,
        least(plano_exclusao.n, _escala + 1) AS fim
    FROM ensaio.plano plano_criacao
    LEFT JOIN ensaio.plano plano_exclusao ON
        plano_exclusao.comando = 3 AND
        plano_exclusao.id = plano_criacao.id AND
        plano_exclusao.n <= _escala
    WHERE
        plano_criacao.comando = 1 AND
        plano_criacao.n <= _escala
    UNION ALL
    SELECT
        2,
        plano_criacao.id,
        plano_criacao.n,
        least(plano_exclusao.n, plano_exclusao_departamento.n, _escala + 1)
    FROM ensaio.plano plano_criacao
    LEFT JOIN ensaio.plano plano_exclusao ON
        plano_exclusao.comando = 6 AND
        plano_exclusao.id = plano_criacao.id AND
        plano_exclusao.n <= _escala
    LEFT JOIN ensaio.plano plano_exclusao_departamento ON
        plano_exclusao_departamento.comando = 3 AND
        plano_exclusao_departamento.id = plano_criacao.departamento AND
        plano_exclusao_departamento.n <= _escala
    WHERE
        plano_criacao.comando = 4 AND
        plano_criacao.n <= _escala
    UNION ALL
    SELECT
        3,
        plano_criacao.id,
        plano_criacao.n,
        least(plano_exclusao.n, _escala + 1)
    FROM ensaio.plano plano_criacao
    LEFT JOIN ensaio.plano plano_exclusao ON
        plano_exclusao.comando = 12 AND
        plano_exclusao.id = plano_criacao.id AND
        plano_exclusao.n <= _escala
    WHERE
        plano_criacao.comando = 7 AND
        plano_criacao.n <= _escala
    UNION ALL
    SELECT
        4,
        plano_criacao.id,
        plano_criacao.n,
        least(plano_exclusao_funcionario.n, _escala + 1)
    FROM ensaio.plano plano_criacao
    LEFT JOIN ensaio.plano plano_exclusao_funcionario ON
        plano_exclusao_funcionario.comando = 12 AND
        plano_exclusao_funcionario.id = plano_criacao.funcionario AND
        plano_exclusao_funcionario.n <= _escala
    WHERE
        plano_criacao.comando = 17 AND
        plano_criacao.n <= _escala
    UNION ALL
    SELECT
        5,
        plano_criacao.id,
        plano_criacao.n,
        least(plano_exclusao.n, plano_exclusao_funcionario.n, _escala + 1)
    FROM ensaio.plano plano_criacao
    LEFT JOIN ensaio.plano plano_exclusao ON
        plano_exclusao.comando = 16 AND
        plano_exclusao.id = plano_criacao.id AND
        plano_exclusao.n <= _escala
    LEFT JOIN ensaio.plano plano_exclusao_funcionario ON
        plano_exclusao_funcionario.comando = 12 AND
        plano_exclusao_funcionario.id = plano_criacao.funcionario AND
        plano_exclusao_funcionario.n <= _escala
    WHERE
        plano_criacao.comando = 13 AND
        plano_criacao.n <= _escala
    ) vidas;

    FOR _codigo_consulta IN 1..15 LOOP
        _tabela_consultada := (_codigo_consulta - 1) % 5 + 1;

        SELECT count(*), count(vigente)
        INTO _total_entidades, _entidades_vigentes
        FROM ensaio.sim_vida
        WHERE tabela = _tabela_consultada;

        FOR _execucao IN 1.._execucoes LOOP
            _momento := NULL;
            IF _codigo_consulta <= 5 THEN
                _posicao_sorteada := 1 + floor(random() * _entidades_vigentes)::integer;

                SELECT id
                INTO _entidade_sorteada
                FROM ensaio.sim_vida
                WHERE
                    tabela = _tabela_consultada AND
                    vigente = _posicao_sorteada;
            ELSE
                _posicao_sorteada := 1 + floor(random() * _total_entidades)::integer;

                SELECT id, inicio, fim
                INTO _entidade_sorteada, _nasceu, _acabou
                FROM ensaio.sim_vida
                WHERE
                    tabela = _tabela_consultada AND
                    posicao = _posicao_sorteada;

                IF _codigo_consulta <= 10 THEN
                    _duracao := (_acabou - _nasceu) * _passo;
                    _momento := ensaio.instante(_nasceu) + least(floor(random() * _duracao)::bigint, _duracao - 1) * interval '1 microsecond';
                END IF;
            END IF;

            INSERT INTO ensaio.leitura (escala, consulta, k, id, instante)
            VALUES (_escala, _codigo_consulta, _execucao, _entidade_sorteada, _momento);
        END LOOP;
    END LOOP;
END;
$$;

COMMIT;

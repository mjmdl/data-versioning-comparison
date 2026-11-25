BEGIN;

CREATE SCHEMA ensaio;

CREATE TABLE ensaio.comando (
    codigo smallint NOT NULL,
    nome   text NOT NULL,

    CONSTRAINT comando_pk      PRIMARY KEY (codigo),
    CONSTRAINT comando_uq_nome UNIQUE (nome)
);

INSERT INTO ensaio.comando (codigo, nome) VALUES
    (1, 'departamento_inserir'),
    (2, 'departamento_alterar'),
    (3, 'departamento_excluir'),
    (4, 'horario_inserir'),
    (5, 'horario_alterar'),
    (6, 'horario_excluir'),
    (7, 'funcionario_inserir'),
    (8, 'funcionario_alterar_cargo'),
    (9, 'funcionario_alterar_salario'),
    (10, 'funcionario_alterar_departamento'),
    (11, 'funcionario_alterar_lider'),
    (12, 'funcionario_excluir'),
    (13, 'ponto_registrar'),
    (14, 'ponto_ajustar'),
    (15, 'ponto_justificar_remocao'),
    (16, 'ponto_remover'),
    (17, 'ferias_solicitar'),
    (18, 'ferias_mudar_status');

CREATE TABLE ensaio.peso (
    cenario text NOT NULL,
    peso    double precision NOT NULL,

    CONSTRAINT peso_pk       PRIMARY KEY (cenario),
    CONSTRAINT peso_ck_valor CHECK (peso >= 0)
);

INSERT INTO ensaio.peso (cenario, peso) VALUES
    ('ponto_registrar', 40),
    ('ponto_ajustar', 10),
    ('ponto_remover', 4),
    ('ferias_solicitar', 8),
    ('ferias_mudar_status', 12),
    ('funcionario_inserir', 4),
    ('funcionario_alterar', 12),
    ('funcionario_excluir', 2),
    ('horario_inserir', 2),
    ('horario_alterar', 2),
    ('horario_excluir', 1),
    ('departamento_inserir', 1),
    ('departamento_alterar', 1.5),
    ('departamento_excluir', 0.5);

CREATE TABLE ensaio.plano (
    n                     integer NOT NULL,
    instante              timestamptz NOT NULL,
    comando               smallint NOT NULL,
    id                    uuid NOT NULL,
    departamento          uuid,
    funcionario           uuid,
    funcionario_lider     uuid,
    nome                  text,
    nome_civil            text,
    documento             text,
    nascimento            date,
    genero                text,
    email                 text,
    telefone              text,
    endereco              text,
    cargo                 text,
    salario               numeric,
    percentual_hora_extra numeric,
    dia                   text,
    hora_inicio           time,
    hora_fim              time,
    registro              timestamptz,
    tipo                  text,
    justificativa         text,
    inicio                date,
    fim                   date,
    status                text,

    CONSTRAINT plano_pk         PRIMARY KEY (n),
    CONSTRAINT plano_fk_comando FOREIGN KEY (comando) REFERENCES ensaio.comando (codigo)
);

CREATE UNLOGGED TABLE ensaio.sim_departamento (
    seq          integer NOT NULL,
    chave        bigint NOT NULL,
    versao       integer NOT NULL,
    funcionarios integer NOT NULL,

    CONSTRAINT sim_departamento_pk       PRIMARY KEY (seq),
    CONSTRAINT sim_departamento_uq_chave UNIQUE (chave)
);
CREATE INDEX sim_departamento_ix_funcionarios ON ensaio.sim_departamento (funcionarios, seq);

CREATE UNLOGGED TABLE ensaio.sim_horario (
    seq          integer NOT NULL,
    chave        bigint NOT NULL,
    departamento integer NOT NULL,
    dia          integer NOT NULL,
    hora         integer NOT NULL,

    CONSTRAINT sim_horario_pk       PRIMARY KEY (seq),
    CONSTRAINT sim_horario_uq_chave UNIQUE (chave)
);
CREATE INDEX sim_horario_ix_departamento ON ensaio.sim_horario (departamento, dia);

CREATE UNLOGGED TABLE ensaio.sim_funcionario (
    seq          integer NOT NULL,
    chave        bigint NOT NULL,
    departamento integer NOT NULL,
    lider        integer,
    cargo        integer NOT NULL,
    salario      numeric NOT NULL,
    proximo_tipo integer NOT NULL,

    CONSTRAINT sim_funcionario_pk       PRIMARY KEY (seq),
    CONSTRAINT sim_funcionario_uq_chave UNIQUE (chave)
);
CREATE INDEX sim_funcionario_ix_departamento ON ensaio.sim_funcionario (departamento, seq);
CREATE INDEX sim_funcionario_ix_lider        ON ensaio.sim_funcionario (lider);

CREATE UNLOGGED TABLE ensaio.sim_ponto (
    seq         integer NOT NULL,
    funcionario integer NOT NULL,
    registro    timestamptz NOT NULL,

    CONSTRAINT sim_ponto_pk          PRIMARY KEY (seq),
    CONSTRAINT sim_ponto_uq_registro UNIQUE (funcionario, registro)
);

CREATE UNLOGGED TABLE ensaio.sim_ferias (
    seq         integer NOT NULL,
    funcionario integer NOT NULL,
    inicio      date NOT NULL,
    fim         date NOT NULL,
    status      text NOT NULL,

    CONSTRAINT sim_ferias_pk PRIMARY KEY (seq)
);
CREATE INDEX sim_ferias_ix_ocupacao ON ensaio.sim_ferias (funcionario, fim) WHERE status NOT IN ('recusada', 'cancelada');
CREATE INDEX sim_ferias_ix_pendente ON ensaio.sim_ferias (funcionario, seq) WHERE status IN ('solicitada', 'aprovada');



CREATE OR REPLACE FUNCTION ensaio.instante(_operacao integer) RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$
    SELECT timestamptz '2026-01-01 00:00:00+00' + (_operacao - 1) * 315360000::bigint * interval '1 microsecond';
$$;

CREATE OR REPLACE FUNCTION ensaio.data(_operacao integer) RETURNS date LANGUAGE sql IMMUTABLE AS $$
    SELECT (ensaio.instante(_operacao) AT TIME ZONE 'UTC')::date;
$$;

CREATE OR REPLACE FUNCTION ensaio.uuid_de(_tipo text, _numero integer) RETURNS uuid LANGUAGE sql IMMUTABLE STRICT AS $$
    SELECT md5(_tipo || ':' || _numero)::uuid;
$$;

CREATE OR REPLACE FUNCTION ensaio.chave(_numero integer) RETURNS bigint LANGUAGE sql IMMUTABLE AS $$
    SELECT (_numero::bigint * 2654435761) % 4294967296;
$$;

CREATE OR REPLACE FUNCTION ensaio.inteiro(_minimo integer, _maximo integer) RETURNS integer LANGUAGE plpgsql VOLATILE AS $$
BEGIN
    RETURN _minimo + floor(random() * (_maximo - _minimo + 1))::integer;
END;
$$;

CREATE OR REPLACE FUNCTION ensaio.zipf(_tamanho integer) RETURNS integer LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    _expoente          constant double precision := 1.1;
    _fator             constant double precision := power(2.0, _expoente - 1.0);
    _sorteio_candidato double precision;
    _sorteio_aceite    double precision;
    _candidato         double precision;
    _razao             double precision;
BEGIN
    IF _tamanho <= 1 THEN
        RETURN 1;
    END IF;

    LOOP
        _sorteio_candidato := 1.0 - random();
        _sorteio_aceite := random();
        _candidato := floor(power(_sorteio_candidato, -1.0 / (_expoente - 1.0)));
        _razao := power(1.0 + 1.0 / _candidato, _expoente - 1.0);
        IF _sorteio_aceite * _candidato * (_razao - 1.0) / (_fator - 1.0) <= _razao / _fator AND _candidato <= _tamanho THEN
            RETURN _candidato::integer;
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION ensaio.emitir(
    _n                     integer,
    _comando               text,
    _id                    uuid,
    _departamento          uuid DEFAULT NULL,
    _funcionario           uuid DEFAULT NULL,
    _funcionario_lider     uuid DEFAULT NULL,
    _nome                  text DEFAULT NULL,
    _nome_civil            text DEFAULT NULL,
    _documento             text DEFAULT NULL,
    _nascimento            date DEFAULT NULL,
    _genero                text DEFAULT NULL,
    _email                 text DEFAULT NULL,
    _telefone              text DEFAULT NULL,
    _endereco              text DEFAULT NULL,
    _cargo                 text DEFAULT NULL,
    _salario               numeric DEFAULT NULL,
    _percentual_hora_extra numeric DEFAULT NULL,
    _dia                   text DEFAULT NULL,
    _hora_inicio           time DEFAULT NULL,
    _hora_fim              time DEFAULT NULL,
    _registro              timestamptz DEFAULT NULL,
    _tipo                  text DEFAULT NULL,
    _justificativa         text DEFAULT NULL,
    _inicio                date DEFAULT NULL,
    _fim                   date DEFAULT NULL,
    _status                text DEFAULT NULL
) RETURNS void LANGUAGE sql AS $$
    INSERT INTO ensaio.plano VALUES (
        _n,
        ensaio.instante(_n),
        (SELECT comando.codigo FROM ensaio.comando WHERE comando.nome = _comando),
        _id,
        _departamento,
        _funcionario,
        _funcionario_lider,
        _nome,
        _nome_civil,
        _documento,
        _nascimento,
        _genero,
        _email,
        _telefone,
        _endereco,
        _cargo,
        _salario,
        _percentual_hora_extra,
        _dia,
        _hora_inicio,
        _hora_fim,
        _registro,
        _tipo,
        _justificativa,
        _inicio,
        _fim,
        _status
    );
$$;

CREATE OR REPLACE PROCEDURE ensaio.gerar_plano(
    _total   integer DEFAULT 1000000,
    _escala  integer DEFAULT 100000,
    _semente double precision DEFAULT 0.5
)
LANGUAGE plpgsql AS $$
DECLARE
    _cargos                 constant text[] := ARRAY['Analista', 'Assistente', 'Auxiliar', 'Coordenador', 'Desenvolvedor', 'Estagiário', 'Gerente', 'Supervisor', 'Técnico', 'Vendedor'];
    _dias                   constant text[] := ARRAY['segunda', 'terca', 'quarta', 'quinta', 'sexta', 'sabado', 'domingo'];
    _generos                constant text[] := ARRAY['masculino', 'feminino', 'outro'];
    _motivos                constant text[] := ARRAY['Esquecimento', 'Falha no relógio', 'Serviço externo', 'Ajuste de horário'];
    _tipos                  constant text[] := ARRAY['entrada', 'saida'];
    _cenarios               text[];
    _pesos_acumulados       double precision[];
    _sorteio                double precision;
    _escolhido              text;
    _limite                 integer;
    _proximo_commit         integer := 10000;
    _operacao               integer := 0;
    _departamentos_criados  integer := 0;
    _horarios_criados       integer := 0;
    _funcionarios_criados   integer := 0;
    _pontos_criados         integer := 0;
    _ferias_criadas         integer := 0;
    _departamentos_vigentes integer := 0;
    _horarios_vigentes      integer := 0;
    _funcionarios_vigentes  integer := 0;
    _departamento_sorteado  integer;
    _departamento_destino   integer;
    _horario_sorteado       integer;
    _funcionario_sorteado   integer;
    _subordinado            integer;
    _ponto_sorteado         integer;
    _ferias_sorteada        integer;
    _quantidade             integer;
    _horarios_removidos     integer;
    _dia_horario            integer;
    _hora_horario           integer;
    _deslocamento           integer;
    _faixas_livres          integer[];
    _lider_atual            integer;
    _lider_novo             integer;
    _cargo_atual            integer;
    _cargo_novo             integer;
    _salario_atual          numeric;
    _salario_novo           numeric;
    _versao_nova            integer;
    _genero_sorteado        integer;
    _percentual             integer;
    _rua                    integer;
    _numero_casa            integer;
    _nascido                date;
    _possivel               boolean;
    _hoje                   date;
    _inicio_ferias          date;
    _termino_ferias         date;
    _momento                timestamptz;
    _registro_novo          timestamptz;
    _motivo                 text;
    _situacao               text;
    _status_novo            text;
    _posicao                integer;
    _tentativa              integer;
    _faixa                  integer;
    _tipo_ponto             integer;
    _funcionario_movido     integer;
    _ferias_cancelada       integer;
BEGIN
    PERFORM setseed(_semente);

    TRUNCATE ensaio.plano, ensaio.sim_departamento, ensaio.sim_horario, ensaio.sim_funcionario, ensaio.sim_ponto, ensaio.sim_ferias;

    SELECT
        array_agg(cenario ORDER BY cenario),
        array_agg(acumulado ORDER BY cenario)
    INTO _cenarios, _pesos_acumulados
    FROM (
        SELECT
            cenario,
            sum(CASE WHEN cenario = 'ponto_remover' THEN peso / 2 ELSE peso END) OVER (ORDER BY cenario) AS acumulado
        FROM ensaio.peso
    ) pesos;

    WHILE _operacao < _total LOOP
        IF _operacao >= _proximo_commit THEN
            COMMIT;
            ANALYZE ensaio.sim_departamento, ensaio.sim_horario, ensaio.sim_funcionario, ensaio.sim_ponto, ensaio.sim_ferias;
            _proximo_commit := _proximo_commit + 10000;
        END IF;

        _limite := CASE WHEN _operacao < _escala THEN least(_escala, _total) ELSE _total END;

        IF _operacao < 5 THEN
            _escolhido := 'departamento_inserir';
        ELSIF _operacao < 40 THEN
            _escolhido := 'horario_bloco';
        ELSIF _operacao < 90 THEN
            _escolhido := 'funcionario_inserir';
        ELSE
            _sorteio := random() * _pesos_acumulados[array_length(_pesos_acumulados, 1)];
            _posicao := 1;
            WHILE _pesos_acumulados[_posicao] <= _sorteio LOOP
                _posicao := _posicao + 1;
            END LOOP;
            _escolhido := _cenarios[_posicao];
        END IF;

        CASE _escolhido
        WHEN 'departamento_inserir' THEN
            _departamentos_criados := _departamentos_criados + 1;
            INSERT INTO ensaio.sim_departamento (seq, chave, versao, funcionarios)
            VALUES (_departamentos_criados, ensaio.chave(_departamentos_criados), 0, 0);
            _departamentos_vigentes := _departamentos_vigentes + 1;
            _operacao := _operacao + 1;
            PERFORM ensaio.emitir(
                _operacao,
                'departamento_inserir',
                ensaio.uuid_de('departamento', _departamentos_criados),
                _nome => 'Departamento ' || _departamentos_criados
            );

        WHEN 'departamento_alterar' THEN
            SELECT seq
            INTO _departamento_sorteado
            FROM ensaio.sim_departamento
            ORDER BY chave
            OFFSET ensaio.zipf(_departamentos_vigentes) - 1
            LIMIT 1;

            UPDATE ensaio.sim_departamento
            SET versao = versao + 1
            WHERE seq = _departamento_sorteado
            RETURNING versao INTO _versao_nova;

            _operacao := _operacao + 1;
            PERFORM ensaio.emitir(
                _operacao,
                'departamento_alterar',
                ensaio.uuid_de('departamento', _departamento_sorteado),
                _nome => 'Departamento ' || _departamento_sorteado || ' v' || _versao_nova
            );

        WHEN 'departamento_excluir' THEN
            IF _departamentos_vigentes >= 2 THEN
                SELECT seq, funcionarios
                INTO _departamento_sorteado, _quantidade
                FROM ensaio.sim_departamento
                ORDER BY funcionarios, seq
                LIMIT 1;

                IF _operacao + _quantidade + 1 <= _limite THEN
                    FOR _funcionario_movido IN
                        SELECT seq
                        FROM ensaio.sim_funcionario
                        WHERE departamento = _departamento_sorteado
                        ORDER BY seq
                    LOOP
                        LOOP
                            SELECT seq
                            INTO _departamento_destino
                            FROM ensaio.sim_departamento
                            ORDER BY chave
                            OFFSET ensaio.zipf(_departamentos_vigentes) - 1
                            LIMIT 1;

                            EXIT WHEN _departamento_destino <> _departamento_sorteado;
                        END LOOP;

                        UPDATE ensaio.sim_funcionario SET departamento = _departamento_destino WHERE seq = _funcionario_movido;
                        UPDATE ensaio.sim_departamento SET funcionarios = funcionarios + 1 WHERE seq = _departamento_destino;
                        _operacao := _operacao + 1;
                        PERFORM ensaio.emitir(
                            _operacao,
                            'funcionario_alterar_departamento',
                            ensaio.uuid_de('funcionario', _funcionario_movido),
                            _departamento => ensaio.uuid_de('departamento', _departamento_destino)
                        );
                    END LOOP;

                    DELETE FROM ensaio.sim_horario WHERE departamento = _departamento_sorteado;
                    GET DIAGNOSTICS _horarios_removidos = ROW_COUNT;
                    _horarios_vigentes := _horarios_vigentes - _horarios_removidos;
                    DELETE FROM ensaio.sim_departamento WHERE seq = _departamento_sorteado;
                    _departamentos_vigentes := _departamentos_vigentes - 1;
                    _operacao := _operacao + 1;
                    PERFORM ensaio.emitir(_operacao, 'departamento_excluir', ensaio.uuid_de('departamento', _departamento_sorteado));
                END IF;
            END IF;

        WHEN 'horario_bloco' THEN
            _departamento_sorteado := (_operacao - 5) / 7 + 1;
            _dia_horario           := (_operacao - 5) % 7 + 1;
            _hora_horario          := ensaio.inteiro(6, 18);
            _horarios_criados      := _horarios_criados + 1;
            INSERT INTO ensaio.sim_horario (seq, chave, departamento, dia, hora)
            VALUES (_horarios_criados, ensaio.chave(_horarios_criados), _departamento_sorteado, _dia_horario, _hora_horario);
            _horarios_vigentes := _horarios_vigentes + 1;
            _operacao := _operacao + 1;
            PERFORM ensaio.emitir(
                _operacao,
                'horario_inserir',
                ensaio.uuid_de('horario', _horarios_criados),
                _departamento => ensaio.uuid_de('departamento', _departamento_sorteado),
                _dia => _dias[_dia_horario],
                _hora_inicio => make_time(_hora_horario, 0, 0),
                _hora_fim => make_time(_hora_horario + 4, 0, 0)
            );

        WHEN 'horario_inserir' THEN
            SELECT seq
            INTO _departamento_sorteado
            FROM ensaio.sim_departamento
            ORDER BY chave
            OFFSET ensaio.zipf(_departamentos_vigentes) - 1
            LIMIT 1;

            SELECT array_agg(dia_candidato * 100 + hora_candidata ORDER BY dia_candidato, hora_candidata)
            INTO _faixas_livres
            FROM
                generate_series(1, 7) AS dia_candidato,
                generate_series(6, 18) AS hora_candidata
            WHERE NOT EXISTS (
                SELECT 1
                FROM ensaio.sim_horario
                WHERE
                    departamento = _departamento_sorteado AND
                    dia = dia_candidato AND
                    abs(hora - hora_candidata) < 4
            );

            IF _faixas_livres IS NOT NULL THEN
                _faixa            := _faixas_livres[ensaio.inteiro(1, array_length(_faixas_livres, 1))];
                _dia_horario      := _faixa / 100;
                _hora_horario     := _faixa % 100;
                _horarios_criados := _horarios_criados + 1;
                INSERT INTO ensaio.sim_horario (seq, chave, departamento, dia, hora)
                VALUES (_horarios_criados, ensaio.chave(_horarios_criados), _departamento_sorteado, _dia_horario, _hora_horario);
                _horarios_vigentes := _horarios_vigentes + 1;
                _operacao := _operacao + 1;
                PERFORM ensaio.emitir(
                    _operacao,
                    'horario_inserir',
                    ensaio.uuid_de('horario', _horarios_criados),
                    _departamento => ensaio.uuid_de('departamento', _departamento_sorteado),
                    _dia => _dias[_dia_horario],
                    _hora_inicio => make_time(_hora_horario, 0, 0),
                    _hora_fim => make_time(_hora_horario + 4, 0, 0)
                );
            END IF;

        WHEN 'horario_alterar' THEN
            IF _horarios_vigentes >= 1 THEN
                SELECT seq, departamento, dia, hora
                INTO _horario_sorteado, _departamento_sorteado, _dia_horario, _hora_horario
                FROM ensaio.sim_horario
                ORDER BY chave
                OFFSET ensaio.zipf(_horarios_vigentes) - 1
                LIMIT 1;

                _deslocamento := CASE WHEN random() < 0.5 THEN 1 ELSE -1 END;
                FOR _tentativa IN 1..2 LOOP
                    IF _hora_horario + _deslocamento BETWEEN 6 AND 18 AND NOT EXISTS (
                        SELECT 1
                        FROM ensaio.sim_horario
                        WHERE
                            departamento = _departamento_sorteado AND
                            dia = _dia_horario AND
                            seq <> _horario_sorteado AND
                            abs(hora - (_hora_horario + _deslocamento)) < 4
                    ) THEN
                        UPDATE ensaio.sim_horario SET hora = _hora_horario + _deslocamento WHERE seq = _horario_sorteado;
                        _operacao := _operacao + 1;
                        PERFORM ensaio.emitir(
                            _operacao,
                            'horario_alterar',
                            ensaio.uuid_de('horario', _horario_sorteado),
                            _hora_inicio => make_time(_hora_horario + _deslocamento, 0, 0),
                            _hora_fim => make_time(_hora_horario + _deslocamento + 4, 0, 0)
                        );
                        EXIT;
                    END IF;
                    _deslocamento := -_deslocamento;
                END LOOP;
            END IF;

        WHEN 'horario_excluir' THEN
            IF _horarios_vigentes >= 1 THEN
                SELECT seq
                INTO _horario_sorteado
                FROM ensaio.sim_horario
                ORDER BY chave
                OFFSET ensaio.zipf(_horarios_vigentes) - 1
                LIMIT 1;

                DELETE FROM ensaio.sim_horario WHERE seq = _horario_sorteado;
                _horarios_vigentes := _horarios_vigentes - 1;
                _operacao := _operacao + 1;
                PERFORM ensaio.emitir(_operacao, 'horario_excluir', ensaio.uuid_de('horario', _horario_sorteado));
            END IF;

        WHEN 'funcionario_inserir' THEN
            SELECT seq, funcionarios
            INTO _departamento_sorteado, _quantidade
            FROM ensaio.sim_departamento
            ORDER BY chave
            OFFSET ensaio.zipf(_departamentos_vigentes) - 1
            LIMIT 1;

            _lider_novo := NULL;
            IF _quantidade > 0 THEN
                SELECT seq
                INTO _lider_novo
                FROM ensaio.sim_funcionario
                WHERE departamento = _departamento_sorteado
                ORDER BY seq
                OFFSET ensaio.inteiro(0, _quantidade - 1)
                LIMIT 1;
            END IF;

            _cargo_novo           := ensaio.inteiro(1, 10);
            _salario_novo         := round((1500 + random() * 13500)::numeric, 2);
            _nascido              := date '1960-01-01' + ensaio.inteiro(0, 16435);
            _genero_sorteado      := ensaio.inteiro(1, 3);
            _percentual           := ensaio.inteiro(150, 200);
            _rua                  := ensaio.inteiro(1, 500);
            _numero_casa          := ensaio.inteiro(1, 2000);
            _funcionarios_criados := _funcionarios_criados + 1;

            INSERT INTO ensaio.sim_funcionario (seq, chave, departamento, lider, cargo, salario, proximo_tipo)
            VALUES (_funcionarios_criados, ensaio.chave(_funcionarios_criados), _departamento_sorteado, _lider_novo, _cargo_novo, _salario_novo, 1);

            UPDATE ensaio.sim_departamento SET funcionarios = funcionarios + 1 WHERE seq = _departamento_sorteado;
            _funcionarios_vigentes := _funcionarios_vigentes + 1;
            _operacao := _operacao + 1;
            PERFORM ensaio.emitir(
                _operacao,
                'funcionario_inserir',
                ensaio.uuid_de('funcionario', _funcionarios_criados),
                _departamento => ensaio.uuid_de('departamento', _departamento_sorteado),
                _funcionario_lider => ensaio.uuid_de('funcionario', _lider_novo),
                _nome_civil => 'Funcionário ' || _funcionarios_criados,
                _documento => lpad(_funcionarios_criados::text, 11, '0'),
                _nascimento => _nascido,
                _genero => _generos[_genero_sorteado],
                _email => 'funcionario' || _funcionarios_criados || '@empresa.com.br',
                _telefone => '+55 42 9' || lpad(_funcionarios_criados::text, 8, '0'),
                _endereco => 'Rua ' || _rua || ', ' || _numero_casa,
                _cargo => _cargos[_cargo_novo],
                _salario => _salario_novo,
                _percentual_hora_extra => _percentual
            );

        WHEN 'funcionario_alterar' THEN
            IF _funcionarios_vigentes >= 1 THEN
                SELECT seq, departamento, lider, cargo, salario
                INTO _funcionario_sorteado, _departamento_sorteado, _lider_atual, _cargo_atual, _salario_atual
                FROM ensaio.sim_funcionario
                ORDER BY chave
                OFFSET ensaio.zipf(_funcionarios_vigentes) - 1
                LIMIT 1;

                _sorteio := random();
                IF _sorteio < 0.4 THEN
                    _cargo_novo := ensaio.inteiro(1, 9);
                    IF _cargo_novo >= _cargo_atual THEN
                        _cargo_novo := _cargo_novo + 1;
                    END IF;
                    UPDATE ensaio.sim_funcionario SET cargo = _cargo_novo WHERE seq = _funcionario_sorteado;
                    _operacao := _operacao + 1;
                    PERFORM ensaio.emitir(
                        _operacao,
                        'funcionario_alterar_cargo',
                        ensaio.uuid_de('funcionario', _funcionario_sorteado),
                        _cargo => _cargos[_cargo_novo]
                    );
                ELSIF _sorteio < 0.8 THEN
                    _deslocamento := ensaio.inteiro(1, 10);
                    IF random() < 0.5 THEN
                        _deslocamento := -_deslocamento;
                    END IF;
                    _salario_novo := round(_salario_atual * (100 + _deslocamento) / 100, 2);
                    UPDATE ensaio.sim_funcionario SET salario = _salario_novo WHERE seq = _funcionario_sorteado;
                    _operacao := _operacao + 1;
                    PERFORM ensaio.emitir(
                        _operacao,
                        'funcionario_alterar_salario',
                        ensaio.uuid_de('funcionario', _funcionario_sorteado),
                        _salario => _salario_novo
                    );
                ELSIF _sorteio < 0.9 THEN
                    IF _departamentos_vigentes >= 2 THEN
                        LOOP
                            SELECT seq
                            INTO _departamento_destino
                            FROM ensaio.sim_departamento
                            ORDER BY chave
                            OFFSET ensaio.zipf(_departamentos_vigentes) - 1
                            LIMIT 1;

                            EXIT WHEN _departamento_destino <> _departamento_sorteado;
                        END LOOP;

                        UPDATE ensaio.sim_funcionario SET departamento = _departamento_destino WHERE seq = _funcionario_sorteado;
                        UPDATE ensaio.sim_departamento SET funcionarios = funcionarios - 1 WHERE seq = _departamento_sorteado;
                        UPDATE ensaio.sim_departamento SET funcionarios = funcionarios + 1 WHERE seq = _departamento_destino;
                        _operacao := _operacao + 1;
                        PERFORM ensaio.emitir(
                            _operacao,
                            'funcionario_alterar_departamento',
                            ensaio.uuid_de('funcionario', _funcionario_sorteado),
                            _departamento => ensaio.uuid_de('departamento', _departamento_destino)
                        );
                    END IF;
                ELSE
                    SELECT count(*)
                    INTO _quantidade
                    FROM ensaio.sim_funcionario
                    WHERE
                        departamento = _departamento_sorteado AND
                        seq < _funcionario_sorteado AND
                        seq IS DISTINCT FROM _lider_atual;

                    _possivel := true;
                    IF _quantidade > 0 THEN
                        SELECT seq
                        INTO _lider_novo
                        FROM ensaio.sim_funcionario
                        WHERE
                            departamento = _departamento_sorteado AND
                            seq < _funcionario_sorteado AND
                            seq IS DISTINCT FROM _lider_atual
                        ORDER BY seq
                        OFFSET ensaio.inteiro(0, _quantidade - 1)
                        LIMIT 1;
                    ELSIF _lider_atual IS NOT NULL THEN
                        _lider_novo := NULL;
                    ELSE
                        _possivel := false;
                    END IF;

                    IF _possivel THEN
                        UPDATE ensaio.sim_funcionario SET lider = _lider_novo WHERE seq = _funcionario_sorteado;
                        _operacao := _operacao + 1;
                        PERFORM ensaio.emitir(
                            _operacao,
                            'funcionario_alterar_lider',
                            ensaio.uuid_de('funcionario', _funcionario_sorteado),
                            _funcionario_lider => ensaio.uuid_de('funcionario', _lider_novo)
                        );
                    END IF;
                END IF;
            END IF;

        WHEN 'funcionario_excluir' THEN
            IF _funcionarios_vigentes >= 2 THEN
                SELECT seq, departamento, lider
                INTO _funcionario_sorteado, _departamento_sorteado, _lider_atual
                FROM ensaio.sim_funcionario
                ORDER BY chave
                OFFSET ensaio.zipf(_funcionarios_vigentes) - 1
                LIMIT 1;

                _hoje := ensaio.data(_operacao + 1);

                SELECT count(*)
                INTO _quantidade
                FROM ensaio.sim_ferias
                WHERE
                    funcionario = _funcionario_sorteado AND
                    status IN ('solicitada', 'aprovada') AND
                    inicio > _hoje;

                SELECT _quantidade + count(*)
                INTO _quantidade
                FROM ensaio.sim_funcionario
                WHERE lider = _funcionario_sorteado;

                IF _operacao + _quantidade + 1 <= _limite THEN
                    FOR _ferias_cancelada IN
                        SELECT seq
                        FROM ensaio.sim_ferias
                        WHERE
                            funcionario = _funcionario_sorteado AND
                            status IN ('solicitada', 'aprovada') AND
                            inicio > _hoje
                        ORDER BY seq
                    LOOP
                        _operacao := _operacao + 1;
                        PERFORM ensaio.emitir(
                            _operacao,
                            'ferias_mudar_status',
                            ensaio.uuid_de('ferias', _ferias_cancelada),
                            _status => 'cancelada'
                        );
                    END LOOP;

                    FOR _subordinado IN
                        SELECT seq
                        FROM ensaio.sim_funcionario
                        WHERE lider = _funcionario_sorteado
                        ORDER BY seq
                    LOOP
                        UPDATE ensaio.sim_funcionario SET lider = _lider_atual WHERE seq = _subordinado;
                        _operacao := _operacao + 1;
                        PERFORM ensaio.emitir(
                            _operacao,
                            'funcionario_alterar_lider',
                            ensaio.uuid_de('funcionario', _subordinado),
                            _funcionario_lider => ensaio.uuid_de('funcionario', _lider_atual)
                        );
                    END LOOP;

                    DELETE FROM ensaio.sim_ponto WHERE funcionario = _funcionario_sorteado;
                    DELETE FROM ensaio.sim_ferias WHERE funcionario = _funcionario_sorteado;
                    DELETE FROM ensaio.sim_funcionario WHERE seq = _funcionario_sorteado;
                    UPDATE ensaio.sim_departamento SET funcionarios = funcionarios - 1 WHERE seq = _departamento_sorteado;
                    _funcionarios_vigentes := _funcionarios_vigentes - 1;
                    _operacao := _operacao + 1;
                    PERFORM ensaio.emitir(_operacao, 'funcionario_excluir', ensaio.uuid_de('funcionario', _funcionario_sorteado));
                END IF;
            END IF;

        WHEN 'ponto_registrar' THEN
            IF _funcionarios_vigentes >= 1 THEN
                SELECT seq, proximo_tipo
                INTO _funcionario_sorteado, _tipo_ponto
                FROM ensaio.sim_funcionario
                ORDER BY chave
                OFFSET ensaio.zipf(_funcionarios_vigentes) - 1
                LIMIT 1;

                _momento := ensaio.instante(_operacao + 1);
                IF NOT EXISTS (
                    SELECT 1
                    FROM ensaio.sim_ponto
                    WHERE
                        funcionario = _funcionario_sorteado AND
                        registro = _momento
                ) THEN
                    UPDATE ensaio.sim_funcionario SET proximo_tipo = 3 - _tipo_ponto WHERE seq = _funcionario_sorteado;
                    _pontos_criados := _pontos_criados + 1;
                    INSERT INTO ensaio.sim_ponto (seq, funcionario, registro) VALUES (_pontos_criados, _funcionario_sorteado, _momento);
                    _operacao := _operacao + 1;
                    PERFORM ensaio.emitir(
                        _operacao,
                        'ponto_registrar',
                        ensaio.uuid_de('ponto', _pontos_criados),
                        _funcionario => ensaio.uuid_de('funcionario', _funcionario_sorteado),
                        _registro => _momento,
                        _tipo => _tipos[_tipo_ponto]
                    );
                END IF;
            END IF;

        WHEN 'ponto_ajustar' THEN
            IF _funcionarios_vigentes >= 1 THEN
                SELECT seq
                INTO _funcionario_sorteado
                FROM ensaio.sim_funcionario
                ORDER BY chave
                OFFSET ensaio.zipf(_funcionarios_vigentes) - 1
                LIMIT 1;

                SELECT seq, registro
                INTO _ponto_sorteado, _momento
                FROM ensaio.sim_ponto
                WHERE funcionario = _funcionario_sorteado
                ORDER BY registro DESC
                LIMIT 1;

                IF FOUND THEN
                    _deslocamento := ensaio.inteiro(1, 30);
                    IF random() < 0.5 THEN
                        _deslocamento := -_deslocamento;
                    END IF;
                    _motivo := _motivos[ensaio.inteiro(1, 4)];
                    FOR _tentativa IN 1..2 LOOP
                        _registro_novo := _momento + _deslocamento * interval '1 minute';
                        IF NOT EXISTS (
                            SELECT 1
                            FROM ensaio.sim_ponto
                            WHERE
                                funcionario = _funcionario_sorteado AND
                                registro = _registro_novo
                        ) THEN
                            UPDATE ensaio.sim_ponto SET registro = _registro_novo WHERE seq = _ponto_sorteado;
                            _operacao := _operacao + 1;
                            PERFORM ensaio.emitir(
                                _operacao,
                                'ponto_ajustar',
                                ensaio.uuid_de('ponto', _ponto_sorteado),
                                _registro => _registro_novo,
                                _justificativa => _motivo
                            );
                            EXIT;
                        END IF;
                        _deslocamento := -_deslocamento;
                    END LOOP;
                END IF;
            END IF;

        WHEN 'ponto_remover' THEN
            IF _funcionarios_vigentes >= 1 AND _operacao + 2 <= _limite THEN
                SELECT seq
                INTO _funcionario_sorteado
                FROM ensaio.sim_funcionario
                ORDER BY chave
                OFFSET ensaio.zipf(_funcionarios_vigentes) - 1
                LIMIT 1;

                SELECT seq
                INTO _ponto_sorteado
                FROM ensaio.sim_ponto
                WHERE funcionario = _funcionario_sorteado
                ORDER BY registro DESC
                LIMIT 1;

                IF FOUND THEN
                    DELETE FROM ensaio.sim_ponto WHERE seq = _ponto_sorteado;
                    _operacao := _operacao + 1;
                    PERFORM ensaio.emitir(
                        _operacao,
                        'ponto_justificar_remocao',
                        ensaio.uuid_de('ponto', _ponto_sorteado),
                        _justificativa => 'Marcação indevida'
                    );
                    _operacao := _operacao + 1;
                    PERFORM ensaio.emitir(_operacao, 'ponto_remover', ensaio.uuid_de('ponto', _ponto_sorteado));
                END IF;
            END IF;

        WHEN 'ferias_solicitar' THEN
            IF _funcionarios_vigentes >= 1 THEN
                SELECT seq
                INTO _funcionario_sorteado
                FROM ensaio.sim_funcionario
                ORDER BY chave
                OFFSET ensaio.zipf(_funcionarios_vigentes) - 1
                LIMIT 1;

                _hoje := ensaio.data(_operacao + 1);
                FOR _tentativa IN 1..5 LOOP
                    _inicio_ferias  := _hoje + ensaio.inteiro(30, 120);
                    _termino_ferias := _inicio_ferias + ensaio.inteiro(5, 30) - 1;
                    IF NOT EXISTS (
                        SELECT 1
                        FROM ensaio.sim_ferias
                        WHERE
                            funcionario = _funcionario_sorteado AND
                            status NOT IN ('recusada', 'cancelada') AND
                            fim >= _inicio_ferias AND
                            inicio <= _termino_ferias
                    ) THEN
                        _ferias_criadas := _ferias_criadas + 1;
                        INSERT INTO ensaio.sim_ferias (seq, funcionario, inicio, fim, status)
                        VALUES (_ferias_criadas, _funcionario_sorteado, _inicio_ferias, _termino_ferias, 'solicitada');
                        _operacao := _operacao + 1;
                        PERFORM ensaio.emitir(
                            _operacao,
                            'ferias_solicitar',
                            ensaio.uuid_de('ferias', _ferias_criadas),
                            _funcionario => ensaio.uuid_de('funcionario', _funcionario_sorteado),
                            _inicio => _inicio_ferias,
                            _fim => _termino_ferias,
                            _status => 'solicitada'
                        );
                        EXIT;
                    END IF;
                END LOOP;
            END IF;

        WHEN 'ferias_mudar_status' THEN
            IF _funcionarios_vigentes >= 1 THEN
                SELECT seq
                INTO _funcionario_sorteado
                FROM ensaio.sim_funcionario
                ORDER BY chave
                OFFSET ensaio.zipf(_funcionarios_vigentes) - 1
                LIMIT 1;

                _hoje := ensaio.data(_operacao + 1);

                SELECT seq, status
                INTO _ferias_sorteada, _situacao
                FROM ensaio.sim_ferias
                WHERE
                    funcionario = _funcionario_sorteado AND
                    status IN ('solicitada', 'aprovada') AND
                    (status = 'solicitada' OR fim < _hoje)
                ORDER BY seq
                LIMIT 1;

                IF FOUND THEN
                    IF _situacao = 'aprovada' THEN
                        _status_novo := 'concluida';
                    ELSE
                        _sorteio := random();
                        _status_novo := CASE
                            WHEN _sorteio < 0.7 THEN 'aprovada'
                            WHEN _sorteio < 0.9 THEN 'recusada'
                            ELSE 'cancelada'
                        END;
                    END IF;
                    UPDATE ensaio.sim_ferias SET status = _status_novo WHERE seq = _ferias_sorteada;
                    _operacao := _operacao + 1;
                    PERFORM ensaio.emitir(
                        _operacao,
                        'ferias_mudar_status',
                        ensaio.uuid_de('ferias', _ferias_sorteada),
                        _status => _status_novo
                    );
                END IF;
            END IF;
        END CASE;
    END LOOP;
END;
$$;

COMMIT;

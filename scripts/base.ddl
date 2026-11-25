BEGIN;

CREATE SCHEMA base;

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TYPE base.dia_semana AS ENUM ('segunda', 'terca', 'quarta', 'quinta', 'sexta', 'sabado', 'domingo');
CREATE TYPE base.ferias_status AS ENUM ('solicitada', 'aprovada', 'recusada', 'cancelada', 'concluida');
CREATE TYPE base.ponto_tipo AS ENUM ('entrada', 'saida');
CREATE TYPE base.genero AS ENUM ('masculino', 'feminino', 'outro');
CREATE TYPE base.timerange AS RANGE (subtype = time);

CREATE TABLE base.departamento (
    id   uuid NOT NULL DEFAULT gen_random_uuid(),
    nome text NOT NULL,

    CONSTRAINT departamento_pk PRIMARY KEY (id)
);
CREATE UNIQUE INDEX departamento_uq_nome ON base.departamento (lower(nome));

CREATE TABLE base.horario (
    id           uuid NOT NULL DEFAULT gen_random_uuid(),
    departamento uuid NOT NULL,
    inicio       time NOT NULL,
    fim          time NOT NULL,
    dia          base.dia_semana NOT NULL,

    CONSTRAINT horario_pk              PRIMARY KEY (id),
    CONSTRAINT horario_fk_departamento FOREIGN KEY (departamento) REFERENCES base.departamento (id) ON DELETE CASCADE,
    CONSTRAINT horario_uq_intervalo    EXCLUDE USING gist (departamento WITH =, dia WITH =, base.timerange(inicio, fim, '[)') WITH &&),
    CONSTRAINT horario_ck_intervalo    CHECK (inicio < fim)
);

CREATE TABLE base.funcionario (
    id                    uuid NOT NULL DEFAULT gen_random_uuid(),
    nome_civil            text NOT NULL,
    nome_social           text,
    documento             text NOT NULL,
    nascimento            date NOT NULL,
    genero                base.genero NOT NULL,
    email                 text,
    telefone              text,
    endereco              text,
    funcionario_lider     uuid,
    departamento          uuid NOT NULL,
    cargo                 text NOT NULL,
    salario               numeric NOT NULL,
    percentual_hora_extra numeric NOT NULL,

    CONSTRAINT funcionario_pk PRIMARY KEY (id),
    CONSTRAINT funcionario_fk_funcionario_lider     FOREIGN KEY (funcionario_lider) REFERENCES base.funcionario (id),
    CONSTRAINT funcionario_fk_departamento          FOREIGN KEY (departamento) REFERENCES base.departamento (id),
    CONSTRAINT funcionario_ck_salario               CHECK (salario >= 0),
    CONSTRAINT funcionario_ck_percentual_hora_extra CHECK (percentual_hora_extra >= 150)
);
CREATE UNIQUE INDEX funcionario_uq_documento ON base.funcionario (lower(documento));

CREATE TABLE base.ferias (
    id          uuid NOT NULL DEFAULT gen_random_uuid(),
    funcionario uuid NOT NULL,
    inicio      date NOT NULL,
    fim         date NOT NULL,
    status      base.ferias_status NOT NULL,
    observacao  text,

    CONSTRAINT ferias_pk             PRIMARY KEY (id),
    CONSTRAINT ferias_fk_funcionario FOREIGN KEY (funcionario) REFERENCES base.funcionario (id) ON DELETE CASCADE,
    CONSTRAINT ferias_uq_intervalo   EXCLUDE USING gist (funcionario WITH =, daterange(inicio, fim, '[]') WITH &&) WHERE (status NOT IN ('recusada', 'cancelada')),
    CONSTRAINT ferias_ck_intervalo   CHECK (inicio <= fim)
);

CREATE TABLE base.ponto (
    id            uuid NOT NULL DEFAULT gen_random_uuid(),
    funcionario   uuid NOT NULL,
    registro      timestamptz NOT NULL,
    tipo          base.ponto_tipo NOT NULL,
    justificativa text,

    CONSTRAINT ponto_pk             PRIMARY KEY (id),
    CONSTRAINT ponto_fk_funcionario FOREIGN KEY (funcionario) REFERENCES base.funcionario (id) ON DELETE CASCADE,
    CONSTRAINT ponto_uq_registro    UNIQUE (funcionario, registro)
);

COMMIT;

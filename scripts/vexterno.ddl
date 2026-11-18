BEGIN;

CREATE SCHEMA vexterno;

CREATE TABLE vexterno.departamento (
    LIKE base.departamento INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    CONSTRAINT departamento_pk PRIMARY KEY (id)
);
CREATE UNIQUE INDEX departamento_uq_nome ON vexterno.departamento (lower(nome));

CREATE TABLE vexterno.horario (
    LIKE base.horario INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    CONSTRAINT horario_pk              PRIMARY KEY (id),
    CONSTRAINT horario_fk_departamento FOREIGN KEY (departamento) REFERENCES vexterno.departamento (id),
    CONSTRAINT horario_uq_intervalo    EXCLUDE USING gist (departamento WITH =, dia WITH =, base.timerange(inicio, fim, '[)') WITH &&)
);

CREATE TABLE vexterno.funcionario (
    LIKE base.funcionario INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    CONSTRAINT funcionario_pk                   PRIMARY KEY (id),
    CONSTRAINT funcionario_fk_funcionario_lider FOREIGN KEY (funcionario_lider) REFERENCES vexterno.funcionario (id),
    CONSTRAINT funcionario_fk_departamento      FOREIGN KEY (departamento) REFERENCES vexterno.departamento (id)
);
CREATE UNIQUE INDEX funcionario_uq_documento ON vexterno.funcionario (lower(documento));
CREATE UNIQUE INDEX funcionario_uq_email     ON vexterno.funcionario (lower(email));
CREATE UNIQUE INDEX funcionario_uq_telefone  ON vexterno.funcionario (lower(telefone));

CREATE TABLE vexterno.ferias (
    LIKE base.ferias INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    CONSTRAINT ferias_pk             PRIMARY KEY (id),
    CONSTRAINT ferias_fk_funcionario FOREIGN KEY (funcionario) REFERENCES vexterno.funcionario (id),
    CONSTRAINT ferias_uq_intervalo   EXCLUDE USING gist (funcionario WITH =, daterange(inicio, fim, '[]') WITH &&) WHERE (status NOT IN ('recusada', 'cancelada'))
);

CREATE TABLE vexterno.ponto (
    LIKE base.ponto INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    CONSTRAINT ponto_pk             PRIMARY KEY (id),
    CONSTRAINT ponto_fk_funcionario FOREIGN KEY (funcionario) REFERENCES vexterno.funcionario (id),
    CONSTRAINT ponto_uq_registro    UNIQUE (funcionario, registro)
);

CREATE TABLE vexterno.historia_departamento (
    valido_desde timestamptz NOT NULL DEFAULT now(),
    valido_ate   timestamptz NOT NULL DEFAULT 'infinity',
    LIKE vexterno.departamento INCLUDING CONSTRAINTS,
    CONSTRAINT historia_departamento_pk          PRIMARY KEY (id, valido_desde),
    CONSTRAINT historia_departamento_uq_nome     EXCLUDE USING gist (lower(nome) WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT historia_departamento_uq_id       EXCLUDE USING gist (id WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT historia_departamento_ck_validade CHECK (valido_desde < valido_ate)
);

CREATE TABLE vexterno.historia_horario (
    valido_desde timestamptz NOT NULL DEFAULT now(),
    valido_ate   timestamptz NOT NULL DEFAULT 'infinity',
    LIKE vexterno.horario INCLUDING CONSTRAINTS,
    CONSTRAINT historia_horario_pk           PRIMARY KEY (id, valido_desde),
    CONSTRAINT historia_horario_uq_intervalo EXCLUDE USING gist (departamento WITH =, dia WITH =, base.timerange(inicio, fim, '[)') WITH &&, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT historia_horario_uq_id        EXCLUDE USING gist (id WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT historia_horario_ck_validade  CHECK (valido_desde < valido_ate)
);
ALTER TABLE vexterno.historia_horario RENAME CONSTRAINT horario_ck_intervalo TO historia_horario_ck_intervalo;

CREATE TABLE vexterno.historia_funcionario (
    valido_desde timestamptz NOT NULL DEFAULT now(),
    valido_ate   timestamptz NOT NULL DEFAULT 'infinity',
    LIKE vexterno.funcionario INCLUDING CONSTRAINTS,
    CONSTRAINT historia_funcionario_pk           PRIMARY KEY (id, valido_desde),
    CONSTRAINT historia_funcionario_uq_documento EXCLUDE USING gist (lower(documento) WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT historia_funcionario_uq_email     EXCLUDE USING gist (lower(email) WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT historia_funcionario_uq_telefone  EXCLUDE USING gist (lower(telefone) WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT historia_funcionario_uq_id        EXCLUDE USING gist (id WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT historia_funcionario_ck_validade  CHECK (valido_desde < valido_ate)
);
ALTER TABLE vexterno.historia_funcionario RENAME CONSTRAINT funcionario_ck_admissao              TO historia_funcionario_ck_admissao;
ALTER TABLE vexterno.historia_funcionario RENAME CONSTRAINT funcionario_ck_salario               TO historia_funcionario_ck_salario;
ALTER TABLE vexterno.historia_funcionario RENAME CONSTRAINT funcionario_ck_percentual_hora_extra TO historia_funcionario_ck_percentual_hora_extra;

CREATE TABLE vexterno.historia_ferias (
    data_insercao timestamptz NOT NULL DEFAULT now(),
    data_exclusao timestamptz,
    LIKE vexterno.ferias INCLUDING CONSTRAINTS,
    CONSTRAINT historia_ferias_pk           PRIMARY KEY (id, data_insercao),
    CONSTRAINT historia_ferias_uq_intervalo EXCLUDE USING gist (funcionario WITH =, daterange(inicio, fim, '[]') WITH &&, tstzrange(data_insercao, data_exclusao) WITH &&) WHERE (status NOT IN ('recusada', 'cancelada')),
    CONSTRAINT historia_ferias_uq_id        EXCLUDE USING gist (id WITH =, tstzrange(data_insercao, data_exclusao) WITH &&),
    CONSTRAINT historia_ferias_ck_transacao CHECK (data_insercao < data_exclusao)
);
ALTER TABLE vexterno.historia_ferias RENAME CONSTRAINT ferias_ck_intervalo TO historia_ferias_ck_intervalo;

CREATE TABLE vexterno.historia_ponto (
    data_insercao timestamptz NOT NULL DEFAULT now(),
    data_exclusao timestamptz,
    LIKE vexterno.ponto INCLUDING CONSTRAINTS,
    CONSTRAINT historia_ponto_pk           PRIMARY KEY (id, data_insercao),
    CONSTRAINT historia_ponto_uq_registro  EXCLUDE USING gist (funcionario WITH =, registro WITH =, tstzrange(data_insercao, data_exclusao) WITH &&),
    CONSTRAINT historia_ponto_uq_id        EXCLUDE USING gist (id WITH =, tstzrange(data_insercao, data_exclusao) WITH &&),
    CONSTRAINT historia_ponto_ck_transacao CHECK (data_insercao < data_exclusao)
);



CREATE OR REPLACE FUNCTION vexterno.departamento_versionar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        UPDATE vexterno.historia_departamento
           SET valido_ate = now()
         WHERE id = OLD.id AND valido_ate = 'infinity' AND valido_desde < now();

        IF NOT FOUND THEN
            DELETE FROM vexterno.historia_departamento WHERE id = OLD.id AND valido_ate = 'infinity';
        END IF;
    END IF;

    IF TG_OP <> 'DELETE' THEN
        INSERT INTO vexterno.historia_departamento SELECT now(), 'infinity', (NEW).*;
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vexterno.horario_versionar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        UPDATE vexterno.historia_horario
           SET valido_ate = now()
         WHERE id = OLD.id AND valido_ate = 'infinity' AND valido_desde < now();

        IF NOT FOUND THEN
            DELETE FROM vexterno.historia_horario WHERE id = OLD.id AND valido_ate = 'infinity';
        END IF;
    END IF;

    IF TG_OP <> 'DELETE' THEN
        INSERT INTO vexterno.historia_horario SELECT now(), 'infinity', (NEW).*;
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vexterno.funcionario_versionar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        UPDATE vexterno.historia_funcionario
           SET valido_ate = now()
         WHERE id = OLD.id AND valido_ate = 'infinity' AND valido_desde < now();

        IF NOT FOUND THEN
            DELETE FROM vexterno.historia_funcionario WHERE id = OLD.id AND valido_ate = 'infinity';
        END IF;
    END IF;

    IF TG_OP <> 'DELETE' THEN
        INSERT INTO vexterno.historia_funcionario SELECT now(), 'infinity', (NEW).*;
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vexterno.ferias_versionar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        UPDATE vexterno.historia_ferias
           SET data_exclusao = now()
         WHERE id = OLD.id AND data_exclusao IS NULL AND data_insercao < now();

        IF NOT FOUND THEN
            DELETE FROM vexterno.historia_ferias WHERE id = OLD.id AND data_exclusao IS NULL;
        END IF;
    END IF;

    IF TG_OP <> 'DELETE' THEN
        INSERT INTO vexterno.historia_ferias SELECT now(), NULL, (NEW).*;
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vexterno.ponto_versionar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        UPDATE vexterno.historia_ponto
           SET data_exclusao = now()
         WHERE id = OLD.id AND data_exclusao IS NULL AND data_insercao < now();

        IF NOT FOUND THEN
            DELETE FROM vexterno.historia_ponto WHERE id = OLD.id AND data_exclusao IS NULL;
        END IF;
    END IF;

    IF TG_OP <> 'DELETE' THEN
        INSERT INTO vexterno.historia_ponto SELECT now(), NULL, (NEW).*;
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER versionar AFTER INSERT OR UPDATE OR DELETE ON vexterno.departamento FOR EACH ROW
    WHEN (lower(current_setting('vexterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vexterno.departamento_versionar();

CREATE TRIGGER versionar AFTER INSERT OR UPDATE OR DELETE ON vexterno.horario FOR EACH ROW
    WHEN (lower(current_setting('vexterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vexterno.horario_versionar();

CREATE TRIGGER versionar AFTER INSERT OR UPDATE OR DELETE ON vexterno.funcionario FOR EACH ROW
    WHEN (lower(current_setting('vexterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vexterno.funcionario_versionar();

CREATE TRIGGER versionar AFTER INSERT OR UPDATE OR DELETE ON vexterno.ferias FOR EACH ROW
    WHEN (lower(current_setting('vexterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vexterno.ferias_versionar();

CREATE TRIGGER versionar AFTER INSERT OR UPDATE OR DELETE ON vexterno.ponto FOR EACH ROW
    WHEN (lower(current_setting('vexterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vexterno.ponto_versionar();

COMMIT;

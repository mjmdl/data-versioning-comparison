BEGIN;

CREATE SCHEMA vinterno;

CREATE TABLE vinterno.departamento (
    entidade     uuid NOT NULL,
    valido_desde timestamptz NOT NULL DEFAULT now(),
    valido_ate   timestamptz NOT NULL DEFAULT 'infinity',
    LIKE base.departamento INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    CONSTRAINT departamento_pk          PRIMARY KEY (id),
    CONSTRAINT departamento_uq_nome     EXCLUDE USING gist (lower(nome) WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT departamento_uq_entidade EXCLUDE USING gist (entidade WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT departamento_ck_validade CHECK (valido_desde < valido_ate)
);

CREATE TABLE vinterno.horario (
    entidade     uuid NOT NULL,
    valido_desde timestamptz NOT NULL DEFAULT now(),
    valido_ate   timestamptz NOT NULL DEFAULT 'infinity',
    LIKE base.horario INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    CONSTRAINT horario_pk              PRIMARY KEY (id),
    CONSTRAINT horario_fk_departamento FOREIGN KEY (departamento) REFERENCES vinterno.departamento (id),
    CONSTRAINT horario_uq_intervalo    EXCLUDE USING gist (departamento WITH =, dia WITH =, base.timerange(inicio, fim, '[)') WITH &&, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT horario_uq_entidade     EXCLUDE USING gist (entidade WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT horario_ck_validade     CHECK (valido_desde < valido_ate)
);

CREATE TABLE vinterno.funcionario (
    entidade     uuid NOT NULL,
    valido_desde timestamptz NOT NULL DEFAULT now(),
    valido_ate   timestamptz NOT NULL DEFAULT 'infinity',
    LIKE base.funcionario INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    CONSTRAINT funcionario_pk                   PRIMARY KEY (id),
    CONSTRAINT funcionario_fk_funcionario_lider FOREIGN KEY (funcionario_lider) REFERENCES vinterno.funcionario (id),
    CONSTRAINT funcionario_fk_departamento      FOREIGN KEY (departamento) REFERENCES vinterno.departamento (id),
    CONSTRAINT funcionario_uq_documento         EXCLUDE USING gist (lower(documento) WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT funcionario_uq_email             EXCLUDE USING gist (lower(email) WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT funcionario_uq_telefone          EXCLUDE USING gist (lower(telefone) WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT funcionario_uq_entidade          EXCLUDE USING gist (entidade WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT funcionario_ck_validade          CHECK (valido_desde < valido_ate)
);

CREATE TABLE vinterno.ferias (
    entidade      uuid NOT NULL,
    data_insercao timestamptz NOT NULL DEFAULT now(),
    data_exclusao timestamptz,
    LIKE base.ferias INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    CONSTRAINT ferias_pk             PRIMARY KEY (id),
    CONSTRAINT ferias_fk_funcionario FOREIGN KEY (funcionario) REFERENCES vinterno.funcionario (id),
    CONSTRAINT ferias_uq_intervalo   EXCLUDE USING gist (funcionario WITH =, daterange(inicio, fim, '[]') WITH &&, tstzrange(data_insercao, data_exclusao) WITH &&) WHERE (status NOT IN ('recusada', 'cancelada')),
    CONSTRAINT ferias_uq_entidade    EXCLUDE USING gist (entidade WITH =, tstzrange(data_insercao, data_exclusao) WITH &&),
    CONSTRAINT ferias_ck_transacao   CHECK (data_insercao < data_exclusao)
);

CREATE TABLE vinterno.ponto (
    entidade      uuid NOT NULL,
    data_insercao timestamptz NOT NULL DEFAULT now(),
    data_exclusao timestamptz,
    LIKE base.ponto INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    CONSTRAINT ponto_pk             PRIMARY KEY (id),
    CONSTRAINT ponto_fk_funcionario FOREIGN KEY (funcionario) REFERENCES vinterno.funcionario (id),
    CONSTRAINT ponto_uq_registro    EXCLUDE USING gist (funcionario WITH =, registro WITH =, tstzrange(data_insercao, data_exclusao) WITH &&),
    CONSTRAINT ponto_uq_entidade    EXCLUDE USING gist (entidade WITH =, tstzrange(data_insercao, data_exclusao) WITH &&),
    CONSTRAINT ponto_ck_transacao   CHECK (data_insercao < data_exclusao)
);



CREATE OR REPLACE FUNCTION vinterno.versionando() RETURNS boolean LANGUAGE sql AS $$
    SELECT pg_trigger_depth() <= 1 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false';
$$;

CREATE OR REPLACE FUNCTION vinterno.before_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.entidade = coalesce(NEW.entidade, NEW.id);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.validade_before_update() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT vinterno.versionando() THEN
        RETURN NEW;
    END IF;

    IF OLD.valido_ate <> 'infinity' THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos enquanto ''vinterno.versionando'' está ativo.';
    END IF;

    NEW.valido_desde := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.transacao_before_update() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT vinterno.versionando() THEN
        RETURN NEW;
    END IF;

    IF OLD.data_exclusao IS NOT NULL THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos enquanto ''vinterno.versionando'' está ativo.';
    END IF;

    NEW.data_insercao := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.departamento_after_update() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE copia vinterno.departamento;
BEGIN
    IF NOT vinterno.versionando() OR OLD.valido_desde = NEW.valido_desde THEN
        RETURN NULL;
    END IF;

    copia            := OLD;
    copia.id         := gen_random_uuid();
    copia.valido_ate := NEW.valido_desde;
    INSERT INTO vinterno.departamento SELECT (copia).*;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.departamento_before_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT vinterno.versionando() THEN
        RETURN OLD;
    END IF;

    IF OLD.valido_ate <> 'infinity' THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos enquanto ''vinterno.versionando'' está ativo.';
    END IF;

    IF OLD.valido_desde = now() THEN
        RETURN OLD;
    END IF;

    UPDATE vinterno.departamento SET valido_ate = now() WHERE id = OLD.id;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.horario_after_update() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE copia vinterno.horario;
BEGIN
    IF NOT vinterno.versionando() OR OLD.valido_desde = NEW.valido_desde THEN
        RETURN NULL;
    END IF;

    copia            := OLD;
    copia.id         := gen_random_uuid();
    copia.valido_ate := NEW.valido_desde;
    INSERT INTO vinterno.horario SELECT (copia).*;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.horario_before_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT vinterno.versionando() THEN
        RETURN OLD;
    END IF;

    IF OLD.valido_ate <> 'infinity' THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos enquanto ''vinterno.versionando'' está ativo.';
    END IF;

    IF OLD.valido_desde = now() THEN
        RETURN OLD;
    END IF;

    UPDATE vinterno.horario SET valido_ate = now() WHERE id = OLD.id;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.funcionario_after_update() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE copia vinterno.funcionario;
BEGIN
    IF NOT vinterno.versionando() OR OLD.valido_desde = NEW.valido_desde THEN
        RETURN NULL;
    END IF;

    copia            := OLD;
    copia.id         := gen_random_uuid();
    copia.valido_ate := NEW.valido_desde;
    INSERT INTO vinterno.funcionario SELECT (copia).*;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.funcionario_before_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT vinterno.versionando() THEN
        RETURN OLD;
    END IF;

    IF OLD.valido_ate <> 'infinity' THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos enquanto ''vinterno.versionando'' está ativo.';
    END IF;

    IF OLD.valido_desde = now() THEN
        RETURN OLD;
    END IF;

    UPDATE vinterno.funcionario SET valido_ate = now() WHERE id = OLD.id;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.ferias_after_update() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE copia vinterno.ferias;
BEGIN
    IF NOT vinterno.versionando() OR OLD.data_insercao = NEW.data_insercao THEN
        RETURN NULL;
    END IF;

    copia               := OLD;
    copia.id            := gen_random_uuid();
    copia.data_exclusao := NEW.data_insercao;
    INSERT INTO vinterno.ferias SELECT (copia).*;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.ferias_before_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT vinterno.versionando() THEN
        RETURN OLD;
    END IF;

    IF OLD.data_exclusao IS NOT NULL THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos enquanto ''vinterno.versionando'' está ativo.';
    END IF;

    IF OLD.data_insercao = now() THEN
        RETURN OLD;
    END IF;

    UPDATE vinterno.ferias SET data_exclusao = now() WHERE id = OLD.id;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.ponto_after_update() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE copia vinterno.ponto;
BEGIN
    IF NOT vinterno.versionando() OR OLD.data_insercao = NEW.data_insercao THEN
        RETURN NULL;
    END IF;

    copia               := OLD;
    copia.id            := gen_random_uuid();
    copia.data_exclusao := NEW.data_insercao;
    INSERT INTO vinterno.ponto SELECT (copia).*;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.ponto_before_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT vinterno.versionando() THEN
        RETURN OLD;
    END IF;

    IF OLD.data_exclusao IS NOT NULL THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos enquanto ''vinterno.versionando'' está ativo.';
    END IF;

    IF OLD.data_insercao = now() THEN
        RETURN OLD;
    END IF;

    UPDATE vinterno.ponto SET data_exclusao = now() WHERE id = OLD.id;
    RETURN NULL;
END;
$$;

CREATE TRIGGER before_insert BEFORE INSERT ON vinterno.departamento FOR EACH ROW
    EXECUTE FUNCTION vinterno.before_insert();

CREATE TRIGGER before_update BEFORE UPDATE ON vinterno.departamento FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vinterno.validade_before_update();

CREATE TRIGGER after_update AFTER UPDATE ON vinterno.departamento FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false' AND OLD.valido_desde <> NEW.valido_desde)
    EXECUTE FUNCTION vinterno.departamento_after_update();

CREATE TRIGGER before_delete BEFORE DELETE ON vinterno.departamento FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vinterno.departamento_before_delete();

CREATE TRIGGER before_insert BEFORE INSERT ON vinterno.horario FOR EACH ROW
    EXECUTE FUNCTION vinterno.before_insert();

CREATE TRIGGER before_update BEFORE UPDATE ON vinterno.horario FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vinterno.validade_before_update();

CREATE TRIGGER after_update AFTER UPDATE ON vinterno.horario FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false' AND OLD.valido_desde <> NEW.valido_desde)
    EXECUTE FUNCTION vinterno.horario_after_update();

CREATE TRIGGER before_delete BEFORE DELETE ON vinterno.horario FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vinterno.horario_before_delete();

CREATE TRIGGER before_insert BEFORE INSERT ON vinterno.funcionario FOR EACH ROW
    EXECUTE FUNCTION vinterno.before_insert();

CREATE TRIGGER before_update BEFORE UPDATE ON vinterno.funcionario FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vinterno.validade_before_update();

CREATE TRIGGER after_update AFTER UPDATE ON vinterno.funcionario FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false' AND OLD.valido_desde <> NEW.valido_desde)
    EXECUTE FUNCTION vinterno.funcionario_after_update();

CREATE TRIGGER before_delete BEFORE DELETE ON vinterno.funcionario FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vinterno.funcionario_before_delete();

CREATE TRIGGER before_insert BEFORE INSERT ON vinterno.ferias FOR EACH ROW
    EXECUTE FUNCTION vinterno.before_insert();

CREATE TRIGGER before_update BEFORE UPDATE ON vinterno.ferias FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vinterno.transacao_before_update();

CREATE TRIGGER after_update AFTER UPDATE ON vinterno.ferias FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false' AND OLD.data_insercao <> NEW.data_insercao)
    EXECUTE FUNCTION vinterno.ferias_after_update();

CREATE TRIGGER before_delete BEFORE DELETE ON vinterno.ferias FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vinterno.ferias_before_delete();

CREATE TRIGGER before_insert BEFORE INSERT ON vinterno.ponto FOR EACH ROW
    EXECUTE FUNCTION vinterno.before_insert();

CREATE TRIGGER before_update BEFORE UPDATE ON vinterno.ponto FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vinterno.transacao_before_update();

CREATE TRIGGER after_update AFTER UPDATE ON vinterno.ponto FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false' AND OLD.data_insercao <> NEW.data_insercao)
    EXECUTE FUNCTION vinterno.ponto_after_update();

CREATE TRIGGER before_delete BEFORE DELETE ON vinterno.ponto FOR EACH ROW
    WHEN (pg_trigger_depth() = 0 AND lower(current_setting('vinterno.versionando', true)) IS DISTINCT FROM 'false')
    EXECUTE FUNCTION vinterno.ponto_before_delete();

COMMIT;
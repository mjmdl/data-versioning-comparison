BEGIN;

CREATE SCHEMA vinterno;

CREATE OR REPLACE FUNCTION vinterno.agora() RETURNS timestamptz LANGUAGE sql STABLE AS $$
    SELECT coalesce(nullif(current_setting('versionamento.agora', true), '')::timestamptz, now());
$$;

CREATE OR REPLACE FUNCTION vinterno.id_versao(_entidade uuid, _instante timestamptz) RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT md5(_entidade::text || '@' || (extract(epoch FROM _instante) * 1000000)::bigint)::uuid;
$$;

CREATE TABLE vinterno.departamento (
    entidade     uuid NOT NULL,
    valido_desde timestamptz NOT NULL DEFAULT vinterno.agora(),
    valido_ate   timestamptz NOT NULL DEFAULT 'infinity',

    LIKE base.departamento INCLUDING DEFAULTS INCLUDING CONSTRAINTS,

    CONSTRAINT departamento_pk          PRIMARY KEY (id),
    CONSTRAINT departamento_uq_nome     EXCLUDE USING gist (lower(nome) WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT departamento_uq_entidade EXCLUDE USING gist (entidade WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT departamento_ck_validade CHECK (valido_desde < valido_ate)
);
CREATE INDEX departamento_ix_entidade ON vinterno.departamento (entidade, valido_desde);

CREATE TABLE vinterno.horario (
    entidade     uuid NOT NULL,
    valido_desde timestamptz NOT NULL DEFAULT vinterno.agora(),
    valido_ate   timestamptz NOT NULL DEFAULT 'infinity',

    LIKE base.horario INCLUDING DEFAULTS INCLUDING CONSTRAINTS,

    CONSTRAINT horario_pk              PRIMARY KEY (id),
    CONSTRAINT horario_fk_departamento FOREIGN KEY (departamento) REFERENCES vinterno.departamento (id),
    CONSTRAINT horario_uq_intervalo    EXCLUDE USING gist (departamento WITH =, dia WITH =, base.timerange(inicio, fim, '[)') WITH &&, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT horario_uq_entidade     EXCLUDE USING gist (entidade WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT horario_ck_validade     CHECK (valido_desde < valido_ate)
);
CREATE INDEX horario_ix_entidade ON vinterno.horario (entidade, valido_desde);

CREATE TABLE vinterno.funcionario (
    entidade     uuid NOT NULL,
    valido_desde timestamptz NOT NULL DEFAULT vinterno.agora(),
    valido_ate   timestamptz NOT NULL DEFAULT 'infinity',

    LIKE base.funcionario INCLUDING DEFAULTS INCLUDING CONSTRAINTS,

    CONSTRAINT funcionario_pk                   PRIMARY KEY (id),
    CONSTRAINT funcionario_fk_funcionario_lider FOREIGN KEY (funcionario_lider) REFERENCES vinterno.funcionario (id),
    CONSTRAINT funcionario_fk_departamento      FOREIGN KEY (departamento) REFERENCES vinterno.departamento (id),
    CONSTRAINT funcionario_uq_documento         EXCLUDE USING gist (lower(documento) WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT funcionario_uq_entidade          EXCLUDE USING gist (entidade WITH =, tstzrange(valido_desde, valido_ate) WITH &&),
    CONSTRAINT funcionario_ck_validade          CHECK (valido_desde < valido_ate)
);
CREATE INDEX funcionario_ix_entidade ON vinterno.funcionario (entidade, valido_desde);

CREATE TABLE vinterno.ferias (
    entidade      uuid NOT NULL,
    data_inclusao timestamptz NOT NULL DEFAULT vinterno.agora(),
    data_exclusao timestamptz,

    LIKE base.ferias INCLUDING DEFAULTS INCLUDING CONSTRAINTS,

    CONSTRAINT ferias_pk             PRIMARY KEY (id),
    CONSTRAINT ferias_fk_funcionario FOREIGN KEY (funcionario) REFERENCES vinterno.funcionario (id),
    CONSTRAINT ferias_uq_intervalo   EXCLUDE USING gist (funcionario WITH =, daterange(inicio, fim, '[]') WITH &&, tstzrange(data_inclusao, data_exclusao) WITH &&) WHERE (status NOT IN ('recusada', 'cancelada')),
    CONSTRAINT ferias_uq_entidade    EXCLUDE USING gist (entidade WITH =, tstzrange(data_inclusao, data_exclusao) WITH &&),
    CONSTRAINT ferias_ck_transacao   CHECK (data_inclusao < data_exclusao)
);
CREATE INDEX ferias_ix_entidade ON vinterno.ferias (entidade, data_inclusao);

CREATE TABLE vinterno.ponto (
    entidade      uuid NOT NULL,
    data_inclusao timestamptz NOT NULL DEFAULT vinterno.agora(),
    data_exclusao timestamptz,

    LIKE base.ponto INCLUDING DEFAULTS INCLUDING CONSTRAINTS,

    CONSTRAINT ponto_pk             PRIMARY KEY (id),
    CONSTRAINT ponto_fk_funcionario FOREIGN KEY (funcionario) REFERENCES vinterno.funcionario (id),
    CONSTRAINT ponto_uq_registro    EXCLUDE USING gist (funcionario WITH =, registro WITH =, tstzrange(data_inclusao, data_exclusao) WITH &&),
    CONSTRAINT ponto_uq_entidade    EXCLUDE USING gist (entidade WITH =, tstzrange(data_inclusao, data_exclusao) WITH &&),
    CONSTRAINT ponto_ck_transacao   CHECK (data_inclusao < data_exclusao)
);
CREATE INDEX ponto_ix_entidade ON vinterno.ponto (entidade, data_inclusao);



CREATE OR REPLACE FUNCTION vinterno.validade_before_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.entidade := NEW.id;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.transacao_before_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.entidade      := NEW.id;
    NEW.data_inclusao := vinterno.agora();
    NEW.data_exclusao := NULL;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.validade_before_update() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.valido_ate <> 'infinity' THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos.';
    END IF;

    IF NEW.valido_desde = OLD.valido_desde THEN
        NEW.valido_desde := vinterno.agora();
    END IF;

    IF NEW.valido_desde < OLD.valido_desde THEN
        RAISE EXCEPTION 'O instante % é anterior ao início da versão vigente (%).', NEW.valido_desde, OLD.valido_desde;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.transacao_before_update() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.data_exclusao IS NOT NULL THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos.';
    END IF;

    NEW.data_inclusao := vinterno.agora();
    NEW.data_exclusao := NULL;

    IF NEW.data_inclusao < OLD.data_inclusao THEN
        RAISE EXCEPTION 'O instante % é anterior ao início da versão vigente (%).', NEW.data_inclusao, OLD.data_inclusao;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.departamento_after_update() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE _copia vinterno.departamento;
BEGIN
    _copia            := OLD;
    _copia.id         := vinterno.id_versao(OLD.entidade, NEW.valido_desde);
    _copia.valido_ate := NEW.valido_desde;
    INSERT INTO vinterno.departamento SELECT (_copia).*;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.departamento_before_delete() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE _instante timestamptz := vinterno.agora();
BEGIN
    IF OLD.valido_ate <> 'infinity' THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos.';
    END IF;

    IF _instante < OLD.valido_desde THEN
        RAISE EXCEPTION 'O instante % é anterior ao início da versão vigente (%).', _instante, OLD.valido_desde;
    END IF;

    IF EXISTS (SELECT 1 FROM vinterno.funcionario WHERE departamento = OLD.id AND id = entidade AND valido_ate > _instante) THEN
        RAISE EXCEPTION 'O departamento % tem funcionários vigentes.', OLD.id;
    END IF;

    DELETE FROM vinterno.horario WHERE departamento = OLD.id AND id = entidade AND valido_desde = _instante;
    UPDATE vinterno.horario SET valido_ate = _instante WHERE departamento = OLD.id AND id = entidade AND valido_ate > _instante;

    IF OLD.valido_desde = _instante THEN
        RETURN OLD;
    END IF;

    UPDATE vinterno.departamento SET valido_ate = _instante WHERE id = OLD.id;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.horario_after_update() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE _copia vinterno.horario;
BEGIN
    _copia            := OLD;
    _copia.id         := vinterno.id_versao(OLD.entidade, NEW.valido_desde);
    _copia.valido_ate := NEW.valido_desde;
    INSERT INTO vinterno.horario SELECT (_copia).*;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.horario_before_delete() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE _instante timestamptz := vinterno.agora();
BEGIN
    IF OLD.valido_ate <> 'infinity' THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos.';
    END IF;

    IF _instante < OLD.valido_desde THEN
        RAISE EXCEPTION 'O instante % é anterior ao início da versão vigente (%).', _instante, OLD.valido_desde;
    END IF;

    IF OLD.valido_desde = _instante THEN
        RETURN OLD;
    END IF;

    UPDATE vinterno.horario SET valido_ate = _instante WHERE id = OLD.id;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.funcionario_after_update() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE _copia vinterno.funcionario;
BEGIN
    _copia            := OLD;
    _copia.id         := vinterno.id_versao(OLD.entidade, NEW.valido_desde);
    _copia.valido_ate := NEW.valido_desde;
    INSERT INTO vinterno.funcionario SELECT (_copia).*;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.funcionario_before_delete() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE _instante timestamptz := vinterno.agora();
BEGIN
    IF OLD.valido_ate <> 'infinity' THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos.';
    END IF;

    IF _instante < OLD.valido_desde THEN
        RAISE EXCEPTION 'O instante % é anterior ao início da versão vigente (%).', _instante, OLD.valido_desde;
    END IF;

    IF EXISTS (SELECT 1 FROM vinterno.funcionario WHERE funcionario_lider = OLD.id AND id <> OLD.id AND id = entidade AND valido_ate > _instante) THEN
        RAISE EXCEPTION 'O funcionário % lidera funcionários vigentes.', OLD.id;
    END IF;

    IF OLD.valido_desde = _instante THEN
        RETURN OLD;
    END IF;

    UPDATE vinterno.funcionario SET valido_ate = _instante WHERE id = OLD.id;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.ferias_after_update() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE _copia vinterno.ferias;
BEGIN
    _copia               := OLD;
    _copia.id            := vinterno.id_versao(OLD.entidade, NEW.data_inclusao);
    _copia.data_exclusao := NEW.data_inclusao;
    INSERT INTO vinterno.ferias SELECT (_copia).*;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.ferias_before_delete() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE _instante timestamptz := vinterno.agora();
BEGIN
    IF OLD.data_exclusao IS NOT NULL THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos.';
    END IF;

    IF _instante < OLD.data_inclusao THEN
        RAISE EXCEPTION 'O instante % é anterior ao início da versão vigente (%).', _instante, OLD.data_inclusao;
    END IF;

    IF OLD.data_inclusao = _instante THEN
        RETURN OLD;
    END IF;

    UPDATE vinterno.ferias SET data_exclusao = _instante WHERE id = OLD.id;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.ponto_after_update() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE _copia vinterno.ponto;
BEGIN
    _copia               := OLD;
    _copia.id            := vinterno.id_versao(OLD.entidade, NEW.data_inclusao);
    _copia.data_exclusao := NEW.data_inclusao;
    INSERT INTO vinterno.ponto SELECT (_copia).*;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION vinterno.ponto_before_delete() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE _instante timestamptz := vinterno.agora();
BEGIN
    IF OLD.data_exclusao IS NOT NULL THEN
        RAISE EXCEPTION 'Não é permitido alterar registros históricos.';
    END IF;

    IF _instante < OLD.data_inclusao THEN
        RAISE EXCEPTION 'O instante % é anterior ao início da versão vigente (%).', _instante, OLD.data_inclusao;
    END IF;

    IF OLD.data_inclusao = _instante THEN
        RETURN OLD;
    END IF;

    UPDATE vinterno.ponto SET data_exclusao = _instante WHERE id = OLD.id;
    RETURN NULL;
END;
$$;

CREATE TRIGGER before_insert BEFORE INSERT ON vinterno.departamento FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.validade_before_insert();
CREATE TRIGGER before_update BEFORE UPDATE ON vinterno.departamento FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.validade_before_update();
CREATE TRIGGER after_update AFTER UPDATE ON vinterno.departamento FOR EACH ROW WHEN (pg_trigger_depth() = 0 AND OLD.valido_desde <> NEW.valido_desde) EXECUTE FUNCTION vinterno.departamento_after_update();
CREATE TRIGGER before_delete BEFORE DELETE ON vinterno.departamento FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.departamento_before_delete();

CREATE TRIGGER before_insert BEFORE INSERT ON vinterno.horario FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.validade_before_insert();
CREATE TRIGGER before_update BEFORE UPDATE ON vinterno.horario FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.validade_before_update();
CREATE TRIGGER after_update AFTER UPDATE ON vinterno.horario FOR EACH ROW WHEN (pg_trigger_depth() = 0 AND OLD.valido_desde <> NEW.valido_desde) EXECUTE FUNCTION vinterno.horario_after_update();
CREATE TRIGGER before_delete BEFORE DELETE ON vinterno.horario FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.horario_before_delete();

CREATE TRIGGER before_insert BEFORE INSERT ON vinterno.funcionario FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.validade_before_insert();
CREATE TRIGGER before_update BEFORE UPDATE ON vinterno.funcionario FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.validade_before_update();
CREATE TRIGGER after_update AFTER UPDATE ON vinterno.funcionario FOR EACH ROW WHEN (pg_trigger_depth() = 0 AND OLD.valido_desde <> NEW.valido_desde) EXECUTE FUNCTION vinterno.funcionario_after_update();
CREATE TRIGGER before_delete BEFORE DELETE ON vinterno.funcionario FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.funcionario_before_delete();

CREATE TRIGGER before_insert BEFORE INSERT ON vinterno.ferias FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.transacao_before_insert();
CREATE TRIGGER before_update BEFORE UPDATE ON vinterno.ferias FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.transacao_before_update();
CREATE TRIGGER after_update AFTER UPDATE ON vinterno.ferias FOR EACH ROW WHEN (pg_trigger_depth() = 0 AND OLD.data_inclusao <> NEW.data_inclusao) EXECUTE FUNCTION vinterno.ferias_after_update();
CREATE TRIGGER before_delete BEFORE DELETE ON vinterno.ferias FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.ferias_before_delete();

CREATE TRIGGER before_insert BEFORE INSERT ON vinterno.ponto FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.transacao_before_insert();
CREATE TRIGGER before_update BEFORE UPDATE ON vinterno.ponto FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.transacao_before_update();
CREATE TRIGGER after_update AFTER UPDATE ON vinterno.ponto FOR EACH ROW WHEN (pg_trigger_depth() = 0 AND OLD.data_inclusao <> NEW.data_inclusao) EXECUTE FUNCTION vinterno.ponto_after_update();
CREATE TRIGGER before_delete BEFORE DELETE ON vinterno.ponto FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION vinterno.ponto_before_delete();

COMMIT;

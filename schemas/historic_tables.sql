CREATE OR REPLACE FUNCTION setup_historic_table(
  _table           text,
  _historic_table  text,
  _schema          text DEFAULT 'public',
  _historic_schema text DEFAULT NULL
)
  RETURNS void
  LANGUAGE plpgsql
AS $setup_historic_table$
DECLARE
  _qualified_table   text;
  _qualified_history text;
  _trigger_function  text;
  _trigger           text;
  _columns           text[];
  _typed_columns     text[];
BEGIN
  _historic_schema   := coalesce(_historic_schema, _schema);
  _qualified_table   := format('%I.%I', _schema, _table);
  _qualified_history := format('%I.%I',
    _historic_schema, _historic_table
  );
  _trigger_function  := format('%I.save_%s_history',
    _historic_schema, _table
  );
  _trigger           := 'save_history';

  SELECT
    array_agg(column_name
      ORDER BY ordinal_position
    ),
    array_agg(
      concat_ws(' ',
        column_name,
        CASE data_type
          WHEN 'USER-DEFINED' THEN udt_name
          ELSE data_type
        END,
        CASE WHEN is_nullable = 'NO' THEN 'NOT NULL' END
      )
      ORDER BY ordinal_position
    )
  INTO _columns, _typed_columns
  FROM information_schema."columns"
  WHERE table_schema = _schema AND table_name = _table;

  EXECUTE format($ddl$
    DROP TABLE IF EXISTS %s;
    CREATE TABLE %s (
      %s,
      version     bigint NOT NULL,
      valid_since timestamptz NOT NULL,
      valid_until timestamptz NOT NULL
    );
  $ddl$,
    _qualified_history,
    _qualified_history,
    array_to_string(_typed_columns, ', ')
  );

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %s()
      RETURNS TRIGGER
      LANGUAGE plpgsql
    AS $trigger_function$
    DECLARE
      _version BIGINT;
    BEGIN
      IF current_setting('%I.history_active', TRUE) = 'false' IS TRUE THEN
        RETURN NEW;
      END IF;

      IF tg_op = 'INSERT' THEN
        _version := 1;
      ELSE
        SELECT max(it.version) INTO _version
        FROM %s AS it WHERE it.id = OLD.id;

        UPDATE %s SET valid_until = now()
        WHERE id = OLD.id AND version = _version;

        _version := _version + 1;
      END IF;

      IF tg_op IN ('INSERT', 'UPDATE') THEN
        INSERT INTO %s (%s, version, valid_since, valid_until)
        VALUES (%s, _version, now(), timestamptz 'infinity');
      END IF;

      RETURN NEW;
    END;
    $trigger_function$;
  $ddl$,
    _trigger_function,
    _historic_schema,
    _qualified_history,
    _qualified_history,
    _qualified_history,
    array_to_string(_columns, ', '),
    (SELECT string_agg('NEW.' || "column", ', ')
      FROM unnest(_columns) AS "column"
    )
  );

  EXECUTE format($ddl$
    DROP TRIGGER IF EXISTS %s ON %s;

    CREATE TRIGGER %s AFTER INSERT OR UPDATE OR DELETE ON %s
    FOR EACH ROW EXECUTE FUNCTION %s();
  $ddl$,
    _trigger,
    _qualified_table,
    _trigger,
    _qualified_table,
    _trigger_function
  );
END;
$setup_historic_table$;

SELECT setup_historic_table("table"::text, historic::text)
FROM (VALUES
  ('person', 'historic_person'),
  ('physician', 'historic_physician'),
  ('insurance', 'historic_insurance'),
  ('appointment', 'historic_appointment'),
  ('treatment', 'historic_treatment')
) AS t ("table", historic);

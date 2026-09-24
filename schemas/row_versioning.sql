CREATE OR REPLACE FUNCTION setup_row_versioning(
  _table           text,
  _schema          text DEFAULT 'public',
  _historic_schema text DEFAULT NULL
)
  RETURNS void
  LANGUAGE plpgsql
AS $setup_row_versioning$
DECLARE
  _qualified        text;
  _trigger_function text;
  _trigger          text;
  _columns          text[];
  _it               record;
BEGIN
  _qualified        := format('%I.%I', _schema, _table);
  _historic_schema  := coalesce(_historic_schema, _schema);
  _trigger_function := format('%I.save_%s_version',
    _historic_schema, _table
  );
  _trigger          := 'save_version';

  SELECT array_agg(column_name
    ORDER BY ordinal_position
  )
  INTO _columns
  FROM information_schema."columns" AS c
  WHERE table_schema = _schema
    AND table_name = _table
    AND column_name NOT IN (
      'id', 'original_id', 'version', 'valid_since', 'valid_until'
    );

  EXECUTE format($ddl$
    ALTER TABLE %s
      ADD COLUMN IF NOT EXISTS original_id uuid NOT NULL,
      ADD COLUMN IF NOT EXISTS version     bigint NOT NULL DEFAULT 1,
      ADD COLUMN IF NOT EXISTS valid_since timestamptz NOT NULL
        DEFAULT now(),
      ADD COLUMN IF NOT EXISTS valid_until timestamptz NOT NULL
        DEFAULT 'infinity';
  $ddl$,
    _qualified
  );

  FOR _it IN (
    SELECT
      tc.constraint_name,
      ARRAY_AGG(kcu.column_name
        ORDER BY kcu.ordinal_position ASC
      ) AS "columns"
    FROM information_schema.table_constraints AS tc
    INNER JOIN information_schema.key_column_usage AS kcu
      ON kcu.table_schema = tc.table_schema
      AND kcu.table_name = tc.table_name
      AND kcu.constraint_name = tc.constraint_name
    WHERE tc.table_schema = _schema
      AND tc.table_name = _table
      AND tc.constraint_type = 'UNIQUE'
    GROUP BY tc.constraint_name
  ) LOOP
    EXECUTE format($ddl$
      ALTER TABLE %s DROP CONSTRAINT %s;

      CREATE UNIQUE INDEX %s ON %s (%s) WHERE valid_until = 'infinity';
    $ddl$,
      _qualified,
      _it.constraint_name,
      format('ux_%s_%s', _table, _it."columns"[1]),
      _qualified,
      array_to_string(_it."columns", ', ')
    );
  END LOOP;

  EXECUTE format($ddl$
    CREATE OR REPLACE FUNCTION %s() RETURNS TRIGGER LANGUAGE plpgsql
    AS $trigger_function$
    BEGIN
      IF
        current_setting('%I.versioning_active', TRUE) = 'false' IS TRUE
      THEN
        RETURN NEW;
      END IF;

      IF tg_op = 'INSERT' THEN
        IF NEW.original_id IS NULL THEN
          NEW.original_id := NEW.id;
        END IF;
        RETURN NEW;
      END IF;

      IF OLD.version <> (
        SELECT max("version")
        FROM %s
        WHERE original_id = OLD.original_id
      ) THEN
        RAISE EXCEPTION 'Can not update an old version.';
      END IF;

      CASE tg_op
        WHEN 'UPDATE' THEN
          IF
            OLD.valid_until <> 'infinity' AND
            NEW.valid_until <> 'infinity'
          THEN
            RAISE EXCEPTION 'To update a soft-deleted record, please explicitly set valid_until to infinity.';
          END IF;

          NEW.valid_since = now();
          NEW.valid_until = 'infinity';
          NEW.version := OLD.version + 1;
          NEW.original_id := OLD.original_id;

          INSERT INTO %s (
            %s,
            version, valid_since, valid_until, original_id
          )
          VALUES (
            %s,
            OLD.version, OLD.valid_since, NEW.valid_since, OLD.original_id
          );

          RETURN NEW;

        WHEN 'DELETE' THEN
          IF OLD.valid_until <> 'infinity' THEN
            RAISE EXCEPTION
              'Can not delete an already soft-deleted record.';
          END IF;

          SET LOCAL %I.versioning_active TO FALSE;
          UPDATE %s SET valid_until = now() WHERE id = OLD.id;
          SET LOCAL %I.versioning_active TO TRUE;

          RETURN NULL;
      END CASE;

      RETURN NEW;
    END;
    $trigger_function$;
  $ddl$,
    _trigger_function,
    _historic_schema,
    _qualified,
    _qualified,
    array_to_string(_columns, ', '),
    (SELECT string_agg(concat('OLD.', "column"), ', ')
      FROM unnest(_columns) AS "column"
    ),
    _historic_schema,
    _qualified,
    _historic_schema
  );

  EXECUTE format($ddl$
    DROP TRIGGER IF EXISTS %I ON %s;

    CREATE TRIGGER %s BEFORE INSERT OR UPDATE OR DELETE ON %s
    FOR EACH ROW EXECUTE FUNCTION %s();
  $ddl$,
    _trigger,
    _qualified,
    _trigger,
    _qualified,
    _trigger_function
  );
END;
$setup_row_versioning$;

SELECT setup_row_versioning("table"::text)
FROM (VALUES
  ('person'),
  ('physician'),
  ('insurance'),
  ('appointment'),
  ('treatment')
) AS t ("table");

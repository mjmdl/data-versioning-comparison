CREATE TABLE audit (
  id             uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  reference_id   uuid NOT NULL,
  table_name     text NOT NULL,
  column_name    text NOT NULL,
  previous_value text,
  next_value     text,
  inserted_at    timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION setup_auditing(
  _table       text,
  _schema      text,
  _audit_table text DEFAULT 'audit'
)
  RETURNS void
  LANGUAGE plpgsql
AS $setup_auditing$
BEGIN
  -- TODO
END;
$setup_auditing$;

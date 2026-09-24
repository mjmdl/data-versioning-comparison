CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE person (
  id    uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  name  text NOT NULL,
  email text UNIQUE,
  phone text UNIQUE
);

CREATE TABLE physician (
  id             uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  person_id      uuid NOT NULL REFERENCES person (id),
  specialization text NOT NULL,
  CONSTRAINT unique_specialization UNIQUE (person_id, specialization)
);

CREATE TABLE insurance (
  id           uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  person_id    uuid REFERENCES person (id),
  physician_id uuid REFERENCES physician (id),
  plan         text NOT NULL,
  monthly_fee  numeric CHECK (monthly_fee >= 0),
  CONSTRAINT ensure_one_target CHECK (
    (person_id IS NOT NULL) <> (physician_id IS NOT NULL)
  ),
  CONSTRAINT check_monthly_fee_allowed CHECK (
    (monthly_fee IS NOT NULL) = (person_id IS NOT NULL)
  ),
  CONSTRAINT unique_person_plan UNIQUE (person_id, plan),
  CONSTRAINT unique_physician_plan UNIQUE (physician_id, plan)
);

CREATE TYPE appointment_status AS ENUM (
  'scheduled', 'rescheduled', 'canceled', 'ongoing', 'finished'
);

CREATE TABLE appointment (
  id           uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  physician_id uuid NOT NULL REFERENCES physician (id),
  patient_id   uuid NOT NULL REFERENCES person (id),
  schedule     timestamptz NOT NULL,
  status       appointment_status NOT NULL DEFAULT 'scheduled',
  remarks      text,
  diagnostics  text,
  treatment    text
);

CREATE TABLE treatment (
  id             uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  appointment_id uuid NOT NULL REFERENCES appointment (id),
  drug           text NOT NULL,
  dosage         text NOT NULL,
  remarks        text
);

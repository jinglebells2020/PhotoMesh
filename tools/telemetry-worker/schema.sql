-- D1 index for the Photocircuits collector. Apply with:
--   wrangler d1 execute photocircuits-telemetry --remote --file schema.sql
-- The objects in R2 stay the source of truth; these tables make the numbers queryable.

CREATE TABLE IF NOT EXISTS installs (
  install_id TEXT PRIMARY KEY,
  first_seen TEXT NOT NULL,
  last_seen  TEXT NOT NULL,
  app        TEXT,
  os         TEXT,
  device     TEXT,
  locale     TEXT,
  plus       INTEGER NOT NULL DEFAULT 0,
  uploads    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS events (
  id         TEXT PRIMARY KEY,
  install_id TEXT NOT NULL,
  ts         TEXT NOT NULL,
  day        TEXT NOT NULL,
  name       TEXT NOT NULL,
  app        TEXT,
  session    TEXT,
  props      TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS events_day_name ON events (day, name);
CREATE INDEX IF NOT EXISTS events_install ON events (install_id);

CREATE TABLE IF NOT EXISTS samples (
  id         TEXT PRIMARY KEY,
  install_id TEXT NOT NULL,
  ts         TEXT NOT NULL,
  day        TEXT NOT NULL,
  model      TEXT,
  accepted   INTEGER NOT NULL DEFAULT 0,
  corrected  INTEGER NOT NULL DEFAULT 0,
  components INTEGER NOT NULL DEFAULT 0,
  image_key  TEXT,
  diff       TEXT,
  dominant   TEXT
);
CREATE INDEX IF NOT EXISTS samples_day ON samples (day);
CREATE INDEX IF NOT EXISTS samples_install ON samples (install_id);

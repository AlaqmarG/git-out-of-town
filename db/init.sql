CREATE TABLE IF NOT EXISTS sessions (
  id          TEXT PRIMARY KEY,
  first_seen  TIMESTAMPTZ NOT NULL DEFAULT now(),
  city        TEXT,
  country     TEXT,
  device      TEXT
);

CREATE TABLE IF NOT EXISTS pieces (
  id               BIGSERIAL PRIMARY KEY,
  lat              DOUBLE PRECISION NOT NULL,
  lng              DOUBLE PRECISION NOT NULL,
  heading          DOUBLE PRECISION,
  accuracy_m       DOUBLE PRECISION,
  raw_image_path   TEXT NOT NULL,        -- transparent art: AR anchor, map marker, Reve input
  final_image_path TEXT,                 -- Reve-transformed art, once it lands
  scene_image_path TEXT,                 -- the camera frame with the art burned in (web preview)
  kind             TEXT NOT NULL DEFAULT 'spray',
  sticker_id       TEXT,
  colors           JSONB,
  stroke_count     INTEGER,
  duration_ms      INTEGER,
  city             TEXT,
  country          TEXT,
  session_id       TEXT REFERENCES sessions(id) ON DELETE SET NULL,
  -- Native AR only (null from web clients).
  client           TEXT NOT NULL DEFAULT 'web',   -- 'ios' | 'web'
  surface_type     TEXT,        -- ARMeshClassification: wall/floor/ceiling/table/seat/door/window
  distance_m       DOUBLE PRECISION,  -- camera -> anchor at placement time
  device_pitch     DOUBLE PRECISION,  -- degrees; negative = aimed down
  used_geo_anchor  BOOLEAN NOT NULL DEFAULT false,
  has_lidar        BOOLEAN,
  altitude_m       DOUBLE PRECISION,  -- metres above mean sea level (ARGeoAnchor altitude)
  placement_transform JSONB,          -- 4x4 COLUMN-major (16 floats, simd order) in a north-up frame at lat/lng; exact AR reconstruction
  deleted_at       TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS views (
  id         BIGSERIAL PRIMARY KEY,
  piece_id   BIGINT REFERENCES pieces(id) ON DELETE CASCADE,
  session_id TEXT,
  viewed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pieces_bbox_idx    ON pieces (lat, lng) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS pieces_created_idx ON pieces (created_at DESC);
CREATE INDEX IF NOT EXISTS pieces_country_idx ON pieces (country);
CREATE INDEX IF NOT EXISTS views_piece_idx    ON views (piece_id);
CREATE INDEX IF NOT EXISTS pieces_surface_idx  ON pieces (surface_type) WHERE surface_type IS NOT NULL;
CREATE INDEX IF NOT EXISTS pieces_client_idx   ON pieces (client);

-- Live updates: LISTEN/NOTIFY feeds the SSE endpoint (replaces Supabase Realtime).
CREATE OR REPLACE FUNCTION notify_new_piece() RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify('new_piece', json_build_object(
    'id', NEW.id, 'lat', NEW.lat, 'lng', NEW.lng, 'city', NEW.city
  )::text);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS pieces_notify ON pieces;
CREATE TRIGGER pieces_notify AFTER INSERT ON pieces
  FOR EACH ROW EXECUTE FUNCTION notify_new_piece();

-- Visual relocalization: serialized ARWorldMap scans, keyed by location.
-- The API also creates this lazily (CREATE TABLE IF NOT EXISTS) so a deploy
-- onto the existing database needs no manual migration.
CREATE TABLE IF NOT EXISTS world_maps (
  id bigserial PRIMARY KEY,
  piece_id bigint REFERENCES pieces(id) ON DELETE CASCADE,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  map_path text NOT NULL,
  size_bytes bigint NOT NULL,
  feature_points integer NOT NULL DEFAULT 0,
  extent_m double precision NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS world_maps_loc_idx ON world_maps (lat, lng);

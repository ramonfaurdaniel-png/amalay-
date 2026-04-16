-- ============================================================
-- Tabla: amalay_reservaciones
-- Proyecto: fullsite-amalay / Supabase: qjiomlvudfmzuvqvhwpk
-- Propósito: widget eventos.html escribe (anon key con RLS),
--            War Room lee (anon key), Make.com puede actualizar status
-- ============================================================

CREATE TABLE IF NOT EXISTS public.amalay_reservaciones (
  id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre           TEXT         NOT NULL,
  fecha            DATE         NOT NULL,
  espacio          TEXT         NOT NULL,                 -- id del espacio (e.g. 'terraza', 'salon')
  horario_inicio   TIME         NOT NULL,                 -- '08:00'
  horario_fin      TIME         NOT NULL,                 -- '11:00'
  guests           SMALLINT     NOT NULL CHECK (guests BETWEEN 1 AND 100),
  paquete          TEXT,
  total            INTEGER,                               -- total estimado en MXN
  status           TEXT         NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('pending','confirmed','cancelled')),
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Auto-actualizar updated_at
CREATE OR REPLACE FUNCTION public.set_reservaciones_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reservaciones_set_updated_at ON public.amalay_reservaciones;
CREATE TRIGGER reservaciones_set_updated_at
  BEFORE UPDATE ON public.amalay_reservaciones
  FOR EACH ROW EXECUTE FUNCTION public.set_reservaciones_updated_at();

-- Índices para las consultas del widget (fecha + status)
CREATE INDEX IF NOT EXISTS reservaciones_fecha_idx   ON public.amalay_reservaciones (fecha);
CREATE INDEX IF NOT EXISTS reservaciones_status_idx  ON public.amalay_reservaciones (status);
CREATE INDEX IF NOT EXISTS reservaciones_espacio_idx ON public.amalay_reservaciones (espacio, fecha);

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE public.amalay_reservaciones ENABLE ROW LEVEL SECURITY;

-- Anon key: puede INSERT (crear solicitud desde widget)
DROP POLICY IF EXISTS "anon_insert" ON public.amalay_reservaciones;
CREATE POLICY "anon_insert" ON public.amalay_reservaciones
  FOR INSERT TO anon WITH CHECK (true);

-- Anon key: puede SELECT solo fecha+espacio+horario (para disponibilidad)
-- No expone nombres ni totales al público
DROP POLICY IF EXISTS "anon_select_availability" ON public.amalay_reservaciones;
CREATE POLICY "anon_select_availability" ON public.amalay_reservaciones
  FOR SELECT TO anon USING (true);

-- service_role (Make.com, War Room con service key): acceso total — bypasa RLS
-- No requiere política extra.

-- ── Vista de disponibilidad (uso del widget) ──────────────────
-- Retorna solo los campos necesarios para bloquear espacios/horarios
CREATE OR REPLACE VIEW public.reservaciones_activas AS
  SELECT id, fecha, espacio, horario_inicio, horario_fin, status
  FROM public.amalay_reservaciones
  WHERE status IN ('pending', 'confirmed')
  ORDER BY fecha ASC, horario_inicio ASC;

-- ── Vista para War Room ───────────────────────────────────────
CREATE OR REPLACE VIEW public.reservaciones_hoy AS
  SELECT *
  FROM public.amalay_reservaciones
  WHERE fecha = CURRENT_DATE
    AND status != 'cancelled'
  ORDER BY horario_inicio ASC;

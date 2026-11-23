-- TP7: multi-user workspaces (tenants) + per-user/per-tenant isolation.
-- Apply after the TP6 migrations (0001 and 0002).

-- 1. Workspace tables -------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tenants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.tenant_members (
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, user_id)
);

-- 2. Scope queue rows to an owner and a workspace --------------------------
ALTER TABLE public.clients
  ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- Backfill pre-TP7 rows so they stay visible after RLS is enabled.
INSERT INTO public.tenants (id, name)
VALUES ('00000000-0000-0000-0000-000000000001', 'Default')
ON CONFLICT (id) DO NOTHING;

UPDATE public.clients
SET tenant_id = '00000000-0000-0000-0000-000000000001'::UUID
WHERE tenant_id IS NULL;

INSERT INTO public.tenant_members (tenant_id, user_id, role)
SELECT '00000000-0000-0000-0000-000000000001'::UUID, id, 'member'
FROM auth.users
ON CONFLICT (tenant_id, user_id) DO NOTHING;

CREATE INDEX IF NOT EXISTS clients_tenant_created_idx
  ON public.clients (tenant_id, created_at DESC);

-- 3. Membership helper (SECURITY DEFINER avoids recursive RLS) -------------
CREATE OR REPLACE FUNCTION public.is_tenant_member(p_tenant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.tenant_members m
    WHERE m.tenant_id = p_tenant_id
      AND m.user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_tenant_member(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_tenant_member(UUID) TO authenticated;

-- 4. Row Level Security -----------------------------------------------------
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tp7_tenants_select ON public.tenants;
CREATE POLICY tp7_tenants_select ON public.tenants
  FOR SELECT TO authenticated
  USING (public.is_tenant_member(id));

DROP POLICY IF EXISTS tp7_tenants_insert ON public.tenants;
CREATE POLICY tp7_tenants_insert ON public.tenants
  FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid());

DROP POLICY IF EXISTS tp7_members_select ON public.tenant_members;
CREATE POLICY tp7_members_select ON public.tenant_members
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS tp7_clients_select ON public.clients;
CREATE POLICY tp7_clients_select ON public.clients
  FOR SELECT TO authenticated
  USING (public.is_tenant_member(tenant_id));

DROP POLICY IF EXISTS tp7_clients_insert ON public.clients;
CREATE POLICY tp7_clients_insert ON public.clients
  FOR INSERT TO authenticated
  WITH CHECK (
    tenant_id IS NOT NULL
    AND public.is_tenant_member(tenant_id)
    AND owner_id = auth.uid()
  );

DROP POLICY IF EXISTS tp7_clients_update ON public.clients;
CREATE POLICY tp7_clients_update ON public.clients
  FOR UPDATE TO authenticated
  USING (public.is_tenant_member(tenant_id))
  WITH CHECK (public.is_tenant_member(tenant_id));

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.tenants, public.tenant_members, public.clients TO authenticated;

-- 5. RPCs used by the Flutter app ------------------------------------------
CREATE OR REPLACE FUNCTION public.list_my_tenants()
RETURNS TABLE (id UUID, name TEXT, role TEXT, created_at TIMESTAMPTZ)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT t.id, t.name, m.role, t.created_at
  FROM public.tenants t
  JOIN public.tenant_members m ON m.tenant_id = t.id
  WHERE m.user_id = auth.uid()
  ORDER BY t.created_at ASC, t.id ASC;
$$;

CREATE OR REPLACE FUNCTION public.create_tenant(p_name TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_tenant_id UUID;
BEGIN
  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RAISE EXCEPTION 'Workspace name is required';
  END IF;

  INSERT INTO public.tenants (name, created_by)
  VALUES (btrim(p_name), auth.uid())
  RETURNING id INTO v_tenant_id;

  INSERT INTO public.tenant_members (tenant_id, user_id, role)
  VALUES (v_tenant_id, auth.uid(), 'owner');

  RETURN v_tenant_id;
END;
$$;

-- Replace the TP6 6-argument function with the tenant-aware version.
DROP FUNCTION IF EXISTS public.register_queue_client(
  UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, TIMESTAMPTZ
);

CREATE OR REPLACE FUNCTION public.register_queue_client(
  p_id UUID,
  p_name TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_accuracy DOUBLE PRECISION,
  p_created_at TIMESTAMPTZ,
  p_tenant_id UUID
)
RETURNS SETOF public.clients
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RAISE EXCEPTION 'Client name is required';
  END IF;

  IF NOT public.is_tenant_member(p_tenant_id) THEN
    RAISE EXCEPTION 'Not a member of this workspace';
  END IF;

  RETURN QUERY
  INSERT INTO public.clients (
    id, name, lat, lng, location_accuracy_m, created_at, owner_id, tenant_id
  )
  VALUES (
    p_id, btrim(p_name), p_lat, p_lng, p_accuracy, p_created_at,
    auth.uid(), p_tenant_id
  )
  ON CONFLICT (id) DO UPDATE
  SET name = EXCLUDED.name,
      owner_id = EXCLUDED.owner_id,
      tenant_id = EXCLUDED.tenant_id
  RETURNING *;
END;
$$;

REVOKE ALL ON FUNCTION public.list_my_tenants() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_tenant(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.register_queue_client(
  UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, TIMESTAMPTZ, UUID
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.list_my_tenants() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_tenant(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_queue_client(
  UUID, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, TIMESTAMPTZ, UUID
) TO authenticated;

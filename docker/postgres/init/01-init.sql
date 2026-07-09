-- =============================================================================
-- PostgreSQL Initialization - Odoo demo support
-- Runs once on first container start as the postgres superuser.
-- =============================================================================

-- The POSTGRES_USER (odoo) is already created as a superuser by the official
-- postgres Docker image, which gives it CREATEDB and CREATEROLE implicitly.
-- We make the grants explicit for clarity and forward-compatibility.

DO $$
BEGIN
    -- Ensure the Odoo user can create databases for Odoo database operations.
    IF NOT (SELECT rolcreatedb FROM pg_roles WHERE rolname = current_user) THEN
        EXECUTE 'ALTER USER ' || current_user || ' CREATEDB';
    END IF;
END;
$$;

-- =============================================================================
-- Legacy tenant registry
-- Kept so older backups with _registry.dump can still be restored cleanly.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.tenant_registry (
    id              SERIAL          PRIMARY KEY,
    tenant_name     VARCHAR(100)    NOT NULL UNIQUE,
    db_name         VARCHAR(100)    NOT NULL UNIQUE,
    subdomain       VARCHAR(100)    NOT NULL UNIQUE,
    admin_email     VARCHAR(255),
    plan            VARCHAR(50)     NOT NULL DEFAULT 'starter',
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_tenant_subdomain  ON public.tenant_registry (subdomain);
CREATE INDEX IF NOT EXISTS idx_tenant_is_active  ON public.tenant_registry (is_active);

COMMENT ON TABLE  public.tenant_registry               IS 'Legacy registry for previously provisioned tenant databases.';
COMMENT ON COLUMN public.tenant_registry.tenant_name   IS 'Human-readable company name.';
COMMENT ON COLUMN public.tenant_registry.db_name       IS 'PostgreSQL database name (matches Odoo dbfilter).';
COMMENT ON COLUMN public.tenant_registry.subdomain     IS 'Subdomain prefix, e.g. "company1" for company1.yourerp.com.';

-- Auto-update updated_at on row changes
CREATE OR REPLACE FUNCTION public.fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tenant_registry_updated_at ON public.tenant_registry;
CREATE TRIGGER trg_tenant_registry_updated_at
    BEFORE UPDATE ON public.tenant_registry
    FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

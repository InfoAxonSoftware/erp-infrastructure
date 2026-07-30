#!/usr/bin/env bash
# =============================================================================
# deploy.sh - ERP Platform Deployment (stack-selectable)
# =============================================================================
# Run from the repository root on the VPS after install.sh has been executed.
#
# Usage:
#   bash scripts/install/deploy.sh [--stack <selection>] [--ssl]
#
# Stack selection:
#   --stack website                    Website only (postgres, react, company-backend, nginx)
#   --stack odoo-community             Odoo Community only (postgres, odoo)
#   --stack website,odoo-community     Both (order-insensitive)
#   (omitted)                          Defaults to website,odoo-community
#
# --ssl requires the website stack to be selected.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

usage() {
    cat <<'USAGE'
Usage: deploy.sh [--stack <selection>] [--ssl] [--help]

  --stack <selection>   Which services to deploy. Comma-separated, order-insensitive.
                         Supported values:
                           website
                           odoo-community
                           website,odoo-community
                         Defaults to "website,odoo-community" (the full stack) when omitted.

  --ssl                  Configure Let's Encrypt SSL for the website after deployment.
                         Requires the website stack to be selected (directly or via default).

  -h, --help             Show this help message and exit.

Examples:
  bash scripts/install/deploy.sh
  bash scripts/install/deploy.sh --stack website
  bash scripts/install/deploy.sh --stack odoo-community
  bash scripts/install/deploy.sh --stack website,odoo-community
  bash scripts/install/deploy.sh --stack website,odoo-community --ssl
USAGE
}

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
ENABLE_SSL=false
STACK_ARG=""
STACK_ARG_SET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssl)
            ENABLE_SSL=true
            shift
            ;;
        --stack)
            [[ "${STACK_ARG_SET}" == "false" ]] || error "--stack may only be specified once."
            [[ $# -ge 2 && "$2" != -* ]] || error "--stack requires a value."
            STACK_ARG="$2"
            STACK_ARG_SET=true
            shift 2
            ;;
        --stack=*)
            [[ "${STACK_ARG_SET}" == "false" ]] || error "--stack may only be specified once."
            STACK_ARG="${1#--stack=}"
            STACK_ARG_SET=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

if [[ "${STACK_ARG_SET}" == "true" && -z "${STACK_ARG}" ]]; then
    error "--stack value cannot be empty."
fi

if [[ "${STACK_ARG_SET}" == "false" ]]; then
    STACK_ARG="website,odoo-community"
fi

SELECT_WEBSITE=false
SELECT_ODOO=false
declare -A SEEN_STACK_PARTS=()

IFS=',' read -ra STACK_PARTS <<< "${STACK_ARG}"
for raw_part in "${STACK_PARTS[@]}"; do
    part="${raw_part// /}"
    [[ -n "${part}" ]] || error "Malformed --stack value: '${STACK_ARG}' contains an empty entry."

    if [[ -n "${SEEN_STACK_PARTS[${part}]:-}" ]]; then
        error "Duplicate stack value: '${part}'."
    fi
    SEEN_STACK_PARTS[${part}]=1

    case "${part}" in
        website)
            SELECT_WEBSITE=true
            ;;
        odoo-community)
            SELECT_ODOO=true
            ;;
        odoo-enterprise)
            error "odoo-enterprise is not supported in this phase."
            ;;
        *)
            error "Unknown stack value: '${part}'. Supported: website, odoo-community."
            ;;
    esac
done

if [[ "${SELECT_WEBSITE}" == "false" && "${SELECT_ODOO}" == "false" ]]; then
    error "No valid stack selected. Supported: website, odoo-community, website,odoo-community."
fi

if [[ "${ENABLE_SSL}" == "true" && "${SELECT_WEBSITE}" == "false" ]]; then
    error "--ssl requires the website stack."
fi

STACK_IS_FULL=false
if [[ "${SELECT_WEBSITE}" == "true" && "${SELECT_ODOO}" == "true" ]]; then
    STACK_IS_FULL=true
fi

PROFILE_ARGS=()
[[ "${SELECT_WEBSITE}" == "true" ]] && PROFILE_ARGS+=(--profile website)
[[ "${SELECT_ODOO}" == "true" ]] && PROFILE_ARGS+=(--profile odoo-community)

SELECTED_SERVICES=(postgres)
[[ "${SELECT_WEBSITE}" == "true" ]] && SELECTED_SERVICES+=(react company-backend nginx)
[[ "${SELECT_ODOO}" == "true" ]] && SELECTED_SERVICES+=(odoo)

STACK_LABEL="website,odoo-community"
if [[ "${SELECT_WEBSITE}" == "true" && "${SELECT_ODOO}" == "false" ]]; then
    STACK_LABEL="website"
elif [[ "${SELECT_ODOO}" == "true" && "${SELECT_WEBSITE}" == "false" ]]; then
    STACK_LABEL="odoo-community"
fi

# Internal self-test mode: parse arguments and print the resolved selection,
# then exit before any prerequisite checks or side effects. Never used during
# a normal deploy; only invoked explicitly via DEPLOY_SH_SELFTEST=1 for static
# validation of the argument parser.
if [[ "${DEPLOY_SH_SELFTEST:-}" == "1" ]]; then
    echo "stack_label=${STACK_LABEL}"
    echo "select_website=${SELECT_WEBSITE}"
    echo "select_odoo=${SELECT_ODOO}"
    echo "enable_ssl=${ENABLE_SSL}"
    echo "stack_is_full=${STACK_IS_FULL}"
    echo "profile_args=${PROFILE_ARGS[*]:-}"
    echo "selected_services=${SELECTED_SERVICES[*]:-}"
    exit 0
fi

info "Selected stack: ${STACK_LABEL}"

cd "${REPO_ROOT}"

ENV_FILE="${REPO_ROOT}/.env"
COMPOSE_FILES=(-f "${REPO_ROOT}/docker/compose.yml" -f "${REPO_ROOT}/docker/compose.prod.yml")
COMPOSE_CMD=(docker compose --env-file "${ENV_FILE}" "${COMPOSE_FILES[@]}")

# -----------------------------------------------------------------------------
# Always-required prerequisites
# -----------------------------------------------------------------------------
info "Checking prerequisites..."
command -v docker &>/dev/null || error "Docker is not installed. Run scripts/install/install.sh first."
docker compose version &>/dev/null || error "Docker Compose v2 is required."
command -v git &>/dev/null || error "git is required."

[[ -f "${ENV_FILE}" ]] || error ".env file not found. Copy .env.example to .env and fill in all values."

set -a
source "${ENV_FILE}"
set +a

: "${POSTGRES_PASSWORD:?Missing POSTGRES_PASSWORD in .env}"

if [[ "${POSTGRES_PASSWORD}" == "CHANGE_ME" ]]; then
    error "Replace CHANGE_ME secrets in .env before deploying."
fi

if [[ "${SELECT_WEBSITE}" == "true" ]]; then
    : "${DOMAIN:?Missing DOMAIN in .env}"
    : "${REACT_REPO_URL:?Missing REACT_REPO_URL in .env}"
    : "${WEBSITE_DB_PASSWORD:?Missing WEBSITE_DB_PASSWORD in .env}"
    : "${VITE_SITE_URL:=https://infoaxon.lk}"
    export VITE_SITE_URL

    if [[ "${WEBSITE_DB_PASSWORD}" == "CHANGE_ME" ]]; then
        error "Replace CHANGE_ME secrets in .env before deploying."
    fi
fi

if [[ "${SELECT_ODOO}" == "true" ]]; then
    : "${ODOO_ADMIN_PASSWORD:?Missing ODOO_ADMIN_PASSWORD in .env}"

    if [[ "${ODOO_ADMIN_PASSWORD}" == "CHANGE_ME" ]]; then
        error "Replace CHANGE_ME secrets in .env before deploying."
    fi
fi

success "Prerequisites satisfied."

info "Creating required directories..."
mkdir -p "${REPO_ROOT}/logs"
if [[ "${SELECT_WEBSITE}" == "true" ]]; then
    mkdir -p \
        "${REPO_ROOT}/logs/nginx" \
        "${REPO_ROOT}/ssl/certbot/www" \
        "${REPO_ROOT}/ssl/live/${DOMAIN}"
fi
if [[ "${SELECT_ODOO}" == "true" ]]; then
    mkdir -p "${REPO_ROOT}/logs/odoo"
fi

# -----------------------------------------------------------------------------
# Website-only workflow
# -----------------------------------------------------------------------------
if [[ "${SELECT_WEBSITE}" == "true" ]]; then
    info "Cloning or updating React frontend from: ${REACT_REPO_URL}"
    REACT_APP_DIR="${REPO_ROOT}/docker/react/app"

    ensure_react_app_git_access() {
        local deploy_uid_gid
        deploy_uid_gid="$(id -u):$(id -g)"

        git config --global --get-all safe.directory | grep -Fxq "${REACT_APP_DIR}" || \
            git config --global --add safe.directory "${REACT_APP_DIR}"

        if [[ -d "${REACT_APP_DIR}" ]]; then
            if [[ "${EUID}" -eq 0 ]]; then
                chown -R "${deploy_uid_gid}" "${REACT_APP_DIR}"
            elif command -v sudo &>/dev/null; then
                sudo chown -R "${deploy_uid_gid}" "${REACT_APP_DIR}"
            else
                chown -R "${deploy_uid_gid}" "${REACT_APP_DIR}"
            fi
        fi
    }

    if [[ -d "${REACT_APP_DIR}/.git" ]]; then
        ensure_react_app_git_access
        info "React repo already cloned; fetching latest refs..."
        git -C "${REACT_APP_DIR}" fetch --all --prune
        if [[ -n "${REACT_BRANCH:-}" ]]; then
            git -C "${REACT_APP_DIR}" checkout "${REACT_BRANCH}"
            git -C "${REACT_APP_DIR}" pull --ff-only origin "${REACT_BRANCH}" || true
        else
            DEFAULT_BRANCH="$(git -C "${REACT_APP_DIR}" symbolic-ref --quiet --short refs/remotes/origin/HEAD | sed 's|^origin/||' || true)"
            if [[ -n "${DEFAULT_BRANCH}" ]]; then
                git -C "${REACT_APP_DIR}" checkout "${DEFAULT_BRANCH}"
                git -C "${REACT_APP_DIR}" pull --ff-only origin "${DEFAULT_BRANCH}" || true
            fi
        fi
    else
        rm -rf "${REACT_APP_DIR}"
        if [[ -n "${REACT_BRANCH:-}" ]]; then
            git clone --branch "${REACT_BRANCH}" "${REACT_REPO_URL}" "${REACT_APP_DIR}"
        else
            git clone "${REACT_REPO_URL}" "${REACT_APP_DIR}"
        fi
    fi
    success "React source is ready at docker/react/app."

    [[ -f "${REACT_APP_DIR}/package.json" ]] || error "External repo must contain package.json at its root."
    [[ -f "${REACT_APP_DIR}/package-lock.json" ]] || error "External repo must contain package-lock.json at its root."
    [[ -f "${REACT_APP_DIR}/server/index.js" ]] || error "External repo must contain server/index.js."
    [[ -f "${REACT_APP_DIR}/server/prisma/schema.prisma" ]] || error "External repo must contain server/prisma/schema.prisma."
    [[ -f "${REPO_ROOT}/docker/company-backend/.env.production" ]] || \
        error "Create docker/company-backend/.env.production from .env.production.example."
fi

# -----------------------------------------------------------------------------
# Shared: start PostgreSQL (always required by either stack)
# -----------------------------------------------------------------------------
info "Starting PostgreSQL..."
"${COMPOSE_CMD[@]}" "${PROFILE_ARGS[@]}" up -d --wait postgres

if [[ "${SELECT_WEBSITE}" == "true" ]]; then
    info "Ensuring the website database/user exist..."
    "${COMPOSE_CMD[@]}" exec -T postgres psql \
        --username "${POSTGRES_USER:-odoo}" --dbname postgres \
        --set=website_user="${WEBSITE_DB_USER:-infoaxon_web}" \
        --set=website_db="${WEBSITE_DB_NAME:-infoaxon_website}" \
        --set=website_password="${WEBSITE_DB_PASSWORD}" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'website_user', :'website_password')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'website_user') \gexec
SELECT format('ALTER ROLE %I LOGIN PASSWORD %L', :'website_user', :'website_password') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'website_db', :'website_user')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'website_db') \gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'website_db', :'website_user') \gexec
SQL
    success "Website database is ready."
fi

info "Validating Docker Compose configuration..."
"${COMPOSE_CMD[@]}" "${PROFILE_ARGS[@]}" config >/dev/null
success "Compose configuration is valid."

# -----------------------------------------------------------------------------
# Website-only build/migrate/deploy steps
# -----------------------------------------------------------------------------
if [[ "${SELECT_WEBSITE}" == "true" ]]; then
    info "Building the company backend image for Prisma migrations..."
    "${COMPOSE_CMD[@]}" "${PROFILE_ARGS[@]}" build --pull company-backend
    success "Company backend image built."

    info "Applying Prisma production migrations..."
    "${COMPOSE_CMD[@]}" "${PROFILE_ARGS[@]}" run --rm --no-deps company-backend npx prisma migrate deploy --schema=server/prisma/schema.prisma
    success "Prisma migrations applied."

    info "Building React..."
    # The React build queries PostgreSQL during SEO generation (server-side
    # data used to prerender SEO files), so it needs reach to the Compose
    # backend network. The classic (non-BuildKit) builder honors the
    # react.build.network setting in compose.yml; BuildKit's default builder
    # does not support attaching a custom Compose network to a build, and the
    # docker-container Buildx builder used previously could not reliably
    # resolve the backend network's DNS during `npm run build`. This is a
    # compatibility workaround for the current database-driven build, not the
    # intended long-term build architecture.
    DOCKER_BUILDKIT=0 COMPOSE_DOCKER_CLI_BUILD=0 "${COMPOSE_CMD[@]}" "${PROFILE_ARGS[@]}" build --pull react
    success "React image built."

    info "Building Nginx..."
    "${COMPOSE_CMD[@]}" "${PROFILE_ARGS[@]}" build --pull nginx
    success "Nginx image built."
fi

# -----------------------------------------------------------------------------
# Odoo Community-only build steps
# -----------------------------------------------------------------------------
if [[ "${SELECT_ODOO}" == "true" ]]; then
    info "Building Odoo..."
    "${COMPOSE_CMD[@]}" "${PROFILE_ARGS[@]}" build --pull odoo
    success "Odoo image built."

    info "Fixing Odoo log directory ownership..."
    ODOO_UID_GID="$("${COMPOSE_CMD[@]}" "${PROFILE_ARGS[@]}" run --rm --no-deps --entrypoint sh odoo -c 'printf "%s:%s" "$(id -u)" "$(id -g)"')"
    if [[ "${EUID}" -eq 0 ]]; then
        chown -R "${ODOO_UID_GID}" "${REPO_ROOT}/logs/odoo"
        chmod -R u+rwX,g+rwX "${REPO_ROOT}/logs/odoo"
    else
        command -v sudo &>/dev/null || error "sudo is required to fix Odoo log permissions."
        sudo chown -R "${ODOO_UID_GID}" "${REPO_ROOT}/logs/odoo"
        sudo chmod -R u+rwX,g+rwX "${REPO_ROOT}/logs/odoo"
    fi
fi

# -----------------------------------------------------------------------------
# Start/update selected services (non-destructive to unselected services)
# -----------------------------------------------------------------------------
info "Starting/recreating selected services (${STACK_LABEL}) without removing volumes..."
if [[ "${STACK_IS_FULL}" == "true" ]]; then
    # Full combined stack: matches the previous unconditional deploy behavior exactly.
    "${COMPOSE_CMD[@]}" "${PROFILE_ARGS[@]}" up -d --remove-orphans "${SELECTED_SERVICES[@]}"
else
    # Subset deployment: never touch containers/services outside the selection.
    "${COMPOSE_CMD[@]}" "${PROFILE_ARGS[@]}" up -d "${SELECTED_SERVICES[@]}"
fi

if [[ "${SELECT_WEBSITE}" == "true" ]]; then
    info "Checking Nginx configuration..."
    "${COMPOSE_CMD[@]}" "${PROFILE_ARGS[@]}" exec -T nginx nginx -t
    success "Nginx configuration is valid."
fi

if [[ "${SELECT_ODOO}" == "true" ]]; then
    info "Waiting for Odoo to become healthy (max 3 minutes)..."
    timeout=180
    elapsed=0
    interval=10
    until docker inspect --format='{{.State.Health.Status}}' erp-odoo 2>/dev/null | grep -q "healthy"; do
        if [[ $elapsed -ge $timeout ]]; then
            error "Odoo did not become healthy in ${timeout}s. Check: docker logs erp-odoo"
        fi
        echo "  ... waiting (${elapsed}s / ${timeout}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    success "Odoo is healthy."
fi

if [[ "${ENABLE_SSL}" == "true" ]]; then
    info "Configuring Let's Encrypt SSL for ${DOMAIN} and www.${DOMAIN}..."
    bash "${SCRIPT_DIR}/setup-ssl.sh" "${DOMAIN}"
fi

# -----------------------------------------------------------------------------
# Verify only the selected services (non-destructive: inspection only)
# -----------------------------------------------------------------------------
info "Verifying selected services (${STACK_LABEL})..."
VERIFY_FAILED=false
for svc in "${SELECTED_SERVICES[@]}"; do
    container_id="$("${COMPOSE_CMD[@]}" "${PROFILE_ARGS[@]}" ps -q "${svc}")"
    if [[ -z "${container_id}" ]]; then
        echo -e "  ${RED}[FAIL]${NC} ${svc}: container not found"
        VERIFY_FAILED=true
        continue
    fi

    state="$(docker inspect --format='{{.State.Status}}' "${container_id}" 2>/dev/null || echo "unknown")"
    health="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container_id}" 2>/dev/null || echo "unknown")"

    if [[ "${health}" == "healthy" ]]; then
        echo -e "  ${GREEN}[PASS]${NC} ${svc}: healthy"
    elif [[ "${health}" == "none" && "${state}" == "running" ]]; then
        echo -e "  ${GREEN}[PASS]${NC} ${svc}: running (no healthcheck defined)"
    else
        echo -e "  ${RED}[FAIL]${NC} ${svc}: state=${state} health=${health}"
        VERIFY_FAILED=true
    fi
done

if [[ "${VERIFY_FAILED}" == "true" ]]; then
    error "One or more selected services failed verification."
fi
success "All selected services verified."

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Deployment complete (stack: ${STACK_LABEL})${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
"${COMPOSE_CMD[@]}" "${PROFILE_ARGS[@]}" ps
echo ""
echo "Access:"
if [[ "${SELECT_WEBSITE}" == "true" ]]; then
    echo "  Website HTTP : http://${DOMAIN}"
    if [[ -f "${REPO_ROOT}/ssl/live/${DOMAIN}/fullchain.pem" ]]; then
        echo "  Website HTTPS: https://${DOMAIN}"
    fi
fi
if [[ "${SELECT_ODOO}" == "true" ]]; then
    SERVER_IP="$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo '<server-ip>')"
    echo "  Odoo demo    : http://${SERVER_IP}:8069"
fi
REDEPLOY_HINT="bash scripts/install/deploy.sh --stack ${STACK_LABEL}"
if [[ "${ENABLE_SSL}" == "true" ]]; then
    REDEPLOY_HINT="${REDEPLOY_HINT} --ssl"
fi

echo ""
echo "Redeploy with:"
echo "  ${REDEPLOY_HINT}"
echo ""

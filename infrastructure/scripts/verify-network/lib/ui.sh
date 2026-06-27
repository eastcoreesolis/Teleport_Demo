# lib/ui.sh
# ============================================================================
#  UI formatting helpers: colors, banner, section, ok/fail/warn/note
#  Sourced by the main script. Defines no global state besides color codes.
# ============================================================================

if [[ -t 1 ]]; then
  RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
  CYN='\033[0;36m'; BLU='\033[0;34m'; BLD='\033[1m'; NC='\033[0m'
else
  RED=''; GRN=''; YLW=''; CYN=''; BLU=''; BLD=''; NC=''
fi

banner() {
  echo ""
  echo -e "${BLU}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLU}║${NC}${BLD}        Kubernetes Cluster Network Verification                ${NC}${BLU}║${NC}"
  echo -e "${BLU}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

section() {
  echo ""
  echo -e "${BLU}────────────────────────────────────────────────────────────────${NC}"
  echo -e "${BLD}  $1${NC}"
  echo -e "${BLU}────────────────────────────────────────────────────────────────${NC}"
}

ok()   { echo -e "  ${GRN}✓${NC}  $1"; }
warn() { echo -e "  ${YLW}⚠${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC}  $1"; }
note() { echo -e "      ${CYN}→${NC}  $1"; }

#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# install_ishare2_eve.sh
# - Instala ishare2
# - Instala adapter "ishare2-eve" para EVE-NG
# - Corrige automaticamente:
#   * função antes do main()
#   * source usando BASH_SOURCE (não $0)
#   * detector do store (não confunde com /opt/qemu-*/etc)
#   * se imagem já existir no EVE com hda.qcow2 -> virtioa.qcow2
#   * fixpermissions robusto
#
# Requisitos: Ubuntu/Debian (EVE-NG community/pro)
# ============================================================

INSTALL_DIR="/opt/ishare2-eve"
BIN_DIR="${INSTALL_DIR}/bin"
LIB_DIR="${INSTALL_DIR}/lib"
CMD_LINK="/usr/local/bin/ishare2-eve"

ISHARE2_REPO="${ISHARE2_REPO:-https://github.com/ishare2-org/ishare2-cli.git}"
ISHARE2_DIR="${ISHARE2_DIR:-/opt/ishare2}"

log()  { echo -e "\e[1;32m[+]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
err()  { echo -e "\e[1;31m[ERRO]\e[0m $*"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Rode como root: sudo bash $0"
    exit 1
  fi
}

detect_platform() {
  if [[ -d /opt/unetlab ]]; then
    echo "eve-ng"
  elif [[ -d /opt/pnetlab ]]; then
    echo "pnetlab"
  else
    echo "unsupported"
  fi
}

install_deps() {
  log "Instalando dependências..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  apt-get install -y \
    git curl wget ca-certificates bash coreutils util-linux \
    findutils grep sed gawk timeout >/dev/null 2>&1 || true
}

# ------------------------------------------------------------
# FIX: instala ishare2 sem travar, com fallback de symlink
# ------------------------------------------------------------
install_ishare2() {
  if command -v ishare2 >/dev/null 2>&1; then
    log "ishare2 já está instalado: $(command -v ishare2)"
    return
  fi

  log "Clonando ishare2 em ${ISHARE2_DIR}..."
  rm -rf "${ISHARE2_DIR}" || true
  git clone --depth 1 "${ISHARE2_REPO}" "${ISHARE2_DIR}" >/dev/null

  if [[ -f "${ISHARE2_DIR}/install.sh" ]]; then
    log "Executando install.sh do ishare2 (com timeout)..."
    set +e
    timeout 180 bash "${ISHARE2_DIR}/install.sh" </dev/null >/tmp/ishare2_install.log 2>&1
    rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
      warn "install.sh retornou código $rc ou timeout"
      warn "Veja /tmp/ishare2_install.log"
    fi
  else
    warn "install.sh não encontrado no repo (seguindo com fallback)."
  fi

  if ! command -v ishare2 >/dev/null 2>&1; then
    log "ishare2 não está no PATH, procurando binário no repo..."
    candidate="$(find "${ISHARE2_DIR}" -maxdepth 5 -type f \( -name ishare2 -o -name ishare2.sh \) 2>/dev/null | head -n1 || true)"
    if [[ -z "${candidate}" ]]; then
      err "Não encontrei binário do ishare2 no repo."
      err "Log: /tmp/ishare2_install.log"
      exit 1
    fi
    chmod +x "${candidate}" || true
    ln -sf "${candidate}" /usr/local/bin/ishare2
  fi

  if ! command -v ishare2 >/dev/null 2>&1; then
    err "ishare2 ainda não ficou disponível."
    err "Veja /tmp/ishare2_install.log"
    exit 1
  fi

  log "ishare2 instalado: $(command -v ishare2)"
}

# ------------------------------------------------------------
# Cria/atualiza os arquivos do adapter
# ------------------------------------------------------------
write_files() {
  log "Criando adapter em ${INSTALL_DIR}..."
  mkdir -p "${BIN_DIR}" "${LIB_DIR}"

  # detect_platform.sh
  cat > "${LIB_DIR}/detect_platform.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
detect_platform() {
  if [ -d /opt/unetlab ]; then
    echo "eve-ng"
  elif [ -d /opt/pnetlab ]; then
    echo "pnetlab"
  else
    echo "unsupported"
  fi
}
EOF

  # validate_image.sh
  cat > "${LIB_DIR}/validate_image.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
validate_image_dir() {
  local img_dir="$1"
  local f
  f="$(ls "$img_dir"/*.qcow2 2>/dev/null | head -n1 || true)"
  if [ -z "$f" ]; then
    echo "[ERRO] Nenhum .qcow2 encontrado em: $img_dir" >&2
    return 1
  fi
  local size
  size="$(stat -c%s "$f" 2>/dev/null || echo 0)"
  if [ "$size" -lt 300000000 ]; then
    echo "[ERRO] Imagem muito pequena (<300MB): $f (size=$size). Provavelmente inválida." >&2
    return 1
  fi
  return 0
}
EOF

  # detect_ishare2_store.sh (robusto: só aceita store com qcow2 e ignora /opt/qemu-*)
  cat > "${LIB_DIR}/detect_ishare2_store.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

detect_ishare2_store() {
  local candidates=(
    "${ISHARE2_STORE:-}"
    "/root/ishare2"
    "/root/.ishare2"
    "/opt/ishare2"
    "/opt/ishare2-store"
    "/opt/ishare2/images"
  )

  for d in /home/*/ishare2 /home/*/.ishare2; do
    [ -d "$d" ] && candidates+=("$d")
  done

  _is_valid_store() {
    local base="$1"
    [ -d "${base}/qemu" ] || return 1
    find "${base}/qemu" -maxdepth 2 -type f -name "*.qcow2" 2>/dev/null | head -n 1 | grep -q .
  }

  for base in "${candidates[@]}"; do
    [ -n "${base}" ] || continue
    _is_valid_store "${base}" && { echo "${base}"; return 0; }
  done

  # Scan controlado: procura "qemu" mas ignora /opt/qemu-*/etc/qemu
  for r in /root /home /opt; do
    [ -d "$r" ] || continue
    while IFS= read -r qdir; do
      case "$qdir" in
        /opt/qemu-*/*) continue ;; # ignora qemu do sistema
      esac
      base="$(dirname "$qdir")"
      _is_valid_store "$base" && { echo "$base"; return 0; }
    done < <(find "$r" -maxdepth 6 -type d -name qemu 2>/dev/null)
  done

  return 1
}
EOF

  # eve_install.sh (BASH_SOURCE + idempotente + corrige hda.qcow2)
  cat > "${LIB_DIR}/eve_install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_THIS_DIR}/validate_image.sh"
source "${_THIS_DIR}/detect_ishare2_store.sh"

run_fixpermissions() {
  if [ -x /opt/unetlab/wrappers/unl_wrapper ]; then
    bash /opt/unetlab/wrappers/unl_wrapper -a fixpermissions
    return 0
  fi
  if [ -x /opt/unetlab/unl_wrapper ]; then
    bash /opt/unetlab/unl_wrapper -a fixpermissions
    return 0
  fi
  if [ -x /opt/unetlab/wrappers/fixpermissions ]; then
    bash /opt/unetlab/wrappers/fixpermissions
    return 0
  fi
  echo "[WARN] fixpermissions não encontrado automaticamente. Rode manualmente." >&2
  return 1
}

install_eve_qemu() {
  local name="$1"
  local dst="/opt/unetlab/addons/qemu/${name}"

  # Caso A: já existe no EVE -> normaliza para virtioa.qcow2
  if [ -d "$dst" ]; then
    echo "[+] Diretório já existe no EVE: $dst"

    if [ -f "$dst/virtioa.qcow2" ]; then
      echo "[+] virtioa.qcow2 já presente"
    else
      local any_qcow
      any_qcow="$(ls "$dst"/*.qcow2 2>/dev/null | head -n1 || true)"
      if [ -n "$any_qcow" ]; then
        echo "[+] Normalizando $(basename "$any_qcow") -> virtioa.qcow2"
        mv "$any_qcow" "$dst/virtioa.qcow2"
      else
        echo "[ERRO] Nenhum qcow2 encontrado em $dst" >&2
        return 1
      fi
    fi

    chown -R root:root "$dst"
    chmod -R 755 "$dst"
    run_fixpermissions || true
    echo "[✓] Imagem pronta no EVE-NG (corrigida/normalizada)"
    return 0
  fi

  # Caso B: não existe no EVE -> instala vindo do store do ishare2
  local store
  if ! store="$(detect_ishare2_store)"; then
    echo "[ERRO] Não consegui detectar o store do ishare2." >&2
    echo "      Dica: rode 'ishare2 pull qemu ${name}' primeiro ou defina ISHARE2_STORE=/caminho/base" >&2
    return 1
  fi

  local src="${store}/qemu/${name}"
  if [ ! -d "$src" ]; then
    echo "[ERRO] Diretório fonte não existe: $src" >&2
    echo "      Dica: rode primeiro: ishare2 pull qemu ${name}" >&2
    echo "      Store detectado: $store" >&2
    return 1
  fi

  echo "[+] Store ishare2: $store"
  validate_image_dir "$src"

  mkdir -p "$dst"

  local qcow
  qcow="$(ls "$src"/*.qcow2 | head -n1)"
  echo "[+] Copiando $(basename "$qcow") -> virtioa.qcow2"
  cp -f "$qcow" "$dst/virtioa.qcow2"

  chown -R root:root "$dst"
  chmod -R 755 "$dst"
  run_fixpermissions || true

  echo "[✓] Imagem instalada no EVE-NG: $dst"
}
EOF

  # main command: ishare2-eve
  cat > "${BIN_DIR}/ishare2-eve" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/ishare2-eve"

source "${INSTALL_DIR}/lib/detect_platform.sh"
source "${INSTALL_DIR}/lib/eve_install.sh"
source "${INSTALL_DIR}/lib/detect_ishare2_store.sh"

usage() {
  echo "Uso:"
  echo "  ishare2-eve pull qemu <nome-ou-id>"
  echo "  ishare2-eve install qemu <nome-ou-id>"
  echo "  ishare2-eve pull-install qemu <nome-ou-id>"
  echo
  echo "Opcional:"
  echo "  ISHARE2_STORE=/caminho/base (força o store do ishare2)"
}

if [ "${#}" -lt 3 ]; then
  usage
  exit 1
fi

ACTION="$1"
TYPE="$2"
NAME="$3"

PLATFORM="$(detect_platform)"
if [ "$PLATFORM" != "eve-ng" ]; then
  echo "[ERRO] Este adapter é para EVE-NG. Detectado: $PLATFORM" >&2
  exit 1
fi

if [ "$TYPE" != "qemu" ]; then
  echo "[ERRO] Neste release suportamos apenas TYPE=qemu" >&2
  exit 1
fi

if ! command -v ishare2 >/dev/null 2>&1; then
  echo "[ERRO] ishare2 não encontrado no PATH." >&2
  exit 1
fi

STORE="$(detect_ishare2_store 2>/dev/null || true)"
[ -n "$STORE" ] && echo "[i] ishare2 store detectado: $STORE" || true

case "$ACTION" in
  pull)
    ishare2 pull "$TYPE" "$NAME"
    ;;
  install)
    install_eve_qemu "$NAME"
    ;;
  pull-install)
    ishare2 pull "$TYPE" "$NAME"
    install_eve_qemu "$NAME"
    ;;
  *)
    usage
    exit 1
    ;;
esac
EOF

  chmod +x "${BIN_DIR}/ishare2-eve" \
    "${LIB_DIR}/detect_platform.sh" \
    "${LIB_DIR}/validate_image.sh" \
    "${LIB_DIR}/detect_ishare2_store.sh" \
    "${LIB_DIR}/eve_install.sh"
}

install_command() {
  log "Instalando comando em ${CMD_LINK}..."
  ln -sf "${BIN_DIR}/ishare2-eve" "${CMD_LINK}"
  log "OK: ${CMD_LINK} -> ${BIN_DIR}/ishare2-eve"
}

run_validations() {
  log "Rodando validações..."
  local platform
  platform="$(detect_platform)"
  log "Plataforma detectada: ${platform}"

  if [[ "${platform}" != "eve-ng" ]]; then
    warn "Não detectei /opt/unetlab (EVE-NG). Este installer é para EVE-NG."
  fi

  command -v ishare2 >/dev/null 2>&1 && log "ishare2 OK: $(command -v ishare2)" || { err "ishare2 não encontrado"; exit 1; }
  command -v ishare2-eve >/dev/null 2>&1 && log "ishare2-eve OK: $(command -v ishare2-eve)" || { err "ishare2-eve não encontrado"; exit 1; }

  if [[ -x /opt/unetlab/wrappers/unl_wrapper ]]; then
    log "unl_wrapper OK: /opt/unetlab/wrappers/unl_wrapper"
  else
    warn "unl_wrapper não executável. Tentaremos via bash quando necessário."
  fi

  if store="$(bash -lc "${LIB_DIR}/detect_ishare2_store.sh; detect_ishare2_store" 2>/dev/null)"; then
    log "Store detectado: ${store}"
  else
    warn "Store do ishare2 ainda não detectável (normal se você não baixou imagens ainda)."
  fi

  log "Validações concluídas."
}

optional_test_download() {
  local test_image="${1:-}"
  [[ -z "${test_image}" ]] && return 0
  log "Teste opcional: tentando pull-install qemu '${test_image}'"
  set +e
  ishare2-eve pull-install qemu "${test_image}"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    warn "Teste pull-install falhou. Pode ser normal (repo/mirror/ID)."
  else
    log "Teste pull-install OK para '${test_image}'."
  fi
}

main() {
  require_root
  install_deps
  install_ishare2
  write_files
  install_command
  run_validations
  optional_test_download "${1:-}"
  log "Pronto! Exemplos:"
  echo "  ishare2 search qemu mikrotik"
  echo "  ishare2-eve pull-install qemu mikrotik-7.17"
  echo "  ishare2-eve install qemu mikrotik-7.17   (se já existir no EVE)"
}

main "$@"

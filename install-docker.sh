#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="2026-03-14.2"

# One-click installer for Docker Engine + Docker Compose plugin
# Supports: Ubuntu, Debian, CentOS, RHEL, Rocky, AlmaLinux, Fedora

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[信息]${NC} $*"; }
ok(){ echo -e "${GREEN}[成功]${NC} $*"; }
warn(){ echo -e "${YELLOW}[警告]${NC} $*"; }
die(){ echo -e "${RED}[错误]${NC} $*" >&2; exit 1; }

has_cmd(){ command -v "$1" >/dev/null 2>&1; }

INSTALL_MODE="install"
DOCKER_BEFORE=""
DOCKER_AFTER=""
COMPOSE_BEFORE=""
COMPOSE_AFTER=""

capture_versions_before() {
  if has_cmd docker; then
    DOCKER_BEFORE="$(docker --version 2>/dev/null || true)"
  fi
  if has_cmd docker && docker compose version >/dev/null 2>&1; then
    COMPOSE_BEFORE="$(docker compose version | head -n1)"
  fi

  if [[ -n "$DOCKER_BEFORE" ]]; then
    INSTALL_MODE="upgrade-or-skip"
    info "检测到已安装 Docker，将自动执行“升级或跳过”逻辑"
    info "当前 Docker: ${DOCKER_BEFORE}"
    [[ -n "$COMPOSE_BEFORE" ]] && info "当前 Compose: ${COMPOSE_BEFORE}"
  fi
}

capture_versions_after() {
  if has_cmd docker; then
    DOCKER_AFTER="$(docker --version 2>/dev/null || true)"
  fi
  if has_cmd docker && docker compose version >/dev/null 2>&1; then
    COMPOSE_AFTER="$(docker compose version | head -n1)"
  fi
}

print_header() {
  echo
  echo "============================= Docker 一键安装 ============================="
  echo "脚本版本: ${SCRIPT_VERSION}"
  echo "支持系统: Ubuntu / Debian / CentOS / RHEL / Rocky / AlmaLinux / Fedora"
  echo "========================================================================="
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "请使用 root 执行（示例：curl ... | sudo bash）"
  fi
}

setup_debian() {
  info "步骤 1/4：检测到 Debian/Ubuntu 系列，安装依赖并配置 Docker 官方源"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null

  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  local codename arch id
  codename=$(. /etc/os-release; echo "$VERSION_CODENAME")
  arch=$(dpkg --print-architecture)
  id=$(. /etc/os-release; echo "$ID")

  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${id} ${codename} stable" \
    > /etc/apt/sources.list.d/docker.list

  info "步骤 2/4：安装 Docker 组件"
  apt-get update -y >/dev/null
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
}

setup_rhel_like() {
  info "步骤 1/4：检测到 RHEL/CentOS/Rocky/Alma/Fedora 系列，配置 Docker 官方源"

  if has_cmd dnf; then
    dnf -y install dnf-plugins-core curl ca-certificates >/dev/null
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null || true
    info "步骤 2/4：安装 Docker 组件"
    dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
  elif has_cmd yum; then
    yum -y install yum-utils curl ca-certificates >/dev/null
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null || true
    info "步骤 2/4：安装 Docker 组件"
    yum -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
  else
    die "系统缺少 dnf/yum，无法安装"
  fi
}

enable_service() {
  info "步骤 3/4：启动并设置 Docker 开机自启"
  systemctl daemon-reload || true
  systemctl enable --now docker >/dev/null

  if ! systemctl is-active --quiet docker; then
    systemctl status docker --no-pager -l >&2 || true
    die "Docker 服务未正常启动"
  fi
}

ensure_compose_compat() {
  if has_cmd docker-compose; then
    return 0
  fi

  if docker compose version >/dev/null 2>&1; then
    ln -sf "$(command -v docker)" /usr/local/bin/docker-compose || true
    warn "已创建兼容命令: /usr/local/bin/docker-compose -> docker"
    warn "建议优先使用: docker compose"
  fi
}

post_check() {
  info "步骤 4/4：安装结果校验"

  has_cmd docker || die "未检测到 docker 命令，安装失败"
  local docker_ver compose_ver
  docker_ver="$(docker --version)"
  capture_versions_after

  if docker compose version >/dev/null 2>&1; then
    compose_ver="$(docker compose version | head -n1)"
  elif has_cmd docker-compose; then
    compose_ver="$(docker-compose --version)"
  else
    compose_ver="未检测到 compose 命令"
  fi

  echo
  echo "================================ 安装结果 ================================="
  echo "Docker:          ${docker_ver}"
  echo "Docker Compose:  ${compose_ver}"
  echo "服务状态:        $(systemctl is-active docker 2>/dev/null || echo unknown)"
  echo "========================================================================="
  local action_result="新安装"
  if [[ "$INSTALL_MODE" == "upgrade-or-skip" ]]; then
    if [[ "$DOCKER_BEFORE" != "$DOCKER_AFTER" || "$COMPOSE_BEFORE" != "$COMPOSE_AFTER" ]]; then
      action_result="已升级"
    else
      action_result="已是最新，跳过升级"
    fi
  fi

  echo "处理结果:        ${action_result}"
  echo
  ok "安装完成 ✅"
  echo "测试命令: docker run --rm hello-world"
  echo "免 sudo 使用（可选）: usermod -aG docker <your-user> && 重新登录"
}

main() {
  print_header
  require_root
  capture_versions_before

  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
  else
    die "系统不支持：缺少 /etc/os-release"
  fi

  case "${ID:-}" in
    ubuntu|debian)
      setup_debian
      ;;
    centos|rhel|rocky|almalinux|fedora)
      setup_rhel_like
      ;;
    *)
      if [[ "${ID_LIKE:-}" == *"debian"* ]]; then
        setup_debian
      elif [[ "${ID_LIKE:-}" == *"rhel"* || "${ID_LIKE:-}" == *"fedora"* ]]; then
        setup_rhel_like
      else
        die "暂不支持当前系统: ${ID:-unknown}"
      fi
      ;;
  esac

  enable_service
  ensure_compose_compat
  post_check
}

main "$@"

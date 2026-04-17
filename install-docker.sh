#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="2026-04-17"

# One-click installer for Docker Engine + Docker Compose plugin
# Supports: Ubuntu, Debian, CentOS, RHEL, Rocky, AlmaLinux, Fedora

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[信息]${NC} $*"; }
ok(){ echo -e "${GREEN}[成功]${NC} $*"; }
warn(){ echo -e "${YELLOW}[警告]${NC} $*"; }
die(){ echo -e "${RED}[错误]${NC} $*" >&2; exit 1; }

has_cmd(){ command -v "$1" >/dev/null 2>&1; }

LOG_FILE="/tmp/docker-install-$(date +%s).log"
INSTALL_MODE="install"
DOCKER_BEFORE=""
DOCKER_AFTER=""
COMPOSE_BEFORE=""
COMPOSE_AFTER=""
USE_CN_MIRROR=0

# ---------- 参数解析 ----------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mirror)
        if [[ "${2:-}" == "cn" ]]; then
          USE_CN_MIRROR=1
          shift
        else
          die "--mirror 仅支持 cn(国内镜像加速)"
        fi
        ;;
      --help|-h)
        echo "用法: install-docker.sh [选项]"
        echo ""
        echo "选项:"
        echo "  --mirror cn    安装后自动配置国内镜像加速"
        echo "  --help         显示帮助"
        exit 0
        ;;
      *)
        warn "未知参数: $1(忽略)"
        ;;
    esac
    shift
  done
}

# ---------- 日志 ----------
# 执行命令并记录日志,失败时输出日志路径
run_logged() {
  if ! "$@" >> "$LOG_FILE" 2>&1; then
    warn "命令失败: $*"
    warn "详细日志: $LOG_FILE"
    return 1
  fi
}

capture_versions_before() {
  if has_cmd docker; then
    DOCKER_BEFORE="$(docker --version 2>/dev/null || true)"
  fi
  if has_cmd docker && docker compose version >/dev/null 2>&1; then
    COMPOSE_BEFORE="$(docker compose version | head -n1)"
  fi

  if [[ -n "$DOCKER_BEFORE" ]]; then
    INSTALL_MODE="upgrade-or-skip"
    info "检测到已安装 Docker,将自动执行「升级或跳过」逻辑"
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
  echo "安装日志: ${LOG_FILE}"
  echo "========================================================================="
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "请使用 root 执行(示例:curl ... | sudo bash)"
  fi
}

# ---------- 旧版 Docker 清理 ----------
remove_old_docker() {
  local old_pkgs=(
    docker docker-engine docker.io containerd runc
    podman-docker docker-client docker-client-latest
    docker-common docker-latest docker-latest-logrotate
    docker-logrotate docker-selinux docker-engine-selinux
  )
  local to_remove=()
  local pkg

  for pkg in "${old_pkgs[@]}"; do
    if dpkg -l "$pkg" >/dev/null 2>&1 || rpm -q "$pkg" >/dev/null 2>&1; then
      to_remove+=("$pkg")
    fi
  done

  if [[ ${#to_remove[@]} -gt 0 ]]; then
    info "检测到旧版 Docker 组件,正在清理: ${to_remove[*]}"
    if has_cmd apt-get; then
      run_logged apt-get remove -y "${to_remove[@]}" || true
    elif has_cmd dnf; then
      run_logged dnf remove -y "${to_remove[@]}" || true
    elif has_cmd yum; then
      run_logged yum remove -y "${to_remove[@]}" || true
    fi
    ok "旧版组件已清理"
  fi
}

# ---------- Debian/Ubuntu ----------
setup_debian() {
  info "步骤 2/5:检测到 Debian/Ubuntu 系列,安装依赖并配置 Docker 官方源"
  export DEBIAN_FRONTEND=noninteractive
  run_logged apt-get update -y
  run_logged apt-get install -y ca-certificates curl gnupg lsb-release

  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg" 2>>"$LOG_FILE" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  local codename arch id
  codename=$(. /etc/os-release; echo "$VERSION_CODENAME")
  arch=$(dpkg --print-architecture)
  id=$(. /etc/os-release; echo "$ID")

  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${id} ${codename} stable" \
    > /etc/apt/sources.list.d/docker.list

  info "步骤 3/5:安装 Docker 组件"
  run_logged apt-get update -y
  run_logged apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# ---------- RHEL/CentOS/Rocky/Alma/Fedora ----------
setup_rhel_like() {
  local repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
  local distro_id
  distro_id="${ID:-centos}"

  # Fedora 使用专用 repo
  if [[ "$distro_id" == "fedora" ]]; then
    repo_url="https://download.docker.com/linux/fedora/docker-ce.repo"
  fi

  info "步骤 2/5:检测到 RHEL/CentOS/Rocky/Alma/Fedora 系列,配置 Docker 官方源"

  if has_cmd dnf; then
    run_logged dnf -y install dnf-plugins-core curl ca-certificates
    run_logged dnf config-manager --add-repo "$repo_url" || true
    info "步骤 3/5:安装 Docker 组件"
    run_logged dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif has_cmd yum; then
    run_logged yum -y install yum-utils curl ca-certificates
    run_logged yum-config-manager --add-repo "$repo_url" || true
    info "步骤 3/5:安装 Docker 组件"
    run_logged yum -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    die "系统缺少 dnf/yum,无法安装"
  fi
}

# ---------- 启动服务 ----------
enable_service() {
  info "步骤 4/5:启动并设置 Docker 开机自启"
  systemctl daemon-reload || true
  systemctl enable --now docker >>"$LOG_FILE" 2>&1

  if ! systemctl is-active --quiet docker; then
    systemctl status docker --no-pager -l >&2 || true
    die "Docker 服务未正常启动,详细日志: $LOG_FILE"
  fi
}

# ---------- docker-compose 兼容 ----------
ensure_compose_compat() {
  # 如果已有独立的 docker-compose 二进制,不覆盖
  if has_cmd docker-compose; then
    return 0
  fi

  # 创建 wrapper 脚本,将 docker-compose 命令转发到 docker compose
  if docker compose version >/dev/null 2>&1; then
    cat > /usr/local/bin/docker-compose <<'WRAPPER'
#!/bin/sh
exec docker compose "$@"
WRAPPER
    chmod +x /usr/local/bin/docker-compose
    warn "已创建兼容命令: /usr/local/bin/docker-compose → docker compose"
    warn "建议优先使用: docker compose"
  fi
}

# ---------- 国内镜像加速 ----------
setup_cn_mirror() {
  if [[ "$USE_CN_MIRROR" -ne 1 ]]; then
    return 0
  fi

  info "配置国内镜像加速..."
  local daemon_json="/etc/docker/daemon.json"
  mkdir -p /etc/docker

  if [[ -f "$daemon_json" ]]; then
    # 已有配置,检查是否已有 registry-mirrors
    if grep -q "registry-mirrors" "$daemon_json" 2>/dev/null; then
      warn "daemon.json 已存在镜像配置,跳过"
      return 0
    fi
    warn "daemon.json 已存在,跳过镜像加速配置(避免覆盖已有设置)"
    return 0
  fi

  cat > "$daemon_json" <<'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ]
}
EOF

  # 重启 Docker 使配置生效
  systemctl restart docker >>"$LOG_FILE" 2>&1 || true
  ok "国内镜像加速已配置"
}

# ---------- 防火墙提醒 ----------
check_firewall() {
  if has_cmd ufw && ufw status 2>/dev/null | grep -q "active"; then
    warn "检测到 ufw 防火墙已启用。Docker 会绕过 ufw 规则直接操作 iptables。"
    warn "如需限制容器端口暴露,请参考: https://github.com/chaifeng/ufw-docker"
  fi
  if has_cmd firewall-cmd && firewall-cmd --state 2>/dev/null | grep -q "running"; then
    warn "检测到 firewalld 已启用。如果容器网络不通,可能需要配置 firewalld 放行规则。"
  fi
}

# ---------- 卸载 ----------
uninstall_docker() {
  echo
  echo "============================= Docker 卸载 ============================="
  warn "此操作将卸载 Docker Engine、CLI、Compose 及相关组件。"
  warn "已有的容器、镜像、卷数据默认保留在 /var/lib/docker。"
  echo "======================================================================="
  echo

  read -rp "确认卸载 Docker?[y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消。"; exit 0; }

  local pkgs=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

  if has_cmd apt-get; then
    run_logged apt-get purge -y "${pkgs[@]}" || true
    run_logged apt-get autoremove -y || true
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/keyrings/docker.gpg
  elif has_cmd dnf; then
    run_logged dnf remove -y "${pkgs[@]}" || true
  elif has_cmd yum; then
    run_logged yum remove -y "${pkgs[@]}" || true
  fi

  rm -f /usr/local/bin/docker-compose

  echo
  read -rp "是否同时删除所有容器、镜像、卷数据(/var/lib/docker)?[y/N]: " confirm_data
  if [[ "$confirm_data" =~ ^[Yy]$ ]]; then
    rm -rf /var/lib/docker /var/lib/containerd
    ok "数据目录已删除"
  else
    info "数据目录已保留: /var/lib/docker"
  fi

  ok "Docker 已卸载 ✅"
  exit 0
}

# ---------- 安装结果 ----------
post_check() {
  info "步骤 5/5:安装结果校验"

  has_cmd docker || die "未检测到 docker 命令,安装失败。详细日志: $LOG_FILE"
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
      action_result="已是最新,跳过升级"
    fi
  fi

  echo "处理结果:        ${action_result}"
  echo
  ok "安装完成 ✅"
  echo "测试命令: docker run --rm hello-world"
  echo "免 sudo 使用(可选): usermod -aG docker <your-user> && 重新登录"

  check_firewall
}

# ---------- 主流程 ----------
main() {
  # 卸载模式
  if [[ "${1:-}" == "--uninstall" || "${1:-}" == "uninstall" ]]; then
    require_root
    uninstall_docker
  fi

  parse_args "$@"
  print_header
  require_root
  capture_versions_before

  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
  else
    die "系统不支持:缺少 /etc/os-release"
  fi

  info "步骤 1/5:清理旧版 Docker 组件"
  remove_old_docker

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
  setup_cn_mirror
  post_check
}

main "$@"

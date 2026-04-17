# docker

一个用于 **一键安装 Docker Engine + Docker Compose** 的 Linux 脚本项目。  
已优化安装过程输出，采用分步骤 + 结果汇总的"安装页面风格"。

## 功能

- 识别常见 Linux 发行版（Ubuntu / Debian / CentOS / RHEL / Rocky / AlmaLinux / Fedora）
- 自动清理旧版 Docker 组件（`docker.io`、`docker-engine`、`podman-docker` 等），避免冲突
- 配置 Docker 官方仓库（Fedora 使用专用 repo）
- 安装 Docker 运行环境与 Compose 插件
- 启动 Docker 并设置开机自启
- 自动检测已安装场景：仅执行"升级或跳过"（不会重复安装）
- 创建 `docker-compose` 兼容命令（wrapper 转发到 `docker compose`）
- 可选国内镜像加速配置（`--mirror cn`）
- 安装完成后自动检测防火墙状态并提醒
- 安装过程记录详细日志，失败时输出日志路径
- 输出安装结果汇总（版本、服务状态、处理结果、测试命令）
- 支持一键卸载（`--uninstall`）

## 使用方法

### 一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/Xiuyixx/docker/master/install-docker.sh | sudo bash
```

### 国内环境（自动配置镜像加速）

```bash
curl -fsSL https://raw.githubusercontent.com/Xiuyixx/docker/master/install-docker.sh | sudo bash -s -- --mirror cn
```

### 下载后执行

```bash
git clone https://github.com/Xiuyixx/docker.git
cd docker
chmod +x install-docker.sh
sudo ./install-docker.sh
```

### 卸载 Docker

```bash
sudo ./install-docker.sh --uninstall
```

或一键卸载：

```bash
curl -fsSL https://raw.githubusercontent.com/Xiuyixx/docker/master/install-docker.sh | sudo bash -s -- --uninstall
```

## 安装后验证

```bash
docker --version
docker compose version
docker run --rm hello-world
```

## 免 sudo 使用 Docker（可选）

```bash
sudo usermod -aG docker $USER
# 重新登录会话后生效
```

## 注意事项

- 必须 root 权限执行（建议 `sudo bash`）
- 脚本会自动清理旧版 Docker 组件，无需手动处理
- 新版 Compose 命令为 `docker compose`（脚本同时提供 `docker-compose` 兼容命令）
- Docker 会绕过 ufw 规则直接操作 iptables，如需限制容器端口暴露请额外配置

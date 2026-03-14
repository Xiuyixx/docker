# docker

一个用于 **一键安装 Docker Engine + Docker Compose** 的 Linux 脚本项目。  
已优化安装过程输出，采用分步骤 + 结果汇总的“安装页面风格”（类似你 Shadowsocks 项目的安装体验）。

## 作用

这个项目可以自动完成：
- 识别常见 Linux 发行版（Ubuntu / Debian / CentOS / RHEL / Rocky / AlmaLinux / Fedora）
- 配置 Docker 官方仓库
- 安装 Docker 运行环境与 Compose 插件
- 启动 Docker 并设置开机自启
- 自动检测已安装场景：仅执行“升级或跳过”（不会重复做无意义安装）
- 输出安装结果汇总（版本、服务状态、处理结果、测试命令）

## 使用方法

### 一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/Xiuyixx/docker/master/install-docker.sh | sudo bash
```

### 下载后执行

```bash
git clone https://github.com/Xiuyixx/docker.git
cd docker
chmod +x install-docker.sh
sudo ./install-docker.sh
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
- 若系统存在旧版 Docker 组件，建议先清理再安装
- 新版 Compose 命令为 `docker compose`

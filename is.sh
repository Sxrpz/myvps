#!/bin/bash

# 检查 Root 权限
[[ $EUID -ne 0 ]] && echo -e "\033[31m错误：请使用 root 用户运行此脚本！\033[0m" && exit 1

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 基础路径
WORKDIR="/etc/sing-box"
CERT_DIR="/etc/sing-box/certs"
mkdir -p $CERT_DIR

# --- 1. 环境预准备 (解决依赖问题) ---
echo -e "${YELLOW}正在初始化环境并安装必要组件 (uuid-runtime, curl, nginx)...${NC}"
apt update && apt install -y socat curl wget nginx uuid-runtime openssl > /dev/null 2>&1

# --- 2. 交互询问环节 ---
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}       Sing-Box 2026 自定义部署工具           ${NC}"
echo -e "${GREEN}==============================================${NC}"

# 域名设置
read -p "请输入你的域名 (必填，确保已解析到此IP): " MY_DOMAIN
if [[ -z "$MY_DOMAIN" ]]; then
    echo -e "${RED}错误：必须输入域名才能申请 SSL 证书！${NC}"
    exit 1
fi

# 端口设置
read -p "请输入服务端口 (默认 443): " MY_PORT
MY_PORT=${MY_PORT:-443}

# UUID 设置
read -p "请输入 UUID (直接回车将随机生成): " MY_UUID
if [[ -z "$MY_UUID" ]]; then
    # 再次确保 uuidgen 可用，如果不可用则使用 openssl 生成随机字符串
    if command -v uuidgen >/dev/null 2>&1; then
        MY_UUID=$(uuidgen)
    else
        MY_UUID=$(openssl rand -hex 16 | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/')
    fi
    echo -e "${YELLOW}已生成随机 UUID: $MY_UUID${NC}"
fi

# 邮箱设置
read -p "请输入联系邮箱 (用于证书申请): " MY_EMAIL
MY_EMAIL=${MY_EMAIL:-"admin@$MY_DOMAIN"}

# --- 3. 安装与配置逻辑 ---

install_acme() {
    echo -e "${YELLOW}正在申请 SSL 证书 (ACME)...${NC}"
    systemctl stop nginx > /dev/null 2>&1
    if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        curl https://get.acme.sh | sh -s email=$MY_EMAIL
    fi
    source ~/.bashrc
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    
    ~/.acme.sh/acme.sh --issue -d $MY_DOMAIN --standalone --force
    ~/.acme.sh/acme.sh --install-cert -d $MY_DOMAIN \
        --fullchain-file $CERT_DIR/server.crt \
        --key-file $CERT_DIR/server.key
}

setup_nginx() {
    echo -e "${YELLOW}配置 Nginx 伪装页...${NC}"
    echo "Service Under Maintenance" > /var/www/html/index.html
    cat <<EOF > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name $MY_DOMAIN;
    root /var/www/html;
}
EOF
    systemctl restart nginx
}

setup_singbox() {
    echo -e "${YELLOW}正在安装并配置 Sing-Box...${NC}"
    bash <(curl -Ls

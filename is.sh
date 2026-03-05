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

# --- 交互询问环节 ---
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}       Sing-Box 2026 自定义部署工具           ${NC}"
echo -e "${GREEN}==============================================${NC}"

# 1. 域名设置
read -p "请输入你的域名 (必填，例如 vpn.example.com): " MY_DOMAIN
if [[ -z "$MY_DOMAIN" ]]; then
    echo -e "${RED}错误：必须输入域名才能申请 SSL 证书！${NC}"
    exit 1
fi

# 2. 端口设置
read -p "请输入服务端口 (默认 443): " MY_PORT
MY_PORT=${MY_PORT:-443}

# 3. UUID 设置
read -p "请输入 UUID (直接回车将随机生成): " MY_UUID
if [[ -z "$MY_UUID" ]]; then
    MY_UUID=$(uuidgen)
    echo -e "${YELLOW}已生成随机 UUID: $MY_UUID${NC}"
fi

# 4. 邮箱设置
read -p "请输入联系邮箱 (用于证书申请): " MY_EMAIL
MY_EMAIL=${MY_EMAIL:-"admin@$MY_DOMAIN"}

echo -e "${GREEN}配置已就绪，准备开始安装...${NC}"
sleep 2

# --- 安装逻辑 ---

prepare_env() {
    echo -e "${YELLOW}正在安装依赖 (Nginx, ACME, Sing-Box)...${NC}"
    apt update && apt install -y socat curl wget nginx uuid-runtime openssl
    systemctl stop nginx
}

install_acme() {
    if [ ! -f "$HOME/.acme.sh/acme.sh" ]; then
        curl https://get.acme.sh | sh -s email=$MY_EMAIL
    fi
    source ~/.bashrc
    ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    
    echo -e "${YELLOW}正在申请证书，请确保 80 端口未被占用且解析已生效...${NC}"
    ~/.acme.sh/acme.sh --issue -d $MY_DOMAIN --standalone
    ~/.acme.sh/acme.sh --install-cert -d $MY_DOMAIN \
        --fullchain-file $CERT_DIR/server.crt \
        --key-file $CERT_DIR/server.key
}

setup_nginx() {
    # 简单的伪装页
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
    # 安装最新的 sing-box
    bash <(curl -Ls https://sing-box.app/install.sh)

    cat <<EOF > $WORKDIR/config.json
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": $MY_PORT,
      "users": [{ "uuid": "$MY_UUID", "flow": "xtls-rprx-vision" }],
      "tls": {
        "enabled": true,
        "server_name": "$MY_DOMAIN",
        "certificate_path": "$CERT_DIR/server.crt",
        "key_path": "$CERT_DIR/server.key",
        "min_version": "1.3"
      }
    }
  ],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF
    systemctl enable sing-box && systemctl restart sing-box
}

# --- 执行与输出 ---
prepare_env
install_acme
setup_nginx
setup_singbox

# 生成客户端链接
LINK="vless://$MY_UUID@$MY_DOMAIN:$MY_PORT?encryption=none&flow=xtls-rprx-vision&security=tls&sni=$MY_DOMAIN&type=tcp#MyCustomServer"

echo -e "\n${GREEN}==============================================${NC}"
echo -e "${GREEN}🎉 部署成功！${NC}"
echo -e "域名: ${YELLOW}$MY_DOMAIN${NC}"
echo -e "端口: ${YELLOW}$MY_PORT${NC}"
echo -e "UUID: ${YELLOW}$MY_UUID${NC}"
echo -e "\n${GREEN}客户端 VLESS 链接:${NC}"
echo -e "${RED}$LINK${NC}"
echo -e "${GREEN}==============================================${NC}"

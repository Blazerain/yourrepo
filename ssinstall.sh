#!/bin/bash

# 一键安装多网卡Shadowsocks服务器脚本
# 使用方法: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/ssinstall.sh | bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误: 必须使用root用户运行此脚本${NC}" >&2
        exit 1
    fi
}

# 安装必要依赖
install_dependencies() {
    echo -e "${YELLOW}[1/5] 安装依赖包...${NC}"
    apt-get update > /dev/null 2>&1
    apt-get install -y curl wget unzip > /dev/null 2>&1
}

# 安装V2Ray
install_v2ray() {
    echo -e "${YELLOW}[2/5] 安装V2Ray...${NC}"
    bash <(curl -L -s https://install.direct/go.sh) > /dev/null 2>&1
    systemctl enable v2ray > /dev/null 2>&1
}

# 配置Shadowsocks多网卡
configure_ss() {
    echo -e "${YELLOW}[3/5] 配置Shadowsocks...${NC}"
    
    # 获取所有非lo网卡的IP
    IPS=($(ip -br addr show | grep -v "127.0.0.1" | awk '{print $3}' | cut -d'/' -f1))
    
    # 生成配置文件
    CONFIG='{
  "inbounds": ['
    
    PORT=11000
    for IP in "${IPS[@]}"; do
        CONFIG+='
    {
      "listen": "'$IP'",
      "port": '$PORT',
      "protocol": "shadowsocks",
      "settings": {
        "method": "aes-128-gcm",
        "password": "qwe123",
        "network": "tcp,udp",
        "level": 0
      }
    },'
        PORT=$((PORT+1000))
    done
    
    # 移除最后一个逗号
    CONFIG=${CONFIG%,}
    
    CONFIG+='
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}'
    
    echo "$CONFIG" > /etc/v2ray/config.json
}

# 开放防火墙端口
configure_firewall() {
    echo -e "${YELLOW}[4/5] 配置防火墙...${NC}"
    if command -v ufw > /dev/null 2>&1; then
        ufw --force enable > /dev/null 2>&1
        PORT=11000
        for IP in "${IPS[@]}"; do
            ufw allow $PORT/tcp > /dev/null 2>&1
            ufw allow $PORT/udp > /dev/null 2>&1
            PORT=$((PORT+1000))
        done
    else
        echo -e "${YELLOW}警告: 未发现ufw，请手动配置防火墙规则${NC}"
    fi
}

# 重启服务
restart_service() {
    echo -e "${YELLOW}[5/5] 重启服务...${NC}"
    systemctl restart v2ray > /dev/null 2>&1
    
    # 显示配置信息
    echo -e "\n${GREEN}Shadowsocks服务器安装成功!${NC}"
    echo -e "${GREEN}=========================${NC}"
    echo -e "${GREEN}协议: Shadowsocks${NC}"
    echo -e "${GREEN}加密方式: aes-128-gcm${NC}"
    echo -e "${GREEN}密码: qwe123${NC}"
    
    PORT=11000
    for IP in "${IPS[@]}"; do
        echo -e "${GREEN}IP: ${IP} 端口: ${PORT}${NC}"
        PORT=$((PORT+1000))
    done
    
    echo -e "${GREEN}=========================${NC}"
    echo -e "${YELLOW}注意: 请确保云服务商安全组已开放对应端口${NC}"
}

# 主流程
main() {
    check_root
    install_dependencies
    install_v2ray
    configure_ss
    configure_firewall
    restart_service
}

main

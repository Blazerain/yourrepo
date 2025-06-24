#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用root权限运行此脚本"
        exit 1
    fi
}

install_packages() {
    log_info "安装必要软件包..."
    if command -v yum &> /dev/null; then
        yum install -y curl wget net-tools
    elif command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y curl wget net-tools
    fi
}

install_v2ray() {
    log_info "安装V2Ray..."
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
    if [ $? -ne 0 ]; then
        log_error "V2Ray安装失败"
        exit 1
    fi
    log_success "V2Ray安装完成"
}

get_ips() {
    log_info "获取网卡IP地址..."
    IPS=()
    
    # 方法1: 使用ip命令
    while read -r line; do
        if [[ -n "$line" ]]; then
            IPS+=("$line")
        fi
    done < <(ip addr show | grep -oP 'inet \K172\.17\.18\.\d+' | sort -u)
    
    # 方法2: 如果方法1失败，手动添加已知IP
    if [ ${#IPS[@]} -eq 0 ]; then
        log_info "自动检测失败，使用默认IP..."
        IPS=("172.17.18.14" "172.17.18.15" "172.17.18.16")
    fi
    
    log_info "检测到IP地址:"
    for ip in "${IPS[@]}"; do
        echo "  - $ip"
    done
}

create_config() {
    log_info "创建V2Ray配置..."
    
    CONFIG_DIR="/usr/local/etc/v2ray"
    CONFIG_FILE="$CONFIG_DIR/config.json"
    
    mkdir -p "$CONFIG_DIR"
    
    # 备份旧配置
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
    fi
    
    # 生成配置文件
    echo '{' > "$CONFIG_FILE"
    echo '  "log": {' >> "$CONFIG_FILE"
    echo '    "loglevel": "warning"' >> "$CONFIG_FILE"
    echo '  },' >> "$CONFIG_FILE"
    echo '  "inbounds": [' >> "$CONFIG_FILE"
    
    # 添加每个IP的配置
    for i in "${!IPS[@]}"; do
        echo '    {' >> "$CONFIG_FILE"
        echo "      \"tag\": \"ss-$i\"," >> "$CONFIG_FILE"
        echo '      "port": 18889,' >> "$CONFIG_FILE"
        echo "      \"listen\": \"${IPS[$i]}\"," >> "$CONFIG_FILE"
        echo '      "protocol": "shadowsocks",' >> "$CONFIG_FILE"
        echo '      "settings": {' >> "$CONFIG_FILE"
        echo '        "method": "aes-128-gcm",' >> "$CONFIG_FILE"
        echo '        "password": "qwe123",' >> "$CONFIG_FILE"
        echo '        "network": "tcp,udp"' >> "$CONFIG_FILE"
        echo '      }' >> "$CONFIG_FILE"
        
        if [ $i -lt $((${#IPS[@]} - 1)) ]; then
            echo '    },' >> "$CONFIG_FILE"
        else
            echo '    }' >> "$CONFIG_FILE"
        fi
    done
    
    echo '  ],' >> "$CONFIG_FILE"
    echo '  "outbounds": [' >> "$CONFIG_FILE"
    echo '    {' >> "$CONFIG_FILE"
    echo '      "protocol": "freedom",' >> "$CONFIG_FILE"
    echo '      "settings": {}' >> "$CONFIG_FILE"
    echo '    }' >> "$CONFIG_FILE"
    echo '  ]' >> "$CONFIG_FILE"
    echo '}' >> "$CONFIG_FILE"
    
    log_success "配置文件创建完成"
}

setup_firewall() {
    log_info "配置防火墙..."
    
    # iptables
    if command -v iptables &> /dev/null; then
        iptables -A INPUT -p tcp --dport 18889 -j ACCEPT
        iptables -A INPUT -p udp --dport 18889 -j ACCEPT
    fi
    
    # firewalld
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port=18889/tcp
        firewall-cmd --permanent --add-port=18889/udp
        firewall-cmd --reload
    fi
    
    log_info "防火墙配置完成"
}

start_v2ray() {
    log_info "启动V2Ray服务..."
    
    CONFIG_FILE="/usr/local/etc/v2ray/config.json"
    V2RAY_BIN="/usr/local/bin/v2ray"
    
    # 测试配置
    if ! $V2RAY_BIN test -config "$CONFIG_FILE"; then
        log_error "配置文件验证失败"
        cat "$CONFIG_FILE"
        exit 1
    fi
    
    # 停止已有服务
    systemctl stop v2ray 2>/dev/null || true
    sleep 2
    
    # 启动服务
    systemctl enable v2ray
    systemctl start v2ray
    
    sleep 3
    
    if systemctl is-active --quiet v2ray; then
        log_success "V2Ray启动成功"
    else
        log_error "V2Ray启动失败"
        systemctl status v2ray
        journalctl -u v2ray -n 10
        exit 1
    fi
}

show_info() {
    log_success "========== 部署完成 =========="
    echo "连接信息:"
    echo "端口: 18889"
    echo "密码: qwe123"
    echo "加密: aes-128-gcm"
    echo ""
    echo "服务器地址:"
    for ip in "${IPS[@]}"; do
        echo "  - $ip:18889"
    done
    echo ""
    echo "管理命令:"
    echo "  systemctl status v2ray   # 查看状态"
    echo "  systemctl restart v2ray  # 重启服务"
    echo "  journalctl -u v2ray -f   # 查看日志"
}

debug_mode() {
    echo "========== 调试信息 =========="
    echo "网卡信息:"
    ip addr show | grep inet
    echo ""
    echo "V2Ray状态:"
    systemctl status v2ray
    echo ""
    echo "端口监听:"
    netstat -tlnp | grep 18889 || echo "端口未监听"
    echo ""
    echo "配置文件:"
    cat /usr/local/etc/v2ray/config.json 2>/dev/null || echo "配置文件不存在"
}

main() {
    echo "Shadowsocks多IP部署脚本"
    echo "========================"
    
    if [ "$1" = "debug" ]; then
        debug_mode
        exit 0
    fi
    
    check_root
    install_packages
    install_v2ray
    get_ips
    create_config
    setup_firewall
    start_v2ray
    show_info
}

main "$@"

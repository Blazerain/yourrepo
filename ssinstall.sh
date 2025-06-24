#!/bin/bash

# Shadowsocks多IP一键部署脚本
# 端口: 18889
# 密码: qwe123
# 加密: aes-128-gcm

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用root权限运行此脚本"
        exit 1
    fi
}

# 更新系统
update_system() {
    print_info "更新系统包管理器..."
    if command -v apt-get &> /dev/null; then
        apt-get update -y
        apt-get install -y wget curl unzip
    elif command -v yum &> /dev/null; then
        yum update -y
        yum install -y wget curl unzip
    else
        print_error "不支持的操作系统"
        exit 1
    fi
}

# 安装V2Ray
install_v2ray() {
    print_info "下载并安装V2Ray..."
    
    # 下载安装脚本
    wget -O go.sh https://install.direct/go.sh
    
    if [ ! -f "go.sh" ]; then
        print_error "下载V2Ray安装脚本失败"
        exit 1
    fi
    
    # 执行安装
    bash go.sh
    
    # 清理安装脚本
    rm -f go.sh
    
    print_success "V2Ray安装完成"
}

# 获取网卡IP地址
get_network_ips() {
    print_info "检测网卡IP地址..."
    
    # 获取所有非回环地址
    IPS=($(ip -br addr show | grep -v "127.0.0.1" | awk '{print $3}' | cut -d'/' -f1 | grep -v '^$'))
    
    if [ ${#IPS[@]} -eq 0 ]; then
        print_error "未检测到可用的IP地址"
        exit 1
    fi
    
    print_info "检测到以下IP地址:"
    for ip in "${IPS[@]}"; do
        echo "  - $ip"
    done
}

# 创建V2Ray配置文件
create_config() {
    print_info "创建V2Ray配置文件..."
    
    # 备份原配置
    if [ -f "/etc/v2ray/config.json" ]; then
        cp /etc/v2ray/config.json /etc/v2ray/config.json.backup.$(date +%s)
        print_info "原配置文件已备份"
    fi
    
    # 创建新配置
    cat > /etc/v2ray/config.json << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
EOF

    # 为每个IP创建入站配置
    for i in "${!IPS[@]}"; do
        cat >> /etc/v2ray/config.json << EOF
    {
      "tag": "ss-${i}",
      "port": 18889,
      "listen": "${IPS[$i]}",
      "protocol": "shadowsocks",
      "settings": {
        "method": "aes-128-gcm",
        "password": "qwe123",
        "network": "tcp,udp"
      }
    }$([ $i -lt $((${#IPS[@]} - 1)) ] && echo "," || echo "")
EOF
    done

    cat >> /etc/v2ray/config.json << EOF
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

    print_success "配置文件创建完成"
}

# 配置防火墙
setup_firewall() {
    print_info "配置防火墙..."
    
    # 检查并配置ufw
    if command -v ufw &> /dev/null; then
        ufw allow 18889/tcp
        ufw allow 18889/udp
        print_info "ufw防火墙规则已添加"
    fi
    
    # 检查并配置iptables
    if command -v iptables &> /dev/null; then
        iptables -A INPUT -p tcp --dport 18889 -j ACCEPT
        iptables -A INPUT -p udp --dport 18889 -j ACCEPT
        
        # 尝试保存iptables规则
        if command -v iptables-save &> /dev/null; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
        print_info "iptables防火墙规则已添加"
    fi
    
    # 检查并配置firewalld
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=18889/tcp
        firewall-cmd --permanent --add-port=18889/udp
        firewall-cmd --reload
        print_info "firewalld防火墙规则已添加"
    fi
}

# 启动服务
start_service() {
    print_info "启动V2Ray服务..."
    
    # 验证配置文件
    if ! /usr/bin/v2ray/v2ray -test -config /etc/v2ray/config.json; then
        print_error "配置文件验证失败"
        exit 1
    fi
    
    # 启动并设置开机自启
    systemctl enable v2ray
    systemctl start v2ray
    
    # 检查服务状态
    sleep 2
    if systemctl is-active --quiet v2ray; then
        print_success "V2Ray服务启动成功"
    else
        print_error "V2Ray服务启动失败"
        print_info "查看日志: journalctl -u v2ray -f"
        exit 1
    fi
}

# 显示连接信息
show_connection_info() {
    print_success "========== Shadowsocks部署完成 =========="
    echo
    print_info "连接信息:"
    echo "端口: 18889"
    echo "密码: qwe123"
    echo "加密方式: aes-128-gcm"
    echo
    print_info "可用的服务器地址:"
    for ip in "${IPS[@]}"; do
        echo "  - ${ip}:18889"
    done
    echo
    print_info "客户端配置示例:"
    echo "服务器: ${IPS[0]}"
    echo "端口: 18889"
    echo "密码: qwe123"
    echo "加密: aes-128-gcm"
    echo
    print_warning "请确保防火墙开放了18889端口"
    print_info "查看服务状态: systemctl status v2ray"
    print_info "查看服务日志: journalctl -u v2ray -f"
    print_info "重启服务: systemctl restart v2ray"
}

# 主函数
main() {
    echo "========================================="
    echo "    Shadowsocks多IP一键部署脚本"
    echo "========================================="
    
    check_root
    update_system
    install_v2ray
    get_network_ips
    create_config
    setup_firewall
    start_service
    show_connection_info
}

# 执行主函数
main "$@"

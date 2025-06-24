#!/bin/bash

# Shadowsocks 自动安装配置脚本
# 端口: 18889, 密码: qwe123, 加密: aes-256-gcm     curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/ssinstall.sh | bash 

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 获取xray监听的内网IP
get_xray_internal_ip() {
    log_info "检测xray进程监听的内网IP..."
    
    # 使用netstat获取xray监听的IP和端口
    xray_listen=$(netstat -tlnp 2>/dev/null | grep xray | head -1)
    
    if [[ -z "$xray_listen" ]]; then
        log_warn "未找到xray进程，尝试获取主要网络接口IP"
        # 获取默认路由的网络接口IP
        internal_ip=$(ip route get 8.8.8.8 | awk '{print $7; exit}')
    else
        # 从netstat输出中提取IP
        internal_ip=$(echo "$xray_listen" | awk '{print $4}' | cut -d':' -f1)
        
        # 如果是0.0.0.0或者::，则获取主接口IP
        if [[ "$internal_ip" == "0.0.0.0" || "$internal_ip" == "::" || -z "$internal_ip" ]]; then
            internal_ip=$(ip route get 8.8.8.8 | awk '{print $7; exit}')
        fi
    fi
    
    log_info "检测到内网IP: $internal_ip"
    echo "$internal_ip"
}

# 获取对应的公网IP
get_public_ip() {
    local internal_ip=$1
    log_info "获取对应的公网IP..."
    
    # 方法1: 通过接口获取公网IP
    local public_ip=""
    
    # 尝试多个服务获取公网IP
    for service in "curl -s ifconfig.me" "curl -s ipinfo.io/ip" "curl -s icanhazip.com" "curl -s ident.me"; do
        public_ip=$(eval $service 2>/dev/null | tr -d '\n\r')
        if [[ -n "$public_ip" && "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            break
        fi
    done
    
    if [[ -z "$public_ip" ]]; then
        log_warn "无法自动获取公网IP，请手动输入"
        read -p "请输入服务器的公网IP: " public_ip
    fi
    
    log_info "检测到公网IP: $public_ip"
    echo "$public_ip"
}

# 检查系统类型
detect_system() {
    if [[ -f /etc/redhat-release ]]; then
        echo "centos"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# 安装依赖
install_dependencies() {
    local system_type=$(detect_system)
    log_info "安装系统依赖..."
    
    case $system_type in
        "centos")
            yum update -y
            yum install -y epel-release
            yum install -y python3 python3-pip curl wget unzip
            ;;
        "debian")
            apt update -y
            apt install -y python3 python3-pip curl wget unzip
            ;;
        *)
            log_error "不支持的系统类型"
            exit 1
            ;;
    esac
}

# 安装shadowsocks
install_shadowsocks() {
    log_info "安装shadowsocks-libev..."
    
    local system_type=$(detect_system)
    
    case $system_type in
        "centos")
            yum install -y shadowsocks-libev || {
                # 如果包管理器没有，则编译安装
                install_shadowsocks_from_source
            }
            ;;
        "debian")
            apt install -y shadowsocks-libev || {
                # 如果包管理器没有，则编译安装
                install_shadowsocks_from_source
            }
            ;;
    esac
}

# 从源码安装shadowsocks
install_shadowsocks_from_source() {
    log_info "从源码编译安装shadowsocks-libev..."
    
    # 安装编译依赖
    local system_type=$(detect_system)
    case $system_type in
        "centos")
            yum groupinstall -y "Development Tools"
            yum install -y autoconf automake libtool pcre-devel libev-devel c-ares-devel
            ;;
        "debian")
            apt install -y build-essential autoconf automake libtool libpcre3-dev libev-dev libc-ares-dev
            ;;
    esac
    
    # 下载和编译
    cd /tmp
    wget https://github.com/shadowsocks/shadowsocks-libev/archive/v3.3.5.tar.gz
    tar -xzf v3.3.5.tar.gz
    cd shadowsocks-libev-3.3.5
    ./configure --prefix=/usr/local
    make && make install
    
    # 创建符号链接
    ln -sf /usr/local/bin/ss-server /usr/bin/ss-server
}

# 创建shadowsocks配置文件
create_shadowsocks_config() {
    local internal_ip=$1
    local public_ip=$2
    
    log_info "创建shadowsocks配置文件..."
    
    # 创建配置目录
    mkdir -p /etc/shadowsocks
    
    # 创建配置文件
    cat > /etc/shadowsocks/config.json << EOF
{
    "server": "$internal_ip",
    "server_port": 18889,
    "password": "qwe123",
    "method": "aes-256-gcm",
    "timeout": 300,
    "fast_open": false,
    "workers": 2
}
EOF
    
    log_info "配置文件已创建: /etc/shadowsocks/config.json"
    
    # 显示配置信息
    echo -e "\n${BLUE}=== Shadowsocks 配置信息 ===${NC}"
    echo -e "服务器地址: ${GREEN}$public_ip${NC}"
    echo -e "服务端口: ${GREEN}18889${NC}"
    echo -e "密码: ${GREEN}qwe123${NC}"
    echo -e "加密方式: ${GREEN}aes-256-gcm${NC}"
    echo -e "内网监听: ${GREEN}$internal_ip:18889${NC}"
}

# 创建systemd服务文件
create_systemd_service() {
    log_info "创建systemd服务文件..."
    
    cat > /etc/systemd/system/shadowsocks.service << EOF
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/ss-server -c /etc/shadowsocks/config.json
Restart=on-failure
RestartSec=5
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=shadowsocks

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable shadowsocks
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙规则..."
    
    # 检查防火墙类型并开放端口
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 18889/tcp
        ufw allow 18889/udp
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=18889/tcp
        firewall-cmd --permanent --add-port=18889/udp
        firewall-cmd --reload
    elif command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport 18889 -j ACCEPT
        iptables -I INPUT -p udp --dport 18889 -j ACCEPT
        # 保存iptables规则
        if [[ -f /etc/redhat-release ]]; then
            service iptables save
        else
            iptables-save > /etc/iptables/rules.v4
        fi
    fi
    
    log_info "防火墙规则已配置"
}

# 启动shadowsocks服务
start_shadowsocks() {
    log_info "启动shadowsocks服务..."
    
    systemctl start shadowsocks
    systemctl status shadowsocks --no-pager
    
    if systemctl is-active --quiet shadowsocks; then
        log_info "shadowsocks服务启动成功!"
    else
        log_error "shadowsocks服务启动失败!"
        journalctl -u shadowsocks --no-pager -n 20
        exit 1
    fi
}

# 显示连接信息
show_connection_info() {
    local public_ip=$1
    
    echo -e "\n${GREEN}=== 安装完成 ===${NC}"
    echo -e "\n${BLUE}客户端连接信息:${NC}"
    echo -e "服务器: ${GREEN}$public_ip${NC}"
    echo -e "端口: ${GREEN}18889${NC}"
    echo -e "密码: ${GREEN}qwe123${NC}"
    echo -e "加密: ${GREEN}aes-256-gcm${NC}"
    
    echo -e "\n${BLUE}管理命令:${NC}"
    echo -e "启动服务: ${YELLOW}systemctl start shadowsocks${NC}"
    echo -e "停止服务: ${YELLOW}systemctl stop shadowsocks${NC}"
    echo -e "重启服务: ${YELLOW}systemctl restart shadowsocks${NC}"
    echo -e "查看状态: ${YELLOW}systemctl status shadowsocks${NC}"
    echo -e "查看日志: ${YELLOW}journalctl -u shadowsocks -f${NC}"
    
    echo -e "\n${BLUE}配置文件位置:${NC}"
    echo -e "${YELLOW}/etc/shadowsocks/config.json${NC}"
}

# 主函数
main() {
    log_info "开始安装配置shadowsocks..."
    
    # 检查root权限
    check_root
    
    # 获取IP信息
    internal_ip=$(get_xray_internal_ip)
    public_ip=$(get_public_ip "$internal_ip")
    
    # 安装依赖和shadowsocks
    install_dependencies
    install_shadowsocks
    
    # 创建配置和服务
    create_shadowsocks_config "$internal_ip" "$public_ip"
    create_systemd_service
    
    # 配置防火墙并启动服务
    configure_firewall
    start_shadowsocks
    
    # 显示连接信息
    show_connection_info "$public_ip"
    
    log_info "shadowsocks安装配置完成!"
}

# 运行主函数
main "$@"

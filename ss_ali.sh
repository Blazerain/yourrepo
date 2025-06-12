#!/bin/bash

# 多公网IP SSR一键配置脚本
# 用途：游戏加速器
# curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/ss_ali.sh| bash

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
        log_error "请使用root权限运行此脚本"
        exit 1
    fi
}

# 获取所有公网IP
get_public_ips() {
    log_info "正在检测公网IP地址..."
    
    declare -a public_ips=()
    
    # 方法1: 通过网络接口获取IP
    for interface in $(ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print $2}' | grep -E '^eth[0-9]+$'); do
        ip_addr=$(ip addr show $interface | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -1)
        if [[ -n "$ip_addr" && "$ip_addr" != "127.0.0.1" ]]; then
            # 检查是否为公网IP
            if is_public_ip "$ip_addr"; then
                public_ips+=("$ip_addr")
                log_info "接口 $interface: $ip_addr (公网IP)"
            else
                log_warn "接口 $interface: $ip_addr (私网IP)"
            fi
        fi
    done
    
    # 方法2: 通过外部服务获取公网IP（备用）
    if [[ ${#public_ips[@]} -eq 0 ]]; then
        log_warn "未通过接口检测到公网IP，尝试外部查询..."
        external_ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null || echo "")
        if [[ -n "$external_ip" ]]; then
            public_ips+=("$external_ip")
            log_info "外部查询到公网IP: $external_ip"
        fi
    fi
    
    # 输出结果
    if [[ ${#public_ips[@]} -eq 0 ]]; then
        log_error "未找到任何公网IP地址"
        exit 1
    fi
    
    log_info "共找到 ${#public_ips[@]} 个公网IP:"
    for i in "${!public_ips[@]}"; do
        echo "  IP$((i+1)): ${public_ips[i]}"
    done
    
    echo "${public_ips[@]}"
}

# 判断是否为公网IP
is_public_ip() {
    local ip=$1
    # 私网地址范围
    if [[ $ip =~ ^10\. ]] || \
       [[ $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
       [[ $ip =~ ^192\.168\. ]] || \
       [[ $ip =~ ^127\. ]] || \
       [[ $ip =~ ^169\.254\. ]]; then
        return 1  # 私网IP
    else
        return 0  # 公网IP
    fi
}

# 安装依赖
install_dependencies() {
    log_info "安装必要依赖..."
    
    # 检测系统类型
    if command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL
        yum update -y
        yum install -y wget curl git python3 python3-pip
    elif command -v apt >/dev/null 2>&1; then
        # Ubuntu/Debian
        apt update
        apt install -y wget curl git python3 python3-pip
    else
        log_error "不支持的系统类型"
        exit 1
    fi
    
    # 安装shadowsocksr
    if [[ ! -d "/usr/local/shadowsocksr" ]]; then
        log_info "下载ShadowsocksR..."
        cd /usr/local
        git clone -b manyuser https://github.com/shadowsocksrr/shadowsocksr.git
        cd shadowsocksr
        chmod +x *.sh
    fi
}

# 生成随机密码
generate_password() {
    openssl rand -base64 16 | tr -d "=+/" | cut -c1-16
}

# 生成SSR配置
generate_ssr_config() {
    local ip=$1
    local port=$2
    local password=$3
    
    cat > "/usr/local/shadowsocksr/user-config-${port}.json" << EOF
{
    "server": "${ip}",
    "server_ipv6": "::",
    "server_port": ${port},
    "local_address": "127.0.0.1",
    "local_port": 1080,
    
    "password": "${password}",
    "method": "aes-256-gcm",
    "protocol": "origin",
    "protocol_param": "",
    "obfs": "plain",
    "obfs_param": "",
    
    "connect_verbose_info": 0,
    "redirect": "",
    "dns_ipv6": false,
    "fast_open": false,
    "workers": 1
}
EOF
}

# 配置防火墙
configure_firewall() {
    local port=$1
    
    # 检查防火墙类型并配置
    if command -v firewall-cmd >/dev/null 2>&1; then
        # firewalld (CentOS 7+)
        firewall-cmd --permanent --add-port=${port}/tcp
        firewall-cmd --permanent --add-port=${port}/udp
        firewall-cmd --reload
    elif command -v ufw >/dev/null 2>&1; then
        # ufw (Ubuntu)
        ufw allow ${port}/tcp
        ufw allow ${port}/udp
    elif command -v iptables >/dev/null 2>&1; then
        # iptables
        iptables -I INPUT -p tcp --dport ${port} -j ACCEPT
        iptables -I INPUT -p udp --dport ${port} -j ACCEPT
        # 保存iptables规则
        if command -v service >/dev/null 2>&1; then
            service iptables save 2>/dev/null || true
        fi
    fi
}

# 创建systemd服务
create_systemd_service() {
    local port=$1
    
    cat > "/etc/systemd/system/ssr-${port}.service" << EOF
[Unit]
Description=ShadowsocksR Server on port ${port}
After=network.target

[Service]
Type=forking
PIDFile=/var/run/shadowsocksr-${port}.pid
ExecStart=/usr/bin/python3 /usr/local/shadowsocksr/shadowsocks/server.py -c /usr/local/shadowsocksr/user-config-${port}.json -d start --pid-file=/var/run/shadowsocksr-${port}.pid
ExecStop=/usr/bin/python3 /usr/local/shadowsocksr/shadowsocks/server.py -c /usr/local/shadowsocksr/user-config-${port}.json -d stop --pid-file=/var/run/shadowsocksr-${port}.pid
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ssr-${port}.service
    systemctl start ssr-${port}.service
}

# 主配置函数
configure_ssr() {
    local ips=("$@")
    local base_port=8388
    
    log_info "开始配置SSR服务..."
    
    # 存储配置信息
    config_file="/root/ssr_configs.txt"
    echo "=== SSR游戏加速器配置信息 ===" > "$config_file"
    echo "生成时间: $(date)" >> "$config_file"
    echo "" >> "$config_file"
    
    for i in "${!ips[@]}"; do
        local ip="${ips[i]}"
        local port=$((base_port + i))
        local password=$(generate_password)
        
        log_info "配置IP ${ip} 端口 ${port}..."
        
        # 生成配置文件
        generate_ssr_config "$ip" "$port" "$password"
        
        # 配置防火墙
        configure_firewall "$port"
        
        # 创建并启动服务
        create_systemd_service "$port"
        
        # 保存配置信息
        echo "--- 配置 $((i+1)) ---" >> "$config_file"
        echo "服务器地址: ${ip}" >> "$config_file"
        echo "端口: ${port}" >> "$config_file"
        echo "密码: ${password}" >> "$config_file"
        echo "加密方式: aes-256-gcm" >> "$config_file"
        echo "协议: origin" >> "$config_file"
        echo "混淆: plain" >> "$config_file"
        echo "" >> "$config_file"
        
        # 生成URL
        local ssr_url=$(echo -n "${ip}:${port}:origin:aes-256-gcm:plain:${password}" | base64 -w 0)
        echo "SSR链接: ssr://${ssr_url}" >> "$config_file"
        echo "" >> "$config_file"
        
        sleep 2
    done
    
    log_info "所有SSR服务配置完成！"
    log_info "配置信息已保存到: $config_file"
}

# 显示服务状态
show_status() {
    log_info "检查SSR服务状态..."
    
    for service in $(systemctl list-units --type=service | grep ssr- | awk '{print $1}'); do
        status=$(systemctl is-active $service)
        if [[ "$status" == "active" ]]; then
            log_info "$service: ${GREEN}运行中${NC}"
        else
            log_error "$service: ${RED}已停止${NC}"
        fi
    done
}

# 主函数
main() {
    echo "=== 多公网IP SSR游戏加速器配置脚本 ==="
    echo ""
    
    # 检查权限
    check_root
    
    # 获取公网IP
    ips_array=($(get_public_ips))
    
    if [[ ${#ips_array[@]} -eq 0 ]]; then
        log_error "未找到可用的公网IP"
        exit 1
    fi
    
    # 安装依赖
    install_dependencies
    
    # 配置SSR
    configure_ssr "${ips_array[@]}"
    
    # 显示状态
    show_status
    
    echo ""
    log_info "配置完成！请查看 /root/ssr_configs.txt 获取连接信息"
    log_info "管理命令:"
    echo "  查看所有服务状态: systemctl status ssr-*"
    echo "  重启服务: systemctl restart ssr-端口号"
    echo "  查看日志: journalctl -u ssr-端口号 -f"
}

# 运行主函数
main "$@"

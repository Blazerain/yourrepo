#!/bin/bash

# 多网卡shadowsocks配置脚本
# 支持多个网卡同时提供shadowsocks服务  curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/ssinstall.sh | bash 

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# 获取所有网卡的内网IP
get_all_internal_ips() {
    log_info "检测所有网卡的内网IP..."
    
    # 获取所有网卡的IP地址（排除lo和docker等虚拟接口）
    local ips=()
    
    # 方法1: 使用ip命令
    if command -v ip >/dev/null 2>&1; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                ips+=("$line")
            fi
        done < <(ip addr show | grep -E "inet [0-9]" | grep -v "127.0.0.1" | grep -v "docker\|lo\|br-" | awk '{print $2}' | cut -d'/' -f1)
    else
        # 方法2: 使用ifconfig命令
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                ips+=("$line")
            fi
        done < <(ifconfig | grep -E "inet [0-9]" | grep -v "127.0.0.1" | awk '{print $2}' | cut -d':' -f2)
    fi
    
    if [[ ${#ips[@]} -eq 0 ]]; then
        log_error "未找到任何内网IP地址"
        exit 1
    fi
    
    log_info "发现 ${#ips[@]} 个内网IP:"
    for i in "${!ips[@]}"; do
        echo -e "  $((i+1)). ${ips[i]}"
    done
    
    echo "${ips[@]}"
}

# 获取IP对应的公网IP
get_public_ip_for_internal() {
    local internal_ip=$1
    log_info "获取 $internal_ip 对应的公网IP..."
    
    # 尝试通过绑定特定IP获取对应的公网IP
    local public_ip=""
    
    # 方法1: 尝试绑定内网IP访问外部服务
    for service in "ifconfig.me" "ipinfo.io/ip" "icanhazip.com" "ident.me"; do
        public_ip=$(curl -s --connect-timeout 10 --bind-address "$internal_ip" "$service" 2>/dev/null | tr -d '\n\r' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        if [[ -n "$public_ip" ]]; then
            log_info "$internal_ip 对应的公网IP: $public_ip"
            echo "$public_ip"
            return
        fi
    done
    
    # 方法2: 如果绑定失败，手动输入
    log_warn "无法自动获取 $internal_ip 对应的公网IP"
    read -p "请输入 $internal_ip 对应的公网IP: " public_ip
    echo "$public_ip"
}

# 创建多IP shadowsocks配置
create_multi_ip_config() {
    local internal_ips=($1)
    
    log_info "创建多IP shadowsocks配置..."
    
    # 备份原配置
    if [[ -f /etc/shadowsocks/config.json ]]; then
        cp /etc/shadowsocks/config.json /etc/shadowsocks/config.json.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # 创建配置目录
    mkdir -p /etc/shadowsocks
    
    # 固定端口和密码配置
    local ports=(11000 12000 13000)
    local password="qwe123"
    local port_password_config=""
    local connection_info=""
    
    echo -e "\n${BLUE}=== 多网卡Shadowsocks配置信息 ===${NC}"
    
    for i in "${!internal_ips[@]}"; do
        local ip="${internal_ips[i]}"
        local public_ip=$(get_public_ip_for_internal "$ip")
        local current_port="${ports[i]}"
        
        if [[ -n "$port_password_config" ]]; then
            port_password_config+=","
        fi
        port_password_config+="\n         \"$current_port\":\"$password\""
        
        echo -e "\n${GREEN}网卡 $ip:${NC}"
        echo -e "  内网IP: ${YELLOW}$ip${NC}"
        echo -e "  公网IP: ${YELLOW}$public_ip${NC}"
        echo -e "  端口: ${YELLOW}$current_port${NC}"
        echo -e "  密码: ${YELLOW}$password${NC}"
        
        # 记录连接信息
        connection_info+="\n网卡$ip -> 公网$public_ip:$current_port (密码: $password)"
    done
    
    # 创建配置文件 - 监听所有IP
    cat > /etc/shadowsocks/config.json << EOF
{
    "server":"0.0.0.0",
    "port_password":{$port_password_config
    },
    "method":"aes-256-cfb",
    "timeout":600
}
EOF
    
    log_info "多IP配置文件已创建: /etc/shadowsocks/config.json"
    
    # 保存连接信息到文件
    echo -e "$connection_info" > /etc/shadowsocks/connection_info.txt
    
    echo -e "\n${BLUE}配置已完成，连接信息已保存到: ${NC}/etc/shadowsocks/connection_info.txt"
}

# 创建多实例配置（每个IP一个实例）
create_multi_instance_config() {
    local internal_ips=($1)
    
    log_info "创建多实例shadowsocks配置..."
    
    # 创建配置目录
    mkdir -p /etc/shadowsocks/instances
    
    # 固定端口和密码配置
    local ports=(11000 12000 13000)
    local password="qwe123"
    local connection_info=""
    
    echo -e "\n${BLUE}=== 多实例Shadowsocks配置信息 ===${NC}"
    
    for i in "${!internal_ips[@]}"; do
        local ip="${internal_ips[i]}"
        local public_ip=$(get_public_ip_for_internal "$ip")
        local current_port="${ports[i]}"
        local instance_name="shadowsocks-nic$i"
        
        # 创建单个实例配置文件
        cat > "/etc/shadowsocks/instances/config-nic$i.json" << EOF
{
    "server":"$ip",
    "server_port":$current_port,
    "password":"$password",
    "method":"aes-256-cfb",
    "timeout":600
}
EOF
        
        # 创建systemd服务文件
        cat > "/etc/systemd/system/$instance_name.service" << EOF
[Unit]
Description=Shadowsocks Server Instance NIC$i
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/shadowsocks-server -c /etc/shadowsocks/instances/config-nic$i.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        echo -e "\n${GREEN}实例 $i (网卡 $ip):${NC}"
        echo -e "  内网IP: ${YELLOW}$ip${NC}"
        echo -e "  公网IP: ${YELLOW}$public_ip${NC}"
        echo -e "  端口: ${YELLOW}$current_port${NC}"
        echo -e "  密码: ${YELLOW}$password${NC}"
        echo -e "  服务名: ${YELLOW}$instance_name${NC}"
        
        # 记录连接信息
        connection_info+="\n实例$i: $public_ip:$current_port (密码: $password) [服务: $instance_name]"
        
        # 启用服务
        systemctl daemon-reload
        systemctl enable "$instance_name"
    done
    
    # 保存连接信息
    echo -e "$connection_info" > /etc/shadowsocks/instances_info.txt
    
    log_info "多实例配置完成，信息保存到: /etc/shadowsocks/instances_info.txt"
    
    # 显示管理命令
    echo -e "\n${BLUE}多实例管理命令:${NC}"
    for i in "${!internal_ips[@]}"; do
        local instance_name="shadowsocks-nic$i"
        echo -e "实例$i: systemctl start/stop/restart/status ${YELLOW}$instance_name${NC}"
    done
}

# 配置防火墙
configure_firewall_multi_port() {
    log_info "配置防火墙规则 (端口 11000, 12000, 13000)..."
    
    local ports=(11000 12000 13000)
    
    for port in "${ports[@]}"; do
        if command -v ufw >/dev/null 2>&1; then
            ufw allow $port/tcp
            ufw allow $port/udp
        elif command -v firewall-cmd >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port=$port/tcp
            firewall-cmd --permanent --add-port=$port/udp
        elif command -v iptables >/dev/null 2>&1; then
            iptables -I INPUT -p tcp --dport $port -j ACCEPT
            iptables -I INPUT -p udp --dport $port -j ACCEPT
        fi
    done
    
    # 重载防火墙
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --reload
    elif command -v iptables >/dev/null 2>&1; then
        if [[ -f /etc/redhat-release ]]; then
            service iptables save 2>/dev/null || true
        else
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
    fi
}

# 重启shadowsocks服务
restart_shadowsocks() {
    log_info "重启shadowsocks服务..."
    
    # 停止服务
    /etc/init.d/shadowsocks stop 2>/dev/null || true
    sleep 2
    
    # 启动服务
    /etc/init.d/shadowsocks start
    
    # 检查状态
    sleep 3
    /etc/init.d/shadowsocks status
}

# 显示最终信息
show_final_info() {
    local config_type=$1
    
    echo -e "\n${GREEN}=== 多网卡Shadowsocks配置完成 ===${NC}"
    echo -e "\n${BLUE}固定端口:${NC} 11000, 12000, 13000"
    echo -e "${BLUE}统一密码:${NC} qwe123"
    echo -e "${BLUE}加密方式:${NC} aes-256-cfb"
    echo -e "${BLUE}配置类型:${NC} $config_type"
    
    if [[ "$config_type" == "多端口单实例" ]]; then
        echo -e "${BLUE}连接信息:${NC} /etc/shadowsocks/connection_info.txt"
        echo -e "${BLUE}配置文件:${NC} /etc/shadowsocks/config.json"
        echo -e "\n${BLUE}管理命令:${NC}"
        echo -e "启动: ${YELLOW}/etc/init.d/shadowsocks start${NC}"
        echo -e "停止: ${YELLOW}/etc/init.d/shadowsocks stop${NC}"
        echo -e "重启: ${YELLOW}/etc/init.d/shadowsocks restart${NC}"
        echo -e "状态: ${YELLOW}/etc/init.d/shadowsocks status${NC}"
    else
        echo -e "${BLUE}连接信息:${NC} /etc/shadowsocks/instances_info.txt"
        echo -e "${BLUE}配置目录:${NC} /etc/shadowsocks/instances/"
        echo -e "\n${BLUE}管理命令:${NC} 见上方实例管理命令"
    fi
    
    echo -e "\n${BLUE}查看连接信息:${NC}"
    if [[ "$config_type" == "多端口单实例" ]]; then
        cat /etc/shadowsocks/connection_info.txt
    else
        cat /etc/shadowsocks/instances_info.txt
    fi
}

# 主函数
main() {
    echo -e "${BLUE}多网卡Shadowsocks配置脚本${NC}"
    echo -e "支持为每个网卡配置独立的shadowsocks服务\n"
    
    # 检查权限
    check_root
    
    # 检查shadowsocks是否已安装
    if [[ ! -f /etc/init.d/shadowsocks ]]; then
        log_error "请先安装shadowsocks-go！"
        echo "安装命令："
        echo "wget --no-check-certificate https://raw.githubusercontent.com/teddysun/shadowsocks_install/master/shadowsocks-go.sh"
        echo "chmod +x shadowsocks-go.sh"
        echo "./shadowsocks-go.sh"
        exit 1
    fi
    
    # 获取所有内网IP
    local internal_ips_str=$(get_all_internal_ips)
    local internal_ips=($internal_ips_str)
    local ip_count=${#internal_ips[@]}
    
    # 选择配置模式
    echo -e "\n${BLUE}请选择配置模式:${NC}"
    echo "1. 多端口单实例 (推荐，一个shadowsocks进程监听所有IP)"
    echo "2. 多实例模式 (每个网卡一个独立的shadowsocks进程)"
    read -p "请选择 [1-2]: " mode_choice
    
    echo -e "\n${BLUE}固定端口配置:${NC} 11000, 12000, 13000"
    echo -e "${BLUE}统一密码:${NC} qwe123"
    
    case $mode_choice in
        1)
            create_multi_ip_config "$internal_ips_str"
            configure_firewall_multi_port
            restart_shadowsocks
            show_final_info "多端口单实例"
            ;;
        2)
            create_multi_instance_config "$internal_ips_str"
            configure_firewall_multi_port
            
            # 启动所有实例
            for i in $(seq 0 $((ip_count-1))); do
                systemctl start "shadowsocks-nic$i"
            done
            
            show_final_info "多实例模式"
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
    
    log_info "配置完成！现在所有网卡都可以提供shadowsocks服务了。"
}

# 运行主函数
main "$@"

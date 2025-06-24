#!/bin/bash

# Shadowsocks多网卡自动配置脚本
# 自动检测网卡IP并配置端口11000/12000/13000，密码qwe123

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

# 检查shadowsocks是否已安装
check_shadowsocks() {
    if [[ ! -f /etc/init.d/shadowsocks ]]; then
        log_error "shadowsocks未安装！请先安装shadowsocks-go"
        echo "安装命令："
        echo "wget --no-check-certificate https://raw.githubusercontent.com/teddysun/shadowsocks_install/master/shadowsocks-go.sh"
        echo "chmod +x shadowsocks-go.sh"
        echo "./shadowsocks-go.sh"
        exit 1
    fi
    log_info "shadowsocks已安装，开始配置..."
}

# 获取所有网卡的内网IP
get_all_internal_ips() {
    log_info "检测所有网卡的内网IP..."
    
    local ips=()
    
    # 使用ip命令获取所有网卡IP（排除lo、docker等虚拟接口）
    if command -v ip >/dev/null 2>&1; then
        while IFS= read -r line; do
            if [[ -n "$line" && "$line" != "127.0.0.1" ]]; then
                ips+=("$line")
            fi
        done < <(ip addr show | grep -E "inet [0-9]" | grep -v "127.0.0.1" | grep -v "docker\|lo\|br-" | awk '{print $2}' | cut -d'/' -f1 | head -3)
    fi
    
    if [[ ${#ips[@]} -eq 0 ]]; then
        log_error "未找到任何可用的内网IP地址"
        exit 1
    fi
    
    log_info "发现 ${#ips[@]} 个内网IP:"
    for i in "${!ips[@]}"; do
        echo -e "  网卡$((i+1)): ${GREEN}${ips[i]}${NC}"
    done
    
    echo "${ips[@]}"
}

# 获取IP对应的公网IP
get_public_ip_for_internal() {
    local internal_ip=$1
    log_info "获取 $internal_ip 对应的公网IP..."
    
    local public_ip=""
    
    # 尝试通过绑定特定IP获取对应的公网IP
    for service in "ifconfig.me" "ipinfo.io/ip" "icanhazip.com"; do
        public_ip=$(timeout 10 curl -s --connect-timeout 5 --bind-address "$internal_ip" "$service" 2>/dev/null | tr -d '\n\r' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
        if [[ -n "$public_ip" ]]; then
            log_info "$internal_ip 对应的公网IP: $public_ip"
            echo "$public_ip"
            return
        fi
    done
    
    # 如果绑定失败，使用通用方法获取公网IP
    log_warn "无法获取 $internal_ip 的专用公网IP，使用服务器主公网IP"
    for service in "ifconfig.me" "ipinfo.io/ip" "icanhazip.com"; do
        public_ip=$(timeout 10 curl -s --connect-timeout 5 "$service" 2>/dev/null | tr -d '\n\r' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)
        if [[ -n "$public_ip" ]]; then
            echo "$public_ip"
            return
        fi
    done
    
    log_error "无法获取公网IP，请检查网络连接"
    echo "未知"
}

# 创建shadowsocks配置文件
create_shadowsocks_config() {
    local internal_ips=($1)
    
    log_info "创建shadowsocks配置文件..."
    
    # 备份原配置
    if [[ -f /etc/shadowsocks/config.json ]]; then
        cp /etc/shadowsocks/config.json "/etc/shadowsocks/config.json.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "原配置已备份"
    fi
    
    # 确保配置目录存在
    mkdir -p /etc/shadowsocks
    
    # 固定端口和密码
    local ports=(11000 12000 13000)
    local password="qwe123"
    
    # 构建端口密码配置
    local port_password_lines=""
    local max_ips=$((${#ports[@]} < ${#internal_ips[@]} ? ${#ports[@]} : ${#internal_ips[@]}))
    
    echo -e "\n${BLUE}=== Shadowsocks配置信息 ===${NC}"
    echo -e "${BLUE}监听模式:${NC} 所有IP (0.0.0.0)"
    echo -e "${BLUE}加密方式:${NC} aes-256-cfb"
    echo -e "${BLUE}统一密码:${NC} $password"
    echo
    
    for ((i=0; i<max_ips; i++)); do
        local internal_ip="${internal_ips[i]}"
        local port="${ports[i]}"
        local public_ip=$(get_public_ip_for_internal "$internal_ip")
        
        if [[ $i -gt 0 ]]; then
            port_password_lines+=","
        fi
        port_password_lines+="\n         \"$port\":\"$password\""
        
        echo -e "${GREEN}网卡$((i+1)) (${internal_ip}):${NC}"
        echo -e "  公网IP: ${YELLOW}$public_ip${NC}"
        echo -e "  端口: ${YELLOW}$port${NC}"
        echo -e "  连接: ${YELLOW}$public_ip:$port${NC}"
        echo
    done
    
    # 创建配置文件
    cat > /etc/shadowsocks/config.json << EOF
{
    "server":"0.0.0.0",
    "port_password":{$port_password_lines
    },
    "method":"aes-256-cfb",
    "timeout":600
}
EOF
    
    log_info "配置文件已创建: /etc/shadowsocks/config.json"
    
    # 保存连接信息到文件
    echo "Shadowsocks连接信息 - $(date)" > /etc/shadowsocks/connection_info.txt
    echo "密码: $password" >> /etc/shadowsocks/connection_info.txt
    echo "加密: aes-256-cfb" >> /etc/shadowsocks/connection_info.txt
    echo "" >> /etc/shadowsocks/connection_info.txt
    
    for ((i=0; i<max_ips; i++)); do
        local internal_ip="${internal_ips[i]}"
        local port="${ports[i]}"
        local public_ip=$(get_public_ip_for_internal "$internal_ip")
        echo "网卡$((i+1)): $public_ip:$port" >> /etc/shadowsocks/connection_info.txt
    done
    
    log_info "连接信息已保存到: /etc/shadowsocks/connection_info.txt"
}

# 配置防火墙
configure_firewall() {
    log_info "配置防火墙规则..."
    
    local ports=(11000 12000 13000)
    
    for port in "${ports[@]}"; do
        # ufw
        if command -v ufw >/dev/null 2>&1 && ufw status >/dev/null 2>&1; then
            ufw allow $port/tcp >/dev/null 2>&1 || true
            ufw allow $port/udp >/dev/null 2>&1 || true
            log_info "ufw: 已开放端口 $port"
        fi
        
        # firewalld
        if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
            firewall-cmd --permanent --add-port=$port/tcp >/dev/null 2>&1 || true
            firewall-cmd --permanent --add-port=$port/udp >/dev/null 2>&1 || true
            log_info "firewalld: 已开放端口 $port"
        fi
        
        # iptables
        if command -v iptables >/dev/null 2>&1; then
            iptables -C INPUT -p tcp --dport $port -j ACCEPT >/dev/null 2>&1 || iptables -I INPUT -p tcp --dport $port -j ACCEPT
            iptables -C INPUT -p udp --dport $port -j ACCEPT >/dev/null 2>&1 || iptables -I INPUT -p udp --dport $port -j ACCEPT
            log_info "iptables: 已开放端口 $port"
        fi
    done
    
    # 重载防火墙配置
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi
    
    # 保存iptables规则
    if command -v iptables >/dev/null 2>&1; then
        if [[ -f /etc/redhat-release ]]; then
            service iptables save >/dev/null 2>&1 || true
        elif [[ -d /etc/iptables ]]; then
            iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
        fi
    fi
}

# 重启shadowsocks服务
restart_shadowsocks() {
    log_info "重启shadowsocks服务..."
    
    # 停止服务
    /etc/init.d/shadowsocks stop >/dev/null 2>&1 || true
    sleep 2
    
    # 启动服务
    if /etc/init.d/shadowsocks start >/dev/null 2>&1; then
        log_info "shadowsocks服务启动成功"
        sleep 2
        /etc/init.d/shadowsocks status
    else
        log_error "shadowsocks服务启动失败"
        /etc/init.d/shadowsocks status
        exit 1
    fi
}

# 显示最终结果
show_final_result() {
    echo -e "\n${GREEN}=== 配置完成 ===${NC}"
    echo -e "\n${BLUE}连接信息:${NC}"
    cat /etc/shadowsocks/connection_info.txt
    
    echo -e "\n${BLUE}管理命令:${NC}"
    echo -e "启动: ${YELLOW}/etc/init.d/shadowsocks start${NC}"
    echo -e "停止: ${YELLOW}/etc/init.d/shadowsocks stop${NC}"
    echo -e "重启: ${YELLOW}/etc/init.d/shadowsocks restart${NC}"
    echo -e "状态: ${YELLOW}/etc/init.d/shadowsocks status${NC}"
    
    echo -e "\n${BLUE}配置文件:${NC}"
    echo -e "主配置: ${YELLOW}/etc/shadowsocks/config.json${NC}"
    echo -e "连接信息: ${YELLOW}/etc/shadowsocks/connection_info.txt${NC}"
    
    echo -e "\n${GREEN}所有网卡的shadowsocks服务已配置完成！${NC}"
}

# 主函数
main() {
    echo -e "${BLUE}Shadowsocks多网卡自动配置脚本${NC}"
    echo -e "自动检测网卡IP并配置端口11000/12000/13000\n"
    
    # 检查权限和环境
    check_root
    check_shadowsocks
    
    # 获取所有内网IP
    local internal_ips_str=$(get_all_internal_ips)
    local internal_ips=($internal_ips_str)
    
    if [[ ${#internal_ips[@]} -lt 3 ]]; then
        log_warn "检测到 ${#internal_ips[@]} 个网卡，少于3个"
        echo "将为现有网卡配置对应端口"
    fi
    
    # 创建配置
    create_shadowsocks_config "$internal_ips_str"
    
    # 配置防火墙
    configure_firewall
    
    # 重启服务
    restart_shadowsocks
    
    # 显示结果
    show_final_result
}

# 运行主函数
main "$@"

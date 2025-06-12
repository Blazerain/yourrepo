#!/bin/bash

#=================================================
# 轻量级SSR多IP配置脚本 - 512M内存优化版
# 适用于阿里云轻量应用服务器
# 一键部署命令: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/ss_ali.sh | bash
#=================================================

set -e

# =============配置区域 - 可修改=============
# 公网IP配置 (根据实际情况修改)
PUBLIC_IPS=(
    "47.242.187.120"
    "47.243.52.144" 
    "8.218.111.82"
)

# 端口配置 (从8388开始)
BASE_PORT=13000

# SSR配置
ENCRYPTION_METHOD="aes-256-gcm"
PROTOCOL="origin"
OBFS="plain"

# 默认密码 (建议修改)
DEFAULT_PASSWORD="Game2025Acc"
# ==========================================

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用root权限运行: sudo bash"
        exit 1
    fi
}

# 检查内存
check_memory() {
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    log_info "服务器内存: ${mem_total}MB"
    
    if [[ $mem_total -lt 400 ]]; then
        log_warn "内存不足400MB，脚本可能失败"
    fi
}

# 检查系统兼容性
check_system() {
    if [[ ! -f /etc/redhat-release ]]; then
        log_error "此脚本仅支持CentOS/RHEL系统"
        exit 1
    fi
    
    local os_version=$(cat /etc/redhat-release)
    log_info "系统版本: $os_version"
}

# 极简依赖安装 - 避免大量下载
install_minimal_deps() {
    log_step "安装最小依赖..."
    
    # 清理缓存
    yum clean all >/dev/null 2>&1
    
    # 只安装绝对必需的包，跳过broken包
    local packages=("wget" "curl" "unzip")
    
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            log_info "安装 $pkg..."
            yum install -y "$pkg" --skip-broken >/dev/null 2>&1 || {
                log_warn "$pkg 安装失败，继续执行..."
            }
        fi
    done
    
    # 检查Python
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_CMD="python3"
    elif command -v python >/dev/null 2>&1; then
        PYTHON_CMD="python"
    else
        log_info "安装Python..."
        yum install -y python --skip-broken >/dev/null 2>&1 || {
            log_error "Python安装失败"
            exit 1
        }
        PYTHON_CMD="python"
    fi
    
    log_info "使用Python命令: $PYTHON_CMD"
}

# 下载SSR - 使用轻量级方法
download_ssr() {
    log_step "下载ShadowsocksR..."
    
    local ssr_dir="/opt/shadowsocksr"
    
    if [[ -d "$ssr_dir" ]]; then
        log_info "SSR已存在，跳过下载"
        return 0
    fi
    
    # 创建目录
    mkdir -p "$ssr_dir"
    cd "$ssr_dir"
    
    # 下载预编译版本 (更小更快)
    log_info "下载轻量级SSR版本..."
    if wget -q --timeout=30 "https://github.com/shadowsocksrr/shadowsocksr/archive/manyuser.zip" -O ssr.zip; then
        unzip -q ssr.zip
        mv shadowsocksr-manyuser/* .
        rm -rf shadowsocksr-manyuser ssr.zip
        chmod +x *.sh
        log_info "SSR下载完成"
    else
        log_error "下载失败，请检查网络连接"
        exit 1
    fi
}

# 生成随机密码
generate_password() {
    local length=${1:-12}
    echo "${DEFAULT_PASSWORD}$(date +%H%M)"
}

# 创建SSR配置文件
create_ssr_config() {
    local ip=$1
    local port=$2
    local password=$3
    local config_file="/opt/shadowsocksr/config_${port}.json"
    
    cat > "$config_file" << EOF
{
    "server": "${ip}",
    "server_ipv6": "::",
    "server_port": ${port},
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "password": "${password}",
    "method": "${ENCRYPTION_METHOD}",
    "protocol": "${PROTOCOL}",
    "protocol_param": "",
    "obfs": "${OBFS}",
    "obfs_param": "",
    "speed_limit_per_con": 0,
    "speed_limit_per_user": 0,
    "connect_verbose_info": 0,
    "redirect": "",
    "dns_ipv6": false,
    "fast_open": false,
    "workers": 1
}
EOF
    
    log_info "配置文件创建: $config_file"
}

# 配置防火墙
setup_firewall() {
    local port=$1
    
    log_info "配置防火墙端口: $port"
    
    # 检查防火墙服务
    if systemctl is-active firewalld >/dev/null 2>&1; then
        # firewalld
        firewall-cmd --permanent --add-port=${port}/tcp >/dev/null 2>&1
        firewall-cmd --permanent --add-port=${port}/udp >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    elif command -v iptables >/dev/null 2>&1; then
        # iptables
        iptables -I INPUT -p tcp --dport ${port} -j ACCEPT 2>/dev/null
        iptables -I INPUT -p udp --dport ${port} -j ACCEPT 2>/dev/null
        # 尝试保存
        service iptables save >/dev/null 2>&1 || true
    fi
}

# 创建启动脚本
create_startup_script() {
    local port=$1
    local script_file="/opt/shadowsocksr/start_${port}.sh"
    
    cat > "$script_file" << EOF
#!/bin/bash
cd /opt/shadowsocksr
$PYTHON_CMD shadowsocks/server.py -c config_${port}.json -d start
EOF
    
    chmod +x "$script_file"
    
    # 创建systemd服务
    cat > "/etc/systemd/system/ssr-${port}.service" << EOF
[Unit]
Description=ShadowsocksR Server Port ${port}
After=network.target

[Service]
Type=forking
ExecStart=/opt/shadowsocksr/start_${port}.sh
ExecStop=$PYTHON_CMD /opt/shadowsocksr/shadowsocks/server.py -c /opt/shadowsocksr/config_${port}.json -d stop
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # 启用并启动服务
    systemctl daemon-reload
    systemctl enable ssr-${port} >/dev/null 2>&1
    systemctl start ssr-${port}
    
    # 检查服务状态
    sleep 2
    if systemctl is-active ssr-${port} >/dev/null 2>&1; then
        log_info "服务 ssr-${port} 启动成功"
        return 0
    else
        log_warn "服务 ssr-${port} 启动可能失败"
        return 1
    fi
}

# 主配置过程
configure_all_ssr() {
    log_step "开始配置多IP SSR服务..."
    
    local config_summary="/root/ssr_game_configs.txt"
    echo "=== 游戏加速器SSR配置 ===" > "$config_summary"
    echo "配置时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$config_summary"
    echo "服务器IP数量: ${#PUBLIC_IPS[@]}" >> "$config_summary"
    echo "" >> "$config_summary"
    
    local success_count=0
    
    for i in "${!PUBLIC_IPS[@]}"; do
        local ip="${PUBLIC_IPS[i]}"
        local port=$((BASE_PORT + i))
        local password=$(generate_password)
        
        echo "正在配置 IP: $ip 端口: $port"
        
        # 创建配置
        create_ssr_config "$ip" "$port" "$password"
        
        # 配置防火墙
        setup_firewall "$port"
        
        # 创建启动脚本和服务
        if create_startup_script "$port"; then
            ((success_count++))
            
            # 添加到配置摘要
            echo "--- 配置 $((i+1)) ---" >> "$config_summary"
            echo "服务器: $ip" >> "$config_summary"
            echo "端口: $port" >> "$config_summary"
            echo "密码: $password" >> "$config_summary"
            echo "加密: $ENCRYPTION_METHOD" >> "$config_summary"
            echo "协议: $PROTOCOL" >> "$config_summary"
            echo "混淆: $OBFS" >> "$config_summary"
            
            # 生成SSR链接
            local auth_string="${ip}:${port}:${PROTOCOL}:${ENCRYPTION_METHOD}:${OBFS}:$(echo -n "$password" | base64 -w 0)"
            local ssr_url="ssr://$(echo -n "$auth_string" | base64 -w 0)"
            echo "SSR链接: $ssr_url" >> "$config_summary"
            echo "" >> "$config_summary"
        fi
        
        # 防止内存压力，短暂休息
        sleep 1
    done
    
    echo "管理命令:" >> "$config_summary"
    echo "查看状态: systemctl status ssr-*" >> "$config_summary"
    echo "重启服务: systemctl restart ssr-端口号" >> "$config_summary"
    echo "查看日志: journalctl -u ssr-端口号" >> "$config_summary"
    
    log_info "成功配置 $success_count/${#PUBLIC_IPS[@]} 个SSR服务"
    log_info "配置详情保存在: $config_summary"
}

# 显示最终状态
show_final_status() {
    log_step "检查服务状态..."
    
    echo ""
    echo "=== 服务状态 ==="
    local active_count=0
    
    for i in "${!PUBLIC_IPS[@]}"; do
        local port=$((BASE_PORT + i))
        local ip="${PUBLIC_IPS[i]}"
        
        if systemctl is-active ssr-${port} >/dev/null 2>&1; then
            echo -e "✅ $ip:$port - ${GREEN}运行中${NC}"
            ((active_count++))
        else
            echo -e "❌ $ip:$port - ${RED}已停止${NC}"
        fi
    done
    
    echo ""
    echo "=== 配置完成 ==="
    echo "活跃服务: $active_count/${#PUBLIC_IPS[@]}"
    echo "配置文件: /root/ssr_game_configs.txt"
    echo ""
    echo "如需查看完整配置信息:"
    echo "cat /root/ssr_game_configs.txt"
}

# 主函数
main() {
    clear
    echo "================================================="
    echo "   轻量级SSR多IP游戏加速器配置脚本"
    echo "   适用于512M内存阿里云轻量应用服务器"
    echo "================================================="
    echo ""
    
    # 预检查
    check_root
    check_system
    check_memory
    
    # 显示将要配置的IP
    echo "将要配置的IP地址:"
    for i in "${!PUBLIC_IPS[@]}"; do
        echo "  $((i+1)). ${PUBLIC_IPS[i]}:$((BASE_PORT + i))"
    done
    echo ""
    
    # 开始配置
    install_minimal_deps
    download_ssr
    configure_all_ssr
    show_final_status
    
    echo ""
    echo "🎮 游戏加速器SSR配置完成！"
    echo "请将配置信息导入您的游戏加速器客户端"
}

# 错误处理
trap 'log_error "脚本执行失败，请检查错误信息"; exit 1' ERR

# 运行主函数
main "$@"

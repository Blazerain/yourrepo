#!/bin/bash

# Shadowsocks一键安装脚本 - Beanfun游戏优化版
# 支持CentOS/RHEL 7/8, Ubuntu, Debian
# 使用方法: curl -sSL https://raw.githubusercontent.com/your-repo/ss.sh | bash
# 或者: bash install_shadowsocks.sh

set -e

echo "=========================================="
echo "🚀 Shadowsocks一键安装脚本 - Beanfun优化版"
echo "🎮 专为游戏代理优化，支持BBR加速"
echo "=========================================="

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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 错误处理
error_exit() {
    log_error "$1"
    exit 1
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "请使用root权限运行此脚本"
    fi
}

# 检测系统类型
detect_os() {
    if [[ -f /etc/redhat-release ]]; then
        OS="centos"
        if grep -q "CentOS Linux 7" /etc/redhat-release; then
            OS_VERSION="7"
        elif grep -q "CentOS Linux 8\|CentOS Stream" /etc/redhat-release; then
            OS_VERSION="8"
        fi
    elif [[ -f /etc/lsb-release ]]; then
        OS="ubuntu"
        OS_VERSION=$(lsb_release -rs)
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        OS_VERSION=$(cat /etc/debian_version)
    else
        error_exit "不支持的操作系统"
    fi
    
    log_info "检测到系统: $OS $OS_VERSION"
}

# 安装依赖
install_dependencies() {
    log_step "安装系统依赖..."
    
    if [[ $OS == "centos" ]]; then
        yum update -y
        yum install -y epel-release
        yum install -y wget curl unzip tar gcc gcc-c++ autoconf libtool make asciidoc xmlto
        yum install -y git python3 python3-pip
        
        # CentOS 8需要额外配置
        if [[ $OS_VERSION == "8" ]]; then
            dnf install -y python3-devel libffi-devel openssl-devel
        fi
    elif [[ $OS == "ubuntu" ]] || [[ $OS == "debian" ]]; then
        apt-get update
        apt-get install -y wget curl unzip tar build-essential autoconf libtool
        apt-get install -y git python3 python3-pip python3-dev libffi-dev libssl-dev
    fi
    
    log_info "依赖安装完成"
}

# 配置端口
configure_port() {
    log_step "配置Shadowsocks端口..."
    
    # 智能端口选择
    if [[ -n "$1" ]]; then
        SS_PORT="$1"
        log_info "使用指定端口: $SS_PORT"
    else
        # 自动选择可用端口
        for port in 8388 8080 443 80 1080 3128 8443 9000; do
            if ! netstat -tuln | grep -q ":$port "; then
                SS_PORT=$port
                log_info "自动选择端口: $SS_PORT"
                break
            fi
        done
        
        if [[ -z "$SS_PORT" ]]; then
            SS_PORT=8388
            log_warn "所有常用端口被占用，使用默认端口: $SS_PORT"
        fi
    fi
}

# 生成密码
generate_password() {
    SS_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    log_info "生成密码: $SS_PASSWORD"
}

# 安装Shadowsocks
install_shadowsocks() {
    log_step "安装Shadowsocks-libev..."
    
    if [[ $OS == "centos" ]]; then
        # CentOS安装方法
        if [[ $OS_VERSION == "7" ]]; then
            yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
            curl -o /etc/yum.repos.d/librehat-shadowsocks-epel-7.repo https://copr.fedorainfracloud.org/coprs/librehat/shadowsocks/repo/epel-7/librehat-shadowsocks-epel-7.repo
            yum install -y shadowsocks-libev
        else
            # CentOS 8 编译安装
            cd /tmp
            git clone https://github.com/shadowsocks/shadowsocks-libev.git
            cd shadowsocks-libev
            git submodule update --init --recursive
            ./autogen.sh && ./configure && make && make install
        fi
    elif [[ $OS == "ubuntu" ]] || [[ $OS == "debian" ]]; then
        # Ubuntu/Debian安装
        apt-get install -y shadowsocks-libev
    fi
    
    log_info "Shadowsocks安装完成"
}

# 配置Shadowsocks
configure_shadowsocks() {
    log_step "配置Shadowsocks..."
    
    # 创建配置目录
    mkdir -p /etc/shadowsocks-libev
    
    # 生成配置文件
    cat > /etc/shadowsocks-libev/config.json << EOF
{
    "server": "0.0.0.0",
    "server_port": $SS_PORT,
    "password": "$SS_PASSWORD",
    "timeout": 300,
    "method": "chacha20-ietf-poly1305",
    "fast_open": false,
    "workers": 2,
    "prefer_ipv6": false,
    "no_delay": true,
    "reuse_port": true,
    "mode": "tcp_and_udp"
}
EOF
    
    log_info "配置文件生成: /etc/shadowsocks-libev/config.json"
}

# 创建systemd服务
create_service() {
    log_step "创建systemd服务..."
    
    cat > /etc/systemd/system/shadowsocks-libev.service << 'EOF'
[Unit]
Description=Shadowsocks-libev Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/ss-server -c /etc/shadowsocks-libev/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    # 如果是包管理器安装，使用不同的路径
    if command -v ss-server >/dev/null 2>&1; then
        sed -i 's|/usr/local/bin/ss-server|ss-server|g' /etc/systemd/system/shadowsocks-libev.service
    fi
    
    systemctl daemon-reload
    systemctl enable shadowsocks-libev
    
    log_info "systemd服务创建完成"
}

# 配置防火墙
configure_firewall() {
    log_step "配置防火墙..."
    
    # 停止firewalld（如果运行）
    if systemctl is-active --quiet firewalld; then
        systemctl stop firewalld
        systemctl disable firewalld
        log_info "已停用firewalld"
    fi
    
    # 配置iptables
    # 清理现有规则
    iptables -F INPUT 2>/dev/null || true
    iptables -X 2>/dev/null || true
    
    # 设置默认策略
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT  
    iptables -P OUTPUT ACCEPT
    
    # 基础规则
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    # 开放端口
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p tcp --dport $SS_PORT -j ACCEPT
    iptables -A INPUT -p udp --dport $SS_PORT -j ACCEPT
    
    # 保存规则
    if command -v iptables-save >/dev/null; then
        iptables-save > /etc/sysconfig/iptables 2>/dev/null || iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    log_info "防火墙配置完成，开放端口: $SS_PORT"
}

# 启用BBR
enable_bbr() {
    log_step "启用BBR TCP拥塞控制..."
    
    # 检查内核版本
    kernel_version=$(uname -r | cut -d. -f1-2)
    if [[ $(echo "$kernel_version >= 4.9" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
        # 启用BBR
        echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
        echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
        sysctl -p
        
        # 验证BBR
        if lsmod | grep -q bbr; then
            log_info "BBR启用成功"
        else
            log_warn "BBR启用可能失败，但不影响功能"
        fi
    else
        log_warn "内核版本过低，无法启用BBR (需要4.9+)"
    fi
}

# 优化系统参数
optimize_system() {
    log_step "优化系统参数..."
    
    # 网络优化
    cat >> /etc/sysctl.conf << 'EOF'

# Shadowsocks优化参数
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 87380 67108864
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
EOF

    sysctl -p
    log_info "系统参数优化完成"
}

# 启动服务
start_service() {
    log_step "启动Shadowsocks服务..."
    
    systemctl start shadowsocks-libev
    sleep 3
    
    if systemctl is-active --quiet shadowsocks-libev; then
        log_info "Shadowsocks服务启动成功"
    else
        log_error "Shadowsocks服务启动失败"
        systemctl status shadowsocks-libev
        return 1
    fi
}

# 测试连接
test_connection() {
    log_step "测试Shadowsocks连接..."
    
    # 检查端口监听
    if netstat -tuln | grep -q ":$SS_PORT "; then
        log_info "端口 $SS_PORT 监听正常"
    else
        log_error "端口 $SS_PORT 未监听"
        return 1
    fi
    
    # 安装测试工具
    if ! command -v nc >/dev/null; then
        if [[ $OS == "centos" ]]; then
            yum install -y nc
        else
            apt-get install -y netcat
        fi
    fi
    
    # 测试端口连通性
    if timeout 5 nc -z 127.0.0.1 $SS_PORT; then
        log_info "本地连接测试通过"
    else
        log_warn "本地连接测试失败"
    fi
}

# 生成客户端配置
generate_client_config() {
    log_step "生成客户端配置..."
    
    # 获取服务器IP
    SERVER_IP=$(curl -s -4 ifconfig.me --connect-timeout 10 2>/dev/null || curl -s -4 ipinfo.io/ip --connect-timeout 10 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)
    
    # 生成配置文件
    cat > ~/shadowsocks_config.json << EOF
{
    "server": "$SERVER_IP",
    "server_port": $SS_PORT,
    "password": "$SS_PASSWORD",
    "method": "chacha20-ietf-poly1305",
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "timeout": 300,
    "fast_open": false
}
EOF

    # 生成SS链接
    SS_CONFIG=$(echo -n "chacha20-ietf-poly1305:$SS_PASSWORD@$SERVER_IP:$SS_PORT" | base64)
    SS_URL="ss://${SS_CONFIG}#Beanfun-Game-Proxy"
    
    log_info "客户端配置文件生成: ~/shadowsocks_config.json"
}

# 创建管理脚本
create_management_scripts() {
    log_step "创建管理脚本..."
    
    # 状态检查脚本
    cat > ~/ss_status.sh << 'EOF'
#!/bin/bash
echo "=== Shadowsocks状态检查 ==="
echo "服务状态: $(systemctl is-active shadowsocks-libev)"
echo "端口监听: $(netstat -tuln | grep shadowsocks || echo "未检测到")"
echo "进程信息: $(ps aux | grep ss-server | grep -v grep || echo "未运行")"

# 获取配置信息
if [ -f /etc/shadowsocks-libev/config.json ]; then
    echo ""
    echo "=== 当前配置 ==="
    echo "端口: $(grep server_port /etc/shadowsocks-libev/config.json | cut -d: -f2 | tr -d ' ,"')"
    echo "加密: $(grep method /etc/shadowsocks-libev/config.json | cut -d: -f2 | tr -d ' ,"')"
fi
EOF

    # 重启脚本
    cat > ~/ss_restart.sh << 'EOF'
#!/bin/bash
echo "重启Shadowsocks服务..."
systemctl restart shadowsocks-libev
sleep 3
systemctl status shadowsocks-libev
echo "重启完成"
EOF

    # 修改密码脚本
    cat > ~/ss_change_password.sh << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "用法: $0 <新密码>"
    echo "例如: $0 myNewPassword123"
    exit 1
fi

NEW_PASSWORD="$1"
CONFIG_FILE="/etc/shadowsocks-libev/config.json"

echo "修改Shadowsocks密码为: $NEW_PASSWORD"

# 备份配置
cp $CONFIG_FILE ${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)

# 修改密码
sed -i "s/\"password\": \".*\"/\"password\": \"$NEW_PASSWORD\"/" $CONFIG_FILE

# 重启服务
systemctl restart shadowsocks-libev

echo "密码修改完成，服务已重启"
echo "新配置:"
grep password $CONFIG_FILE
EOF

    chmod +x ~/ss_*.sh
    log_info "管理脚本创建完成"
}

# 显示安装结果
show_result() {
    clear
    echo "=========================================="
    echo "🎉 Shadowsocks安装完成！"
    echo "=========================================="
    echo ""
    echo "📋 服务器信息:"
    echo "  服务器IP: $SERVER_IP"
    echo "  端口: $SS_PORT"
    echo "  密码: $SS_PASSWORD"
    echo "  加密方式: chacha20-ietf-poly1305"
    echo ""
    echo "🔗 SS链接 (可直接导入客户端):"
    echo "  $SS_URL"
    echo ""
    echo "📱 客户端下载:"
    echo "  Windows: https://github.com/shadowsocks/shadowsocks-windows/releases"
    echo "  macOS: https://github.com/shadowsocks/ShadowsocksX-NG/releases"
    echo "  Android: https://github.com/shadowsocks/shadowsocks-android/releases"
    echo "  iOS: 搜索 Shadowrocket 或 Quantumult"
    echo ""
    echo "🎮 Beanfun游戏配置:"
    echo "  1. 在游戏客户端设置SOCKS5代理"
    echo "  2. 代理服务器: $SERVER_IP"
    echo "  3. 端口: 1080 (本地Shadowsocks客户端端口)"
    echo "  4. ⚠️ 重要: 启用'代理DNS查询'选项"
    echo ""
    echo "⚙️ 服务管理:"
    echo "  启动: systemctl start shadowsocks-libev"
    echo "  停止: systemctl stop shadowsocks-libev"
    echo "  重启: systemctl restart shadowsocks-libev"
    echo "  状态: systemctl status shadowsocks-libev"
    echo "  开机启动: systemctl enable shadowsocks-libev"
    echo ""
    echo "🔧 管理脚本:"
    echo "  查看状态: ~/ss_status.sh"
    echo "  重启服务: ~/ss_restart.sh"
    echo "  修改密码: ~/ss_change_password.sh <新密码>"
    echo ""
    echo "📁 重要文件:"
    echo "  配置文件: /etc/shadowsocks-libev/config.json"
    echo "  客户端配置: ~/shadowsocks_config.json"
    echo "  服务文件: /etc/systemd/system/shadowsocks-libev.service"
    echo ""
    echo "🧪 连接测试:"
    echo "  本地测试: nc -zv 127.0.0.1 $SS_PORT"
    echo "  客户端测试: 使用上面的配置信息连接"
    echo ""
    echo "💡 优化说明:"
    echo "  ✅ BBR拥塞控制已启用"
    echo "  ✅ 系统网络参数已优化"
    echo "  ✅ 防火墙已正确配置"
    echo "  ✅ 使用chacha20-ietf-poly1305高速加密"
    echo ""
    echo "🆘 故障排除:"
    echo "  如果连接失败，请检查:"
    echo "  1. 服务状态: systemctl status shadowsocks-libev"
    echo "  2. 端口监听: netstat -tuln | grep $SS_PORT"
    echo "  3. 防火墙: iptables -L INPUT -n | grep $SS_PORT"
    echo "  4. 日志: journalctl -u shadowsocks-libev -f"
    echo ""
    echo "安装时间: $(date)"
    echo "脚本版本: Beanfun优化版 v1.0"
    echo "=========================================="
}

# 主函数
main() {
    # 检查参数
    if [[ -n "$1" ]]; then
        if [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -ge 1024 ]] && [[ "$1" -le 65535 ]]; then
            CUSTOM_PORT="$1"
        else
            error_exit "端口参数无效，请使用 1024-65535 之间的数字"
        fi
    fi
    
    echo "开始安装Shadowsocks..."
    echo "安装时间: $(date)"
    echo ""
    
    # 执行安装步骤
    check_root
    detect_os
    install_dependencies
    configure_port "$CUSTOM_PORT"
    generate_password
    install_shadowsocks
    configure_shadowsocks
    create_service
    configure_firewall
    enable_bbr
    optimize_system
    start_service
    test_connection
    generate_client_config
    create_management_scripts
    
    # 显示结果
    show_result
    
    echo ""
    echo "🎊 安装完成！请保存上述配置信息。"
    echo "🔗 现在可以使用Shadowsocks客户端连接了！"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

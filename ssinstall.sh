#!/bin/bash
# Shadowsocks多IP多端口一键部署脚本
# 使用方法: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/ssinstall.sh | bash -s ip1 ip2 ip3

set -e

# 定义端口数组
PORTS=(12000 12100 12300)

echo "================================================"
echo "🚀 Shadowsocks多IP多端口一键部署脚本"
echo "🎮 支持为每个IP自动配置独立端口"
echo "================================================"

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo "❌ 请使用root权限运行此脚本"
    exit 1
fi

# 获取输入的IP参数
INPUT_IPS=("$@")
if [ ${#INPUT_IPS[@]} -eq 0 ]; then
    echo "❌ 请至少提供一个IP地址作为参数"
    echo "示例: curl -sSL https://example.com/ss.sh | bash -s ip1 ip2 ip3"
    exit 1
fi

# 检测系统
if [[ -f /etc/redhat-release ]]; then
    OS="centos"
    echo "✅ 检测到CentOS系统"
elif [[ -f /etc/debian_version ]]; then
    OS="debian"
    echo "✅ 检测到Debian/Ubuntu系统"
else
    echo "❌ 不支持的操作系统"
    exit 1
fi

# 安装依赖
echo "📦 安装依赖包..."
if [[ $OS == "centos" ]]; then
    yum update -y >/dev/null 2>&1
    yum install -y epel-release >/dev/null 2>&1
    yum install -y wget curl unzip tar git docker-ce >/dev/null 2>&1
else
    apt-get update >/dev/null 2>&1
    apt-get install -y wget curl unzip tar git docker.io >/dev/null 2>&1
fi

# 启动Docker服务
systemctl start docker >/dev/null 2>&1
systemctl enable docker >/dev/null 2>&1

# 停止现有容器
echo "🛑 清理现有Shadowsocks容器..."
docker stop ss-$(hostname) 2>/dev/null || true
docker rm ss-$(hostname) 2>/dev/null || true

# 为每个IP创建Shadowsocks实例
for i in "${!INPUT_IPS[@]}"; do
    IP=${INPUT_IPS[$i]}
    PORT=${PORTS[$i]}
    
    if [ -z "$PORT" ]; then
        PORT=$((12000 + $i))
    fi

    # 生成随机密码
    PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    
    echo "🔧 正在为IP $IP 配置端口 $PORT"
    
    # 启动容器
    docker run -d \
        --name ss-$IP \
        --restart unless-stopped \
        -p $IP:$PORT:8388/tcp \
        -p $IP:$PORT:8388/udp \
        shadowsocks/shadowsocks-libev \
        ss-server -s 0.0.0.0 -p 8388 -k "$PASSWORD" -m chacha20-ietf-poly1305 -u
    
    # 生成SS链接
    SS_CONFIG=$(echo -n "chacha20-ietf-poly1305:$PASSWORD@$IP:$PORT" | base64 -w 0)
    SS_URL="ss://${SS_CONFIG}#SS_$IP"
    
    # 保存配置
    cat >> ~/ss_multi_config.txt << EOF
[配置 $((i+1))]
服务器IP: $IP
端口: $PORT
密码: $PASSWORD
加密方式: chacha20-ietf-poly1305
SS链接: $SS_URL
本地代理: $IP:1080

EOF

    echo "✅ $IP 配置完成"
done

# 配置防火墙
echo "🔥 配置防火墙..."
if [[ $OS == "centos" ]]; then
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
fi

# 设置iptables规则
iptables -F 2>/dev/null || true
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

for PORT in "${PORTS[@]}"; do
    iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
    iptables -A INPUT -p udp --dport $PORT -j ACCEPT
done

# 保存防火墙规则
if [[ $OS == "centos" ]]; then
    iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
else
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
fi

# 启用BBR加速
echo "🚀 启用BBR加速..."
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

# 创建管理脚本
cat > /usr/local/bin/ss-manage << 'EOF'
#!/bin/bash
case "$1" in
    status)
        echo "=== Shadowsocks状态 ==="
        docker ps -a --filter "name=ss-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        ;;
    restart)
        echo "重启所有Shadowsocks容器..."
        docker restart $(docker ps -a --filter "name=ss-" --format "{{.Names}}")
        ;;
    stop)
        echo "停止所有Shadowsocks容器..."
        docker stop $(docker ps -a --filter "name=ss-" --format "{{.Names}}")
        ;;
    start)
        echo "启动所有Shadowsocks容器..."
        docker start $(docker ps -a --filter "name=ss-" --format "{{.Names}}")
        ;;
    *)
        echo "使用方法: ss-manage {status|restart|stop|start}"
        exit 1
esac
EOF

chmod +x /usr/local/bin/ss-manage

# 显示安装结果
clear
echo "================================================"
echo "🎉 Shadowsocks多IP部署完成！"
echo "================================================"
echo ""
cat ~/ss_multi_config.txt
echo ""
echo "⚙️ 服务管理命令:"
echo "  查看状态: ss-manage status"
echo "  重启服务: ss-manage restart"
echo "  停止服务: ss-manage stop"
echo "  启动服务: ss-manage start"
echo ""
echo "📱 客户端下载:"
echo "  Windows: https://github.com/shadowsocks/shadowsocks-windows/releases"
echo "  Android: https://github.com/shadowsocks/shadowsocks-android/releases"
echo "  macOS: https://github.com/shadowsocks/ShadowsocksX-NG/releases"
echo ""
echo "💡 重要提醒:"
echo "  - 每个IP使用独立的端口和密码"
echo "  - 配置信息已保存到 ~/ss_multi_config.txt"
echo "  - 确保客户端启用了'代理DNS查询'"
echo ""
echo "安装时间: $(date)"
echo "================================================"

#!/bin/bash

# Shadowsocks一键安装脚本 - 修复版
# 专为Beanfun游戏优化

set -e

echo "================================================"
echo "🚀 Shadowsocks一键安装脚本 - Beanfun优化版"
echo "🎮 专为游戏代理优化，支持BBR加速"
echo "================================================"

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo "❌ 请使用root权限运行此脚本"
    exit 1
fi

# 停止可能冲突的服务
echo "🛑 停止可能冲突的服务..."
systemctl stop xray 2>/dev/null || true
systemctl stop v2ray 2>/dev/null || true

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

# 端口配置
if [[ -n "$1" ]]; then
    SS_PORT="$1"
else
    # 自动选择可用端口
    for port in 8388 8080 443 80 1080 3128 8443; do
        if ! netstat -tuln | grep -q ":$port "; then
            SS_PORT=$port
            break
        fi
    done
    
    if [[ -z "$SS_PORT" ]]; then
        SS_PORT=8388
    fi
fi

echo "📍 使用端口: $SS_PORT"

# 生成随机密码
SS_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
echo "🔑 生成密码: $SS_PASSWORD"

# 安装依赖
echo "📦 安装依赖包..."
if [[ $OS == "centos" ]]; then
    yum update -y >/dev/null 2>&1
    yum install -y epel-release >/dev/null 2>&1
    yum install -y wget curl unzip tar git python3 python3-pip >/dev/null 2>&1
    yum install -y gcc gcc-c++ autoconf libtool make >/dev/null 2>&1
else
    apt-get update >/dev/null 2>&1
    apt-get install -y wget curl unzip tar git python3 python3-pip >/dev/null 2>&1
    apt-get install -y build-essential autoconf libtool >/dev/null 2>&1
fi

echo "✅ 依赖安装完成"

# 使用Docker方式安装（最稳定）
echo "🐳 使用Docker安装Shadowsocks..."

# 安装Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "📦 安装Docker..."
    curl -fsSL https://get.docker.com | bash >/dev/null 2>&1
    systemctl start docker
    systemctl enable docker
fi

echo "✅ Docker安装完成"

# 停止现有容器
docker stop shadowsocks 2>/dev/null || true
docker rm shadowsocks 2>/dev/null || true

# 启动Shadowsocks容器
echo "🚀 启动Shadowsocks服务..."
docker run -d \
    --name shadowsocks \
    -p $SS_PORT:8388 \
    -p $SS_PORT:8388/udp \
    --restart unless-stopped \
    shadowsocks/shadowsocks-libev:latest \
    ss-server -s 0.0.0.0 -p 8388 -k "$SS_PASSWORD" -m chacha20-ietf-poly1305 -u

# 等待容器启动
sleep 5

# 检查容器状态
if docker ps | grep -q shadowsocks; then
    echo "✅ Shadowsocks服务启动成功"
else
    echo "❌ Shadowsocks服务启动失败"
    docker logs shadowsocks
    exit 1
fi

# 配置防火墙
echo "🔥 配置防火墙..."

# 停止firewalld
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true

# 配置iptables
iptables -F INPUT 2>/dev/null || true
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 基础规则
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport $SS_PORT -j ACCEPT
iptables -A INPUT -p udp --dport $SS_PORT -j ACCEPT

# 保存防火墙规则
iptables-save > /etc/sysconfig/iptables 2>/dev/null || iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

echo "✅ 防火墙配置完成"

# 启用BBR
echo "🚀 启用BBR加速..."
echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

echo "✅ BBR加速启用完成"

# 获取服务器IP
SERVER_IP=$(curl -s -4 ifconfig.me --connect-timeout 10 2>/dev/null || curl -s -4 ipinfo.io/ip --connect-timeout 10 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)

# 生成客户端配置
cat > ~/shadowsocks_config.json << EOF
{
    "server": "$SERVER_IP",
    "server_port": $SS_PORT,
    "password": "$SS_PASSWORD",
    "method": "chacha20-ietf-poly1305",
    "local_address": "127.0.0.1",
    "local_port": 1080,
    "timeout": 300
}
EOF

# 生成SS链接
SS_CONFIG=$(echo -n "chacha20-ietf-poly1305:$SS_PASSWORD@$SERVER_IP:$SS_PORT" | base64)
SS_URL="ss://${SS_CONFIG}#Beanfun-Game-Proxy"

# 创建管理脚本
cat > ~/ss_status.sh << 'EOF'
#!/bin/bash
echo "=== Shadowsocks状态 ==="
echo "容器状态: $(docker ps --format 'table {{.Names}}\t{{.Status}}' | grep shadowsocks || echo '未运行')"
echo "端口监听: $(netstat -tuln | grep :8388 || echo '未监听')"
SERVER_IP=$(curl -s ifconfig.me)
if [ -f ~/shadowsocks_config.json ]; then
    PORT=$(grep server_port ~/shadowsocks_config.json | cut -d: -f2 | tr -d ' ,"')
    PASSWORD=$(grep password ~/shadowsocks_config.json | cut -d: -f2 | tr -d ' ,"')
    echo "服务器: $SERVER_IP"
    echo "端口: $PORT"
    echo "密码: $PASSWORD"
fi
EOF

cat > ~/ss_restart.sh << 'EOF'
#!/bin/bash
echo "重启Shadowsocks..."
docker restart shadowsocks
sleep 3
docker ps | grep shadowsocks
echo "重启完成"
EOF

chmod +x ~/ss_*.sh

# 测试连接
echo "🧪 测试连接..."
sleep 3

if netstat -tuln | grep -q ":$SS_PORT "; then
    echo "✅ 端口监听正常"
else
    echo "❌ 端口监听异常"
fi

# 显示安装结果
clear
echo "================================================"
echo "🎉 Shadowsocks安装完成！"
echo "================================================"
echo ""
echo "📋 服务器信息:"
echo "  服务器IP: $SERVER_IP"
echo "  端口: $SS_PORT"
echo "  密码: $SS_PASSWORD"
echo "  加密方式: chacha20-ietf-poly1305"
echo ""
echo "🔗 SS链接 (复制到客户端):"
echo "  $SS_URL"
echo ""
echo "📱 客户端下载:"
echo "  Windows: https://github.com/shadowsocks/shadowsocks-windows/releases"
echo "  Android: https://github.com/shadowsocks/shadowsocks-android/releases"
echo "  iOS: 搜索 Shadowrocket"
echo ""
echo "🎮 Beanfun游戏设置:"
echo "  1. 启动Shadowsocks客户端"
echo "  2. 游戏中设置SOCKS5代理: 127.0.0.1:1080"
echo "  3. ⚠️ 必须启用'代理DNS查询'选项"
echo ""
echo "⚙️ 服务管理:"
echo "  查看状态: ~/ss_status.sh"
echo "  重启服务: ~/ss_restart.sh"
echo "  容器管理: docker restart shadowsocks"
echo ""
echo "📁 配置文件: ~/shadowsocks_config.json"
echo ""
echo "🧪 连接测试:"
echo "  1. 安装并启动Shadowsocks客户端"
echo "  2. 测试命令: curl --socks5 127.0.0.1:1080 https://httpbin.org/ip"
echo "  3. 测试Beanfun: 打开游戏客户端测试登录"
echo ""
echo "💡 重要提醒:"
echo "  - 确保客户端启用了'代理DNS查询'"
echo "  - 如果连接失败，检查防火墙设置"
echo "  - 游戏代理设置为: 127.0.0.1:1080"
echo ""
echo "安装时间: $(date)"
echo "================================================"

# 保存配置信息到文件
cat > ~/shadowsocks_info.txt << EOF
Shadowsocks配置信息
==================

服务器: $SERVER_IP
端口: $SS_PORT
密码: $SS_PASSWORD
加密: chacha20-ietf-poly1305

SS链接: $SS_URL

客户端本地代理: 127.0.0.1:1080

安装时间: $(date)
EOF

echo ""
echo "🎊 安装完成！配置信息已保存到 ~/shadowsocks_info.txt"
echo "🔗 现在请在本地安装Shadowsocks客户端并使用上述配置连接！"

#!/bin/bash

# Shadowsocks一键安装脚本
# 加密方式: aes-256-gcm
# 端口: 18889 (TCP+UDP)
# 密码: qwe123
# 自动检测所有公网IP

set -e

echo "=========================================="
echo "🚀 Shadowsocks一键安装脚本"
echo "🔐 加密: aes-256-gcm"
echo "🔌 端口: 18889 (TCP+UDP)"
echo "🔑 密码: qwe123"
echo "🌐 自动检测所有公网IP"
echo "=========================================="

# 检查root权限
if [[ $EUID -ne 0 ]]; then
   echo "❌ 需要root权限运行"
   exit 1
fi

# 获取网卡IP
get_ip() {
    local interface=$1
    ip addr show "$interface" 2>/dev/null | grep 'inet ' | head -1 | awk '{print $2}' | cut -d'/' -f1
}

# 获取外网IP
get_external_ip() {
    local internal_ip=$1
    echo "🔍 检测外网IP..." >&2
    
    local external_ip=""
    # 尝试多个IP检测服务
    for service in "ifconfig.me" "ipinfo.io/ip" "icanhazip.com"; do
        external_ip=$(timeout 10 curl -s --max-time 8 "$service" 2>/dev/null | tr -d '\n\r' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
        if [[ "$external_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "✅ 检测到外网IP: $external_ip" >&2
            echo "$external_ip"
            return 0
        fi
    done
    
    echo "未知"
}

echo "🔍 检测网卡配置..."

# 更强力的IP检测方法
declare -A CONFIG
CONFIG_COUNT=0

# 方法1: 检测常见网卡
for interface in eth0 eth1 eth2 ens3 ens4 ens5; do
    ip=$(get_ip "$interface")
    if [[ -n "$ip" ]] && [[ "$ip" != "127.0.0.1" ]]; then
        CONFIG["$interface"]="$ip"
        echo "✅ $interface: $ip"
        ((CONFIG_COUNT++))
    fi
done

# 方法2: 检测子接口 (eth1:1格式)
for main_if in eth0 eth1 eth2; do
    for sub in 1 2 3; do
        interface="${main_if}:${sub}"
        ip=$(get_ip "$interface")
        if [[ -n "$ip" ]] && [[ "$ip" != "127.0.0.1" ]]; then
            # 检查是否已存在相同IP
            duplicate=false
            for existing_ip in "${CONFIG[@]}"; do
                if [[ "$existing_ip" == "$ip" ]]; then
                    duplicate=true
                    break
                fi
            done
            
            if [[ "$duplicate" == false ]]; then
                CONFIG["$interface"]="$ip"
                echo "✅ $interface: $ip"
                ((CONFIG_COUNT++))
            fi
        fi
    done
done

# 方法3: 从已知IP强制添加 (根据您的netstat输出)
known_ips=("172.17.18.14" "172.17.18.15" "172.17.18.16")
for ip in "${known_ips[@]}"; do
    # 检查IP是否已在CONFIG中
    found=false
    for existing_ip in "${CONFIG[@]}"; do
        if [[ "$existing_ip" == "$ip" ]]; then
            found=true
            break
        fi
    done
    
    if [[ "$found" == false ]]; then
        # 尝试找到对应的接口
        interface=$(ip addr show | grep "$ip" | head -1 | awk '{print $NF}' 2>/dev/null || echo "unknown")
        if [[ -n "$interface" ]] && [[ "$interface" != "unknown" ]]; then
            CONFIG["$interface"]="$ip"
            echo "✅ $interface: $ip (强制检测)"
            ((CONFIG_COUNT++))
        fi
    fi
done

if [[ ${#CONFIG[@]} -eq 0 ]]; then
    echo "❌ 未检测到可用的网络接口"
    exit 1
fi

# 获取外网IP
echo "🌐 检测外网IP..."
EXTERNAL_IP=$(get_external_ip)
echo "外网IP: $EXTERNAL_IP"

# 停止现有服务
echo "🛑 停止现有服务..."
systemctl stop shadowsocks-libev 2>/dev/null || true
systemctl stop ss-server 2>/dev/null || true
pkill -f ss-server 2>/dev/null || true
sleep 2

# 安装依赖
echo "📦 安装依赖..."
if command -v yum >/dev/null 2>&1; then
    # CentOS/RHEL - 超时控制和错误处理
    echo "  检测到yum包管理器..."
    
    timeout 300 yum update -y >/dev/null 2>&1 || echo "  ⚠️ yum update超时，继续安装..."
    timeout 180 yum install -y epel-release >/dev/null 2>&1 || echo "  ⚠️ epel-release安装可能失败，继续..."
    timeout 300 yum install -y wget curl net-tools >/dev/null 2>&1 || echo "  ⚠️ 基础工具安装可能失败，继续..."
    
    # 尝试安装shadowsocks-libev
    if ! command -v ss-server >/dev/null 2>&1; then
        echo "📥 安装shadowsocks-libev..."
        
        # 先尝试简单安装
        if ! timeout 300 yum install -y shadowsocks-libev >/dev/null 2>&1; then
            echo "  ⚠️ yum安装shadowsocks-libev失败，尝试其他方法..."
            
            # 方法2: 手动下载预编译版本
            echo "  📥 下载预编译版本..."
            cd /tmp
            if wget -q --timeout=30 "https://github.com/shadowsocks/shadowsocks-libev/releases/download/v3.3.5/shadowsocks-libev-3.3.5.tar.gz"; then
                echo "  ⚠️ 需要编译安装，可能较慢..."
                
                # 安装编译依赖
                timeout 300 yum install -y gcc gettext autoconf libtool automake make pcre-devel asciidoc xmlto c-ares-devel libev-devel libsodium-devel mbedtls-devel >/dev/null 2>&1 || {
                    echo "  ❌ 编译依赖安装失败，尝试简化安装..."
                    timeout 300 yum install -y gcc make >/dev/null 2>&1
                }
                
                tar -xzf shadowsocks-libev-3.3.5.tar.gz 2>/dev/null || echo "  ⚠️ 解压可能有问题..."
                cd shadowsocks-libev-3.3.5 2>/dev/null || {
                    echo "  ❌ 编译安装失败，跳过..."
                    cd /tmp
                }
                
                if [ -d "shadowsocks-libev-3.3.5" ]; then
                    cd shadowsocks-libev-3.3.5
                    ./configure --prefix=/usr/local >/dev/null 2>&1 && \
                    make -j2 >/dev/null 2>&1 && \
                    make install >/dev/null 2>&1 && \
                    ln -sf /usr/local/bin/ss-server /usr/bin/ss-server
                fi
            else
                echo "  ❌ 下载失败，请检查网络连接"
            fi
        fi
    fi
    
elif command -v apt >/dev/null 2>&1; then
    # Ubuntu/Debian - 超时控制
    echo "  检测到apt包管理器..."
    timeout 300 apt update -y >/dev/null 2>&1 || echo "  ⚠️ apt update超时，继续..."
    timeout 300 apt install -y wget curl net-tools shadowsocks-libev >/dev/null 2>&1 || echo "  ⚠️ 安装可能失败，继续..."
else
    echo "  ⚠️ 未识别的包管理器，尝试手动安装..."
fi

# 验证安装
echo "🔍 验证shadowsocks安装..."
if command -v ss-server >/dev/null 2>&1; then
    echo "✅ shadowsocks-libev安装成功: $(ss-server --help 2>&1 | head -1 | grep -o 'shadowsocks-libev' || echo 'ss-server')"
else
    echo "⚠️ shadowsocks-libev未找到，尝试使用Go版本替代..."
    
    # 使用Go版本shadowsocks2作为备用
    cd /tmp
    if wget -q --timeout=30 "https://github.com/shadowsocks/go-shadowsocks2/releases/download/v0.1.5/shadowsocks2-linux.gz"; then
        gunzip shadowsocks2-linux.gz
        chmod +x shadowsocks2-linux
        mv shadowsocks2-linux /usr/local/bin/ss-server-go
        ln -sf /usr/local/bin/ss-server-go /usr/bin/ss-server
        echo "✅ 使用Go版本shadowsocks2"
        USE_GO_VERSION=true
    else
        echo "❌ shadowsocks安装失败，请手动安装"
        exit 1
    fi
fi

# 创建配置目录
mkdir -p /etc/shadowsocks-libev

# 生成配置文件
echo "⚙️ 生成配置文件..."

cat > /etc/shadowsocks-libev/config.json << CONFIGEOF
{
    "server": [
CONFIGEOF

# 添加所有内网IP到配置
ip_count=0
for interface in "${!CONFIG[@]}"; do
    ip="${CONFIG[$interface]}"
    
    if [ $ip_count -gt 0 ]; then
        echo "," >> /etc/shadowsocks-libev/config.json
    fi
    
    echo "        \"$ip\"" >> /etc/shadowsocks-libev/config.json
    ((ip_count++))
done

cat >> /etc/shadowsocks-libev/config.json << CONFIGEOF
    ],
    "server_port": 18889,
    "password": "qwe123",
    "method": "aes-256-gcm",
    "timeout": 300,
    "fast_open": true,
    "mode": "tcp_and_udp"
}
CONFIGEOF

echo "✅ 配置文件生成完成"

# 创建systemd服务
echo "📋 创建系统服务..."

cat > /etc/systemd/system/shadowsocks.service << 'SERVICEEOF'
[Unit]
Description=Shadowsocks Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ss-server -c /etc/shadowsocks-libev/config.json -v
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=10s
StandardOutput=journal
StandardError=journal

# 优化设置
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
SERVICEEOF

# 配置防火墙
echo "🔥 配置防火墙..."
if systemctl is-active firewalld >/dev/null 2>&1; then
    systemctl stop firewalld
    systemctl disable firewalld
fi

# 简单的iptables配置
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -F

# 基本规则
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 18889 -j ACCEPT
iptables -A INPUT -p udp --dport 18889 -j ACCEPT

echo "✅ 防火墙配置完成"

# 系统优化
echo "🔧 系统优化..."
cat >> /etc/sysctl.conf << 'SYSCTLEOF'

# Shadowsocks优化
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 16384 67108864
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = hybla
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
SYSCTLEOF

sysctl -p >/dev/null 2>&1

# 启动服务
echo "🚀 启动服务..."
systemctl daemon-reload
systemctl enable shadowsocks

if systemctl start shadowsocks; then
    echo "✅ 服务启动成功"
else
    echo "❌ 服务启动失败，查看日志:"
    journalctl -u shadowsocks -n 10 --no-pager
    exit 1
fi

# 等待服务启动
sleep 5

# 验证服务
echo "🔍 验证服务..."
if systemctl is-active --quiet shadowsocks; then
    echo "✅ Shadowsocks服务运行正常"
else
    echo "❌ 服务状态异常"
fi

# 检查端口监听
listening_count=0
echo ""
echo "🔌 端口监听状态:"
for interface in "${!CONFIG[@]}"; do
    ip="${CONFIG[$interface]}"
    if netstat -tlnp 2>/dev/null | grep -q "$ip:18889"; then
        echo "  ✅ $interface ($ip:18889) TCP监听正常"
        ((listening_count++))
    else
        echo "  ❌ $interface ($ip:18889) TCP未监听"
    fi
    
    if netstat -ulnp 2>/dev/null | grep -q "$ip:18889"; then
        echo "  ✅ $interface ($ip:18889) UDP监听正常"
    else
        echo "  ❌ $interface ($ip:18889) UDP未监听"
    fi
done

# 生成客户端配置
echo ""
echo "📝 生成客户端配置..."

cat > ~/Shadowsocks_Config.txt << CONFIGEOF
#############################################################################
🎯 Shadowsocks代理配置

📡 服务器信息:
外网IP: $EXTERNAL_IP
内网IP数量: ${#CONFIG[@]}
监听端口: 18889 (TCP+UDP)

🔐 连接信息:
服务器地址: $EXTERNAL_IP
服务器端口: 18889
密码: qwe123
加密方式: aes-256-gcm
协议: TCP+UDP

📱 各平台客户端配置:

Windows/Mac/Linux:
- 服务器: $EXTERNAL_IP
- 端口: 18889
- 密码: qwe123
- 加密: aes-256-gcm

Android/iOS:
- 服务器: $EXTERNAL_IP
- 端口: 18889
- 密码: qwe123
- 方法: aes-256-gcm

🔗 SS链接 (一键导入):
ss://$(echo -n "aes-256-gcm:qwe123" | base64)@$EXTERNAL_IP:18889

📋 内网IP列表:
CONFIGEOF

for interface in "${!CONFIG[@]}"; do
    ip="${CONFIG[$interface]}"
    echo "$interface: $ip" >> ~/Shadowsocks_Config.txt
done

cat >> ~/Shadowsocks_Config.txt << CONFIGEOF2

⚙️ 服务管理:
启动: systemctl start shadowsocks
停止: systemctl stop shadowsocks
重启: systemctl restart shadowsocks
状态: systemctl status shadowsocks
日志: journalctl -u shadowsocks -f

🔧 配置文件: /etc/shadowsocks-libev/config.json

🧪 连接测试:
# 在客户端测试连接
curl --proxy socks5://127.0.0.1:1080 https://httpbin.org/ip

安装时间: $(date)
版本: Shadowsocks一键脚本 v1.0
#############################################################################
CONFIGEOF2

# 创建管理脚本
cat > /usr/local/bin/ss-info.sh << 'INFOEOF'
#!/bin/bash

echo "🔍 Shadowsocks服务状态"
echo "======================"

echo "📊 服务状态: $(systemctl is-active shadowsocks)"
echo "📋 进程状态: $(pgrep -c ss-server) 个进程"

echo ""
echo "🔌 端口监听:"
netstat -tlnp | grep :18889 | head -5
echo ""
netstat -ulnp | grep :18889 | head -5

echo ""
echo "📄 配置信息:"
if [ -f /etc/shadowsocks-libev/config.json ]; then
    cat /etc/shadowsocks-libev/config.json | grep -E "(server|server_port|password|method)" | head -10
fi

echo ""
echo "🔗 连接信息:"
external_ip=$(curl -s ifconfig.me 2>/dev/null || echo "获取失败")
echo "服务器: $external_ip:18889"
echo "密码: qwe123"
echo "加密: aes-256-gcm"
INFOEOF

chmod +x /usr/local/bin/ss-info.sh

# 最终报告
echo ""
echo "=========================================="
echo "🎉 Shadowsocks安装完成！"
echo "=========================================="
echo "🌐 外网IP: $EXTERNAL_IP"
echo "🔌 端口: 18889 (TCP+UDP)"
echo "🔑 密码: qwe123"
echo "🔐 加密: aes-256-gcm"
echo "📊 监听IP数: ${#CONFIG[@]}"
echo ""

for interface in "${!CONFIG[@]}"; do
    ip="${CONFIG[$interface]}"
    if netstat -tlnp 2>/dev/null | grep -q "$ip:18889"; then
        status="✅ 正常"
    else
        status="❌ 异常"
    fi
    echo "📌 $interface ($ip): $status"
done

echo ""
echo "📄 详细配置: ~/Shadowsocks_Config.txt"
echo "🔧 状态检查: /usr/local/bin/ss-info.sh"

if [ $listening_count -gt 0 ]; then
    echo ""
    echo "🎯 安装成功！Shadowsocks服务正常运行！"
    echo ""
    echo "🔗 SS链接 (一键导入):"
    echo "ss://$(echo -n "aes-256-gcm:qwe123" | base64)@$EXTERNAL_IP:18889"
    echo ""
    echo "📱 客户端配置:"
    echo "   服务器: $EXTERNAL_IP"
    echo "   端口: 18889"
    echo "   密码: qwe123"
    echo "   加密: aes-256-gcm"
else
    echo ""
    echo "⚠️ 部分端口可能异常，请检查:"
    echo "   systemctl status shadowsocks"
    echo "   journalctl -u shadowsocks -f"
fi

# 清理
cd /
rm -rf /tmp/shadowsocks*

echo ""
echo "🎊 Shadowsocks代理服务已就绪！"

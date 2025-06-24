#!/bin/bash

# newinstall.sh - 完整功能版多IP SOCKS5代理安装脚本
# 功能：自动检测外网IP，单进程多用户，解决连接冲突
# 使用方法: curl -sSL https://raw.githubusercontent.com/your-repo/newinstall.sh | bash
# 警告：【脚本命令不可重复运行】，如需重新搭建，请【重置云服务器系统】

set -e

echo "=========================================="
echo "🚀 完整功能版多IP SOCKS5安装脚本"
echo "🌐 自动检测外网IP + 解决连接冲突"
echo "🔌 单进程，多用户，同端口18889"
echo "⚠️  【不可重复运行，需重置系统重装】"
echo "=========================================="

# 检查root权限
if [[ $EUID -ne 0 ]]; then
   echo "❌ 需要root权限运行"
   exit 1
fi

# 检查是否已安装
if [ -f "/etc/xray/serve.toml" ] || [ -f "/etc/xray-multi/config_eth0_11000.json" ]; then
    echo "❌ 检测到已有安装，请重置系统后重新运行"
    echo "   已存在配置文件，避免冲突"
    exit 1
fi

# 获取网卡IP
get_ip() {
    local interface=$1
    ip addr show "$interface" 2>/dev/null | grep 'inet ' | head -1 | awk '{print $2}' | cut -d'/' -f1
}

# 获取网卡对应的外网IP
get_external_ip() {
    local interface=$1
    local internal_ip=$2
    
    echo "🔍 检测 $interface ($internal_ip) 的外网IP..." >&2
    
    # 方法1: 使用路由测试
    if command -v curl >/dev/null 2>&1; then
        # 尝试通过特定接口访问IP检测服务
        local external_ip=""
        
        # 创建临时路由强制使用特定接口
        local test_routes=()
        
        # 添加临时路由到IP检测服务
        for service_ip in "208.67.222.222" "1.1.1.1" "8.8.8.8"; do
            if ip route add "$service_ip" dev "$interface" 2>/dev/null; then
                test_routes+=("$service_ip")
            fi
        done
        
        # 尝试检测外网IP
        for service in "ifconfig.me" "ipinfo.io/ip" "icanhazip.com"; do
            external_ip=$(timeout 10 curl -s --max-time 8 "$service" 2>/dev/null | tr -d '\n\r' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
            if [[ "$external_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "✅ 检测到外网IP: $external_ip" >&2
                break
            fi
        done
        
        # 清理临时路由
        for route_ip in "${test_routes[@]}"; do
            ip route del "$route_ip" dev "$interface" 2>/dev/null || true
        done
        
        if [[ "$external_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$external_ip"
            return 0
        fi
    fi
    
    # 方法2: 使用默认路由检测 (备用)
    echo "⚠️ 使用通用检测..." >&2
    local fallback_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null | tr -d '\n\r')
    if [[ "$fallback_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$fallback_ip"
    else
        echo "未知"
    fi
}

echo "🔍 检测网卡配置..."
eth0_ip=$(get_ip "eth0")
eth1_ip=$(get_ip "eth1")
eth1_1_ip=$(get_ip "eth1:1")

# 存储配置信息
declare -A CONFIG
declare -A EXTERNAL_IPS

if [[ -n "$eth0_ip" ]]; then
    CONFIG["eth0"]="$eth0_ip:vip1"
    EXTERNAL_IPS["eth0"]=$(get_external_ip "eth0" "$eth0_ip")
    echo "✅ eth0: $eth0_ip -> ${EXTERNAL_IPS[eth0]} (用户vip1)"
fi

if [[ -n "$eth1_ip" ]]; then
    CONFIG["eth1"]="$eth1_ip:vip2"
    EXTERNAL_IPS["eth1"]=$(get_external_ip "eth1" "$eth1_ip")
    echo "✅ eth1: $eth1_ip -> ${EXTERNAL_IPS[eth1]} (用户vip2)"
fi

if [[ -n "$eth1_1_ip" ]] && [[ "$eth1_1_ip" != "$eth1_ip" ]]; then
    CONFIG["eth1:1"]="$eth1_1_ip:vip3"
    EXTERNAL_IPS["eth1:1"]=$(get_external_ip "eth1:1" "$eth1_1_ip")
    echo "✅ eth1:1: $eth1_1_ip -> ${EXTERNAL_IPS[eth1:1]} (用户vip3)"
fi

if [[ ${#CONFIG[@]} -lt 2 ]]; then
    echo "❌ 检测到的可用IP少于2个，退出安装"
    exit 1
fi

# 彻底清理环境
echo "🛑 清理环境..."
systemctl stop xray 2>/dev/null || true
systemctl stop xray-multi 2>/dev/null || true
pkill -f xray 2>/dev/null || true
sleep 3
pkill -9 -f xray 2>/dev/null || true

# 清理旧配置
rm -rf /etc/xray /etc/xray-multi /var/log/xray-multi 2>/dev/null || true

# 安装依赖
echo "📦 安装依赖软件..."
if command -v yum >/dev/null 2>&1; then
    yum -y install wget unzip bind-utils net-tools curl >/dev/null 2>&1
elif command -v apt >/dev/null 2>&1; then
    apt update >/dev/null 2>&1
    apt -y install wget unzip dnsutils net-tools curl >/dev/null 2>&1
fi

# ====== 系统优化 ======
echo "🔧 系统网络优化..."

# 备份并优化sysctl
cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

cat >> /etc/sysctl.conf << 'SYSCTLEOF'

# SOCKS5代理优化参数
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 16384 16777216
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 10000
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 5000
net.ipv4.ip_forward = 1
SYSCTLEOF

sysctl -p >/dev/null 2>&1

# DNS优化
echo "🌐 DNS优化..."
cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

cat > /etc/resolv.conf << 'DNSEOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
options timeout:3
options attempts:2
options rotate
DNSEOF

# Beanfun游戏优化
cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d_%H%M%S)
sed -i '/beanfun/d' /etc/hosts

cdn_ip=$(dig +short cdn.hk.beanfun.com @8.8.8.8 2>/dev/null | head -1)
[[ ! "$cdn_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && cdn_ip="112.121.124.69"

cat >> /etc/hosts << EOF

# Beanfun游戏优化 $(date)
112.121.124.11 hk.beanfun.com
112.121.124.69 bfweb.hk.beanfun.com
$cdn_ip cdn.hk.beanfun.com
18.167.13.186 csp.hk.beanfun.com
202.80.107.11 tw.beanfun.com
52.147.74.109 beanfun.com
127.0.0.1 31.13.106.4
EOF

echo "✅ 系统优化完成"

# ====== 下载安装Xray ======
echo "📥 下载Xray..."
cd /tmp
rm -f xray.zip xray

download_success=false
for url in \
    "https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-64.zip" \
    "https://vip.123pan.cn/1816473155/%E6%8F%92%E4%BB%B6%E6%B3%A8%E5%86%8CIP/xray"
do
    if wget -q -O xray.zip "$url" --timeout=30; then
        download_success=true
        break
    fi
done

if [ "$download_success" = false ]; then
    echo "❌ Xray下载失败，请检查网络"
    exit 1
fi

unzip -q -o xray.zip
if [ ! -f "xray" ]; then
    echo "❌ Xray解压失败"
    exit 1
fi

mv xray /usr/local/bin/
chmod +x /usr/local/bin/xray
rm -f xray.zip

echo "✅ Xray安装成功: $(/usr/local/bin/xray version | head -1)"

# ====== 创建优化的TOML配置 ======
echo "⚙️ 生成TOML配置..."
mkdir -p /etc/xray

cat > /etc/xray/serve.toml << 'TOMLHEADER'
# 多IP SOCKS5代理配置 - 解决连接冲突版
# 生成时间: $(date)
# 特性: 单进程，多用户并发，连接稳定

TOMLHEADER

tag_counter=1
for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip user <<< "${CONFIG[$interface]}"
    external_ip="${EXTERNAL_IPS[$interface]}"
    
    echo "✅ 配置 $interface: $ip -> $external_ip (用户$user)"
    
    cat >> /etc/xray/serve.toml << TOMLEOF

[[inbounds]] # $interface ($ip -> $external_ip)
listen = "$ip"
port = 18889
protocol = "socks"
tag = "$tag_counter"

[inbounds.settings]
auth = "password"
udp = true
ip = "$ip"

# 允许多连接并发
[inbounds.settings.userLevel]
connIdle = 300
uplinkOnly = 5
downlinkOnly = 5

[[inbounds.settings.accounts]]
user = "$user"
pass = "123456"
Waiwangip = "$external_ip"

[[routing.rules]]
type = "field"
inboundTag = "$tag_counter"
outboundTag = "$tag_counter"

[[outbounds]]
sendThrough = "$ip"
protocol = "freedom"
tag = "$tag_counter"

# 连接优化设置
[outbounds.streamSettings]
sockopt = { tcpNoDelay = true, tcpKeepAliveIdle = 120 }

TOMLEOF

    ((tag_counter++))
done

echo "✅ 配置文件生成完成"

# ====== 创建服务 ======
echo "📋 创建系统服务..."

cat > /etc/systemd/system/xray.service << 'SERVICEEOF'
[Unit]
Description=The Xray Proxy Serve (Multi-IP)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xray -c /etc/xray/serve.toml
ExecReload=/bin/kill -HUP $MAINPID
ExecStop=/bin/kill -QUIT $MAINPID
Restart=always
RestartSec=10s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=xray
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30s

# 资源限制优化
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
SERVICEEOF

# ====== 简化防火墙 ======
echo "🔥 配置防火墙..."
if systemctl is-active firewalld >/dev/null 2>&1; then
    systemctl stop firewalld
    systemctl disable firewalld
fi

# 使用最简单的iptables规则
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -F

# 只保留基本安全规则
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

echo "✅ 防火墙优化完成 (默认ACCEPT策略)"

# ====== 启动服务 ======
echo "🚀 启动服务..."
systemctl daemon-reload
systemctl enable xray

if systemctl start xray; then
    echo "✅ 服务启动成功"
else
    echo "❌ 服务启动失败，查看日志:"
    journalctl -u xray -n 10 --no-pager
    exit 1
fi

# 等待服务完全启动
sleep 8

# ====== 验证安装 ======
echo "🔍 验证安装..."
working_count=0
total_count=${#CONFIG[@]}

echo ""
echo "端口监听状态:"
for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip user <<< "${CONFIG[$interface]}"
    
    if netstat -tlnp 2>/dev/null | grep -q "$ip:18889"; then
        echo "  ✅ $interface ($ip:18889) 正常监听"
        ((working_count++))
    else
        echo "  ❌ $interface ($ip:18889) 未监听"
    fi
done

# 检查进程
xray_pid=$(pgrep -f "xray.*serve.toml" | wc -l)
echo ""
echo "进程状态: $xray_pid 个Xray进程 (应该是1个)"

# ====== 生成最终配置信息 ======
echo ""
echo "📝 生成配置信息..."

# 控制台输出格式 (仿照别人的格式)
echo ""
echo "【脚本命令不可重复运行】，如需重新搭建，请【重置(重做)云服务器系统】。然后再运行脚本命令"
echo "#############################################################################"

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip user <<< "${CONFIG[$interface]}"
    external_ip="${EXTERNAL_IPS[$interface]}"
    
    printf "外网IP  %-15s 用户名  %-8s 密码  %-8s 端口  %-8s 内网IP  %s\n" \
           "$external_ip" "$user" "123456" "18889" "$ip"
done

echo "#############################################################################"

# 详细配置文件
cat > ~/Multi_IP_SOCKS5_Final_Config.txt << CONFIGEOF
#############################################################################
🎯 完整功能版多IP SOCKS5代理配置

📊 安装状态:
✅ 工作端口: $working_count/$total_count
✅ 进程数: $xray_pid (单进程管理)
✅ 配置文件: /etc/xray/serve.toml
✅ 自动检测外网IP: 已启用

📡 代理信息:
CONFIGEOF

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip user <<< "${CONFIG[$interface]}"
    external_ip="${EXTERNAL_IPS[$interface]}"
    
    cat >> ~/Multi_IP_SOCKS5_Final_Config.txt << CONFIGEOF2
📌 $interface:
   外网IP: $external_ip
   内网IP: $ip
   端口: 18889
   用户名: $user
   密码: 123456
   
   🧪 测试命令:
   curl --socks5 $user:123456@$external_ip:18889 https://httpbin.org/ip
   
CONFIGEOF2
done

cat >> ~/Multi_IP_SOCKS5_Final_Config.txt << CONFIGEOF3

🌐 Beanfun游戏优化: ✅ 已集成
🔧 连接冲突优化: ✅ 已解决

⚙️ 服务管理:
启动: systemctl start xray
停止: systemctl stop xray
重启: systemctl restart xray
状态: systemctl status xray
日志: journalctl -u xray -f

💡 使用建议:
1. 不同机器使用不同用户账号
2. 所有用户使用相同端口18889
3. 单进程管理，支持多用户并发连接
4. 每个IP自动检测对应的外网IP

🔧 故障排除:
如遇连接问题: systemctl restart xray
查看实时日志: journalctl -u xray -f
检查端口监听: netstat -tlnp | grep :18889

安装时间: $(date)
版本: newinstall.sh v1.0 (完整功能版)
#############################################################################
CONFIGEOF3

# ====== 创建管理工具 ======
cat > /usr/local/bin/socks5-info.sh << 'INFOEOF'
#!/bin/bash

echo "🔍 SOCKS5代理状态"
echo "=================="

echo "📊 服务状态: $(systemctl is-active xray)"
echo "📋 进程数量: $(pgrep -c -f 'xray.*serve.toml')"
echo ""

echo "🔌 端口监听:"
netstat -tlnp | grep xray | while IFS= read -r line; do
    echo "  $line"
done

echo ""
echo "📄 配置概览:"
if [ -f /etc/xray/serve.toml ]; then
    grep -E "(listen|user|Waiwangip)" /etc/xray/serve.toml | while IFS= read -r line; do
        echo "  $line"
    done
fi

echo ""
echo "🧪 测试命令示例:"
if [ -f /etc/xray/serve.toml ]; then
    grep -E "user.*vip" /etc/xray/serve.toml | head -3 | while IFS= read -r line; do
        user=$(echo "$line" | sed 's/.*"\(vip[0-9]*\)".*/\1/')
        external_ip=$(grep -A2 -B2 "$line" /etc/xray/serve.toml | grep Waiwangip | sed 's/.*"\([0-9.]*\)".*/\1/')
        echo "  curl --socks5 $user:123456@$external_ip:18889 https://httpbin.org/ip"
    done
fi
INFOEOF

chmod +x /usr/local/bin/socks5-info.sh

# ====== 最终报告 ======
echo ""
echo "=========================================="
echo "🎉 安装完成！"
echo "=========================================="

if [ $working_count -eq $total_count ] && [ $xray_pid -eq 1 ]; then
    echo "✅ 安装成功！所有功能正常"
    echo ""
    echo "🧪 快速测试:"
    for interface in "${!CONFIG[@]}"; do
        IFS=':' read -r ip user <<< "${CONFIG[$interface]}"
        external_ip="${EXTERNAL_IPS[$interface]}"
        echo "   curl --socks5 $user:123456@$external_ip:18889 https://httpbin.org/ip"
        break
    done
    echo ""
    echo "📄 详细配置: ~/Multi_IP_SOCKS5_Final_Config.txt"
    echo "🔧 状态检查: /usr/local/bin/socks5-info.sh"
else
    echo "⚠️ 部分功能可能异常"
    echo "   查看状态: systemctl status xray"
    echo "   查看日志: journalctl -u xray -n 20"
fi

# 清理临时文件
cd /
rm -rf /tmp/xray*

echo ""
echo "💡 注意: 脚本不可重复运行！"
echo "🔄 如需重装: 重置系统后再次运行"
echo ""
echo "🎊 享受稳定的多IP SOCKS5代理服务！"

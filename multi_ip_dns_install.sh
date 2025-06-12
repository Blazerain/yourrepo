#!/bin/bash

# 轻量版多公网IP服务器SOCKS5代理安装脚本 - 集成DNS优化版
# 低内存优化，固定端口，集成Beanfun防污染
# 端口: 11000, 12000, 13000
# 用户: vip1/123456
# 使用方法: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/multi_ip_dns_install.sh | bash
set -e

echo "=========================================="
echo "🚀 多IP SOCKS5安装 - DNS优化版"
echo "🌐 集成Beanfun游戏DNS优化、防污染"
echo "🔌 固定端口: 11000, 12000, 13000"
echo "👤 固定用户: vip1/123456"
echo "=========================================="

# 错误处理函数
error_exit() {
    echo "❌ 错误: $1" >&2
    echo "📍 脚本在第 $2 行停止执行" >&2
    exit 1
}

# 设置错误陷阱
trap 'error_exit "脚本执行失败" $LINENO' ERR

# 安全的命令执行函数
safe_execute() {
    local cmd="$1"
    local description="$2"
    
    echo "🔄 执行: $description"
    if eval "$cmd"; then
        echo "✅ 完成: $description"
        return 0
    else
        echo "❌ 失败: $description"
        return 1
    fi
}

# 检查root权限
if [[ $EUID -ne 0 ]]; then
   echo "❌ 需要root权限运行"
   exit 1
fi

# 获取IP信息（简化版）
get_ip() {
    local interface=$1
    ifconfig "$interface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1 | tr -d ' \n\r\t'
}

echo "🔍 检测网卡配置..."
eth0_ip=$(get_ip "eth0")
eth1_ip=$(get_ip "eth1")
eth1_1_ip=$(get_ip "eth1:1")

# 配置端口映射（固定）
declare -A CONFIG
if [[ -n "$eth0_ip" ]]; then
    CONFIG["eth0"]="$eth0_ip:11000"
    echo "✅ eth0: $eth0_ip -> 11000"
fi
if [[ -n "$eth1_ip" ]]; then
    CONFIG["eth1"]="$eth1_ip:12000"
    echo "✅ eth1: $eth1_ip -> 12000"
fi
if [[ -n "$eth1_1_ip" ]] && [[ "$eth1_1_ip" != "$eth1_ip" ]]; then
    CONFIG["eth1:1"]="$eth1_1_ip:13000"
    echo "✅ eth1:1: $eth1_1_ip -> 13000"
fi

if [[ ${#CONFIG[@]} -lt 2 ]]; then
    echo "❌ 检测到的IP少于2个，退出"
    exit 1
fi

# 停止现有服务
echo "🛑 停止现有服务..."
systemctl stop xray 2>/dev/null || true
systemctl stop xray-multi 2>/dev/null || true
pkill -f xray 2>/dev/null || true

# 安装依赖（包含DNS工具）
echo "📦 安装必要软件..."
yum -y install wget unzip jq bind-utils >/dev/null 2>&1

# ====== Beanfun域名DNS优化配置 ======
echo "=========================================="
echo "🌐 配置Beanfun游戏DNS优化（防污染）"
echo "=========================================="

# 备份DNS配置
safe_execute "cp /etc/resolv.conf /etc/resolv.conf.bak.\$(date +%Y%m%d_%H%M%S) 2>/dev/null || true" "备份DNS配置"

# 创建优化DNS配置
safe_execute "tee /etc/resolv.conf > /dev/null << 'DNSCONFIG'
# DNS配置 - Beanfun游戏优化版本 (多IP服务器)
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
nameserver 114.114.114.114
nameserver 208.67.222.222
options timeout:2
options attempts:3
options rotate
options edns0
DNSCONFIG" "创建DNS配置"

# 备份hosts文件
safe_execute "cp /etc/hosts /etc/hosts.bak.\$(date +%Y%m%d_%H%M%S)" "备份hosts文件"

# 移除旧的beanfun条目和污染IP
safe_execute "sed -i '/beanfun/d' /etc/hosts" "清理旧hosts条目"
safe_execute "sed -i '/31\.13\.106\.4/d' /etc/hosts" "清理污染IP"

echo "🔍 检测cdn.hk.beanfun.com的IP..."

# CDN IP检测逻辑
cdn_ip=""
echo "正在检测cdn.hk.beanfun.com..."

# 先尝试直接解析A记录
direct_ip=$(dig +short cdn.hk.beanfun.com @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+

# 下载xray（保持简洁）
echo "=========================================="
echo "⬬ 下载和安装Xray"
echo "=========================================="

cd /tmp
rm -f xray.zip xray

# 获取最新版本或使用默认版本
XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest 2>/dev/null | jq -r .tag_name 2>/dev/null || echo "v1.8.4")
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"

echo "📥 下载xray版本: $XRAY_VERSION"
if ! wget -q -O xray.zip "$XRAY_URL" --timeout=30; then
    echo "⚠️ 主下载失败，尝试备用地址..."
    if ! wget -q -O xray.zip "https://vip.123pan.cn/1816473155/%E6%8F%92%E4%BB%B6%E6%B3%A8%E5%86%8CIP/xray" --timeout=30; then
        error_exit "Xray下载失败" $LINENO
    fi
fi

unzip -q -o xray.zip

if [ ! -f "xray" ]; then
    error_exit "Xray解压失败，文件不存在" $LINENO
fi

mv xray /usr/local/bin/
chmod +x /usr/local/bin/xray
rm -f xray.zip

echo "✅ Xray安装成功"

# 创建目录
mkdir -p /etc/xray-multi /var/log/xray-multi

# ====== 为每个IP创建优化配置 ======
echo "=========================================="
echo "⚙️ 为每个IP创建DNS优化配置"
echo "=========================================="
config_count=0

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    
    config_file="/etc/xray-multi/config_${interface//:/_}.json"
    
    cat > "$config_file" << XRAYCONFIG
{
  "log": {
    "loglevel": "info",
    "access": "/var/log/xray-multi/access_${interface//:/_}.log",
    "error": "/var/log/xray-multi/error_${interface//:/_}.log"
  },
  "dns": {
    "servers": [
      {
        "address": "8.8.8.8",
        "port": 53,
        "domains": [
          "domain:beanfun.com",
          "domain:gamania.com",
          "domain:gnjoy.com"
        ]
      },
      {
        "address": "1.1.1.1",
        "port": 53,
        "domains": [
          "domain:amazonaws.com",
          "domain:elasticbeanstalk.com",
          "domain:cloudfront.net"
        ]
      },
      {
        "address": "208.67.222.222",
        "port": 53
      },
      {
        "address": "223.5.5.5",
        "port": 53
      }
    ],
    "clientIp": "1.2.3.4",
    "tag": "dns-inbound"
  },
  "inbounds": [
    {
      "tag": "socks5-in-${interface//:/_}",
      "port": $port,
      "protocol": "socks",
      "listen": "$ip",
      "settings": {
        "auth": "password",
        "accounts": [
          {"user": "vip1", "pass": "123456"}
        ],
        "udp": true,
        "ip": "$ip"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "domainsExcluded": ["courier.push.apple.com"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct-${interface//:/_}",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIPv4",
        "userLevel": 0
      }
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {
        "response": {
          "type": "http"
        }
      }
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "domain": [
          "domain:beanfun.com",
          "domain:gamania.com", 
          "domain:gnjoy.com",
          "hk.beanfun.com",
          "bfweb.hk.beanfun.com",
          "cdn.hk.beanfun.com",
          "csp.hk.beanfun.com",
          "tw.beanfun.com",
          "csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com"
        ],
        "outboundTag": "direct-${interface//:/_}"
      },
      {
        "type": "field",
        "ip": [
          "112.121.124.11/32",
          "112.121.124.69/32",
          "$cdn_ip/32",
          "18.167.13.186/32",
          "18.163.12.31/32",
          "202.80.107.11/32",
          "52.147.74.109/32"
        ],
        "outboundTag": "direct-${interface//:/_}"
      },
      {
        "type": "field",
        "ip": [
          "31.13.106.4/32"
        ],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "ip": [
          "127.0.0.0/8",
          "10.0.0.0/8",
          "172.16.0.0/12",
          "192.168.0.0/16"
        ],
        "outboundTag": "direct-${interface//:/_}"
      }
    ]
  }
}
XRAYCONFIG

    echo "✅ 配置: $interface ($ip:$port) - 包含Beanfun优化"
    
    # 验证配置文件语法
    if /usr/local/bin/xray test -config "$config_file" >/dev/null 2>&1; then
        echo "  ✅ 配置语法正确"
    else
        echo "  ⚠️ 配置语法可能有问题，但继续执行"
    fi
    
    config_count=$((config_count + 1))
done

# 创建简化启动脚本
echo "📝 创建启动脚本..."
cat > /usr/local/bin/xray-multi-start.sh << 'STARTSCRIPT'
#!/bin/bash

CONFIG_DIR="/etc/xray-multi"
PID_FILE="/var/run/xray-multi.pid"

echo "启动多IP代理..."

# 清理
rm -f "$PID_FILE"
pkill -f "xray run -config /etc/xray-multi" 2>/dev/null || true

PIDS=()

for config in "$CONFIG_DIR"/config_*.json; do
    if [ -f "$config" ]; then
        /usr/local/bin/xray run -config "$config" >/dev/null 2>&1 &
        PID=$!
        PIDS+=($PID)
        echo "启动: $(basename "$config") PID=$PID"
        sleep 1
    fi
done

if [ ${#PIDS[@]} -gt 0 ]; then
    printf '%s\n' "${PIDS[@]}" > "$PID_FILE"
    echo "启动完成: ${#PIDS[@]} 个实例"
    exit 0
else
    echo "启动失败"
    exit 1
fi
STARTSCRIPT

cat > /usr/local/bin/xray-multi-stop.sh << 'STOPSCRIPT'
#!/bin/bash

PID_FILE="/var/run/xray-multi.pid"

echo "停止服务..."

if [ -f "$PID_FILE" ]; then
    while read -r pid; do
        kill -TERM "$pid" 2>/dev/null || true
    done < "$PID_FILE"
    sleep 2
    while read -r pid; do
        kill -KILL "$pid" 2>/dev/null || true
    done < "$PID_FILE"
    rm -f "$PID_FILE"
fi

pkill -f "xray run -config /etc/xray-multi" 2>/dev/null || true
echo "停止完成"
STOPSCRIPT

chmod +x /usr/local/bin/xray-multi-start.sh
chmod +x /usr/local/bin/xray-multi-stop.sh

# 创建systemd服务
echo "📋 创建系统服务..."
cat > /etc/systemd/system/xray-multi.service << 'SYSTEMDCONFIG'
[Unit]
Description=Xray Multi-IP Service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/xray-multi-start.sh
ExecStop=/usr/local/bin/xray-multi-stop.sh
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
SYSTEMDCONFIG

# 配置防火墙（保持简化但开放所有端口）
echo "=========================================="
echo "🔥 配置防火墙"
echo "=========================================="
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true

# 简单iptables规则
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT  
iptables -P OUTPUT ACCEPT
iptables -F

iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 11000 -j ACCEPT
iptables -A INPUT -p udp --dport 11000 -j ACCEPT
iptables -A INPUT -p tcp --dport 12000 -j ACCEPT
iptables -A INPUT -p udp --dport 12000 -j ACCEPT
iptables -A INPUT -p tcp --dport 13000 -j ACCEPT
iptables -A INPUT -p udp --dport 13000 -j ACCEPT

# 保存防火墙规则
service iptables save 2>/dev/null || iptables-save > /etc/sysconfig/iptables 2>/dev/null || true

echo "✅ 防火墙配置完成，已开放: 11000, 12000, 13000"

# 启用IP转发
echo "启用IP转发..."
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1 || true

# ====== 创建管理工具 ======
echo "=========================================="
echo "🔧 创建管理和测试工具"
echo "=========================================="

# DNS测试脚本
cat > /usr/local/bin/beanfun-dns-test.sh << 'DNSTESTSCRIPT'
#!/bin/bash

echo "==========================================="
echo "🌐 Beanfun DNS测试工具 (多IP版)"
echo "==========================================="

declare -A EXPECTED_IPS
EXPECTED_IPS["hk.beanfun.com"]="112.121.124.11"
EXPECTED_IPS["bfweb.hk.beanfun.com"]="112.121.124.69"
EXPECTED_IPS["csp.hk.beanfun.com"]="18.167.13.186"
EXPECTED_IPS["tw.beanfun.com"]="202.80.107.11"
EXPECTED_IPS["beanfun.com"]="52.147.74.109"

echo "🔍 检查关键域名解析:"
for domain in "${!EXPECTED_IPS[@]}"; do
    expected="${EXPECTED_IPS[$domain]}"
    current=$(getent hosts $domain 2>/dev/null | awk '{print $1}' | head -1)
    
    echo -n "  $domain: "
    if [ "$current" = "$expected" ]; then
        echo "✅ $current"
    else
        echo "❌ $current (期望: $expected)"
    fi
done

echo -n "  cdn.hk.beanfun.com: "
cdn_ip=$(getent hosts cdn.hk.beanfun.com 2>/dev/null | awk '{print $1}' | head -1)
if [ -n "$cdn_ip" ]; then
    echo "✅ $cdn_ip (hosts配置)"
else
    echo "❌ 解析失败"
fi

echo ""
echo "🔧 多IP代理测试:"
# 检查所有代理端口
for port in 11000 12000 13000; do
    echo -n "  端口 $port: "
    if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        echo "✅ 监听正常"
    else
        echo "❌ 未监听"
    fi
done

echo ""
echo "📊 服务状态:"
if systemctl is-active --quiet xray-multi; then
    echo "  ✅ xray-multi 服务运行中"
else
    echo "  ❌ xray-multi 服务未运行"
fi

if [ -f /var/run/xray-multi.pid ]; then
    pid_count=$(cat /var/run/xray-multi.pid | wc -l)
    echo "  📋 运行实例数: $pid_count"
else
    echo "  📋 PID文件不存在"
fi
DNSTESTSCRIPT

chmod +x /usr/local/bin/beanfun-dns-test.sh

# 多IP端口检测脚本
cat > /usr/local/bin/multi-ip-status.sh << 'STATUSSCRIPT'
#!/bin/bash

echo "==========================================="
echo "📊 多IP代理状态检查"
echo "==========================================="

# 检测IP配置
echo "🔍 网卡IP配置:"
for interface in eth0 eth1 eth1:1; do
    ip=$(ifconfig "$interface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
    if [ -n "$ip" ]; then
        echo "  $interface: $ip"
    fi
done

echo ""
echo "🔌 端口监听状态:"
declare -A PORT_MAP
PORT_MAP["11000"]="eth0"
PORT_MAP["12000"]="eth1"  
PORT_MAP["13000"]="eth1:1"

for port in "${!PORT_MAP[@]}"; do
    interface="${PORT_MAP[$port]}"
    echo -n "  $interface ($port): "
    if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        echo "✅ 正常监听"
    else
        echo "❌ 未监听"
    fi
done

echo ""
echo "⚙️ 服务状态:"
if systemctl is-active --quiet xray-multi; then
    echo "  ✅ systemd服务: 运行中"
else
    echo "  ❌ systemd服务: 停止"
fi

if [ -f /var/run/xray-multi.pid ]; then
    echo "  📋 PID文件存在"
    while read -r pid; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "    ✅ 进程 $pid: 运行中"
        else
            echo "    ❌ 进程 $pid: 已停止"
        fi
    done < /var/run/xray-multi.pid
else
    echo "  📋 PID文件不存在"
fi

echo ""
echo "📂 配置文件:"
for config in /etc/xray-multi/config_*.json; do
    if [ -f "$config" ]; then
        echo "  ✅ $(basename "$config")"
    fi
done

echo ""
echo "🔧 管理命令:"
echo "  启动: systemctl start xray-multi"
echo "  停止: systemctl stop xray-multi"
echo "  重启: systemctl restart xray-multi"
echo "  手动启动: /usr/local/bin/xray-multi-start.sh"
echo "  DNS测试: /usr/local/bin/beanfun-dns-test.sh"
STATUSSCRIPT

chmod +x /usr/local/bin/multi-ip-status.sh

echo "✅ 管理工具创建完成"

# 启动服务
echo "🚀 启动服务..."
systemctl daemon-reload
systemctl enable xray-multi

echo "手动启动测试..."
if /usr/local/bin/xray-multi-start.sh; then
    echo "✅ 手动启动成功"
    /usr/local/bin/xray-multi-stop.sh
    sleep 2
    
    echo "通过systemd启动..."
    systemctl start xray-multi
    
    if systemctl is-active --quiet xray-multi; then
        echo "✅ systemd启动成功"
    else
        echo "❌ systemd启动失败"
    fi
else
    echo "❌ 手动启动失败"
fi

# 验证端口
echo ""
echo "🔍 验证端口监听..."
sleep 3
for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    if netstat -tlnp 2>/dev/null | grep -q "$ip:$port "; then
        echo "✅ $interface ($ip:$port) 正常"
    else
        echo "❌ $interface ($ip:$port) 异常"
    fi
done

# 获取公网IP
SERVER_IP=$(curl -s -4 ifconfig.me --timeout=10 2>/dev/null || echo "未知")

# 生成配置文件
echo ""
echo "📝 生成配置文件..."
cat > ~/Multi_IP_Config.txt << USERCONFIG
#############################################################################
🎯 轻量版多IP SOCKS5代理配置

📡 服务器公网IP: $SERVER_IP

🔌 代理配置:
USERCONFIG

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    cat >> ~/Multi_IP_Config.txt << INTERFACECONFIG
📌 $interface (内网: $ip):
   代理地址: $SERVER_IP:$port
   用户名: vip1
   密码: 123456
   测试命令: curl --socks5 vip1:123456@$SERVER_IP:$port https://httpbin.org/ip

INTERFACECONFIG
done

cat >> ~/Multi_IP_Config.txt << USERCONFIG

⚙️ 服务管理:
启动: systemctl start xray-multi
停止: systemctl stop xray-multi
状态: systemctl status xray-multi
重启: systemctl restart xray-multi

🔧 手动管理:
启动: /usr/local/bin/xray-multi-start.sh
停止: /usr/local/bin/xray-multi-stop.sh

📂 文件位置:
配置目录: /etc/xray-multi/
日志目录: /var/log/xray-multi/
PID文件: /var/run/xray-multi.pid

🎮 客户端配置:
- 代理类型: SOCKS5
- 服务器: $SERVER_IP  
- 端口: 11000/12000/13000 (选择一个)
- 用户名: vip1
- 密码: 123456
- 启用DNS解析: 是

安装时间: $(date)
版本: 轻量版 v1.0 (低内存优化)
#############################################################################
USERCONFIG

# 最终状态报告
echo ""
echo "=========================================="
echo "🎉 轻量版安装完成！"
echo "=========================================="
echo "🌐 服务器: $SERVER_IP"
echo "🔌 端口: 11000, 12000, 13000"
echo "👤 用户: vip1/123456"
echo "📄 配置文件: ~/Multi_IP_Config.txt"
echo ""

service_status="未知"
if systemctl is-active --quiet xray-multi; then
    service_status="运行中"
    echo "✅ 服务状态: $service_status"
else
    service_status="停止"
    echo "❌ 服务状态: $service_status"
    echo ""
    echo "🔧 调试命令:"
    echo "systemctl status xray-multi"
    echo "/usr/local/bin/xray-multi-start.sh"
fi

echo ""
echo "🧪 快速测试 (选择一个端口):"
for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    echo "curl --socks5 vip1:123456@$SERVER_IP:$port https://httpbin.org/ip"
    break
done

echo ""
echo "📋 服务管理:"
echo "启动: systemctl start xray-multi"
echo "停止: systemctl stop xray-multi"
echo "状态: systemctl status xray-multi"

# 清理
cd /
rm -rf /tmp/xray*

echo ""
echo "🎊 安装完成！低内存优化版本！" | head -1)

if [ -n "$direct_ip" ]; then
    cdn_ip="$direct_ip"
    echo "✅ 直接解析到IP: $cdn_ip"
else
    # 如果是CNAME，解析CNAME目标
    echo "检测到CNAME，正在解析最终IP..."
    cname_target=$(dig +short cdn.hk.beanfun.com @8.8.8.8 2>/dev/null | grep -v '^[0-9]' | head -1)
    if [ -n "$cname_target" ]; then
        echo "CNAME目标: $cname_target"
        final_ips=$(dig +short "$cname_target" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+

# 下载xray（简化）
echo "⬇️ 下载xray..."
cd /tmp
rm -f xray.zip xray
if ! wget -q -O xray.zip "https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-64.zip" --timeout=30; then
    echo "❌ 下载失败"
    exit 1
fi

unzip -q -o xray.zip
mv xray /usr/local/bin/
chmod +x /usr/local/bin/xray
rm -f xray.zip

# 创建目录
mkdir -p /etc/xray-multi /var/log/xray-multi

# 为每个IP创建最简配置
echo "⚙️ 创建配置文件..."
config_count=0

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    
    config_file="/etc/xray-multi/config_${interface//:/_}.json"
    
    cat > "$config_file" << XRAYCONFIG
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $port,
      "protocol": "socks",
      "listen": "$ip",
      "settings": {
        "auth": "password",
        "accounts": [
          {"user": "vip1", "pass": "123456"}
        ],
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
XRAYCONFIG

    echo "✅ 配置: $interface ($ip:$port)"
    config_count=$((config_count + 1))
done

# 创建简化启动脚本
echo "📝 创建启动脚本..."
cat > /usr/local/bin/xray-multi-start.sh << 'STARTSCRIPT'
#!/bin/bash

CONFIG_DIR="/etc/xray-multi"
PID_FILE="/var/run/xray-multi.pid"

echo "启动多IP代理..."

# 清理
rm -f "$PID_FILE"
pkill -f "xray run -config /etc/xray-multi" 2>/dev/null || true

PIDS=()

for config in "$CONFIG_DIR"/config_*.json; do
    if [ -f "$config" ]; then
        /usr/local/bin/xray run -config "$config" >/dev/null 2>&1 &
        PID=$!
        PIDS+=($PID)
        echo "启动: $(basename "$config") PID=$PID"
        sleep 1
    fi
done

if [ ${#PIDS[@]} -gt 0 ]; then
    printf '%s\n' "${PIDS[@]}" > "$PID_FILE"
    echo "启动完成: ${#PIDS[@]} 个实例"
    exit 0
else
    echo "启动失败"
    exit 1
fi
STARTSCRIPT

cat > /usr/local/bin/xray-multi-stop.sh << 'STOPSCRIPT'
#!/bin/bash

PID_FILE="/var/run/xray-multi.pid"

echo "停止服务..."

if [ -f "$PID_FILE" ]; then
    while read -r pid; do
        kill -TERM "$pid" 2>/dev/null || true
    done < "$PID_FILE"
    sleep 2
    while read -r pid; do
        kill -KILL "$pid" 2>/dev/null || true
    done < "$PID_FILE"
    rm -f "$PID_FILE"
fi

pkill -f "xray run -config /etc/xray-multi" 2>/dev/null || true
echo "停止完成"
STOPSCRIPT

chmod +x /usr/local/bin/xray-multi-start.sh
chmod +x /usr/local/bin/xray-multi-stop.sh

# 创建systemd服务
echo "📋 创建系统服务..."
cat > /etc/systemd/system/xray-multi.service << 'SYSTEMDCONFIG'
[Unit]
Description=Xray Multi-IP Service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/xray-multi-start.sh
ExecStop=/usr/local/bin/xray-multi-stop.sh
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
SYSTEMDCONFIG

# 配置防火墙（简化）
echo "🔥 配置防火墙..."
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true

# 简单iptables规则
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT  
iptables -P OUTPUT ACCEPT
iptables -F

iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 11000 -j ACCEPT
iptables -A INPUT -p tcp --dport 12000 -j ACCEPT
iptables -A INPUT -p tcp --dport 13000 -j ACCEPT

# 启动服务
echo "🚀 启动服务..."
systemctl daemon-reload
systemctl enable xray-multi

echo "手动启动测试..."
if /usr/local/bin/xray-multi-start.sh; then
    echo "✅ 手动启动成功"
    /usr/local/bin/xray-multi-stop.sh
    sleep 2
    
    echo "通过systemd启动..."
    systemctl start xray-multi
    
    if systemctl is-active --quiet xray-multi; then
        echo "✅ systemd启动成功"
    else
        echo "❌ systemd启动失败"
    fi
else
    echo "❌ 手动启动失败"
fi

# 验证端口
echo ""
echo "🔍 验证端口监听..."
sleep 3
for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    if netstat -tlnp 2>/dev/null | grep -q "$ip:$port "; then
        echo "✅ $interface ($ip:$port) 正常"
    else
        echo "❌ $interface ($ip:$port) 异常"
    fi
done

# 获取公网IP
SERVER_IP=$(curl -s -4 ifconfig.me --timeout=10 2>/dev/null || echo "未知")

# 生成配置文件
echo ""
echo "📝 生成配置文件..."
cat > ~/Multi_IP_Config.txt << USERCONFIG
#############################################################################
🎯 轻量版多IP SOCKS5代理配置

📡 服务器公网IP: $SERVER_IP

🔌 代理配置:
USERCONFIG

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    cat >> ~/Multi_IP_Config.txt << INTERFACECONFIG
📌 $interface (内网: $ip):
   代理地址: $SERVER_IP:$port
   用户名: vip1
   密码: 123456
   测试命令: curl --socks5 vip1:123456@$SERVER_IP:$port https://httpbin.org/ip

INTERFACECONFIG
done

cat >> ~/Multi_IP_Config.txt << USERCONFIG

⚙️ 服务管理:
启动: systemctl start xray-multi
停止: systemctl stop xray-multi
状态: systemctl status xray-multi
重启: systemctl restart xray-multi

🔧 手动管理:
启动: /usr/local/bin/xray-multi-start.sh
停止: /usr/local/bin/xray-multi-stop.sh

📂 文件位置:
配置目录: /etc/xray-multi/
日志目录: /var/log/xray-multi/
PID文件: /var/run/xray-multi.pid

🎮 客户端配置:
- 代理类型: SOCKS5
- 服务器: $SERVER_IP  
- 端口: 11000/12000/13000 (选择一个)
- 用户名: vip1
- 密码: 123456
- 启用DNS解析: 是

安装时间: $(date)
版本: 轻量版 v1.0 (低内存优化)
#############################################################################
USERCONFIG

# 最终状态报告
echo ""
echo "=========================================="
echo "🎉 轻量版安装完成！"
echo "=========================================="
echo "🌐 服务器: $SERVER_IP"
echo "🔌 端口: 11000, 12000, 13000"
echo "👤 用户: vip1/123456"
echo "📄 配置文件: ~/Multi_IP_Config.txt"
echo ""

service_status="未知"
if systemctl is-active --quiet xray-multi; then
    service_status="运行中"
    echo "✅ 服务状态: $service_status"
else
    service_status="停止"
    echo "❌ 服务状态: $service_status"
    echo ""
    echo "🔧 调试命令:"
    echo "systemctl status xray-multi"
    echo "/usr/local/bin/xray-multi-start.sh"
fi

echo ""
echo "🧪 快速测试 (选择一个端口):"
for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    echo "curl --socks5 vip1:123456@$SERVER_IP:$port https://httpbin.org/ip"
    break
done

echo ""
echo "📋 服务管理:"
echo "启动: systemctl start xray-multi"
echo "停止: systemctl stop xray-multi"
echo "状态: systemctl status xray-multi"

# 清理
cd /
rm -rf /tmp/xray*

echo ""
echo "🎊 安装完成！低内存优化版本！")
        if [ -n "$final_ips" ]; then
            # 选择第一个IP
            cdn_ip=$(echo "$final_ips" | head -1)
            echo "✅ CNAME解析到IP: $cdn_ip"
            echo "其他可用IP: $(echo "$final_ips" | tr '\n' ' ')"
        fi
    fi
fi

# 如果所有检测都失败，使用合理的默认值
if [ -z "$cdn_ip" ]; then
    cdn_ip="112.121.124.69"
    echo "⚠️ 自动检测失败，使用默认IP: $cdn_ip"
fi

# 添加完整的Beanfun域名优化
safe_execute "tee -a /etc/hosts > /dev/null << HOSTSCONFIG

# Beanfun游戏平台域名 - 防DNS污染优化 \$(date)
112.121.124.11 hk.beanfun.com
112.121.124.69 bfweb.hk.beanfun.com
$cdn_ip cdn.hk.beanfun.com
18.167.13.186 csp.hk.beanfun.com
18.163.12.31 csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com
202.80.107.11 tw.beanfun.com
52.147.74.109 beanfun.com

# 阻止DNS污染IP
127.0.0.1 31.13.106.4
HOSTSCONFIG" "添加Beanfun域名映射"

echo "✅ Beanfun域名DNS优化完成"

# 下载xray（简化）
echo "⬇️ 下载xray..."
cd /tmp
rm -f xray.zip xray
if ! wget -q -O xray.zip "https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-64.zip" --timeout=30; then
    echo "❌ 下载失败"
    exit 1
fi

unzip -q -o xray.zip
mv xray /usr/local/bin/
chmod +x /usr/local/bin/xray
rm -f xray.zip

# 创建目录
mkdir -p /etc/xray-multi /var/log/xray-multi

# 为每个IP创建最简配置
echo "⚙️ 创建配置文件..."
config_count=0

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    
    config_file="/etc/xray-multi/config_${interface//:/_}.json"
    
    cat > "$config_file" << XRAYCONFIG
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $port,
      "protocol": "socks",
      "listen": "$ip",
      "settings": {
        "auth": "password",
        "accounts": [
          {"user": "vip1", "pass": "123456"}
        ],
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
XRAYCONFIG

    echo "✅ 配置: $interface ($ip:$port)"
    config_count=$((config_count + 1))
done

# 创建简化启动脚本
echo "📝 创建启动脚本..."
cat > /usr/local/bin/xray-multi-start.sh << 'STARTSCRIPT'
#!/bin/bash

CONFIG_DIR="/etc/xray-multi"
PID_FILE="/var/run/xray-multi.pid"

echo "启动多IP代理..."

# 清理
rm -f "$PID_FILE"
pkill -f "xray run -config /etc/xray-multi" 2>/dev/null || true

PIDS=()

for config in "$CONFIG_DIR"/config_*.json; do
    if [ -f "$config" ]; then
        /usr/local/bin/xray run -config "$config" >/dev/null 2>&1 &
        PID=$!
        PIDS+=($PID)
        echo "启动: $(basename "$config") PID=$PID"
        sleep 1
    fi
done

if [ ${#PIDS[@]} -gt 0 ]; then
    printf '%s\n' "${PIDS[@]}" > "$PID_FILE"
    echo "启动完成: ${#PIDS[@]} 个实例"
    exit 0
else
    echo "启动失败"
    exit 1
fi
STARTSCRIPT

cat > /usr/local/bin/xray-multi-stop.sh << 'STOPSCRIPT'
#!/bin/bash

PID_FILE="/var/run/xray-multi.pid"

echo "停止服务..."

if [ -f "$PID_FILE" ]; then
    while read -r pid; do
        kill -TERM "$pid" 2>/dev/null || true
    done < "$PID_FILE"
    sleep 2
    while read -r pid; do
        kill -KILL "$pid" 2>/dev/null || true
    done < "$PID_FILE"
    rm -f "$PID_FILE"
fi

pkill -f "xray run -config /etc/xray-multi" 2>/dev/null || true
echo "停止完成"
STOPSCRIPT

chmod +x /usr/local/bin/xray-multi-start.sh
chmod +x /usr/local/bin/xray-multi-stop.sh

# 创建systemd服务
echo "📋 创建系统服务..."
cat > /etc/systemd/system/xray-multi.service << 'SYSTEMDCONFIG'
[Unit]
Description=Xray Multi-IP Service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/xray-multi-start.sh
ExecStop=/usr/local/bin/xray-multi-stop.sh
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
SYSTEMDCONFIG

# 配置防火墙（简化）
echo "🔥 配置防火墙..."
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true

# 简单iptables规则
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT  
iptables -P OUTPUT ACCEPT
iptables -F

iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 11000 -j ACCEPT
iptables -A INPUT -p tcp --dport 12000 -j ACCEPT
iptables -A INPUT -p tcp --dport 13000 -j ACCEPT

# 启动服务
echo "🚀 启动服务..."
systemctl daemon-reload
systemctl enable xray-multi

echo "手动启动测试..."
if /usr/local/bin/xray-multi-start.sh; then
    echo "✅ 手动启动成功"
    /usr/local/bin/xray-multi-stop.sh
    sleep 2
    
    echo "通过systemd启动..."
    systemctl start xray-multi
    
    if systemctl is-active --quiet xray-multi; then
        echo "✅ systemd启动成功"
    else
        echo "❌ systemd启动失败"
    fi
else
    echo "❌ 手动启动失败"
fi

# 验证端口
echo ""
echo "🔍 验证端口监听..."
sleep 3
for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    if netstat -tlnp 2>/dev/null | grep -q "$ip:$port "; then
        echo "✅ $interface ($ip:$port) 正常"
    else
        echo "❌ $interface ($ip:$port) 异常"
    fi
done

# 获取公网IP
SERVER_IP=$(curl -s -4 ifconfig.me --timeout=10 2>/dev/null || echo "未知")

# 生成配置文件
echo ""
echo "📝 生成配置文件..."
cat > ~/Multi_IP_Config.txt << USERCONFIG
#############################################################################
🎯 轻量版多IP SOCKS5代理配置

📡 服务器公网IP: $SERVER_IP

🔌 代理配置:
USERCONFIG

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    cat >> ~/Multi_IP_Config.txt << INTERFACECONFIG
📌 $interface (内网: $ip):
   代理地址: $SERVER_IP:$port
   用户名: vip1
   密码: 123456
   测试命令: curl --socks5 vip1:123456@$SERVER_IP:$port https://httpbin.org/ip

INTERFACECONFIG
done

cat >> ~/Multi_IP_Config.txt << USERCONFIG

⚙️ 服务管理:
启动: systemctl start xray-multi
停止: systemctl stop xray-multi
状态: systemctl status xray-multi
重启: systemctl restart xray-multi

🔧 手动管理:
启动: /usr/local/bin/xray-multi-start.sh
停止: /usr/local/bin/xray-multi-stop.sh

📂 文件位置:
配置目录: /etc/xray-multi/
日志目录: /var/log/xray-multi/
PID文件: /var/run/xray-multi.pid

🎮 客户端配置:
- 代理类型: SOCKS5
- 服务器: $SERVER_IP  
- 端口: 11000/12000/13000 (选择一个)
- 用户名: vip1
- 密码: 123456
- 启用DNS解析: 是

安装时间: $(date)
版本: 轻量版 v1.0 (低内存优化)
#############################################################################
USERCONFIG

# 最终状态报告
echo ""
echo "=========================================="
echo "🎉 轻量版安装完成！"
echo "=========================================="
echo "🌐 服务器: $SERVER_IP"
echo "🔌 端口: 11000, 12000, 13000"
echo "👤 用户: vip1/123456"
echo "📄 配置文件: ~/Multi_IP_Config.txt"
echo ""

service_status="未知"
if systemctl is-active --quiet xray-multi; then
    service_status="运行中"
    echo "✅ 服务状态: $service_status"
else
    service_status="停止"
    echo "❌ 服务状态: $service_status"
    echo ""
    echo "🔧 调试命令:"
    echo "systemctl status xray-multi"
    echo "/usr/local/bin/xray-multi-start.sh"
fi

echo ""
echo "🧪 快速测试 (选择一个端口):"
for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    echo "curl --socks5 vip1:123456@$SERVER_IP:$port https://httpbin.org/ip"
    break
done

echo ""
echo "📋 服务管理:"
echo "启动: systemctl start xray-multi"
echo "停止: systemctl stop xray-multi"
echo "状态: systemctl status xray-multi"

# 清理
cd /
rm -rf /tmp/xray*

echo ""
echo "🎊 安装完成！低内存优化版本！"
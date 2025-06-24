#!/bin/bash

# 稳定版多公网IP服务器SOCKS5代理安装脚本
# 修复语法错误，简化复杂操作
# 端口: 11000, 12000, 13000
# 用户: vip1-vip10/123456 (支持多用户)
# 使用方法: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/multi_ip_dns_install.sh | bash
set -e

echo "=========================================="
echo "🚀 稳定版多IP SOCKS5安装"
echo "🌐 集成Beanfun游戏DNS优化"
echo "🔌 固定端口: 11000, 12000, 13000"
echo "👤 多用户: vip1-vip10/123456"
echo "=========================================="

# 检查root权限
if [[ $EUID -ne 0 ]]; then
   echo "❌ 需要root权限运行"
   exit 1
fi

# 简化的IP获取函数
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

# 安装依赖
echo "📦 安装必要软件..."
yum -y install wget unzip jq bind-utils net-tools >/dev/null 2>&1

# ====== DNS优化配置 ======
echo "=========================================="
echo "🌐 配置DNS优化"
echo "=========================================="

# 备份DNS配置
cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

# 创建DNS配置
cat > /etc/resolv.conf << 'EOF'
# DNS配置 - 多IP服务器优化版本
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
nameserver 114.114.114.114
nameserver 208.67.222.222
options timeout:2
options attempts:3
options rotate
options edns0
EOF

echo "✅ DNS配置完成"

# 备份hosts文件
cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d_%H%M%S)

# 清理旧的beanfun条目
sed -i '/beanfun/d' /etc/hosts
sed -i '/31\.13\.106\.4/d' /etc/hosts

echo "🔍 检测cdn.hk.beanfun.com的IP..."

# 简化的CDN IP检测
cdn_ip=""
# 使用更简单的nslookup命令
cdn_lookup=$(nslookup cdn.hk.beanfun.com 8.8.8.8 2>/dev/null | grep 'Address:' | tail -1 | awk '{print $2}')

if [[ "$cdn_lookup" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    cdn_ip="$cdn_lookup"
    echo "✅ 检测到CDN IP: $cdn_ip"
else
    # 备用检测方法
    cdn_ip=$(dig +short cdn.hk.beanfun.com @8.8.8.8 2>/dev/null | head -1)
    if [[ "$cdn_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "✅ 使用dig检测到CDN IP: $cdn_ip"
    else
        cdn_ip="112.121.124.69"
        echo "⚠️ 自动检测失败，使用默认IP: $cdn_ip"
    fi
fi

# 添加Beanfun域名映射（使用简单的追加方式）
cat >> /etc/hosts << EOF

# Beanfun游戏平台域名 - 防DNS污染优化 $(date)
112.121.124.11 hk.beanfun.com
112.121.124.69 bfweb.hk.beanfun.com
$cdn_ip cdn.hk.beanfun.com
18.167.13.186 csp.hk.beanfun.com
18.163.12.31 csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com
202.80.107.11 tw.beanfun.com
52.147.74.109 beanfun.com

# 阻止DNS污染IP
127.0.0.1 31.13.106.4
EOF

echo "✅ Beanfun域名DNS优化完成"

# ====== 下载和安装Xray ======
echo "=========================================="
echo "⬬ 下载和安装Xray"
echo "=========================================="

cd /tmp
rm -f xray.zip xray

# 简化下载逻辑
echo "📥 下载xray..."
if ! wget -q -O xray.zip "https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-64.zip" --timeout=30; then
    echo "⚠️ 主下载失败，尝试备用地址..."
    if ! wget -q -O xray.zip "https://vip.123pan.cn/1816473155/%E6%8F%92%E4%BB%B6%E6%B3%A8%E5%86%8CIP/xray" --timeout=30; then
        echo "❌ Xray下载失败"
        exit 1
    fi
fi

unzip -q -o xray.zip

if [ ! -f "xray" ]; then
    echo "❌ Xray解压失败"
    exit 1
fi

mv xray /usr/local/bin/
chmod +x /usr/local/bin/xray
rm -f xray.zip

echo "✅ Xray安装成功"

# 创建目录
mkdir -p /etc/xray-multi /var/log/xray-multi

# ====== 为每个IP创建配置 ======
echo "=========================================="
echo "⚙️ 为每个IP创建配置"
echo "=========================================="

config_count=0
for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    
    config_file="/etc/xray-multi/config_${interface//:/_}.json"
    
    # 创建配置文件（避免复杂的heredoc）
    cat > "$config_file" << CONFIGEOF
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
          {
            "user": "vip1",
            "pass": "123456"
          },
          {
            "user": "vip2", 
            "pass": "123456"
          },
          {
            "user": "vip3",
            "pass": "123456"
          },
          {
            "user": "vip4",
            "pass": "123456"
          },
          {
            "user": "vip5",
            "pass": "123456"
          },
          {
            "user": "vip6",
            "pass": "123456"
          },
          {
            "user": "vip7",
            "pass": "123456"
          },
          {
            "user": "vip8",
            "pass": "123456"
          },
          {
            "user": "vip9",
            "pass": "123456"
          },
          {
            "user": "vip10",
            "pass": "123456"
          }
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
CONFIGEOF

    echo "✅ 配置: $interface ($ip:$port)"
    
    # 验证配置语法
    if /usr/local/bin/xray test -config "$config_file" >/dev/null 2>&1; then
        echo "  ✅ 配置语法正确"
    else
        echo "  ⚠️ 配置语法警告，但继续执行"
    fi
    
    config_count=$((config_count + 1))
done

# ====== 创建启动脚本 ======
echo "📝 创建启动脚本..."
cat > /usr/local/bin/xray-multi-start.sh << 'STARTEOF'
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
STARTEOF

cat > /usr/local/bin/xray-multi-stop.sh << 'STOPEOF'
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
STOPEOF

chmod +x /usr/local/bin/xray-multi-start.sh
chmod +x /usr/local/bin/xray-multi-stop.sh

# ====== 创建systemd服务 ======
echo "📋 创建systemd服务..."
cat > /etc/systemd/system/xray-multi.service << 'SERVICEEOF'
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
SERVICEEOF

# ====== 配置防火墙 ======
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

echo "✅ 防火墙配置完成"

# 启用IP转发
echo "启用IP转发..."
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1 || true

# ====== 创建管理工具 ======
echo "🔧 创建管理工具..."

# DNS测试脚本
cat > /usr/local/bin/beanfun-dns-test.sh << 'DNSEOF'
#!/bin/bash

echo "==========================================="
echo "🌐 Beanfun DNS测试工具"
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
    echo "✅ $cdn_ip"
else
    echo "❌ 解析失败"
fi

echo ""
echo "🔧 代理端口状态:"
for port in 11000 12000 13000; do
    echo -n "  端口 $port: "
    if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        echo "✅ 监听正常"
    else
        echo "❌ 未监听"
    fi
done
DNSEOF

chmod +x /usr/local/bin/beanfun-dns-test.sh

# 配置检查和修复工具
cat > /usr/local/bin/xray-config-check.sh << 'CHECKEOF'
#!/bin/bash

echo "==========================================="
echo "🔧 Xray配置检查和修复工具"
echo "==========================================="

CONFIG_DIR="/etc/xray-multi"

if [ ! -d "$CONFIG_DIR" ]; then
    echo "❌ 配置目录不存在: $CONFIG_DIR"
    exit 1
fi

echo "🔍 检查配置文件..."

for config in "$CONFIG_DIR"/config_*.json; do
    if [ -f "$config" ]; then
        echo ""
        echo "📄 检查: $(basename "$config")"
        
        # 语法检查
        if /usr/local/bin/xray test -config "$config" 2>/dev/null; then
            echo "  ✅ JSON语法正确"
        else
            echo "  ❌ JSON语法错误，显示详细错误:"
            /usr/local/bin/xray test -config "$config"
            echo ""
            echo "  🔧 尝试修复配置..."
            
            # 备份原配置
            cp "$config" "${config}.backup.$(date +%Y%m%d_%H%M%S)"
            
            # 重新生成配置文件
            interface_name=$(basename "$config" .json | sed 's/config_//')
            
            echo "  📝 重新生成配置文件..."
            # 这里需要重新生成配置，但由于没有原始变量，先输出提示
            echo "  ⚠️ 请重新运行安装脚本或手动修复配置"
        fi
        
        # 检查用户配置
        echo "  👥 检查用户配置:"
        if grep -q '"user": "vip1"' "$config" && grep -q '"user": "vip10"' "$config"; then
            user_count=$(grep -c '"user": "vip' "$config")
            echo "    ✅ 检测到 $user_count 个用户账号"
        else
            echo "    ❌ 用户配置可能有问题"
        fi
        
        # 检查端口配置
        port=$(grep -o '"port": [0-9]*' "$config" | grep -o '[0-9]*')
        if [ -n "$port" ]; then
            echo "    🔌 配置端口: $port"
            if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
                echo "    ✅ 端口正在监听"
            else
                echo "    ❌ 端口未监听"
            fi
        fi
    fi
done

echo ""
echo "🧪 测试用户认证:"
echo "curl --socks5 vip1:123456@127.0.0.1:11000 https://httpbin.org/ip --connect-timeout 10"
echo ""
echo "如果连接失败，可能需要重新运行安装脚本"
CHECKEOF

chmod +x /usr/local/bin/xray-config-check.sh

# ====== 启动服务 ======
echo "=========================================="
echo "🚀 启动多IP SOCKS5服务"
echo "=========================================="

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

# 获取服务器IP
echo "获取服务器IP地址..."
SERVER_IP=$(curl -s -4 ifconfig.me --timeout=10 2>/dev/null || curl -s -4 ipinfo.io/ip --timeout=10 2>/dev/null || echo "未知")

# 验证端口
echo ""
echo "🔍 验证端口监听..."
sleep 5
ALL_WORKING=true

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    if netstat -tlnp 2>/dev/null | grep -q "$ip:$port "; then
        echo "✅ $interface ($ip:$port) 正常"
    else
        echo "❌ $interface ($ip:$port) 异常"
        ALL_WORKING=false
    fi
done

# 执行DNS测试
echo ""
echo "=========================================="
echo "🧪 执行DNS测试"
echo "=========================================="
/usr/local/bin/beanfun-dns-test.sh

# 生成配置文件
echo ""
echo "📝 生成配置文件..."
cat > ~/Multi_IP_Socks5_Config.txt << USEREOF
#############################################################################
🎯 稳定版多IP SOCKS5代理配置 (多用户版)

📡 服务器信息:
公网IP: $SERVER_IP
检测到接口数: ${#CONFIG[@]}

👥 支持用户账号 (密码都是123456):
vip1, vip2, vip3, vip4, vip5, vip6, vip7, vip8, vip9, vip10

🌐 Beanfun DNS优化 (已集成):
✅ hk.beanfun.com -> 112.121.124.11
✅ bfweb.hk.beanfun.com -> 112.121.124.69
✅ cdn.hk.beanfun.com -> $cdn_ip
✅ csp.hk.beanfun.com -> 18.167.13.186
✅ tw.beanfun.com -> 202.80.107.11
✅ beanfun.com -> 52.147.74.109
✅ 阻止污染IP: 31.13.106.4

🔌 独立代理服务配置:
USEREOF

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    
    # 检查端口状态
    if netstat -tlnp 2>/dev/null | grep -q "$ip:$port "; then
        status="运行正常"
    else
        status="异常"
    fi
    
    cat >> ~/Multi_IP_Socks5_Config.txt << USEREOF2
📌 $interface (内网IP: $ip):
   代理地址: $SERVER_IP:$port
   支持用户: vip1-vip10 (任选一个)
   密码: 123456
   状态: $status
   
   🔗 连接测试示例:
   curl --socks5 vip1:123456@$SERVER_IP:$port https://httpbin.org/ip
   curl --socks5 vip5:123456@$SERVER_IP:$port https://httpbin.org/ip
   curl --socks5 vip10:123456@$SERVER_IP:$port https://httpbin.org/ip
   
   🎮 Beanfun测试:
   curl --socks5-hostname vip1:123456@$SERVER_IP:$port https://bfweb.hk.beanfun.com

USEREOF2
done

cat >> ~/Multi_IP_Socks5_Config.txt << USEREOF3

⚙️ 服务管理:
启动: systemctl start xray-multi
停止: systemctl stop xray-multi  
重启: systemctl restart xray-multi
状态: systemctl status xray-multi

🔧 管理工具:
DNS测试: /usr/local/bin/beanfun-dns-test.sh
配置检查: /usr/local/bin/xray-config-check.sh
手动启动: /usr/local/bin/xray-multi-start.sh
手动停止: /usr/local/bin/xray-multi-stop.sh

🎮 客户端配置要点:
- 代理类型: SOCKS5
- 服务器: $SERVER_IP  
- 端口: 11000/12000/13000 (选择一个)
- 用户名: vip1-vip10 (任选一个)
- 密码: 123456
- 🚨 重要: 启用"代理DNS查询"或"远程DNS解析"
- Firefox设置: network.proxy.socks_remote_dns = true

💡 多用户使用建议:
1. 账号隔离: 不同游戏/业务使用不同vip用户
2. 同一IP可同时支持10个不同用户连接
3. 建议为每个客户分配固定的vip账号
4. vip1-vip10用户权限完全相同，可随意选择

安装时间: $(date)
版本: 稳定版 v2.2 (多用户支持版本)
#############################################################################
USEREOF3

# 最终状态报告
echo ""
echo "=========================================="
echo "🎉 稳定版多IP多用户SOCKS5安装完成！"
echo "=========================================="
echo "🌐 服务器公网IP: $SERVER_IP"
echo "🔌 检测到 ${#CONFIG[@]} 个网络接口"
echo "👥 支持用户: vip1-vip10 (密码:123456)"
echo ""

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    
    if netstat -tlnp 2>/dev/null | grep -q "$ip:$port "; then
        status="✅ 正常"
    else
        status="❌ 异常"
    fi
    
    echo "📌 $interface ($ip): 端口$port $status"
done

echo ""
echo "📄 详细配置: ~/Multi_IP_Socks5_Config.txt"
echo ""

if [[ "$ALL_WORKING" == "true" ]]; then
    echo "🎯 所有服务正常运行！"
    echo ""
    echo "🧪 快速测试示例 (任选用户):"
    for interface in "${!CONFIG[@]}"; do
        IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
        echo "   curl --socks5 vip1:123456@$SERVER_IP:$port https://httpbin.org/ip"
        echo "   curl --socks5 vip5:123456@$SERVER_IP:$port https://httpbin.org/ip"
        echo "   curl --socks5 vip10:123456@$SERVER_IP:$port https://httpbin.org/ip"
        break
    done
    echo ""
    echo "🌐 Beanfun测试:"
    for interface in "${!CONFIG[@]}"; do
        IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
        echo "   curl --socks5-hostname vip1:123456@$SERVER_IP:$port https://bfweb.hk.beanfun.com"
        break
    done
else
    echo "⚠️ 部分服务可能存在问题，请检查:"
    echo "   systemctl status xray-multi"
    echo "   /usr/local/bin/beanfun-dns-test.sh"
fi

echo ""
echo "🔧 常用命令:"
echo "   DNS测试: /usr/local/bin/beanfun-dns-test.sh"
echo "   配置检查: /usr/local/bin/xray-config-check.sh"
echo "   服务状态: systemctl status xray-multi"
echo "   重启服务: systemctl restart xray-multi"

# 清理临时文件
cd /
rm -rf /tmp/xray*

echo ""
echo "🎊 安装完成！稳定版多IP多用户代理服务已就绪！"
echo "🌐 每个IP都支持vip1-vip10共10个用户同时使用！"
echo "🔗 详细配置信息请查看: ~/Multi_IP_Socks5_Config.txt"

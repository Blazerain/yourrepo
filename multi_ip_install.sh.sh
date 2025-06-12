#!/bin/bash

# 多公网IP服务器SOCKS5代理一键安装脚本
# 适用于阿里云多公网IP型规格族
# 每个公网IP独立代理服务，支持账号隔离和流量分离
# 使用方法: curl -sSL https://raw.githubusercontent.com/你的用户名/你的仓库名/main/multi_ip_install.sh | bash

set -e

echo "=========================================="
echo "🚀 多公网IP服务器 SOCKS5 代理安装程序"
echo "🌐 每个IP独立代理 + 账号隔离 + 流量分离"
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

# 检查是否为root用户
if [[ $EUID -ne 0 ]]; then
   echo "❌ 错误：此脚本需要root权限运行"
   echo "请使用: sudo $0"
   exit 1
fi

# 获取网络接口IP信息
get_interface_ip() {
    local interface=$1
    local ip
    
    if command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig "$interface" 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
    fi
    
    if [[ -z "$ip" ]]; then
        ip=$(ip addr show "$interface" 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -1)
    fi
    
    ip=$(echo "$ip" | tr -d ' \n\r\t')
    echo "$ip"
}

# 检查IP地址是否有效
check_ip_valid() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

echo "🔍 检测多公网IP配置..."

# 自动检测网卡和IP
declare -A IP_CONFIG
INTERFACE_COUNT=0

# 检测eth0
eth0_ip=$(get_interface_ip "eth0")
if [[ -n "$eth0_ip" ]] && check_ip_valid "$eth0_ip"; then
    IP_CONFIG["eth0"]="$eth0_ip"
    INTERFACE_COUNT=$((INTERFACE_COUNT + 1))
    echo "✅ 检测到 eth0: $eth0_ip"
fi

# 检测eth1
eth1_ip=$(get_interface_ip "eth1")
if [[ -n "$eth1_ip" ]] && check_ip_valid "$eth1_ip"; then
    IP_CONFIG["eth1"]="$eth1_ip"
    INTERFACE_COUNT=$((INTERFACE_COUNT + 1))
    echo "✅ 检测到 eth1: $eth1_ip"
fi

# 检测eth1:1
eth1_1_ip=$(get_interface_ip "eth1:1")
if [[ -n "$eth1_1_ip" ]] && check_ip_valid "$eth1_1_ip" && [[ "$eth1_1_ip" != "$eth1_ip" ]]; then
    IP_CONFIG["eth1:1"]="$eth1_1_ip"
    INTERFACE_COUNT=$((INTERFACE_COUNT + 1))
    echo "✅ 检测到 eth1:1: $eth1_1_ip"
fi

if [[ $INTERFACE_COUNT -lt 2 ]]; then
    echo "❌ 检测到的IP数量少于2个，当前脚本适用于多公网IP服务器"
    echo "   如果是单IP服务器，请使用标准版安装脚本"
    exit 1
fi

echo ""
echo "📊 检测到 $INTERFACE_COUNT 个网络接口，将为每个IP创建独立代理服务"

# 生成端口配置
declare -A PORT_CONFIG
BASE_PORT=10000
PORT_STEP=10

index=0
for interface in "${!IP_CONFIG[@]}"; do
    socks_port=$((BASE_PORT + index * PORT_STEP))
    http_port=$((socks_port + 1))
    PORT_CONFIG["${interface}_socks"]="$socks_port"
    PORT_CONFIG["${interface}_http"]="$http_port"
    echo "🔌 $interface (${IP_CONFIG[$interface]}): SOCKS5=$socks_port, HTTP=$http_port"
    index=$((index + 1))
done

echo ""
echo "🛠️ 开始安装多IP SOCKS5环境..."

# 创建临时目录
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

# 停止现有服务
echo "🛑 停止现有代理服务..."
safe_execute "sudo systemctl stop xray 2>/dev/null || true" "停止xray服务" || true
safe_execute "sudo systemctl stop xray-multi 2>/dev/null || true" "停止xray-multi服务" || true

# 安装必要软件
echo "📦 安装依赖软件..."
safe_execute "sudo yum clean all >/dev/null 2>&1 || true" "清理yum缓存"
safe_execute "sudo yum -y install jq unzip wget curl net-tools bind-utils >/dev/null 2>&1" "安装依赖软件"

# ====== DNS优化配置 ======
echo "=========================================="
echo "🌐 配置DNS优化"
echo "=========================================="

# 备份DNS配置
safe_execute "sudo cp /etc/resolv.conf /etc/resolv.conf.bak.\$(date +%Y%m%d_%H%M%S) 2>/dev/null || true" "备份DNS配置"

# 创建优化DNS配置
safe_execute "sudo tee /etc/resolv.conf > /dev/null << 'DNSCONFIG'
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
DNSCONFIG" "创建DNS配置"

echo "✅ DNS优化配置完成"

# ====== 下载和安装Xray ======
echo "=========================================="
echo "⬬ 下载和安装Xray"
echo "=========================================="

# 获取最新版本
XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name 2>/dev/null || echo "v1.8.4")
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"

echo "📥 下载xray版本: $XRAY_VERSION"
if ! wget -q -O xray.zip "$XRAY_URL" --timeout=30; then
    echo "⚠️ 主下载失败，尝试备用地址..."
    if ! wget -q -O xray.zip "https://vip.123pan.cn/1816473155/%E6%8F%92%E4%BB%B6%E6%B3%A8%E5%86%8CIP/xray" --timeout=30; then
        error_exit "Xray下载失败" $LINENO
    fi
fi

# 解压和安装
safe_execute "unzip -q -o xray.zip" "解压Xray"

if [ ! -f "xray" ]; then
    error_exit "Xray解压失败，文件不存在" $LINENO
fi

safe_execute "sudo mv xray /usr/local/bin/" "移动Xray到系统目录"
safe_execute "sudo chmod +x /usr/local/bin/xray" "设置Xray执行权限"

echo "✅ Xray安装成功"

# 创建配置目录
safe_execute "sudo mkdir -p /etc/xray-multi /var/log/xray-multi" "创建配置目录"

# ====== 为每个IP创建Xray配置 ======
echo "=========================================="
echo "⚙️ 为每个IP创建独立代理配置"
echo "=========================================="

config_index=1
for interface in "${!IP_CONFIG[@]}"; do
    ip="${IP_CONFIG[$interface]}"
    socks_port="${PORT_CONFIG[${interface}_socks]}"
    http_port="${PORT_CONFIG[${interface}_http]}"
    
    # 根据接口生成用户名前缀
    case $interface in
        "eth0") user_prefix="ip1" ;;
        "eth1") user_prefix="ip2" ;;
        "eth1:1") user_prefix="ip3" ;;
        *) user_prefix="ip$config_index" ;;
    esac
    
    echo "🔧 配置 $interface ($ip) - 端口: $socks_port/$http_port - 用户: ${user_prefix}user"
    
    # 创建独立配置文件
    sudo tee "/etc/xray-multi/config_${interface//:/_}.json" > /dev/null << XRAYCONFIG
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
      "port": $socks_port,
      "protocol": "socks",
      "listen": "$ip",
      "settings": {
        "auth": "password",
        "accounts": [
          {"user": "${user_prefix}user", "pass": "123456"},
          {"user": "${user_prefix}vip", "pass": "123456"},
          {"user": "${user_prefix}pro", "pass": "123456"}
        ],
        "udp": true,
        "ip": "$ip"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "domainsExcluded": ["courier.push.apple.com"]
      }
    },
    {
      "tag": "http-in-${interface//:/_}",
      "port": $http_port,
      "protocol": "http",
      "listen": "$ip",
      "settings": {
        "accounts": [
          {"user": "${user_prefix}user", "pass": "123456"},
          {"user": "${user_prefix}vip", "pass": "123456"},
          {"user": "${user_prefix}pro", "pass": "123456"}
        ],
        "allowTransparent": false
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
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
      },
      "streamSettings": {
        "sockopt": {
          "bindToDevice": "${interface%%:*}"
        }
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
        "ip": [
          "127.0.0.0/8",
          "10.0.0.0/8",
          "172.16.0.0/12",
          "192.168.0.0/16"
        ],
        "outboundTag": "direct-${interface//:/_}"
      },
      {
        "type": "field",
        "ip": [
          "31.13.106.4/32"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
XRAYCONFIG

    echo "✅ 配置文件创建: /etc/xray-multi/config_${interface//:/_}.json"
    config_index=$((config_index + 1))
done

# ====== 创建启动脚本 ======
echo "🚀 创建多实例启动脚本..."

sudo tee /usr/local/bin/xray-multi-start.sh > /dev/null << 'STARTSCRIPT'
#!/bin/bash

PIDS=()
CONFIG_DIR="/etc/xray-multi"

echo "启动多IP代理服务..."

for config_file in "$CONFIG_DIR"/config_*.json; do
    if [ -f "$config_file" ]; then
        config_name=$(basename "$config_file" .json)
        echo "启动: $config_name"
        
        # 启动xray实例
        /usr/local/bin/xray run -config "$config_file" &
        PID=$!
        PIDS+=($PID)
        
        echo "  PID: $PID"
        sleep 1
    fi
done

# 保存PID文件
printf '%s\n' "${PIDS[@]}" > /var/run/xray-multi.pid

echo "所有实例启动完成"
echo "PID文件: /var/run/xray-multi.pid"

# 等待进程
wait
STARTSCRIPT

sudo tee /usr/local/bin/xray-multi-stop.sh > /dev/null << 'STOPSCRIPT'
#!/bin/bash

echo "停止多IP代理服务..."

if [ -f /var/run/xray-multi.pid ]; then
    while read -r pid; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "停止进程: $pid"
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done < /var/run/xray-multi.pid
    
    sleep 3
    
    # 强制杀死残留进程
    while read -r pid; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "强制停止进程: $pid"
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done < /var/run/xray-multi.pid
    
    rm -f /var/run/xray-multi.pid
fi

# 清理任何残留的xray进程
pkill -f "/usr/local/bin/xray run -config /etc/xray-multi" 2>/dev/null || true

echo "停止完成"
STOPSCRIPT

sudo chmod +x /usr/local/bin/xray-multi-start.sh
sudo chmod +x /usr/local/bin/xray-multi-stop.sh

# ====== 创建systemd服务 ======
echo "📋 创建systemd服务..."
safe_execute "sudo tee /etc/systemd/system/xray-multi.service > /dev/null << 'SYSTEMDCONFIG'
[Unit]
Description=Xray Multi-IP Service
Documentation=https://github.com/xtls/xray-core
After=network.target nss-lookup.target

[Service]
Type=forking
User=root
ExecStart=/usr/local/bin/xray-multi-start.sh
ExecStop=/usr/local/bin/xray-multi-stop.sh
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
PIDFile=/var/run/xray-multi.pid

[Install]
WantedBy=multi-user.target
SYSTEMDCONFIG" "创建systemd服务文件"

echo "✅ systemd服务创建完成"

# ====== 配置防火墙 ======
echo "=========================================="
echo "🔥 配置防火墙"
echo "=========================================="

# 停止firewalld
safe_execute "sudo systemctl stop firewalld 2>/dev/null || true" "停止firewalld" || true
safe_execute "sudo systemctl disable firewalld 2>/dev/null || true" "禁用firewalld" || true

# 清理现有规则
safe_execute "sudo iptables -F INPUT 2>/dev/null || true" "清理INPUT规则" || true
safe_execute "sudo iptables -X 2>/dev/null || true" "清理自定义链" || true

# 设置默认策略
safe_execute "sudo iptables -P INPUT ACCEPT" "设置INPUT默认策略"
safe_execute "sudo iptables -P FORWARD ACCEPT" "设置FORWARD默认策略"
safe_execute "sudo iptables -P OUTPUT ACCEPT" "设置OUTPUT默认策略"

# 基础规则
safe_execute "sudo iptables -A INPUT -i lo -j ACCEPT" "允许本地回环"
safe_execute "sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT" "允许已建立连接"

# 开放SSH
safe_execute "sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT" "开放SSH端口"

# 开放所有配置的端口
for interface in "${!IP_CONFIG[@]}"; do
    socks_port="${PORT_CONFIG[${interface}_socks]}"
    http_port="${PORT_CONFIG[${interface}_http]}"
    
    safe_execute "sudo iptables -A INPUT -p tcp --dport $socks_port -j ACCEPT" "开放 $interface SOCKS5端口 $socks_port"
    safe_execute "sudo iptables -A INPUT -p udp --dport $socks_port -j ACCEPT" "开放 $interface SOCKS5 UDP端口 $socks_port"
    safe_execute "sudo iptables -A INPUT -p tcp --dport $http_port -j ACCEPT" "开放 $interface HTTP端口 $http_port"
done

# 保存防火墙规则
safe_execute "sudo service iptables save 2>/dev/null || sudo iptables-save > /etc/sysconfig/iptables 2>/dev/null || echo '防火墙规则保存完成'" "保存防火墙规则" || true

echo "✅ 防火墙配置完成"

# 启用IP转发
echo "启用IP转发..."
safe_execute "echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf >/dev/null" "配置IPv4转发"
safe_execute "sudo sysctl -p >/dev/null 2>&1 || true" "应用内核参数" || true

# ====== 配置路由规则（如果需要） ======
echo "=========================================="
echo "🛣️ 配置网络路由"
echo "=========================================="

# 如果是多公网IP服务器，配置路由规则确保流量分离
if [[ $INTERFACE_COUNT -ge 2 ]]; then
    echo "🔧 配置路由规则确保流量分离..."
    
    # 获取网关
    gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    
    if [[ -n "$gateway" ]]; then
        echo "使用网关: $gateway"
        
        # 为eth1配置路由表
        if [[ -n "${IP_CONFIG[eth1]}" ]]; then
            safe_execute "ip route add default via $gateway dev eth1 table 1001 2>/dev/null || true" "配置eth1路由表" || true
            safe_execute "ip rule add from ${IP_CONFIG[eth1]} lookup 1001 2>/dev/null || true" "配置eth1路由规则" || true
            echo "✅ eth1路由配置完成"
        fi
        
        # 为eth1:1配置路由表
        if [[ -n "${IP_CONFIG[eth1:1]}" ]]; then
            safe_execute "ip route add default via $gateway dev eth1 table 1002 2>/dev/null || true" "配置eth1:1路由表" || true
            safe_execute "ip rule add from ${IP_CONFIG[eth1:1]} lookup 1002 2>/dev/null || true" "配置eth1:1路由规则" || true
            echo "✅ eth1:1路由配置完成"
        fi
    fi
fi

# ====== 启动服务 ======
echo "=========================================="
echo "🚀 启动多IP SOCKS5服务"
echo "=========================================="

safe_execute "sudo systemctl daemon-reload" "重新加载systemd"
safe_execute "sudo systemctl enable xray-multi" "启用xray-multi服务"
safe_execute "sudo systemctl start xray-multi" "启动xray-multi服务"

# 获取服务器IP
echo "获取服务器公网IP地址..."
SERVER_IP=$(curl -s -4 ifconfig.me --connect-timeout 10 2>/dev/null || curl -s -4 ipinfo.io/ip --connect-timeout 10 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)

# 验证服务状态
echo ""
echo "=========================================="
echo "🧪 验证服务状态"
echo "=========================================="

sleep 5

ALL_WORKING=true
declare -A SERVICE_STATUS

for interface in "${!IP_CONFIG[@]}"; do
    ip="${IP_CONFIG[$interface]}"
    socks_port="${PORT_CONFIG[${interface}_socks]}"
    http_port="${PORT_CONFIG[${interface}_http]}"
    
    echo "🔍 检查 $interface ($ip):"
    
    if netstat -tlnp | grep -q "$ip:$socks_port "; then
        echo "  ✅ SOCKS5端口 $socks_port 正常监听"
        SERVICE_STATUS["${interface}_socks"]="正常"
    else
        echo "  ❌ SOCKS5端口 $socks_port 未监听"
        SERVICE_STATUS["${interface}_socks"]="异常"
        ALL_WORKING=false
    fi
    
    if netstat -tlnp | grep -q "$ip:$http_port "; then
        echo "  ✅ HTTP端口 $http_port 正常监听"
        SERVICE_STATUS["${interface}_http"]="正常"
    else
        echo "  ❌ HTTP端口 $http_port 未监听"
        SERVICE_STATUS["${interface}_http"]="异常"
        ALL_WORKING=false
    fi
done

# ====== 生成配置文件 ======
echo ""
echo "📝 生成用户配置文件..."

cat > ~/Multi_IP_Socks5_Config.txt << USERCONFIG
#############################################################################
🎯 多公网IP服务器 SOCKS5代理配置 - 完成安装

📡 服务器信息:
公网IP: $SERVER_IP
检测到接口数: $INTERFACE_COUNT

🌐 独立代理服务配置:
USERCONFIG

for interface in "${!IP_CONFIG[@]}"; do
    ip="${IP_CONFIG[$interface]}"
    socks_port="${PORT_CONFIG[${interface}_socks]}"
    http_port="${PORT_CONFIG[${interface}_http]}"
    
    case $interface in
        "eth0") user_prefix="ip1" ;;
        "eth1") user_prefix="ip2" ;;
        "eth1:1") user_prefix="ip3" ;;
        *) user_prefix="ip$config_index" ;;
    esac
    
    socks_status="${SERVICE_STATUS[${interface}_socks]:-未知}"
    http_status="${SERVICE_STATUS[${interface}_http]:-未知}"
    
    cat >> ~/Multi_IP_Socks5_Config.txt << INTERFACECONFIG

📌 $interface (内网IP: $ip):
   SOCKS5: $SERVER_IP:$socks_port (状态: $socks_status)
   HTTP: $SERVER_IP:$http_port (状态: $http_status)
   用户账号: ${user_prefix}user/123456, ${user_prefix}vip/123456, ${user_prefix}pro/123456
   
   🔗 连接测试:
   curl --socks5 ${user_prefix}user:123456@$SERVER_IP:$socks_port https://httpbin.org/ip
   curl --proxy http://${user_prefix}user:123456@$SERVER_IP:$http_port https://httpbin.org/ip
INTERFACECONFIG
done

cat >> ~/Multi_IP_Socks5_Config.txt << USERCONFIG

🎮 客户端配置要点:
- 每个公网IP有独立的代理服务和账号
- 建议不同应用使用不同IP的代理，实现账号隔离
- 启用"代理DNS查询"或"远程DNS解析"
- 使用socks5h://协议而不是socks5://

⚙️ 服务管理:
启动: sudo systemctl start xray-multi
停止: sudo systemctl stop xray-multi  
重启: sudo systemctl restart xray-multi
状态: sudo systemctl status xray-multi
日志: sudo journalctl -u xray-multi -f

🔧 高级管理:
手动启动: sudo /usr/local/bin/xray-multi-start.sh
手动停止: sudo /usr/local/bin/xray-multi-stop.sh
配置目录: /etc/xray-multi/
日志目录: /var/log/xray-multi/

🛣️ 网络路由状态:
USERCONFIG

# 添加路由状态信息
if [[ $INTERFACE_COUNT -ge 2 ]]; then
    cat >> ~/Multi_IP_Socks5_Config.txt << ROUTECONFIG
路由表1001 (eth1): $(ip route show table 1001 2>/dev/null | head -1 || echo "未配置")
路由表1002 (eth1:1): $(ip route show table 1002 2>/dev/null | head -1 || echo "未配置")
路由规则: $(ip rule show | grep -E "(1001|1002)" | wc -l)条自定义规则
ROUTECONFIG
fi

cat >> ~/Multi_IP_Socks5_Config.txt << USERCONFIG

💡 使用建议:
1. 游戏账号隔离: 不同游戏使用不同IP代理
2. 电商账号安全: 每个店铺使用独立IP
3. 社交媒体管理: 不同平台使用不同IP
4. 爬虫和API: 分散请求到不同IP避免限制

🚨 重要提醒:
- 确保客户端配置使用socks5h://协议
- 启用"通过代理解析DNS"选项
- 不同应用建议使用不同的代理IP

安装时间: $(date)
版本: 多IP专版 v1.0
#############################################################################
USERCONFIG

# 显示最终结果
echo ""
echo "=========================================="
echo "🎉 多IP SOCKS5代理安装完成！"
echo "=========================================="
echo "🌐 服务器公网IP: $SERVER_IP"
echo "🔌 检测到 $INTERFACE_COUNT 个网络接口"
echo ""

for interface in "${!IP_CONFIG[@]}"; do
    ip="${IP_CONFIG[$interface]}"
    socks_port="${PORT_CONFIG[${interface}_socks]}"
    http_port="${PORT_CONFIG[${interface}_http]}"
    
    case $interface in
        "eth0") user_prefix="ip1" ;;
        "eth1") user_prefix="ip2" ;;
        "eth1:1") user_prefix="ip3" ;;
        *) user_prefix="ip$config_index" ;;
    esac
    
    socks_status="${SERVICE_STATUS[${interface}_socks]:-未知}"
    http_status="${SERVICE_STATUS[${interface}_http]:-未知}"
    
    echo "📌 $interface (${IP_CONFIG[$interface]}):"
    echo "   SOCKS5: $socks_port (状态: $socks_status)"
    echo "   HTTP: $http_port (状态: $http_status)"
    echo "   用户: ${user_prefix}user/vip/pro"
    echo ""
done

echo "📄 详细配置: ~/Multi_IP_Socks5_Config.txt"
echo ""

if [[ "$ALL_WORKING" == "true" ]]; then
    echo "🎯 所有服务正常运行！"
    echo ""
    echo "🧪 快速测试示例:"
    for interface in "${!IP_CONFIG[@]}"; do
        socks_port="${PORT_CONFIG[${interface}_socks]}"
        case $interface in
            "eth0") user_prefix="ip1" ;;
            "eth1") user_prefix="ip2" ;;
            "eth1:1") user_prefix="ip3" ;;
            *) user_prefix="ip$config_index" ;;
        esac
        echo "   $interface: curl --socks5 ${user_prefix}user:123456@$SERVER_IP:$socks_port https://httpbin.org/ip"
        break  # 只显示第一个作为示例
    done
else
    echo "⚠️ 部分服务可能存在问题，请检查:"
    echo "   sudo journalctl -u xray-multi -f"
    echo "   sudo systemctl status xray-multi"
fi

echo ""
echo "🔧 服务管理:"
echo "   启动: sudo systemctl start xray-multi"
echo "   停止: sudo systemctl stop xray-multi"
echo "   重启: sudo systemctl restart xray-multi"
echo "   状态: sudo systemctl status xray-multi"

# 清理临时文件
cd /
rm -rf $TEMP_DIR

echo ""
echo "🎊 多IP代理服务安装完成！每个IP独立运行，支持账号隔离！"
echo "🔗 详细配置信息请查看: ~/Multi_IP_Socks5_Config.txt"
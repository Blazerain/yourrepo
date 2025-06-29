#!/bin/bash

# 简化版多公网IP服务器SOCKS5代理安装脚本
# 实现入口IP=出口IP
# 每个IP一个端口：11000, 12000, 13000
# 用户: vip1/123456
# curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/multi_ip_install.sh | bash


set -e

echo "=========================================="
echo "🚀 简化版多IP SOCKS5安装"
echo "🔌 每IP一个端口：11000/12000/13000"
echo "👤 用户: vip1/123456"
echo "🎯 入口IP=出口IP"
echo "=========================================="

# 检查root权限
if [[ $EUID -ne 0 ]]; then
   echo "❌ 需要root权限运行"
   exit 1
fi

# 获取服务器公网IP
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || curl -s ip.sb)
if [[ -z "$SERVER_IP" ]]; then
    echo "❌ 无法获取服务器公网IP"
    exit 1
fi
echo "🌐 服务器公网IP: $SERVER_IP"

# 简化的IP获取函数
get_ip() {
    local interface=$1
    ifconfig "$interface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1 | tr -d ' \n\r\t'
}

echo "🔍 检测网卡配置..."
eth0_ip=$(get_ip "eth0")
eth1_ip=$(get_ip "eth1")
eth1_1_ip=$(get_ip "eth1:1")

# 简化配置端口映射（每个IP一个端口）
declare -A CONFIG
PORT=11000
if [[ -n "$eth0_ip" ]]; then
    CONFIG["eth0"]="$eth0_ip:$PORT"
    echo "✅ eth0: $eth0_ip -> $PORT"
    ((PORT+=1000))
fi
if [[ -n "$eth1_ip" ]]; then
    CONFIG["eth1"]="$eth1_ip:$PORT"
    echo "✅ eth1: $eth1_ip -> $PORT"
    ((PORT+=1000))
fi
if [[ -n "$eth1_1_ip" ]] && [[ "$eth1_1_ip" != "$eth1_ip" ]]; then
    CONFIG["eth1:1"]="$eth1_1_ip:$PORT"
    echo "✅ eth1:1: $eth1_1_ip -> $PORT"
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
yum -y install wget unzip net-tools >/dev/null 2>&1

# ====== 下载和安装Xray ======
echo "=========================================="
echo "⬇️ 下载和安装Xray"
echo "=========================================="

cd /tmp
rm -f xray.zip xray

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
    
    echo "✅ 配置: $interface ($ip) -> 端口: $port"
    
    single_config_file="/etc/xray-multi/config_${interface//:/_}_${port}.json"
    
    # 创建配置文件
    cat > "$single_config_file" << CONFIGEOF
{
  "log": {
    "loglevel": "info",
    "access": "/var/log/xray-multi/access_${interface//:/_}_${port}.log",
    "error": "/var/log/xray-multi/error_${interface//:/_}_${port}.log"
  },
  "inbounds": [
    {
      "tag": "socks5-in-${interface//:/_}-${port}",
      "port": $port,
      "protocol": "socks",
      "listen": "0.0.0.0",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "vip1",
            "pass": "123456"
          }
        ],
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct-${interface//:/_}-${port}",
      "protocol": "freedom",
      "sendThrough": "origin",
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
        "inboundTag": ["socks5-in-${interface//:/_}-${port}"],
        "outboundTag": "direct-${interface//:/_}-${port}"
      },
      {
        "type": "field",
        "ip": [
          "127.0.0.0/8",
          "10.0.0.0/8",
          "172.16.0.0/12",
          "192.168.0.0/16"
        ],
        "outboundTag": "direct-${interface//:/_}-${port}"
      }
    ]
  }
}
CONFIGEOF

    echo "    ✅ 端口$port 配置文件已生成"
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
        sleep 0.5
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
TimeoutStartSec=60

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

# 开放所有配置的端口
echo "开放端口..."
for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
    iptables -A INPUT -p udp --dport "$port" -j ACCEPT
    echo "  ✅ 端口 $port 已开放"
done

# 保存防火墙规则
service iptables save 2>/dev/null || iptables-save > /etc/sysconfig/iptables 2>/dev/null || true

echo "✅ 防火墙配置完成"

# 启用IP转发
echo "启用IP转发..."
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1 || true

# ====== 创建管理工具 ======
echo "🔧 创建管理工具..."

# 配置检查脚本
cat > /usr/local/bin/xray-check.sh << 'CHECKEOF'
#!/bin/bash

echo "🔍 SOCKS5服务检查"
echo "===================="

echo "📄 配置文件:"
ls -la /etc/xray-multi/config_*.json | wc -l | xargs echo "  生成配置文件数量:"

echo ""
echo "🔧 服务状态:"
if systemctl is-active --quiet xray-multi; then
    echo "  ✅ xray-multi 服务运行正常"
else
    echo "  ❌ xray-multi 服务异常"
    echo "  查看状态: systemctl status xray-multi"
fi

echo ""
echo "🔌 端口监听检查:"
listening_count=0
total_count=0

for port in 11000 12000 13000; do
    ((total_count++))
    if netstat -tlnp 2>/dev/null | grep -q "0.0.0.0:$port "; then
        echo "  ✅ 端口 $port"
        ((listening_count++))
    else
        echo "  ❌ 端口 $port"
    fi
done

echo ""
echo "📊 统计: $listening_count/$total_count 端口正常监听"

if [ $listening_count -gt 0 ]; then
    echo ""
    echo "🧪 测试连接:"
    for port in 11000 12000 13000; do
        if netstat -tlnp 2>/dev/null | grep -q "0.0.0.0:$port "; then
            echo "curl --socks5 vip1:123456@$(curl -s ifconfig.me):$port https://httpbin.org/ip"
            break
        fi
    done
fi
CHECKEOF

chmod +x /usr/local/bin/xray-check.sh

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
    sleep 3
    
    echo "通过systemd启动..."
    systemctl start xray-multi
    
    if systemctl is-active --quiet xray-multi; then
        echo "✅ systemd启动成功"
    else
        echo "❌ systemd启动失败"
        echo "查看日志: journalctl -u xray-multi -n 20"
    fi
else
    echo "❌ 手动启动失败"
fi

# 统计工作端口
working_ports=0
total_ports=${#CONFIG[@]}
for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    if netstat -tlnp 2>/dev/null | grep -q "0.0.0.0:$port "; then
        ((working_ports++))
    fi
done

# 生成配置文件
echo ""
echo "📝 生成配置文件..."
cat > ~/Multi_IP_Socks5_Config.txt << USEREOF
#############################################################################
🎯 简化版多IP SOCKS5代理配置

📡 服务器信息:
公网IP: $SERVER_IP
检测到接口数: ${#CONFIG[@]}
工作端口: $working_ports/$total_ports

👤 统一用户账号:
用户名: vip1
密码: 123456

🎯 特性: 入口IP=出口IP (sendThrough: origin)

🔌 代理服务配置:
USEREOF

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    
    # 检查端口状态
    if netstat -tlnp 2>/dev/null | grep -q "0.0.0.0:$port "; then
        status="✅ 运行正常"
    else
        status="❌ 异常"
    fi
    
    cat >> ~/Multi_IP_Socks5_Config.txt << USEREOF2
📌 $interface (内网IP: $ip):
   端口 $port: $status
     代理地址: $SERVER_IP:$port
     用户名: vip1
     密码: 123456
     测试: curl --socks5 vip1:123456@$SERVER_IP:$port https://httpbin.org/ip
     
USEREOF2
done

cat >> ~/Multi_IP_Socks5_Config.txt << USEREOF3

⚙️ 服务管理:
启动: systemctl start xray-multi
停止: systemctl stop xray-multi  
重启: systemctl restart xray-multi
状态: systemctl status xray-multi

🔧 管理工具:
服务检查: /usr/local/bin/xray-check.sh
手动启动: /usr/local/bin/xray-multi-start.sh
手动停止: /usr/local/bin/xray-multi-stop.sh

🎮 客户端配置要点:
- 代理类型: SOCKS5
- 服务器: $SERVER_IP  
- 端口: 11000/12000/13000 (选择任意可用)
- 用户名: vip1
- 密码: 123456

🧪 快速测试示例:
curl --socks5 vip1:123456@$SERVER_IP:11000 https://httpbin.org/ip
curl --socks5 vip1:123456@$SERVER_IP:12000 https://httpbin.org/ip
curl --socks5 vip1:123456@$SERVER_IP:13000 https://httpbin.org/ip

安装时间: $(date)
版本: 简化版 v6.0 (入口IP=出口IP)
#############################################################################
USEREOF3

# 最终状态报告
echo ""
echo "=========================================="
echo "🎉 简化版多IP SOCKS5安装完成！"
echo "=========================================="
echo "🌐 服务器公网IP: $SERVER_IP"
echo "🔌 检测到 ${#CONFIG[@]} 个网络接口"
echo "👤 用户: vip1/123456"
echo "📊 工作端口: $working_ports/$total_ports"
echo "🎯 特性: 入口IP=出口IP"
echo ""

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
    
    if netstat -tlnp 2>/dev/null | grep -q "0.0.0.0:$port "; then
        status="✅ 正常"
    else
        status="❌ 异常"
    fi
    
    echo "📌 $interface ($ip): 端口$port $status"
done

echo ""
echo "📄 详细配置: ~/Multi_IP_Socks5_Config.txt"
echo ""

if [[ $working_ports -gt 0 ]]; then
    echo "🎯 服务安装成功！有 $working_ports 个端口正常工作！"
    echo ""
    echo "🧪 快速测试 (选择任意正常端口):"
    
    # 找第一个工作的端口
    for interface in "${!CONFIG[@]}"; do
        IFS=':' read -r ip port <<< "${CONFIG[$interface]}"
        if netstat -tlnp 2>/dev/null | grep -q "0.0.0.0:$port "; then
            echo "   curl --socks5 vip1:123456@$SERVER_IP:$port https://httpbin.org/ip"
            break
        fi
    done
else
    echo "⚠️ 没有端口正常工作，请检查:"
    echo "   systemctl status xray-multi"
    echo "   /usr/local/bin/xray-check.sh"
    echo "   journalctl -u xray-multi -n 20"
fi

echo ""
echo "🔧 常用命令:"
echo "   服务检查: /usr/local/bin/xray-check.sh"
echo "   服务状态: systemctl status xray-multi"
echo "   重启服务: systemctl restart xray-multi"

# 清理临时文件
cd /
rm -rf /tmp/xray*

echo ""
echo "🎊 安装完成！简化版多IP代理服务已就绪！"
echo "🌐 每个IP一个端口，统一使用 vip1/123456 账号！"
echo "🎯 实现入口IP=出口IP功能！"
echo "🔗 详细配置信息请查看: ~/Multi_IP_Socks5_Config.txt"
echo ""
echo "💡 如有问题，运行检查工具: /usr/local/bin/xray-check.sh"

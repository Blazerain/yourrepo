#!/bin/bash

# 轻量版多公网IP服务器SOCKS5代理安装脚本
# 低内存优化，固定端口，减少测试
# 端口: 11000, 12000, 13000
# 用户: vip1/123456
# 使用方法: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/multi_ip_install.sh | bash
set -e

echo "=========================================="
echo "🚀 轻量版多IP SOCKS5安装 (低内存优化)"
echo "🔌 固定端口: 11000, 12000, 13000"
echo "👤 固定用户: vip1/123456"
echo "=========================================="

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

# 安装依赖（最小化）
echo "📦 安装必要软件..."
yum -y install wget unzip >/dev/null 2>&1

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

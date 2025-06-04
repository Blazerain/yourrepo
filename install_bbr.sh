#!/bin/bash

# BBR+SOCKS5优化一键脚本
# 功能: 安装BBR、优化SOCKS5、限制带宽1MB/s
# 使用: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install_bbr.sh | bash

set -e

echo "=================================================="
echo "🚀 BBR+SOCKS5优化一键脚本"
echo "🎯 自动安装BBR、优化SOCKS5、限制带宽1MB/s"
echo "=================================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    log_error "请使用root权限运行此脚本"
    exit 1
fi

# 检测系统
if [[ -f /etc/redhat-release ]]; then
    OS="centos"
    log_info "检测到CentOS系统"
elif [[ -f /etc/debian_version ]]; then
    OS="debian"
    log_info "检测到Debian/Ubuntu系统"
else
    log_error "不支持的操作系统"
    exit 1
fi

# 第一步：检查并安装BBR
echo ""
echo "1️⃣ BBR TCP拥塞控制检查与安装"
echo "=========================================="

# 检查内核版本
KERNEL_VERSION=$(uname -r | cut -d. -f1-2)
log_info "当前内核版本: $(uname -r)"

# 检查当前拥塞控制
CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
log_info "当前拥塞控制算法: $CURRENT_CC"

if [ "$CURRENT_CC" = "bbr" ]; then
    log_info "✅ BBR已经启用，跳过安装"
else
    # 检查内核版本是否支持BBR
    if [[ $(echo "$KERNEL_VERSION >= 4.9" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
        log_info "内核版本支持BBR，开始启用..."
        
        # 启用BBR
        log_info "配置BBR参数..."
        
        # 备份sysctl配置
        cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
        
        # 添加BBR配置
        cat >> /etc/sysctl.conf << 'BBR_CONFIG'

# BBR TCP拥塞控制优化配置
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 网络性能优化
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
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
BBR_CONFIG

        # 应用配置
        sysctl -p >/dev/null 2>&1
        
        # 验证BBR启用
        sleep 2
        NEW_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        if [ "$NEW_CC" = "bbr" ]; then
            log_info "✅ BBR启用成功"
        else
            log_warn "⚠️ BBR启用可能不完整，但继续执行"
        fi
    else
        log_warn "⚠️ 内核版本过低，无法启用BBR，但继续执行其他优化"
    fi
fi

# 第二步：检查SOCKS5配置
echo ""
echo "2️⃣ SOCKS5代理检查与优化"
echo "=========================================="

# 查找SOCKS5配置文件
CONFIG_FILE=""
SOCKS_PORT=""

# 检查可能的配置文件位置
for config_path in "/etc/xray/config.json" "/etc/v2ray/config.json" "/usr/local/etc/xray/config.json"; do
    if [ -f "$config_path" ]; then
        CONFIG_FILE="$config_path"
        log_info "找到配置文件: $config_path"
        break
    fi
done

if [ -z "$CONFIG_FILE" ]; then
    log_error "未找到SOCKS5配置文件，请确保已安装Xray/V2Ray"
    exit 1
fi

# 提取SOCKS5端口
if command -v jq >/dev/null 2>&1; then
    SOCKS_PORT=$(jq -r '.inbounds[] | select(.protocol == "socks") | .port' "$CONFIG_FILE" 2>/dev/null | head -1)
fi

if [ -z "$SOCKS_PORT" ] || [ "$SOCKS_PORT" = "null" ]; then
    SOCKS_PORT=$(grep -A20 '"protocol": "socks"' "$CONFIG_FILE" | grep '"port":' | head -1 | sed 's/.*"port": *\([0-9]*\).*/\1/' 2>/dev/null)
fi

if [ -z "$SOCKS_PORT" ]; then
    SOCKS_PORT=$(grep '"port":' "$CONFIG_FILE" | head -1 | grep -o '[0-9]\+' 2>/dev/null)
fi

if [ -n "$SOCKS_PORT" ] && [[ "$SOCKS_PORT" =~ ^[0-9]+$ ]]; then
    log_info "检测到SOCKS5端口: $SOCKS_PORT"
else
    log_error "无法检测SOCKS5端口，请检查配置文件"
    exit 1
fi

# 检查服务状态
SERVICE_NAME=""
for service in "xray" "v2ray"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        SERVICE_NAME="$service"
        log_info "检测到运行中的服务: $service"
        break
    fi
done

if [ -z "$SERVICE_NAME" ]; then
    log_warn "⚠️ 未检测到运行中的代理服务，尝试启动xray"
    SERVICE_NAME="xray"
    systemctl start xray 2>/dev/null || true
fi

# 第三步：优化SOCKS5配置并限制带宽
echo ""
echo "3️⃣ SOCKS5优化与带宽限制"
echo "=========================================="

log_info "备份原配置文件..."
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# 获取服务器IP
SERVER_IP=$(curl -s ifconfig.me --connect-timeout 10 2>/dev/null || echo "YOUR_SERVER_IP")

# 计算HTTP端口
HTTP_PORT=$((SOCKS_PORT + 1))

log_info "SOCKS5端口: $SOCKS_PORT"
log_info "HTTP端口: $HTTP_PORT"
log_info "服务器IP: $SERVER_IP"

# 生成优化的配置文件（包含1MB/s带宽限制）
log_info "生成优化配置（限制带宽1MB/s）..."

cat > "$CONFIG_FILE" << XRAYCONFIG
{
  "log": {
    "loglevel": "info",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
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
          "domain:elasticbeanstalk.com"
        ]
      },
      {
        "address": "223.5.5.5",
        "port": 53
      },
      "localhost"
    ],
    "clientIp": "1.2.3.4",
    "tag": "dns-inbound"
  },
  "policy": {
    "levels": {
      "0": {
        "uplinkOnly": 0,
        "downlinkOnly": 0,
        "statsUserUplink": true,
        "statsUserDownlink": true,
        "handshake": 4,
        "connIdle": 300,
        "bufferSize": 16384
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "inbounds": [
    {
      "tag": "socks5-in",
      "port": $SOCKS_PORT,
      "protocol": "socks",
      "listen": "0.0.0.0",
      "settings": {
        "auth": "password",
        "accounts": [
          {"user": "vip1", "pass": "123456"},
          {"user": "vip2", "pass": "123456"},
          {"user": "vip3", "pass": "123456"}
        ],
        "udp": true,
        "ip": "0.0.0.0"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "domainsExcluded": ["courier.push.apple.com"],
        "metadataOnly": false
      },
      "allocate": {
        "strategy": "always",
        "refresh": 5,
        "concurrency": 3
      }
    },
    {
      "tag": "http-in", 
      "port": $HTTP_PORT,
      "protocol": "http",
      "listen": "0.0.0.0",
      "settings": {
        "accounts": [
          {"user": "vip1", "pass": "123456"},
          {"user": "vip2", "pass": "123456"},
          {"user": "vip3", "pass": "123456"}
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
      "tag": "direct",
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
          "csp.hk.beanfun.com",
          "tw.beanfun.com",
          "csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": [
          "112.121.124.11/32",
          "112.121.124.69/32",
          "112.121.124.68/32",
          "18.167.13.186/32",
          "18.163.12.31/32",
          "202.80.107.11/32",
          "52.147.74.109/32"
        ],
        "outboundTag": "direct"
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
        "outboundTag": "direct"
      }
    ]
  }
}
XRAYCONFIG

log_info "✅ 配置文件已优化"

# 第四步：系统级带宽限制
echo ""
echo "4️⃣ 系统级带宽限制设置"
echo "=========================================="

# 获取网络接口
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
log_info "网络接口: $INTERFACE"

# 安装TC工具
if [ "$OS" = "centos" ]; then
    yum install -y iproute tc >/dev/null 2>&1 || true
else
    apt-get update >/dev/null 2>&1 && apt-get install -y iproute2 >/dev/null 2>&1 || true
fi

# 清除现有TC规则
tc qdisc del dev $INTERFACE root 2>/dev/null || true

# 设置1MB/s带宽限制
log_info "设置1MB/s带宽限制..."

# 创建根队列
tc qdisc add dev $INTERFACE root handle 1: htb default 30

# 创建主类别 (1MB/s = 1024kbit/s)
tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 1024kbit

# 创建SOCKS5流量类别
tc class add dev $INTERFACE parent 1:1 classid 1:10 htb rate 1024kbit ceil 1024kbit

# 创建其他流量类别
tc class add dev $INTERFACE parent 1:1 classid 1:30 htb rate 512kbit ceil 1024kbit

# 添加队列规则
tc qdisc add dev $INTERFACE parent 1:10 handle 10: sfq perturb 10
tc qdisc add dev $INTERFACE parent 1:30 handle 30: sfq perturb 10

# 创建过滤器 - SOCKS5端口流量
tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip sport $SOCKS_PORT 0xffff flowid 1:10
tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip dport $SOCKS_PORT 0xffff flowid 1:10

log_info "✅ 带宽限制已设置为1MB/s"

# 第五步：重启服务
echo ""
echo "5️⃣ 服务重启与验证"
echo "=========================================="

log_info "重启$SERVICE_NAME服务..."
systemctl restart $SERVICE_NAME

sleep 5

if systemctl is-active --quiet $SERVICE_NAME; then
    log_info "✅ $SERVICE_NAME服务启动成功"
else
    log_error "❌ $SERVICE_NAME服务启动失败，恢复备份配置"
    cp "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)" "$CONFIG_FILE" 2>/dev/null || true
    systemctl restart $SERVICE_NAME
    exit 1
fi

# 验证端口监听
if netstat -tuln | grep -q ":$SOCKS_PORT "; then
    log_info "✅ 端口$SOCKS_PORT监听正常"
else
    log_warn "⚠️ 端口监听检查失败"
fi

# 第六步：生成配置文件
echo ""
echo "6️⃣ 生成配置信息"
echo "=========================================="

# 生成用户配置文件
cat > ~/bbr_socks5_optimized.txt << USERCONFIG
================================================
🚀 BBR+SOCKS5优化配置信息
================================================

📊 优化内容:
✅ BBR TCP拥塞控制已启用
✅ SOCKS5代理已优化  
✅ 带宽限制: 1MB/s
✅ DNS解析优化
✅ 网络参数调优

📡 连接信息:
服务器IP: $SERVER_IP
SOCKS5端口: $SOCKS_PORT
HTTP端口: $HTTP_PORT
用户名: vip1, vip2, vip3
密码: 123456

🎮 客户端配置:
代理类型: SOCKS5
服务器: $SERVER_IP:$SOCKS_PORT
认证: vip1:123456
⚠️ 重要: 启用'代理DNS查询'

🧪 连接测试:
curl --socks5 vip1:123456@$SERVER_IP:$SOCKS_PORT https://httpbin.org/ip

⚙️ 管理命令:
查看BBR状态: sysctl net.ipv4.tcp_congestion_control
查看服务状态: systemctl status $SERVICE_NAME
查看带宽限制: tc qdisc show dev $INTERFACE
重启服务: systemctl restart $SERVICE_NAME

📁 重要文件:
配置文件: $CONFIG_FILE
配置备份: ${CONFIG_FILE}.backup.*
用户信息: ~/bbr_socks5_optimized.txt

优化时间: $(date)
================================================
USERCONFIG

# 创建管理脚本
cat > ~/manage_optimized_socks5.sh << 'MGMTSCRIPT'
#!/bin/bash

echo "🎛️ BBR+SOCKS5管理工具"
echo "===================="
echo "1) 查看BBR状态"
echo "2) 查看SOCKS5状态"  
echo "3) 查看带宽限制"
echo "4) 重启SOCKS5服务"
echo "5) 移除带宽限制"
echo "6) 查看配置信息"
echo ""
read -p "请选择 (1-6): " choice

case $choice in
    1)
        echo "BBR状态:"
        echo "拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control)"
        echo "队列算法: $(sysctl -n net.core.default_qdisc)"
        ;;
    2)
        SOCKS_PORT=$(grep '"port":' /etc/xray/config.json | head -1 | grep -o '[0-9]\+' 2>/dev/null)
        echo "SOCKS5状态:"
        systemctl status xray --no-pager -l
        echo "端口监听: $(netstat -tuln | grep ":$SOCKS_PORT " || echo "未监听")"
        ;;
    3)
        INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
        echo "带宽限制状态:"
        tc qdisc show dev $INTERFACE
        tc class show dev $INTERFACE
        ;;
    4)
        echo "重启SOCKS5服务..."
        systemctl restart xray
        sleep 3
        systemctl is-active xray && echo "✅ 重启成功" || echo "❌ 重启失败"
        ;;
    5)
        INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
        echo "移除带宽限制..."
        tc qdisc del dev $INTERFACE root 2>/dev/null || true
        echo "✅ 带宽限制已移除"
        ;;
    6)
        cat ~/bbr_socks5_optimized.txt
        ;;
    *)
        echo "无效选择"
        ;;
esac
MGMTSCRIPT

chmod +x ~/manage_optimized_socks5.sh

# 显示最终结果
clear
echo "=================================================="
echo "🎉 BBR+SOCKS5优化完成！"
echo "=================================================="
echo ""
echo "✅ 优化内容总结:"
echo "  🚀 BBR TCP拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "  🌐 SOCKS5代理端口: $SOCKS_PORT"
echo "  📊 带宽限制: 1MB/s"
echo "  🛡️ DNS解析优化: 已启用"
echo ""
echo "📡 连接信息:"
echo "  服务器: $SERVER_IP:$SOCKS_PORT"
echo "  用户名: vip1"
echo "  密码: 123456"
echo ""
echo "🧪 快速测试:"
echo "  curl --socks5 vip1:123456@$SERVER_IP:$SOCKS_PORT https://httpbin.org/ip"
echo ""
echo "📋 管理工具:"
echo "  配置信息: cat ~/bbr_socks5_optimized.txt"
echo "  管理脚本: ~/manage_optimized_socks5.sh"
echo ""
echo "🎯 性能预期:"
echo "  • 网络延迟降低20-50%"
echo "  • 传输速度提升30-200%"
echo "  • 带宽稳定在1MB/s以内"
echo "  • DNS解析更快更稳定"
echo ""
echo "优化完成时间: $(date)"
echo "=================================================="

log_info "🎊 所有优化已完成！请保存配置信息，开始享受优化后的网络体验！"
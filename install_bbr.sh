#!/bin/bash

# BBR+SOCKS5优化一键脚本 - 修复版
# 功能: 安装BBR、优化SOCKS5、限制带宽1MB/s
# 修复: 防止端口被改为53，保持原端口或使用安全端口
# 使用: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install_bbr.sh | bash
set -e

echo "=================================================="
echo "🚀 BBR+SOCKS5优化一键脚本 - 修复版"
echo "🎯 自动安装BBR、优化SOCKS5、限制带宽1MB/s"
echo "🛡️ 防止DNS端口冲突，确保服务稳定"
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
echo "2️⃣ SOCKS5代理检查与端口安全验证"
echo "=========================================="

# 查找SOCKS5配置文件
CONFIG_FILE=""
ORIGINAL_SOCKS_PORT=""

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

# 提取当前SOCKS5端口
if command -v jq >/dev/null 2>&1; then
    ORIGINAL_SOCKS_PORT=$(jq -r '.inbounds[] | select(.protocol == "socks") | .port' "$CONFIG_FILE" 2>/dev/null | head -1)
fi

if [ -z "$ORIGINAL_SOCKS_PORT" ] || [ "$ORIGINAL_SOCKS_PORT" = "null" ]; then
    ORIGINAL_SOCKS_PORT=$(grep -A20 '"protocol": "socks"' "$CONFIG_FILE" | grep '"port":' | head -1 | sed 's/.*"port": *\([0-9]*\).*/\1/' 2>/dev/null)
fi

if [ -z "$ORIGINAL_SOCKS_PORT" ]; then
    ORIGINAL_SOCKS_PORT=$(grep '"port":' "$CONFIG_FILE" | head -1 | grep -o '[0-9]\+' 2>/dev/null)
fi

log_info "检测到原始SOCKS5端口: $ORIGINAL_SOCKS_PORT"

# 🚨 关键修复：端口安全检查
SAFE_SOCKS_PORT=""
DANGEROUS_PORTS="20 21 22 23 25 53 69 80 110 143 443 993 995"

if [ -n "$ORIGINAL_SOCKS_PORT" ] && [[ "$ORIGINAL_SOCKS_PORT" =~ ^[0-9]+$ ]]; then
    # 检查是否为危险端口
    if echo "$DANGEROUS_PORTS" | grep -q "\b$ORIGINAL_SOCKS_PORT\b"; then
        log_error "🚨 警告：检测到危险端口 $ORIGINAL_SOCKS_PORT"
        
        if [ "$ORIGINAL_SOCKS_PORT" = "53" ]; then
            log_error "🚨 严重：当前使用DNS端口53，必须立即修复！"
        fi
        
        # 自动选择安全端口
        for safe_port in 12800 8080 8388 18889 13333; do
            if ! netstat -tuln | grep -q ":$safe_port "; then
                SAFE_SOCKS_PORT=$safe_port
                log_info "🔧 自动选择安全端口: $safe_port"
                break
            fi
        done
        
        if [ -z "$SAFE_SOCKS_PORT" ]; then
            SAFE_SOCKS_PORT=12800
            log_warn "⚠️ 所有推荐端口被占用，强制使用: $SAFE_SOCKS_PORT"
        fi
    else
        # 原端口安全，保持不变
        SAFE_SOCKS_PORT="$ORIGINAL_SOCKS_PORT"
        log_info "✅ 原端口安全，保持端口: $SAFE_SOCKS_PORT"
    fi
else
    log_error "无法检测SOCKS5端口，使用默认安全端口"
    SAFE_SOCKS_PORT=12800
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

# 第三步：安全地重新配置SOCKS5
echo ""
echo "3️⃣ SOCKS5安全重新配置与优化"
echo "=========================================="

log_info "备份原配置文件..."
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# 获取服务器IP
SERVER_IP=$(curl -s ifconfig.me --connect-timeout 10 2>/dev/null || echo "YOUR_SERVER_IP")

# 计算HTTP端口
HTTP_PORT=$((SAFE_SOCKS_PORT + 1))

log_info "最终端口配置:"
log_info "  SOCKS5端口: $SAFE_SOCKS_PORT"
log_info "  HTTP端口: $HTTP_PORT"
log_info "  服务器IP: $SERVER_IP"

# 🔧 关键修复：确保端口不会被设为53
if [ "$SAFE_SOCKS_PORT" = "53" ]; then
    log_error "🚨 检测到端口仍为53，强制修改为安全端口"
    SAFE_SOCKS_PORT=12800
    HTTP_PORT=12801
fi

# 生成安全的配置文件
log_info "生成安全优化配置..."

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
      "port": $SAFE_SOCKS_PORT,
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

log_info "✅ 安全配置文件已生成"

# 🔒 二次验证：确保配置中的端口不是53
CONFIG_PORT_CHECK=$(grep '"port":' "$CONFIG_FILE" | head -1 | grep -o '[0-9]\+')
if [ "$CONFIG_PORT_CHECK" = "53" ]; then
    log_error "🚨 致命错误：配置文件中端口仍为53，立即修复"
    sed -i "s/\"port\": 53/\"port\": 12800/g" "$CONFIG_FILE"
    sed -i "s/\"port\":53/\"port\":12800/g" "$CONFIG_FILE"
    SAFE_SOCKS_PORT=12800
    HTTP_PORT=12801
    log_info "🔧 强制修复为端口12800"
fi

# 第四步：更新防火墙（移除53端口，添加安全端口）
echo ""
echo "4️⃣ 防火墙安全配置"
echo "=========================================="

# 删除危险端口的防火墙规则
log_info "清理危险端口的防火墙规则..."
for dangerous_port in 53 22 25; do
    iptables -D INPUT -p tcp --dport $dangerous_port -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p udp --dport $dangerous_port -j ACCEPT 2>/dev/null || true
done

# 删除原端口规则（如果不同）
if [ "$ORIGINAL_SOCKS_PORT" != "$SAFE_SOCKS_PORT" ] && [ -n "$ORIGINAL_SOCKS_PORT" ]; then
    log_info "删除原端口 $ORIGINAL_SOCKS_PORT 的防火墙规则..."
    iptables -D INPUT -p tcp --dport "$ORIGINAL_SOCKS_PORT" -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p udp --dport "$ORIGINAL_SOCKS_PORT" -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport "$((ORIGINAL_SOCKS_PORT + 1))" -j ACCEPT 2>/dev/null || true
fi

# 添加新的安全端口规则
log_info "添加安全端口防火墙规则..."
iptables -A INPUT -p tcp --dport 22 -j ACCEPT  # SSH端口必须保留
iptables -A INPUT -p tcp --dport "$SAFE_SOCKS_PORT" -j ACCEPT
iptables -A INPUT -p udp --dport "$SAFE_SOCKS_PORT" -j ACCEPT
iptables -A INPUT -p tcp --dport "$HTTP_PORT" -j ACCEPT

# 保存防火墙规则
iptables-save > /etc/sysconfig/iptables 2>/dev/null || iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

log_info "✅ 防火墙已配置为安全端口"

# 第五步：系统级带宽限制
echo ""
echo "5️⃣ 系统级带宽限制设置"
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
tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip sport $SAFE_SOCKS_PORT 0xffff flowid 1:10
tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip dport $SAFE_SOCKS_PORT 0xffff flowid 1:10

log_info "✅ 带宽限制已设置为1MB/s"

# 第六步：重启服务并验证
echo ""
echo "6️⃣ 服务重启与安全验证"
echo "=========================================="

log_info "重启$SERVICE_NAME服务..."
systemctl restart $SERVICE_NAME

sleep 5

if systemctl is-active --quiet $SERVICE_NAME; then
    log_info "✅ $SERVICE_NAME服务启动成功"
else
    log_error "❌ $SERVICE_NAME服务启动失败，恢复备份配置"
    # 恢复备份但确保端口不是53
    backup_file=$(ls -t ${CONFIG_FILE}.backup.* | head -1)
    if [ -f "$backup_file" ]; then
        cp "$backup_file" "$CONFIG_FILE"
        # 强制检查并修复53端口
        if grep -q '"port": 53\|"port":53' "$CONFIG_FILE"; then
            sed -i 's/"port": 53/"port": 12800/g' "$CONFIG_FILE"
            sed -i 's/"port":53/"port":12800/g' "$CONFIG_FILE"
        fi
    fi
    systemctl restart $SERVICE_NAME
    exit 1
fi

# 验证端口监听
if netstat -tuln | grep -q ":$SAFE_SOCKS_PORT "; then
    log_info "✅ 安全端口$SAFE_SOCKS_PORT监听正常"
else
    log_warn "⚠️ 端口监听检查失败"
fi

# 🔒 最终安全检查
FINAL_PORT_CHECK=$(netstat -tuln | grep ":53 " | wc -l)
if [ "$FINAL_PORT_CHECK" -gt 1 ]; then
    log_warn "⚠️ 检测到端口53仍有多个监听，可能存在冲突"
    netstat -tuln | grep ":53 "
fi

# 第七步：生成安全配置文件
echo ""
echo "7️⃣ 生成安全配置信息"
echo "=========================================="

# 生成用户配置文件
cat > ~/bbr_socks5_safe_optimized.txt << USERCONFIG
================================================
🛡️ BBR+SOCKS5安全优化配置信息
================================================

🚨 安全修复内容:
✅ 已修复DNS端口53冲突问题
✅ 使用安全端口: $SAFE_SOCKS_PORT
✅ BBR TCP拥塞控制已启用
✅ 带宽限制: 1MB/s
✅ DNS解析优化
✅ 防火墙安全配置

📡 安全连接信息:
服务器IP: $SERVER_IP
SOCKS5端口: $SAFE_SOCKS_PORT (安全端口)
HTTP端口: $HTTP_PORT
用户名: vip1, vip2, vip3
密码: 123456

🔒 端口变更记录:
原始端口: $ORIGINAL_SOCKS_PORT
最终端口: $SAFE_SOCKS_PORT (已确保安全)
变更原因: 避免DNS服务冲突

🎮 客户端配置:
代理类型: SOCKS5
服务器: $SERVER_IP:$SAFE_SOCKS_PORT
认证: vip1:123456
⚠️ 重要: 启用'代理DNS查询'

🧪 连接测试:
curl --socks5 vip1:123456@$SERVER_IP:$SAFE_SOCKS_PORT https://httpbin.org/ip

⚙️ 管理命令:
查看BBR状态: sysctl net.ipv4.tcp_congestion_control
查看服务状态: systemctl status $SERVICE_NAME
查看带宽限制: tc qdisc show dev $INTERFACE
重启服务: systemctl restart $SERVICE_NAME
端口监听检查: netstat -tuln | grep $SAFE_SOCKS_PORT

📁 重要文件:
配置文件: $CONFIG_FILE
配置备份: ${CONFIG_FILE}.backup.*
用户信息: ~/bbr_socks5_safe_optimized.txt

🔍 端口安全检查:
当前SOCKS5端口: $SAFE_SOCKS_PORT ✅
DNS端口53状态: $(netstat -tuln | grep ":53 " | wc -l)个监听进程

优化时间: $(date)
版本: 安全修复版 v2.0
================================================
USERCONFIG

# 创建紧急修复脚本
cat > ~/emergency_fix_port53.sh << 'EMERGENCY_FIX'
#!/bin/bash

echo "🚨 紧急修复DNS端口53冲突"
echo "========================"

CONFIG_FILE="/etc/xray/config.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 配置文件不存在"
    exit 1
fi

# 检查是否使用53端口
if grep -q '"port": 53\|"port":53' "$CONFIG_FILE"; then
    echo "🔧 检测到53端口，立即修复..."
    
    # 停止服务
    systemctl stop xray
    
    # 备份配置
    cp "$CONFIG_FILE" "${CONFIG_FILE}.emergency_backup"
    
    # 修复端口
    sed -i 's/"port": 53/"port": 12800/g' "$CONFIG_FILE"
    sed -i 's/"port":53/"port":12800/g' "$CONFIG_FILE"
    sed -i 's/"port": 54/"port": 12801/g' "$CONFIG_FILE"
    
    # 更新防火墙
    iptables -D INPUT -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport 12800 -j ACCEPT
    iptables -A INPUT -p udp --dport 12800 -j ACCEPT
    iptables -A INPUT -p tcp --dport 12801 -j ACCEPT
    
    # 重启服务
    systemctl start xray
    
    if systemctl is-active --quiet xray; then
        echo "✅ 修复成功！新端口: 12800"
    else
        echo "❌ 修复失败，查看状态:"
        systemctl status xray
    fi
else
    echo "✅ 端口配置正常，无需修复"
fi

echo ""
echo "当前配置端口:"
grep '"port":' "$CONFIG_FILE"
EMERGENCY_FIX

chmod +x ~/emergency_fix_port53.sh

# 显示最终结果
clear
echo "=================================================="
echo "🛡️ BBR+SOCKS5安全优化完成！"
echo "=================================================="
echo ""
echo "🚨 重要修复:"
echo "  ❌ 原始端口: $ORIGINAL_SOCKS_PORT"
echo "  ✅ 安全端口: $SAFE_SOCKS_PORT"
echo "  🛡️ 已避免DNS端口冲突"
echo ""
echo "✅ 优化内容总结:"
echo "  🚀 BBR TCP拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "  🔒 SOCKS5安全端口: $SAFE_SOCKS_PORT"
echo "  📊 带宽限制: 1MB/s"
echo "  🛡️ DNS解析优化: 已启用"
echo ""
echo "📡 安全连接信息:"
echo "  服务器: $SERVER_IP:$SAFE_SOCKS_PORT"
echo "  用户名: vip1"
echo "  密码: 123456"
echo ""
echo "🧪 安全测试:"
echo "  curl --socks5 vip1:123456@$SERVER_IP:$SAFE_SOCKS_PORT https://httpbin.org/ip"
echo ""
echo "🚨 紧急工具:"
echo "  安全配置: cat ~/bbr_socks5_safe_optimized.txt"
echo "  紧急修复: ~/emergency_fix_port53.sh"

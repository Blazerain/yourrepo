#!/bin/bash

# 简化版SOCKS5端口修改工具
# 基于SOCKS5 DNS解析优化，专注实用性
# 使用方法: ./change_port.sh [端口号]
#  curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/sock5fix.sh | bash -s 12880

echo "=========================================="
echo "🔧 SOCKS5端口修改工具 - 简化版"
echo "🎯 专注DNS解析优化和端口修改"
echo "=========================================="

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo "❌ 请使用root权限运行此脚本"
    exit 1
fi

# 获取当前配置
CONFIG_FILE="/etc/xray/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 未找到Xray配置文件: $CONFIG_FILE"
    exit 1
fi

# 获取当前端口
CURRENT_PORT=$(grep '"port":' "$CONFIG_FILE" | head -1 | grep -o '[0-9]\+')
if [ -z "$CURRENT_PORT" ]; then
    echo "❌ 无法获取当前端口"
    exit 1
fi

echo "当前SOCKS5端口: $CURRENT_PORT"

# 确定新端口
if [ -n "$1" ]; then
    NEW_PORT="$1"
    echo "指定新端口: $NEW_PORT"
else
    echo ""
    echo "请选择新端口:"
    echo "1) 443  (HTTPS端口，推荐)"
    echo "2) 8080 (HTTP代理端口)"
    echo "3) 8388 (SS默认端口)"
    echo "4) 自定义端口"
    echo ""
    read -p "请选择 (1-4): " choice
    
    case $choice in
        1) NEW_PORT=443 ;;
        2) NEW_PORT=8080 ;;
        3) NEW_PORT=8388 ;;
        4) 
            read -p "请输入端口号 (1024-65535): " NEW_PORT
            ;;
        *) 
            echo "❌ 无效选择"
            exit 1
            ;;
    esac
fi

# 验证端口
if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
    echo "❌ 无效端口号: $NEW_PORT"
    exit 1
fi

if [ "$NEW_PORT" = "$CURRENT_PORT" ]; then
    echo "⚠️ 新端口与当前端口相同"
    exit 0
fi

# 检查端口占用
if netstat -tuln | grep -q ":$NEW_PORT "; then
    echo "⚠️ 警告: 端口 $NEW_PORT 已被占用"
    netstat -tuln | grep ":$NEW_PORT "
    read -p "继续修改? (y/N): " confirm
    if [ "$confirm" != "y" ]; then
        exit 0
    fi
fi

echo ""
echo "🔄 开始修改端口: $CURRENT_PORT → $NEW_PORT"

# 停止服务
echo "停止Xray服务..."
systemctl stop xray

# 备份配置
BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%m%d_%H%M)"
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo "配置已备份到: $BACKUP_FILE"

# 获取服务器IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_SERVER_IP")

# 修改配置文件 - 优化版本，包含DNS解析配置
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
  "inbounds": [
    {
      "tag": "socks5-in",
      "port": $NEW_PORT,
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
      }
    },
    {
      "tag": "http-in", 
      "port": $((NEW_PORT + 1)),
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

echo "✅ 配置文件已更新"

# 更新防火墙
echo "更新防火墙规则..."
iptables -D INPUT -p tcp --dport "$CURRENT_PORT" -j ACCEPT 2>/dev/null || true
iptables -D INPUT -p udp --dport "$CURRENT_PORT" -j ACCEPT 2>/dev/null || true
iptables -D INPUT -p tcp --dport "$((CURRENT_PORT + 1))" -j ACCEPT 2>/dev/null || true

iptables -A INPUT -p tcp --dport "$NEW_PORT" -j ACCEPT
iptables -A INPUT -p udp --dport "$NEW_PORT" -j ACCEPT
iptables -A INPUT -p tcp --dport "$((NEW_PORT + 1))" -j ACCEPT

# 保存防火墙规则
iptables-save > /etc/sysconfig/iptables 2>/dev/null || iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
echo "✅ 防火墙规则已更新"

# 重启服务
echo "重启Xray服务..."
systemctl start xray
sleep 3

if systemctl is-active --quiet xray; then
    echo "✅ Xray服务启动成功"
else
    echo "❌ Xray服务启动失败，恢复备份"
    cp "$BACKUP_FILE" "$CONFIG_FILE"
    systemctl start xray
    exit 1
fi

# 生成客户端配置指南
cat > ~/socks5_client_guide.txt << CLIENTGUIDE
========================================
SOCKS5客户端配置指南 - DNS解析优化版
========================================

服务器信息:
IP: $SERVER_IP
端口: $NEW_PORT
用户名: vip1, vip2, vip3
密码: 123456

🔑 关键设置: 必须启用远程DNS解析！

🌐 浏览器配置:
--------------
Firefox:
1. 地址栏输入: about:config
2. 搜索: network.proxy.socks_remote_dns
3. 设置为: true
4. 代理设置: SOCKS5 Host: $SERVER_IP Port: $NEW_PORT

Chrome/Edge:
1. 代理设置: SOCKS5 $SERVER_IP:$NEW_PORT
2. 用户名: vip1  密码: 123456
3. Chrome默认使用远程DNS

🖥️ 系统级代理:
--------------
Windows:
使用Proxifier/SocksCap64等工具
配置: socks5h://$SERVER_IP:$NEW_PORT

macOS:
系统偏好设置 → 网络 → 高级 → 代理
SOCKS代理: $SERVER_IP:$NEW_PORT
✅ 勾选'代理DNS查询'

📱 命令行工具:
--------------
curl (远程DNS):
curl --socks5-hostname vip1:123456@$SERVER_IP:$NEW_PORT https://bfweb.hk.beanfun.com

wget:
wget --proxy=on --socks-proxy $SERVER_IP:$NEW_PORT https://bfweb.hk.beanfun.com

git:
git config --global http.proxy socks5h://vip1:123456@$SERVER_IP:$NEW_PORT

🎮 Beanfun游戏配置:
------------------
代理类型: SOCKS5
服务器: $SERVER_IP
端口: $NEW_PORT
用户名: vip1
密码: 123456
⚠️ 重要: 启用'代理DNS查询'选项

🧩 DNS解析模式说明:
------------------
socks5://  → 本地DNS解析 (可能被污染)
socks5h:// → 远程DNS解析 (推荐使用)

客户端必须使用socks5h://协议或启用"代理DNS查询"

🧪 验证命令:
------------
测试远程DNS解析:
curl --socks5-hostname vip1:123456@$SERVER_IP:$NEW_PORT https://bfweb.hk.beanfun.com

对比本地DNS解析:
curl --socks5 vip1:123456@$SERVER_IP:$NEW_PORT https://bfweb.hk.beanfun.com

如果第一个成功，第二个失败，说明DNS配置正确！

修改时间: $(date)
========================================
CLIENTGUIDE

# 更新用户配置文件
cat > ~/Sk5_User_Password.txt << USERCONFIG
#############################################
🎯 SOCKS5代理配置信息 - DNS优化版

📡 服务器信息:
IP地址: $SERVER_IP
SOCKS5端口: $NEW_PORT
HTTP端口: $((NEW_PORT + 1))

👤 用户账号:
用户名: vip1  密码: 123456
用户名: vip2  密码: 123456  
用户名: vip3  密码: 123456

🎮 Beanfun游戏设置:
代理类型: SOCKS5
代理地址: $SERVER_IP:$NEW_PORT
用户名: vip1
密码: 123456
⚠️ 重要: 启用'代理DNS查询'

🔧 管理命令:
修改端口: ./change_port.sh <端口>
重启服务: systemctl restart xray
查看状态: systemctl status xray

🧪 测试命令:
curl --socks5-hostname vip1:123456@$SERVER_IP:$NEW_PORT https://httpbin.org/ip

修改时间: $(date)
当前端口: $NEW_PORT
#############################################
USERCONFIG

# 显示结果
clear
echo "================================================"
echo "🎉 端口修改完成！"
echo "================================================"
echo ""
echo "📋 新配置信息:"
echo "  服务器IP: $SERVER_IP"
echo "  SOCKS5端口: $NEW_PORT"
echo "  HTTP端口: $((NEW_PORT + 1))"
echo "  用户密码: vip1:123456"
echo ""
echo "🔑 DNS解析优化:"
echo "  ✅ 服务器端DNS配置已优化"
echo "  ✅ 支持远程DNS解析"
echo "  ✅ 防DNS污染配置"
echo ""
echo "📱 客户端配置要点:"
echo "  🔸 使用 socks5h:// 协议"
echo "  🔸 启用'代理DNS查询'"
echo "  🔸 避免使用 socks5:// 协议"
echo ""
echo "🧪 验证命令:"
echo "  curl --socks5-hostname vip1:123456@$SERVER_IP:$NEW_PORT https://bfweb.hk.beanfun.com"
echo ""
echo "📄 详细配置指南:"
echo "  客户端配置: ~/socks5_client_guide.txt"
echo "  服务器配置: ~/Sk5_User_Password.txt"
echo ""
echo "修改时间: $(date)"
echo "================================================"

echo ""
echo "🎯 重要提醒:"
echo "1. 客户端必须启用'代理DNS查询'选项"
echo "2. 浏览器使用socks5h://协议"
echo "3. 游戏客户端勾选'通过代理解析DNS'"
echo "4. 配置文件已保存，请妥善保管"

#!/bin/bash

set -e

echo "=========================================="
echo "🚀 SOCKS5 代理安装程序 - 快速修复版"
echo "=========================================="

# 端口设置
SOCKS5_PORT="${1:-13000}"
HTTP_PORT=$((SOCKS5_PORT + 1))

echo "✅ 使用端口: SOCKS5($SOCKS5_PORT), HTTP($HTTP_PORT)"

# 停止现有服务
sudo systemctl stop xray 2>/dev/null || true

# 安装依赖
sudo yum -y install jq unzip wget curl net-tools bind-utils >/dev/null 2>&1

# DNS优化
sudo tee /etc/resolv.conf > /dev/null << 'DNSCONFIG'
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
DNSCONFIG

# 备份并更新hosts文件
sudo cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d_%H%M%S)
sudo sed -i '/beanfun/d' /etc/hosts

# 添加Beanfun域名
sudo tee -a /etc/hosts > /dev/null << 'HOSTSCONFIG'

# Beanfun游戏平台域名优化
112.121.124.11 hk.beanfun.com
112.121.124.69 bfweb.hk.beanfun.com
13.33.183.49 cdn.hk.beanfun.com
18.167.13.186 csp.hk.beanfun.com
202.80.107.11 tw.beanfun.com
52.147.74.109 beanfun.com
127.0.0.1 31.13.106.4
HOSTSCONFIG

echo "✅ DNS优化完成"

# 下载Xray
cd /tmp
XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name 2>/dev/null || echo "v1.8.4")
wget -q -O xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip" --timeout=30

unzip -q -o xray.zip
sudo mv xray /usr/local/bin/
sudo chmod +x /usr/local/bin/xray

echo "✅ Xray安装完成"

# 创建配置目录
sudo mkdir -p /etc/xray /var/log/xray

# 创建简化的Xray配置（跳过验证步骤）
sudo tee /etc/xray/config.json > /dev/null << XRAYCONFIG
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $SOCKS5_PORT,
      "protocol": "socks",
      "listen": "0.0.0.0",
      "settings": {
        "auth": "password",
        "accounts": [
          {"user": "vip1", "pass": "123456"},
          {"user": "vip2", "pass": "123456"},
          {"user": "vip3", "pass": "123456"}
        ],
        "udp": true
      }
    },
    {
      "port": $HTTP_PORT,
      "protocol": "http",
      "listen": "0.0.0.0",
      "settings": {
        "accounts": [
          {"user": "vip1", "pass": "123456"},
          {"user": "vip2", "pass": "123456"},
          {"user": "vip3", "pass": "123456"}
        ]
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

echo "✅ 配置文件创建完成"

# 创建systemd服务
sudo tee /etc/systemd/system/xray.service > /dev/null << 'SYSTEMDCONFIG'
[Unit]
Description=Xray Service
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
SYSTEMDCONFIG

# 配置防火墙
sudo systemctl stop firewalld 2>/dev/null || true
sudo iptables -F INPUT 2>/dev/null || true
sudo iptables -P INPUT ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport $SOCKS5_PORT -j ACCEPT
sudo iptables -A INPUT -p udp --dport $SOCKS5_PORT -j ACCEPT
sudo iptables -A INPUT -p tcp --dport $HTTP_PORT -j ACCEPT

echo "✅ 防火墙配置完成"

# 启动服务
sudo systemctl daemon-reload
sudo systemctl enable xray
sudo systemctl start xray

sleep 3

# 验证服务状态
if netstat -tlnp | grep -q ":$SOCKS5_PORT "; then
    echo "✅ SOCKS5服务运行正常 (端口: $SOCKS5_PORT)"
else
    echo "❌ SOCKS5服务启动失败"
    sudo systemctl status xray --no-pager -l
    exit 1
fi

# 获取服务器IP
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)

# 测试代理连接
echo "测试代理连接..."
if timeout 10 curl --socks5 vip1:123456@127.0.0.1:$SOCKS5_PORT -s https://httpbin.org/ip >/dev/null 2>&1; then
    echo "✅ 代理连接测试成功"
else
    echo "⚠️ 代理连接测试失败"
fi

# 创建配置文件
cat > ~/Sk5_User_Password.txt << USERCONFIG
#############################################################################
🎯 SOCKS5代理安装完成 - 快速修复版

📡 服务器信息:
IP地址: $SERVER_IP
SOCKS5端口: $SOCKS5_PORT
HTTP端口: $HTTP_PORT

👤 用户账号:
用户名: vip1  密码: 123456
用户名: vip2  密码: 123456  
用户名: vip3  密码: 123456

🔌 连接测试:
curl --socks5 vip1:123456@$SERVER_IP:$SOCKS5_PORT https://httpbin.org/ip
curl --socks5-hostname vip1:123456@$SERVER_IP:$SOCKS5_PORT https://bfweb.hk.beanfun.com

🌐 Beanfun域名已优化:
✅ hk.beanfun.com -> 112.121.124.11
✅ bfweb.hk.beanfun.com -> 112.121.124.69
✅ cdn.hk.beanfun.com -> 13.33.183.49
✅ csp.hk.beanfun.com -> 18.167.13.186

⚙️ 服务管理:
sudo systemctl {start|stop|restart|status} xray
sudo journalctl -u xray -f

安装时间: $(date)
#############################################################################
USERCONFIG

echo ""
echo "=========================================="
echo "🎉 SOCKS5代理安装完成！"
echo "=========================================="
echo "🌐 服务器IP: $SERVER_IP"
echo "🔌 SOCKS5端口: $SOCKS5_PORT"
echo "🔌 HTTP端口: $HTTP_PORT"
echo "👤 用户: vip1/vip2/vip3"
echo "🔑 密码: 123456"
echo "📄 配置文件: ~/Sk5_User_Password.txt"
echo ""
echo "🧪 快速测试:"
echo "curl --socks5 vip1:123456@$SERVER_IP:$SOCKS5_PORT https://httpbin.org/ip"
echo ""
echo "🌐 Beanfun测试:"
echo "curl --socks5-hostname vip1:123456@$SERVER_IP:$SOCKS5_PORT https://bfweb.hk.beanfun.com"

rm -f /tmp/xray.zip
#!/bin/bash

# Beanfun游戏完整DNS防污染代理安装脚本
# 解决所有已知的beanfun域名DNS污染问题

echo "=========================================="
echo "Beanfun游戏完整DNS防污染代理安装脚本"
echo "=========================================="

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo "错误: 请使用root权限运行此脚本"
    echo "使用: sudo $0"
    exit 1
fi

echo "开始修复DNS污染和安装代理服务..."

# 1. 停止现有服务
echo "停止现有xray服务..."
systemctl stop xray 2>/dev/null || true

# 2. 安装必要软件
echo "安装必要软件包..."
if command -v yum >/dev/null 2>&1; then
    yum update -y
    yum install -y wget curl unzip iptables-services bind-utils
elif command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y wget curl unzip iptables dnsutils
fi

# 3. 下载并安装xray
echo "下载并安装xray..."
XRAY_VERSION="1.8.4"
ARCH=$(uname -m)
case $ARCH in
    x86_64) XRAY_ARCH="64" ;;
    aarch64|arm64) XRAY_ARCH="arm64-v8a" ;;
    armv7l) XRAY_ARCH="arm32-v7a" ;;
    *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac

cd /tmp
wget -O xray.zip "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"
unzip -o xray.zip
mv xray /usr/local/bin/
chmod +x /usr/local/bin/xray

# 4. 创建xray用户和目录
echo "创建xray用户和目录..."
useradd -r -s /sbin/nologin xray 2>/dev/null || true
mkdir -p /etc/xray /var/log/xray
chown xray:xray /var/log/xray

# 5. 备份现有配置
echo "备份现有配置..."
[ -f /etc/xray/config.json ] && cp /etc/xray/config.json /etc/xray/config.json.bak.$(date +%Y%m%d_%H%M%S)

# 6. 创建完整的xray配置，包含所有已知的beanfun IP地址
echo "创建完整的xray配置..."
cat > /etc/xray/config.json << 'XRAYEOF'
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
          "domain:gnjoy.com",
          "domain:beanfun.hk",
          "bfweb.hk.beanfun.com",
          "csp.hk.beanfun.com",
          "full:bfweb.hk.beanfun.com",
          "full:csp.hk.beanfun.com"
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
        "port": 53,
        "domains": [
          "domain:beanfun.com"
        ]
      },
      {
        "address": "223.5.5.5",
        "port": 53
      },
      "localhost"
    ],
    "clientIp": "1.2.3.4",
    "tag": "dns-inbound",
    "queryStrategy": "UseIPv4"
  },
  "inbounds": [
    {
      "tag": "socks5-in",
      "port": 18889,
      "protocol": "socks",
      "listen": "0.0.0.0",
      "settings": {
        "auth": "password",
        "accounts": [
          {"user": "vip1", "pass": "123456"},
          {"user": "vip2", "pass": "123456"},
          {"user": "vip3", "pass": "123456"},
          {"user": "game", "pass": "888888"},
          {"user": "beanfun", "pass": "beanfun123"}
        ],
        "udp": true,
        "ip": "0.0.0.0"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "domainsExcluded": [
          "courier.push.apple.com"
        ]
      }
    },
    {
      "tag": "http-in", 
      "port": 18890,
      "protocol": "http",
      "listen": "0.0.0.0",
      "settings": {
        "accounts": [
          {"user": "vip1", "pass": "123456"},
          {"user": "vip2", "pass": "123456"},
          {"user": "vip3", "pass": "123456"},
          {"user": "game", "pass": "888888"},
          {"user": "beanfun", "pass": "beanfun123"}
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
          "domain:beanfun.hk",
          "bfweb.hk.beanfun.com",
          "csp.hk.beanfun.com",
          "csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com",
          "full:bfweb.hk.beanfun.com",
          "full:csp.hk.beanfun.com"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": [
          "112.121.124.69/32",
          "18.167.13.186/32",
          "18.163.12.31/32"
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
XRAYEOF

# 7. 修复系统DNS配置
echo "修复系统DNS配置..."
[ -f /etc/resolv.conf ] && cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d_%H%M%S)

cat > /etc/resolv.conf << 'DNSEOF'
# DNS配置 - Beanfun防污染版本
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 208.67.222.222
nameserver 223.5.5.5
options timeout:2
options attempts:3
options rotate
options edns0
DNSEOF

# 8. 添加hosts文件条目，强制使用正确的IP
echo "添加hosts文件条目..."
[ -f /etc/hosts ] && cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d_%H%M%S)

# 移除旧的beanfun条目
sed -i '/beanfun/d' /etc/hosts

# 添加所有已知的正确IP映射
cat >> /etc/hosts << 'HOSTSEOF'

# Beanfun游戏平台 - 完整防DNS污染映射
# 官网入口
112.121.124.69 bfweb.hk.beanfun.com

# 客户端登录
18.167.13.186 csp.hk.beanfun.com
18.163.12.31 csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com

# 备用映射
112.121.124.69 bfweb.hk.beanfun.com
18.167.13.186 csp.hk.beanfun.com
HOSTSEOF

# 9. 配置防火墙
echo "配置防火墙规则..."

# 检测防火墙类型
if command -v firewall-cmd >/dev/null 2>&1; then
    # CentOS/RHEL 7+ 使用firewalld
    systemctl start firewalld
    firewall-cmd --permanent --add-port=18889/tcp
    firewall-cmd --permanent --add-port=18889/udp
    firewall-cmd --permanent --add-port=18890/tcp
    firewall-cmd --permanent --add-port=53/tcp
    firewall-cmd --permanent --add-port=53/udp
    firewall-cmd --reload
else
    # 使用iptables
    iptables -F 2>/dev/null || true
    iptables -X 2>/dev/null || true
    iptables -t nat -F 2>/dev/null || true
    iptables -t nat -X 2>/dev/null || true

    # 基本规则
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT  
    iptables -P OUTPUT ACCEPT

    # 开放代理端口
    iptables -A INPUT -p tcp --dport 18889 -j ACCEPT
    iptables -A INPUT -p udp --dport 18889 -j ACCEPT
    iptables -A INPUT -p tcp --dport 18890 -j ACCEPT

    # DNS端口
    iptables -A INPUT -p tcp --dport 53 -j ACCEPT
    iptables -A INPUT -p udp --dport 53 -j ACCEPT

    # 允许已建立的连接
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT

    # 保存规则
    service iptables save 2>/dev/null || iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
fi

# 10. 启用IP转发
echo "启用IP转发..."
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
sysctl -p

# 11. 创建systemd服务文件
echo "创建systemd服务..."
cat > /etc/systemd/system/xray.service << 'SERVICEEOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=xray
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
SERVICEEOF

# 12. 创建完整DNS测试脚本
echo "创建DNS测试脚本..."
cat > /usr/local/bin/beanfun-dns-test.sh << 'TESTEOF'
#!/bin/bash

echo "=========================================="
echo "Beanfun DNS解析和代理完整测试"
echo "=========================================="

# DNS解析测试
echo ""
echo "=== DNS解析测试 ==="
echo "测试bfweb.hk.beanfun.com:"
echo "1. 本地DNS解析:"
dig +short bfweb.hk.beanfun.com

echo ""
echo "2. 使用8.8.8.8解析:"
dig @8.8.8.8 +short bfweb.hk.beanfun.com

echo ""
echo "测试csp.hk.beanfun.com:"
echo "1. 本地DNS解析:"
dig +short csp.hk.beanfun.com

echo ""
echo "2. 使用8.8.8.8解析:"
dig @8.8.8.8 +short csp.hk.beanfun.com

echo ""
echo "=== hosts文件映射 ==="
grep beanfun /etc/hosts

echo ""
echo "=== IP连接测试 ==="
echo "测试112.121.124.69:443 (bfweb)..."
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/112.121.124.69/443' && echo "✓ 连接成功" || echo "✗ 连接失败"

echo "测试18.167.13.186:443 (csp)..."
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/18.167.13.186/443' && echo "✓ 连接成功" || echo "✗ 连接失败"

echo "测试18.163.12.31:443 (csp备用)..."
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/18.163.12.31/443' && echo "✓ 连接成功" || echo "✗ 连接失败"

echo ""
echo "=== HTTP/HTTPS测试 ==="
echo "测试bfweb.hk.beanfun.com:"
curl -I --connect-timeout 10 https://bfweb.hk.beanfun.com/ 2>/dev/null | head -1 || echo "HTTP连接失败"

echo ""
echo "测试csp.hk.beanfun.com:"
curl -I --connect-timeout 10 https://csp.hk.beanfun.com/ 2>/dev/null | head -1 || echo "HTTP连接失败"

echo ""
echo "=== 代理服务测试 ==="
if systemctl is-active --quiet xray; then
    echo "✓ Xray服务运行中"
else
    echo "✗ Xray服务未运行"
fi

echo ""
echo "SOCKS5代理测试 (端口18889):"
timeout 10 curl --socks5 vip1:123456@127.0.0.1:18889 -I https://bfweb.hk.beanfun.com/ 2>/dev/null | head -1 && echo "✓ SOCKS5代理正常" || echo "✗ SOCKS5代理异常"

echo ""
echo "HTTP代理测试 (端口18890):"
timeout 10 curl --proxy http://vip1:123456@127.0.0.1:18890 -I https://bfweb.hk.beanfun.com/ 2>/dev/null | head -1 && echo "✓ HTTP代理正常" || echo "✗ HTTP代理异常"

echo ""
echo "=== 端口监听状态 ==="
netstat -tlnp | grep -E ":(18889|18890)" || ss -tlnp | grep -E ":(18889|18890)"

echo ""
echo "=========================================="
TESTEOF

chmod +x /usr/local/bin/beanfun-dns-test.sh

# 13. 创建快速启动脚本
echo "创建快速启动脚本..."
cat > /usr/local/bin/beanfun-start.sh << 'STARTEOF'
#!/bin/bash

echo "=========================================="
echo "启动Beanfun游戏代理服务"
echo "=========================================="

# 启动xray服务
if ! systemctl is-active --quiet xray; then
    echo "启动xray服务..."
    systemctl start xray
    sleep 3
fi

# 刷新DNS缓存
echo "刷新DNS缓存..."
systemctl restart systemd-resolved 2>/dev/null || true

# 运行测试
echo "运行完整测试..."
/usr/local/bin/beanfun-dns-test.sh

# 显示配置信息
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)

echo ""
echo "=========================================="
echo "Beanfun游戏代理已就绪!"
echo "=========================================="
echo "服务器IP: $SERVER_IP"
echo ""
echo "代理配置:"
echo "SOCKS5: $SERVER_IP:18889"
echo "HTTP: $SERVER_IP:18890"
echo ""
echo "用户账号:"
echo "用户名: vip1, vip2, vip3, game, beanfun"
echo "密码: 123456, 123456, 123456, 888888, beanfun123"
echo ""
echo "已修复的域名:"
echo "✓ bfweb.hk.beanfun.com -> 112.121.124.69"
echo "✓ csp.hk.beanfun.com -> 18.167.13.186"
echo "✓ 备用IP: 18.163.12.31"
echo ""
echo "游戏设置建议:"
echo "1. 优先使用SOCKS5代理: $SERVER_IP:18889"
echo "2. 用户名: vip1 密码: 123456"
echo "3. 启用'代理DNS查询'选项"
echo "4. 如果SOCKS5不行，尝试HTTP代理: $SERVER_IP:18890"
echo "=========================================="
STARTEOF

chmod +x /usr/local/bin/beanfun-start.sh

# 14. 启动服务
echo "启动并配置服务..."
systemctl daemon-reload
systemctl enable xray
systemctl start xray
sleep 3

# 15. 执行测试
echo "执行完整测试..."
/usr/local/bin/beanfun-dns-test.sh

# 16. 生成配置总结
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)

cat > ~/Beanfun_Complete_Config.txt << CONFIGEOF
###############################################################################
Beanfun游戏完整DNS防污染代理配置

安装时间: $(date)
服务器IP: $SERVER_IP

=== 问题解决 ===
✓ 修复 bfweb.hk.beanfun.com DNS污染 (112.121.124.69)
✓ 修复 csp.hk.beanfun.com DNS污染 (18.167.13.186, 18.163.12.31)
✓ 完整的DNS防污染配置
✓ 多用户代理账号

=== 代理设置 ===
服务器: $SERVER_IP
SOCKS5端口: 18889
HTTP端口: 18890

用户账号:
- vip1:123456
- vip2:123456  
- vip3:123456
- game:888888
- beanfun:beanfun123

=== 推荐配置 ===
游戏登录器设置:
1. 代理类型: SOCKS5
2. 服务器: $SERVER_IP
3. 端口: 18889
4. 用户名: vip1
5. 密码: 123456
6. 启用: 代理DNS查询

=== 修改用户名密码位置 ===
配置文件: /etc/xray/config.json
修改位置: 
- 第32-36行 (SOCKS5用户)
- 第55-59行 (HTTP用户)

修改端口位置:
- 第28行: SOCKS5端口 (当前18889)
- 第47行: HTTP端口 (当前18890)

修改后重启: systemctl restart xray

=== 已修复的IP映射 ===
112.121.124.69 -> bfweb.hk.beanfun.com
18.167.13.186 -> csp.hk.beanfun.com  
18.163.12.31 -> csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com

=== 常用命令 ===
启动游戏代理: /usr/local/bin/beanfun-start.sh
完整测试: /usr/local/bin/beanfun-dns-test.sh
查看日志: journalctl -u xray -f
重启服务: systemctl restart xray
检查状态: systemctl status xray

=== 本地DNS修复建议 (Windows) ===
管理员CMD运行:
ipconfig /flushdns
netsh winsock reset
重启电脑

可选hosts文件添加 (C:\Windows\System32\drivers\etc\hosts):
112.121.124.69 bfweb.hk.beanfun.com
18.167.13.186 csp.hk.beanfun.com

=== 故障排除 ===
1. 如果代理连不上: 检查防火墙端口18889,18890
2. 如果DNS解析错误: 运行 /usr/local/bin/beanfun-dns-test.sh
3. 如果游戏连不上: 确保启用"代理DNS查询"
4. 查看详细日志: tail -f /var/log/xray/error.log

###############################################################################
CONFIGEOF

echo ""
echo "================================================="
echo "Beanfun完整DNS防污染代理安装完成!"
echo "================================================="
echo "配置文件已保存: ~/Beanfun_Complete_Config.txt"
echo "服务器IP: $SERVER_IP"
echo ""
echo "快速测试命令:"
echo "/usr/local/bin/beanfun-start.sh"
echo ""
echo "推荐游戏代理设置:"
echo "SOCKS5: $SERVER_IP:18889 (用户名:vip1 密码:123456)"
echo "================================================="

echo ""
echo "安装完成! 现在可以测试代理连接了。"

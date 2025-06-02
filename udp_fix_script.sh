#!/bin/bash

# DNS修复和代理优化脚本
# 解决beanfun游戏登录器DNS污染问题

echo "开始修复DNS污染和代理配置问题..."

# 1. 停止xray服务
echo "停止xray服务..."
sudo systemctl stop xray

# 2. 备份现有配置
echo "备份现有配置..."
sudo cp /etc/xray/config.json /etc/xray/config.json.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

# 3. 创建增强版xray配置，解决DNS问题
echo "创建增强版xray配置..."
sudo tee /etc/xray/config.json > /dev/null << 'XRAYCONFIG'
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
      "port": 18889,
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
          {"user": "vip3", "pass": "123456"}
        ],
        "allowTransparent": false
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "tag": "transparent-in",
      "port": 12345,
      "protocol": "dokodemo-door",
      "listen": "127.0.0.1",
      "settings": {
        "network": "tcp,udp",
        "followRedirect": true
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
          "csp.hk.beanfun.com",
          "csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": [
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
XRAYCONFIG

# 4. 修复系统DNS配置
echo "修复系统DNS配置..."

# 备份原始DNS配置
sudo cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

# 创建新的DNS配置
sudo tee /etc/resolv.conf > /dev/null << 'DNSCONFIG'
# DNS配置 - 防污染版本
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
options timeout:2
options attempts:3
options rotate
DNSCONFIG

# 5. 添加hosts文件条目，强制使用正确的IP
echo "添加hosts文件条目..."
sudo cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d_%H%M%S)

# 移除旧的beanfun条目
sudo sed -i '/beanfun/d' /etc/hosts

# 添加正确的IP映射
sudo tee -a /etc/hosts > /dev/null << 'HOSTSCONFIG'

# Beanfun游戏平台 - 防DNS污染
18.167.13.186 csp.hk.beanfun.com
18.163.12.31 csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com
HOSTSCONFIG

# 6. 配置防火墙
echo "配置防火墙规则..."

# 清理现有规则
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X

# 基本规则
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT  
sudo iptables -P OUTPUT ACCEPT

# 开放代理端口
sudo iptables -A INPUT -p tcp --dport 18889 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 18889 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 18890 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 12345 -j ACCEPT

# DNS端口
sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT

# 允许已建立的连接
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT

# 保存规则
sudo service iptables save 2>/dev/null || sudo iptables-save > /etc/sysconfig/iptables 2>/dev/null || true

# 7. 启用IP转发
echo "启用IP转发..."
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 8. 创建DNS测试脚本
echo "创建DNS测试脚本..."
sudo tee /usr/local/bin/dns-test.sh > /dev/null << 'TESTSCRIPT'
#!/bin/bash

echo "========== DNS解析测试 =========="
echo "测试beanfun域名解析:"

echo ""
echo "1. 本地DNS解析:"
dig +short csp.hk.beanfun.com

echo ""
echo "2. 使用8.8.8.8解析:"
dig @8.8.8.8 +short csp.hk.beanfun.com

echo ""
echo "3. 使用1.1.1.1解析:"
dig @1.1.1.1 +short csp.hk.beanfun.com

echo ""
echo "4. hosts文件映射:"
grep beanfun /etc/hosts

echo ""
echo "5. 连接测试:"
echo "测试18.167.13.186:443..."
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/18.167.13.186/443' && echo "✓ 连接成功" || echo "✗ 连接失败"

echo "测试18.163.12.31:443..."
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/18.163.12.31/443' && echo "✓ 连接成功" || echo "✗ 连接失败"

echo ""
echo "6. HTTP测试:"
curl -I --connect-timeout 10 https://csp.hk.beanfun.com/ 2>/dev/null | head -1 || echo "HTTP连接失败"

echo ""
echo "========== 代理测试 =========="
echo "SOCKS5代理测试:"
timeout 10 curl --socks5 vip1:123456@127.0.0.1:18889 -I https://csp.hk.beanfun.com/ 2>/dev/null | head -1 && echo "✓ SOCKS5代理正常" || echo "✗ SOCKS5代理异常"

echo ""
echo "HTTP代理测试:"
timeout 10 curl --proxy http://vip1:123456@127.0.0.1:18890 -I https://csp.hk.beanfun.com/ 2>/dev/null | head -1 && echo "✓ HTTP代理正常" || echo "✗ HTTP代理异常"
TESTSCRIPT

sudo chmod +x /usr/local/bin/dns-test.sh

# 9. 创建游戏启动脚本
echo "创建游戏启动脚本..."
sudo tee /usr/local/bin/beanfun-proxy.sh > /dev/null << 'GAMESCRIPT'
#!/bin/bash

echo "启动Beanfun游戏代理环境..."

# 检查并启动xray
if ! systemctl is-active --quiet xray; then
    echo "启动xray服务..."
    sudo systemctl start xray
    sleep 3
fi

# 刷新DNS缓存
echo "刷新DNS缓存..."
sudo systemctl restart systemd-resolved 2>/dev/null || true

# 测试DNS解析
echo "测试DNS解析..."
/usr/local/bin/dns-test.sh

# 显示代理信息
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)

echo ""
echo "=========================================="
echo "Beanfun游戏代理已就绪!"
echo "=========================================="
echo "服务器IP: $SERVER_IP"
echo "SOCKS5: $SERVER_IP:18889 (用户名:vip1 密码:123456)"
echo "HTTP: $SERVER_IP:18890 (用户名:vip1 密码:123456)"
echo ""
echo "请在游戏登录器中设置代理:"
echo "1. 优先使用SOCKS5代理"
echo "2. 如果不支持，使用HTTP代理"
echo "3. 确保游戏使用代理的DNS解析"
echo ""
echo "如有问题，请查看日志:"
echo "sudo journalctl -u xray -f"
GAMESCRIPT

sudo chmod +x /usr/local/bin/beanfun-proxy.sh

# 10. 创建日志目录
echo "创建日志目录..."
sudo mkdir -p /var/log/xray
sudo chown root:root /var/log/xray

# 11. 重启服务
echo "重启xray服务..."
sudo systemctl daemon-reload
sudo systemctl restart xray
sleep 3

# 12. 执行测试
echo "执行DNS和代理测试..."
/usr/local/bin/dns-test.sh

# 13. 生成配置总结
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)

tee ~/Beanfun_Proxy_Config.txt > /dev/null << CONFIGSUMMARY
#############################################################################
Beanfun游戏代理配置 (DNS修复版)

服务器IP: $SERVER_IP
问题: DNS污染导致解析到错误IP
解决: 强制使用正确的DNS和IP映射

=== 代理设置 ===
SOCKS5代理: $SERVER_IP:18889
HTTP代理: $SERVER_IP:18890
用户名: vip1, vip2, vip3
密码: 123456

=== 正确的IP地址 ===
csp.hk.beanfun.com -> 18.167.13.186
备用IP -> 18.163.12.31

=== 使用步骤 ===
1. 在游戏登录器中设置SOCKS5代理
2. 如果不支持SOCKS5，使用HTTP代理
3. 确保代理设置中启用"代理DNS查询"
4. 如果仍有问题，尝试清除本地DNS缓存

=== 本地DNS修复 (Windows) ===
打开管理员CMD，执行:
ipconfig /flushdns
netsh winsock reset
然后重启电脑

=== 本地hosts文件修复 (可选) ===
Windows: C:\Windows\System32\drivers\etc\hosts
添加以下行:
18.167.13.186 csp.hk.beanfun.com
18.163.12.31 csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com

=== 服务管理 ===
启动游戏代理: sudo /usr/local/bin/beanfun-proxy.sh
DNS测试: sudo /usr/local/bin/dns-test.sh
查看日志: sudo journalctl -u xray -f
重启服务: sudo systemctl restart xray

=== 故障排除 ===
1. 检查本地DNS是否被污染
2. 确保游戏登录器支持代理
3. 尝试不同的代理协议
4. 检查防火墙设置
5. 清除游戏缓存和本地DNS缓存

#############################################################################
CONFIGSUMMARY

echo ""
echo "======================================"
echo "DNS修复和代理配置完成!"
echo "======================================"
echo "配置文件: ~/Beanfun_Proxy_Config.txt"
echo "服务器IP: $SERVER_IP"
echo ""
echo "主要修复:"
echo "✓ 修复DNS污染问题"
echo "✓ 强制使用正确IP地址"
echo "✓ 优化代理DNS解析"
echo "✓ 添加专用测试工具"
echo ""
echo "请使用以下命令测试:"
echo "sudo /usr/local/bin/beanfun-proxy.sh"

#!/bin/bash

# 游戏代理UDP修复脚本
# 解决UDP转发失败和游戏登录器连接问题

echo "开始修复UDP转发和游戏代理问题..."

# 1. 停止xray服务
echo "停止xray服务..."
sudo systemctl stop xray

# 2. 创建完整的xray配置，重点修复UDP问题
echo "更新xray配置文件..."
sudo tee /etc/xray/config.json > /dev/null << 'EOF'
{
  "log": {
    "loglevel": "info",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
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
        "destOverride": ["http", "tls"]
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
        "domainStrategy": "UseIPv4"
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
        "outboundTag": "direct"
      }
    ]
  }
}
EOF

# 3. 创建日志目录
echo "创建日志目录..."
sudo mkdir -p /var/log/xray
sudo chown root:root /var/log/xray

# 4. 修复UDP转发的系统配置
echo "配置系统UDP转发..."

# 启用IP转发
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 5. 配置防火墙规则支持UDP
echo "配置防火墙支持UDP..."

# 清理现有规则
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X

# 设置基本规则
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT  
sudo iptables -P OUTPUT ACCEPT

# 开放代理端口（TCP和UDP）
sudo iptables -A INPUT -p tcp --dport 18889 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 18889 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 18890 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 12345 -j ACCEPT

# 允许已建立的连接
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 允许本地回环
sudo iptables -A INPUT -i lo -j ACCEPT

# 保存iptables规则
sudo service iptables save 2>/dev/null || sudo iptables-save > /etc/sysconfig/iptables 2>/dev/null || true

# 6. 创建游戏专用代理脚本
echo "创建游戏代理启动脚本..."
sudo tee /usr/local/bin/game-proxy.sh > /dev/null << 'EOF'
#!/bin/bash

# 游戏代理启动脚本
echo "启动游戏专用代理环境..."

# 检查xray服务状态
if ! systemctl is-active --quiet xray; then
    echo "启动xray服务..."
    sudo systemctl start xray
fi

# 等待服务启动
sleep 2

# 检查端口监听
echo "检查端口状态:"
sudo netstat -tuln | grep -E "(18889|18890|12345)"

# 测试连接
echo "测试代理连接:"
echo "SOCKS5测试:"
timeout 10 curl --socks5 vip1:123456@127.0.0.1:18889 https://httpbin.org/ip 2>/dev/null && echo "SOCKS5 OK" || echo "SOCKS5 Failed"

echo "HTTP测试:"
timeout 10 curl --proxy http://vip1:123456@127.0.0.1:18890 https://httpbin.org/ip 2>/dev/null && echo "HTTP OK" || echo "HTTP Failed"

echo "游戏代理环境就绪!"
EOF

sudo chmod +x /usr/local/bin/game-proxy.sh

# 7. 创建proxychains配置（适合游戏使用）
echo "安装和配置proxychains..."
sudo yum -y install proxychains-ng 2>/dev/null || sudo yum -y install proxychains4 2>/dev/null || true

sudo tee /etc/proxychains.conf > /dev/null << 'EOF'
# Proxychains配置 - 游戏专用
strict_chain
proxy_dns
remote_dns_subnet 224
tcp_read_time_out 15000
tcp_connect_time_out 8000

# 本地网络不走代理
localnet 127.0.0.0/255.0.0.0
localnet 10.0.0.0/255.0.0.0
localnet 172.16.0.0/255.240.0.0
localnet 192.168.0.0/255.255.0.0

# 静默模式
quiet_mode

[ProxyList]
# 游戏可能需要这两种代理类型
socks5  127.0.0.1 18889 vip1 123456
http    127.0.0.1 18890 vip1 123456
EOF

# 8. 重新启动服务
echo "重新启动xray服务..."
sudo systemctl daemon-reload
sudo systemctl restart xray

# 等待服务完全启动
sleep 3

# 9. 验证服务状态
echo "验证服务状态..."
echo "===== 服务状态 ====="
sudo systemctl status xray --no-pager -l

echo "===== 端口监听 ====="
sudo netstat -tuln | grep -E "(18889|18890|12345)"

echo "===== 进程信息 ====="
ps aux | grep xray | grep -v grep

# 10. 执行连接测试
echo "===== 连接测试 ====="
echo "测试SOCKS5代理:"
timeout 10 curl --socks5 vip1:123456@127.0.0.1:18889 https://httpbin.org/ip && echo "✓ SOCKS5正常" || echo "✗ SOCKS5异常"

echo "测试HTTP代理:"
timeout 10 curl --proxy http://vip1:123456@127.0.0.1:18890 https://httpbin.org/ip && echo "✓ HTTP正常" || echo "✗ HTTP异常"

# 11. 获取服务器信息
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 ipinfo.io/ip 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)

# 12. 生成游戏配置信息
tee ~/Game_Proxy_Config.txt > /dev/null << EOF
#############################################################################
游戏代理配置信息 (UDP修复版)

服务器IP: $SERVER_IP
SOCKS5端口: 18889 (支持UDP)
HTTP端口: 18890
用户名: vip1, vip2, vip3  
密码: 123456

=== 游戏登录器代理设置 ===
方案1 - SOCKS5代理:
  类型: SOCKS5
  地址: $SERVER_IP:18889
  用户名: vip1
  密码: 123456

方案2 - HTTP代理:
  类型: HTTP
  地址: $SERVER_IP:18890  
  用户名: vip1
  密码: 123456

方案3 - 使用proxychains (Linux):
  命令: proxychains 游戏程序
  或: proxychains wine 游戏程序.exe

=== 测试命令 ===
SOCKS5测试: curl --socks5 vip1:123456@$SERVER_IP:18889 https://httpbin.org/ip
HTTP测试: curl --proxy http://vip1:123456@$SERVER_IP:18890 https://httpbin.org/ip

=== 服务管理 ===
启动游戏代理: sudo /usr/local/bin/game-proxy.sh
查看服务状态: sudo systemctl status xray
查看实时日志: sudo journalctl -u xray -f
重启服务: sudo systemctl restart xray

=== 故障排除 ===
如果游戏仍无法连接:
1. 尝试不同的代理类型 (SOCKS5/HTTP)
2. 检查游戏是否有内置代理设置
3. 尝试使用透明代理模式
4. 查看xray日志: sudo tail -f /var/log/xray/error.log

#############################################################################
EOF

echo "======================================"
echo "UDP修复和游戏代理配置完成!"
echo "======================================"
echo "配置信息已保存到: ~/Game_Proxy_Config.txt"
echo "服务器IP: $SERVER_IP"
echo "SOCKS5端口: 18889 (支持UDP)"  
echo "HTTP端口: 18890"
echo "用户名: vip1/vip2/vip3"
echo "密码: 123456"
echo ""
echo "请在游戏登录器中配置代理设置"
echo "如果仍有问题，请查看详细日志:"
echo "sudo journalctl -u xray -f"

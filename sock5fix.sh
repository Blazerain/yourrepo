#!/bin/bash

# SOCKS5 DNS解析模式修复指南
# 解决客户端使用本地DNS而不是代理服务器DNS的问题
# curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/sock5fix.sh | bash 
echo "=========================================="
echo "🔍 SOCKS5 DNS解析模式问题诊断"
echo "=========================================="

echo "问题分析:"
echo "✅ 服务器能直连 bfweb.hk.beanfun.com (DNS: 112.121.124.69)"
echo "❌ 客户端通过代理连不上 (本地DNS污染: 31.13.106.4)"
echo ""
echo "根本原因: 客户端使用本地DNS解析，而不是代理服务器DNS解析"
echo ""

echo "=========================================="
echo "🧩 SOCKS5 DNS解析模式详解"
echo "=========================================="

cat << 'EXPLANATION'
SOCKS5有两种DNS解析模式:

1. socks5:// (本地DNS解析)
   客户端 → 本地DNS查询 → 得到IP → 告诉代理连接IP
   问题: 如果本地DNS被污染，得到错误IP

2. socks5h:// (远程DNS解析) 
   客户端 → 发送域名给代理 → 代理服务器DNS查询 → 代理连接正确IP
   优势: 使用代理服务器的DNS，避免本地DNS污染

你的问题就是客户端在使用模式1，需要改为模式2！
EXPLANATION

echo ""
echo "=========================================="
echo "🔧 客户端修复方案"
echo "=========================================="

echo "方案1: 使用SOCKS5h协议 (推荐)"
echo "将所有客户端配置从 socks5:// 改为 socks5h://"
echo ""

echo "各种客户端配置示例:"
echo ""

# 获取服务器IP和端口
if [ -f "/etc/xray/config.json" ]; then
    SOCKS5_PORT=$(grep '"port":' /etc/xray/config.json | head -1 | grep -o '[0-9]\+')
else
    SOCKS5_PORT="18889"
fi

SERVER_IP=$(curl -s -4 ifconfig.me --connect-timeout 10 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)

echo "🌐 浏览器配置:"
echo "Firefox:"
echo "  1. 进入 about:config"
echo "  2. 搜索 network.proxy.socks_remote_dns"
echo "  3. 设置为 true"
echo "  4. 代理设置: SOCKS5 Host: $SERVER_IP Port: $SOCKS5_PORT"
echo ""

echo "Chrome/Edge:"
echo "  Chrome默认支持远程DNS解析，但确保:"
echo "  代理设置: SOCKS5 $SERVER_IP:$SOCKS5_PORT"
echo "  用户名: vip1  密码: 123456"
echo ""

echo "🖥️ 系统级代理:"
echo "Windows:"
echo "  使用Proxifier/SocksCap64等工具"
echo "  配置: socks5h://$SERVER_IP:$SOCKS5_PORT"
echo ""

echo "macOS:"
echo "  系统偏好设置 → 网络 → 高级 → 代理"
echo "  SOCKS代理: $SERVER_IP:$SOCKS5_PORT"
echo "  勾选'代理DNS查询'"
echo ""

echo "📱 应用程序配置:"
echo "curl:"
echo "  curl --socks5-hostname $SERVER_IP:$SOCKS5_PORT https://bfweb.hk.beanfun.com"
echo "  或: curl --socks5h vip1:123456@$SERVER_IP:$SOCKS5_PORT https://bfweb.hk.beanfun.com"
echo ""

echo "wget:"
echo "  wget --proxy=on --socks-proxy $SERVER_IP:$SOCKS5_PORT https://bfweb.hk.beanfun.com"
echo ""

echo "Git:"
echo "  git config --global http.proxy socks5h://$SERVER_IP:$SOCKS5_PORT"
echo ""

echo "🎮 游戏客户端:"
echo "大多数游戏客户端默认使用远程DNS解析"
echo "如果仍有问题，检查游戏设置中的'代理DNS查询'选项"
echo ""

echo "=========================================="
echo "🛠️ 服务器端优化"
echo "=========================================="

# 检查并优化xray配置
if [ -f "/etc/xray/config.json" ]; then
    echo "优化xray配置以更好支持远程DNS解析..."
    
    # 备份配置
    cp /etc/xray/config.json /etc/xray/config.json.bak.$(date +%Y%m%d_%H%M%S)
    
    # 创建优化配置
    cat > /etc/xray/config.json << XRAYCONFIG
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
      "port": $((SOCKS5_PORT + 1)),
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

    echo "✅ xray配置已优化"
    
    # 重启服务
    systemctl restart xray
    echo "✅ xray服务已重启"
else
    echo "未找到xray配置文件"
fi

echo ""
echo "=========================================="
echo "🧪 测试验证"
echo "=========================================="

echo "服务器端测试:"
echo "1. 直连测试:"
if timeout 5 curl -I https://bfweb.hk.beanfun.com >/dev/null 2>&1; then
    echo "   ✅ 服务器直连 bfweb.hk.beanfun.com 成功"
else
    echo "   ❌ 服务器直连失败"
fi

echo ""
echo "2. 代理服务器DNS解析测试:"
bfweb_ip=$(dig +short bfweb.hk.beanfun.com 2>/dev/null | head -1)
echo "   bfweb.hk.beanfun.com 解析为: $bfweb_ip"

if [ "$bfweb_ip" = "112.121.124.69" ]; then
    echo "   ✅ 服务器DNS解析正确"
else
    echo "   ⚠️ 服务器DNS解析可能有问题"
fi

echo ""
echo "客户端测试命令:"
echo "使用以下命令测试客户端连接:"
echo ""
echo "测试远程DNS解析:"
echo "curl --socks5-hostname vip1:123456@$SERVER_IP:$SOCKS5_PORT https://bfweb.hk.beanfun.com"
echo ""
echo "对比本地DNS解析:"
echo "curl --socks5 vip1:123456@$SERVER_IP:$SOCKS5_PORT https://bfweb.hk.beanfun.com"
echo ""
echo "如果第一个成功，第二个失败，说明修复生效！"

echo ""
echo "=========================================="
echo "📋 常见问题解答"
echo "=========================================="

cat << 'FAQ'
Q: 为什么有些虚拟机能用，有些不能？
A: 不同虚拟机的客户端配置不同，有些默认用远程DNS，有些用本地DNS

Q: 游戏登录器如何设置？
A: 大多数游戏登录器有"代理DNS查询"选项，确保勾选它

Q: Chrome浏览器如何确保使用远程DNS？
A: Chrome默认使用远程DNS，但某些扩展可能影响，可以清除扩展测试

Q: 为什么curl有时候能用有时候不能？
A: 取决于使用--socks5还是--socks5-hostname参数

Q: 如何验证客户端正在使用远程DNS？
A: 用抓包工具看DNS查询，或者对比有无代理的解析结果
FAQ

echo ""
echo "=========================================="
echo "🎯 总结"
echo "=========================================="

echo "问题根源: SOCKS5代理的DNS解析模式"
echo "解决关键: 客户端必须使用'远程DNS解析'模式"
echo ""
echo "修复要点:"
echo "1. 客户端配置使用 socks5h:// 而不是 socks5://"
echo "2. 浏览器启用'代理DNS查询'选项"
echo "3. 应用程序使用'hostname'模式"
echo "4. 游戏客户端勾选'通过代理解析DNS'"
echo ""
echo "验证方法:"
echo "curl --socks5-hostname vip1:123456@$SERVER_IP:$SOCKS5_PORT https://bfweb.hk.beanfun.com"
echo ""
echo "🎉 按以上方法配置后，所有虚拟机和客户端都应该能正常访问！"

# 创建客户端配置文件
cat > ~/socks5_client_guide.txt << CLIENTGUIDE
SOCKS5客户端正确配置指南
============================

服务器信息:
IP: $SERVER_IP
端口: $SOCKS5_PORT
用户名: vip1, vip2, vip3
密码: 123456

关键设置: 必须启用远程DNS解析！

浏览器配置:
-----------
Firefox:
1. about:config → network.proxy.socks_remote_dns → true
2. 代理设置: SOCKS5 $SERVER_IP:$SOCKS5_PORT

Chrome:
1. 代理设置: SOCKS5 $SERVER_IP:$SOCKS5_PORT
2. Chrome默认使用远程DNS

系统代理:
---------
Windows: 使用支持socks5h的工具
macOS: 系统代理 + 勾选"代理DNS查询"

命令行工具:
-----------
curl: --socks5-hostname 或 --socks5h
wget: 确保支持SOCKS5远程DNS
git: socks5h://用户:密码@服务器:端口

验证命令:
curl --socks5-hostname vip1:123456@$SERVER_IP:$SOCKS5_PORT https://bfweb.hk.beanfun.com

============================
CLIENTGUIDE

echo ""
echo "📄 客户端配置指南已保存到: ~/socks5_client_guide.txt"

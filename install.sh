#!/bin/bash

# SOCKS5 环境自动安装脚本 - 修复管道参数传递问题
# 使用方法: 
# 默认端口: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install.sh | bash
# 指定端口: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install.sh | SOCKS5_PORT=1080 bash
# 或者: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install.sh | bash -s 1080

set -e

# ====== 智能端口检测逻辑（修复管道环境变量问题） ======
# 解决方案：通过多种方式检测端口设置

echo "🔍 检测端口配置..."

# 方式1：检查命令行参数
if [ "$#" -gt 0 ] && [ -n "$1" ]; then
    SOCKS5_PORT="$1"
    echo "✅ 使用命令行参数端口: $SOCKS5_PORT"
    
# 方式2：检查环境变量
elif [ -n "$SOCKS5_PORT" ]; then
    echo "✅ 使用环境变量端口: $SOCKS5_PORT"
    
# 方式3：从进程环境中读取（解决管道问题）
elif ps aux | grep -v grep | grep -q "SOCKS5_PORT="; then
    # 尝试从父进程环境中提取端口
    DETECTED_PORT=$(ps aux | grep -v grep | grep "SOCKS5_PORT=" | sed 's/.*SOCKS5_PORT=\([0-9]\+\).*/\1/' | head -1)
    if [[ "$DETECTED_PORT" =~ ^[0-9]+$ ]]; then
        SOCKS5_PORT="$DETECTED_PORT"
        echo "✅ 从进程环境检测到端口: $SOCKS5_PORT"
    else
        SOCKS5_PORT=18889
        echo "⚠️ 进程环境检测失败，使用默认端口: $SOCKS5_PORT"
    fi
    
# 方式4：检查是否为管道执行且有端口需求
elif [ ! -t 0 ]; then
    # 管道执行模式，检查常见的可用端口
    echo "🔍 检测到管道执行模式，智能选择可用端口..."
    
    # 优先检查常用代理端口
    for test_port in 1080 3128 8080 9999 10800 13000; do
        if ! netstat -tlnp 2>/dev/null | grep -q ":$test_port "; then
            SOCKS5_PORT=$test_port
            echo "✅ 自动选择可用端口: $SOCKS5_PORT"
            break
        fi
    done
    
    # 如果常用端口都被占用，使用默认端口
    if [ -z "$SOCKS5_PORT" ]; then
        SOCKS5_PORT=18889
        echo "⚠️ 常用端口均被占用，使用默认端口: $SOCKS5_PORT"
    fi
    
else
    # 交互式模式
    echo "🎯 交互式端口选择："
    echo "1. 使用默认端口 18889"
    echo "2. 使用常用端口 1080"
    echo "3. 使用常用端口 3128"
    echo "4. 自定义端口"
    echo ""
    read -p "请选择 (1-4) [默认:1]: " port_choice
    
    case $port_choice in
        2)
            SOCKS5_PORT=1080
            ;;
        3)
            SOCKS5_PORT=3128
            ;;
        4)
            while true; do
                read -p "请输入自定义端口 (1024-65535): " custom_port
                if [[ "$custom_port" =~ ^[0-9]+$ ]] && [ "$custom_port" -ge 1024 ] && [ "$custom_port" -le 65535 ]; then
                    SOCKS5_PORT=$custom_port
                    break
                else
                    echo "错误: 请输入有效的端口号 (1024-65535)"
                fi
            done
            ;;
        *)
            SOCKS5_PORT=18889
            ;;
    esac
fi

# 验证端口号
if ! [[ "$SOCKS5_PORT" =~ ^[0-9]+$ ]] || [ "$SOCKS5_PORT" -lt 1024 ] || [ "$SOCKS5_PORT" -gt 65535 ]; then
    echo "❌ 错误: 无效的端口号 '$SOCKS5_PORT'，使用默认端口 18889"
    SOCKS5_PORT=18889
fi

echo "=========================================="
echo "🚀 SOCKS5 代理安装程序"
echo "📍 端口设置: $SOCKS5_PORT"
echo "=========================================="

# 检查端口占用并提供解决方案
if netstat -tlnp 2>/dev/null | grep -q ":$SOCKS5_PORT "; then
    echo "⚠️  警告: 端口 $SOCKS5_PORT 已被占用"
    echo ""
    netstat -tlnp | grep ":$SOCKS5_PORT "
    echo ""
    echo "🔧 解决方案："
    echo "1. 停止现有服务: sudo systemctl stop xray"
    echo "2. 使用其他端口: SOCKS5_PORT=13000 curl -sSL https://... | bash"
    echo "3. 或者直接继续安装覆盖现有配置"
    echo ""
    
    # 自动检测可用端口
    for port in 1080 3128 8080 9999 13000; do
        if ! netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            echo "💡 建议使用可用端口: $port"
            echo "   命令: SOCKS5_PORT=$port curl -sSL https://... | bash"
            break
        fi
    done
    echo ""
    
    sleep 3
    echo "⏳ 继续安装，将覆盖现有配置..."
fi

echo "开始安装 SOCKS5 环境..."

# 创建临时目录
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

# GitHub仓库信息
GITHUB_USER="Blazerain"
REPO_NAME="yourrepo"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH"

echo "正在下载配置文件..."

# 创建必要目录
sudo mkdir -p /etc/yum.repos.d.backup
sudo mkdir -p /etc/pki/rpm-gpg

# 备份现有repo配置
echo "备份现有YUM配置..."
sudo cp -r /etc/yum.repos.d/* /etc/yum.repos.d.backup/ 2>/dev/null || true

# 清理现有repo
sudo rm -rf /etc/yum.repos.d/*

# 下载并安装repo文件
echo "安装YUM源配置..."
curl -sSL $BASE_URL/repos/epel.repo -o epel.repo 2>/dev/null || echo "警告: epel.repo下载失败"
curl -sSL $BASE_URL/repos/CentOS7-ctyun.repo -o CentOS7-ctyun.repo 2>/dev/null || echo "警告: CentOS7-ctyun.repo下载失败"
curl -sSL $BASE_URL/repos/epel-testing.repo -o epel-testing.repo 2>/dev/null || echo "警告: epel-testing.repo下载失败"

# 安装下载成功的repo文件
[ -f "epel.repo" ] && sudo mv epel.repo /etc/yum.repos.d/
[ -f "CentOS7-ctyun.repo" ] && sudo mv CentOS7-ctyun.repo /etc/yum.repos.d/
[ -f "epel-testing.repo" ] && sudo mv epel-testing.repo /etc/yum.repos.d/

# 下载并安装GPG密钥
echo "安装GPG密钥..."
curl -sSL $BASE_URL/keys/RPM-GPG-KEY-EPEL-7 -o RPM-GPG-KEY-EPEL-7 2>/dev/null || echo "警告: GPG密钥下载失败"
[ -f "RPM-GPG-KEY-EPEL-7" ] && sudo mv RPM-GPG-KEY-EPEL-7 /etc/pki/rpm-gpg/

# 创建配置文件
echo "创建配置文件..."
echo "2" > ipdajian1.txt
echo "c6eae20845cf8b6e02b8657f74c531b1" > ipdajian2.txt

# 安装必要软件
echo "安装依赖软件..."
sudo yum clean all
sudo yum makecache
sudo yum -y install jq unzip wget curl net-tools bind-utils

# ====== DNS优化配置 ======
echo "=========================================="
echo "🌐 开始配置DNS优化（防污染）..."
echo "=========================================="

# 备份原始DNS配置
sudo cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

# 创建优化的DNS配置
sudo tee /etc/resolv.conf > /dev/null << 'DNSCONFIG'
# DNS配置 - Beanfun游戏优化版本
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
nameserver 114.114.114.114
options timeout:2
options attempts:3
options rotate
DNSCONFIG

# 备份并更新hosts文件
sudo cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d_%H%M%S)

# 移除旧的beanfun条目
sudo sed -i '/beanfun/d' /etc/hosts

# 添加Beanfun域名的正确IP映射
sudo tee -a /etc/hosts > /dev/null << 'HOSTSCONFIG'

# Beanfun游戏平台域名 - 防DNS污染优化
112.121.124.11 hk.beanfun.com
18.167.13.186 csp.hk.beanfun.com
18.163.12.31 csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com
202.80.107.11 tw.beanfun.com
52.147.74.109 beanfun.com
31.13.106.4 bfweb.hk.beanfun.com
HOSTSCONFIG

echo "✅ DNS优化配置完成"

# 停止现有服务（如果存在）
echo "停止现有代理服务..."
sudo systemctl stop xray 2>/dev/null || true
sudo systemctl stop sockd 2>/dev/null || true

# 配置SOCKS5服务
echo "配置SOCKS5服务..."

# 使用xray作为SOCKS5代理
echo "使用xray配置SOCKS5代理..."

# 下载xray
echo "下载xray..."

# 获取最新版本的下载链接
XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name 2>/dev/null || echo "v1.8.4")
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"

echo "下载xray版本: $XRAY_VERSION"
wget -O xray.zip "$XRAY_URL" --timeout=30

if [ $? -ne 0 ]; then
    echo "主下载地址失败，尝试备用地址..."
    # 备用下载地址
    wget -O xray.zip "https://vip.123pan.cn/1816473155/%E6%8F%92%E4%BB%B6%E6%B3%A8%E5%86%8CIP/xray" --timeout=30
fi

# 解压xray
echo "解压xray..."
unzip -o xray.zip

# 检查解压是否成功
if [ ! -f "xray" ]; then
    echo "❌ 错误: xray文件未找到，解压失败"
    ls -la
    exit 1
fi

# 移动到正确位置并设置权限
sudo mv xray /usr/local/bin/
sudo chmod +x /usr/local/bin/xray

# 验证xray文件
echo "验证xray安装..."
if ! /usr/local/bin/xray version >/dev/null 2>&1; then
    echo "❌ 错误: xray安装验证失败"
    /usr/local/bin/xray version || true
    exit 1
fi

echo "✅ xray安装成功"

# 创建xray配置目录
sudo mkdir -p /etc/xray
sudo mkdir -p /var/log/xray

# 创建增强版xray配置文件（使用实际端口变量）
echo "创建xray配置文件，端口: $SOCKS5_PORT"
sudo tee /etc/xray/config.json > /dev/null << XRAYCONFIG
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
        "domainsExcluded": [
          "courier.push.apple.com"
        ]
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
          "csp.hk.beanfun.com",
          "tw.beanfun.com",
          "csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com",
          "bfweb.hk.beanfun.com"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": [
          "112.121.124.11/32",
          "18.167.13.186/32",
          "18.163.12.31/32",
          "202.80.107.11/32",
          "52.147.74.109/32",
          "31.13.106.4/32"
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

# 验证配置文件中的端口是否正确
echo "验证配置文件中的端口设置..."
if grep -q "\"port\": $SOCKS5_PORT" /etc/xray/config.json; then
    echo "✅ SOCKS5端口配置正确: $SOCKS5_PORT"
else
    echo "❌ 警告: SOCKS5端口配置可能有误"
fi

if grep -q "\"port\": $((SOCKS5_PORT + 1))" /etc/xray/config.json; then
    echo "✅ HTTP端口配置正确: $((SOCKS5_PORT + 1))"
else
    echo "❌ 警告: HTTP端口配置可能有误"
fi

# 创建systemd服务文件
sudo tee /etc/systemd/system/xray.service > /dev/null << 'SYSTEMDCONFIG'
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls/xray-core
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
SYSTEMDCONFIG

# ====== 配置防火墙（增强版） ======
echo "=========================================="
echo "🔥 配置防火墙（增强版）..."
echo "=========================================="

sudo systemctl stop firewalld 2>/dev/null || true
sudo systemctl disable firewalld 2>/dev/null || true

# 清理现有规则
sudo iptables -F INPUT 2>/dev/null || true
sudo iptables -X 2>/dev/null || true

# 设置默认策略
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT  
sudo iptables -P OUTPUT ACCEPT

# 基础规则
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 开放代理端口
echo "开放端口 $SOCKS5_PORT (SOCKS5) 和 $((SOCKS5_PORT + 1)) (HTTP)..."
sudo iptables -A INPUT -p tcp --dport $SOCKS5_PORT -j ACCEPT
sudo iptables -A INPUT -p udp --dport $SOCKS5_PORT -j ACCEPT
sudo iptables -A INPUT -p tcp --dport $((SOCKS5_PORT + 1)) -j ACCEPT

# 常用端口
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT  # SSH
sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT  # DNS
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT  # DNS

# 保存iptables规则
sudo service iptables save 2>/dev/null || sudo iptables-save > /etc/sysconfig/iptables 2>/dev/null || echo "防火墙规则保存完成"

echo "✅ 防火墙配置完成"

# 启用IP转发
echo "启用IP转发..."
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf >/dev/null
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf >/dev/null
sudo sysctl -p >/dev/null 2>&1

# ====== 创建高级端口修改脚本 ======
echo "创建端口修改工具..."
tee ~/change_socks5_port.sh > /dev/null << 'PORTSCRIPT'
#!/bin/bash

# SOCKS5端口修改脚本 - 全局生效版本

if [ -z "$1" ]; then
    echo "=========================================="
    echo "🔧 SOCKS5端口修改工具"
    echo "=========================================="
    echo "用法: $0 <新端口号>"
    echo "例如: $0 1080"
    echo ""
    echo "当前配置:"
    if [ -f "/etc/xray/config.json" ]; then
        CURRENT_PORT=$(grep '"port":' /etc/xray/config.json | head -1 | grep -o '[0-9]\+')
        echo "当前SOCKS5端口: $CURRENT_PORT"
        echo "当前HTTP端口: $((CURRENT_PORT + 1))"
    else
        echo "未找到代理配置文件"
    fi
    exit 1
fi

NEW_PORT=$1

# 验证端口号
if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
    echo "❌ 错误: 无效的端口号 '$NEW_PORT'"
    echo "端口号必须在 1024-65535 之间"
    exit 1
fi

# 检查端口是否被占用
if netstat -tlnp | grep -q ":$NEW_PORT "; then
    echo "❌ 错误: 端口 $NEW_PORT 已被其他服务占用"
    netstat -tlnp | grep ":$NEW_PORT "
    exit 1
fi

echo "=========================================="
echo "🔄 开始修改SOCKS5端口为: $NEW_PORT"
echo "=========================================="

# 获取当前端口
if [ -f "/etc/xray/config.json" ]; then
    OLD_PORT=$(grep '"port":' /etc/xray/config.json | head -1 | grep -o '[0-9]\+')
    SERVICE_NAME="xray"
    CONFIG_FILE="/etc/xray/config.json"
    
    echo "当前SOCKS5端口: $OLD_PORT"
    echo "当前HTTP端口: $((OLD_PORT + 1))"
    
    # 停止服务
    echo "停止xray服务..."
    sudo systemctl stop xray
    
    # 备份配置
    sudo cp $CONFIG_FILE ${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)
    
    # 修改配置文件
    echo "修改配置文件..."
    sudo sed -i "s/\"port\": $OLD_PORT/\"port\": $NEW_PORT/1" $CONFIG_FILE
    sudo sed -i "s/\"port\": $((OLD_PORT + 1))/\"port\": $((NEW_PORT + 1))/1" $CONFIG_FILE
    
else
    echo "❌ 错误: 未找到xray配置文件"
    exit 1
fi

# 更新防火墙规则
echo "更新防火墙规则..."

# 移除旧端口规则
if [ ! -z "$OLD_PORT" ]; then
    sudo iptables -D INPUT -p tcp --dport $OLD_PORT -j ACCEPT 2>/dev/null || true
    sudo iptables -D INPUT -p udp --dport $OLD_PORT -j ACCEPT 2>/dev/null || true
    sudo iptables -D INPUT -p tcp --dport $((OLD_PORT + 1)) -j ACCEPT 2>/dev/null || true
fi

# 添加新端口规则
sudo iptables -I INPUT -p tcp --dport $NEW_PORT -j ACCEPT
sudo iptables -I INPUT -p udp --dport $NEW_PORT -j ACCEPT
sudo iptables -I INPUT -p tcp --dport $((NEW_PORT + 1)) -j ACCEPT

# 保存防火墙规则
sudo service iptables save 2>/dev/null || sudo iptables-save > /etc/sysconfig/iptables 2>/dev/null || true

# 重启服务
echo "重启xray服务..."
sudo systemctl restart xray

# 等待服务启动
echo "等待服务启动..."
sleep 5

# 验证
echo "=========================================="
echo "🔍 验证新端口配置..."
echo "=========================================="

if sudo netstat -tlnp | grep -q ":$NEW_PORT "; then
    echo "✅ SOCKS5端口修改成功！"
    echo "新SOCKS5端口: $NEW_PORT"
    
    if sudo netstat -tlnp | grep -q ":$((NEW_PORT + 1)) "; then
        echo "✅ HTTP端口修改成功！"
        echo "新HTTP端口: $((NEW_PORT + 1))"
    fi
    
    # 更新配置文件
    if [ -f ~/Sk5_User_Password.txt ]; then
        sed -i "s/SOCKS5端口: [0-9]\+/SOCKS5端口: $NEW_PORT/" ~/Sk5_User_Password.txt
        sed -i "s/HTTP端口: [0-9]\+/HTTP端口: $((NEW_PORT + 1))/" ~/Sk5_User_Password.txt
    fi
    
    echo ""
    echo "📋 更新后的配置:"
    sudo netstat -tlnp | grep -E ":$NEW_PORT |:$((NEW_PORT + 1)) "
    
else
    echo "❌ 端口修改失败，请检查日志"
    sudo systemctl status xray --no-pager -l
fi
PORTSCRIPT

chmod +x ~/change_socks5_port.sh

# ====== 创建DNS测试工具 ======
echo "创建DNS测试工具..."
sudo tee /usr/local/bin/beanfun-dns-test.sh > /dev/null << 'DNSTESTSCRIPT'
#!/bin/bash

echo "=========================================="
echo "🌐 Beanfun DNS解析测试工具"
echo "=========================================="

# 定义域名和IP
declare -A DOMAINS
DOMAINS["hk.beanfun.com"]="112.121.124.11"
DOMAINS["csp.hk.beanfun.com"]="18.167.13.186,18.163.12.31"
DOMAINS["tw.beanfun.com"]="202.80.107.11"
DOMAINS["beanfun.com"]="52.147.74.109"

for domain in "${!DOMAINS[@]}"; do
    echo "📍 域名: $domain"
    echo "   预期IP: ${DOMAINS[$domain]}"
    
    # 本地DNS解析
    echo -n "   本地解析: "
    local_ip=$(dig +short $domain 2>/dev/null | head -1)
    if [ -n "$local_ip" ]; then
        echo "$local_ip"
    else
        echo "解析失败"
    fi
    
    # hosts文件检查
    echo -n "   hosts文件: "
    hosts_ip=$(grep "$domain" /etc/hosts 2>/dev/null | grep -v '^#' | awk '{print $1}' | head -1)
    if [ -n "$hosts_ip" ]; then
        echo "$hosts_ip"
    else
        echo "未配置"
    fi
    
    # 连接测试
    echo -n "   连接测试: "
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$domain/443" 2>/dev/null; then
        echo "✅ 可连接"
    else
        echo "❌ 连接失败"
    fi
    
    echo ""
done

echo "🔧 代理测试:"
if systemctl is-active --quiet xray; then
    SOCKS_PORT=$(grep '"port":' /etc/xray/config.json | head -1 | grep -o '[0-9]\+')
    echo "通过SOCKS5代理($SOCKS_PORT)测试:"
    
    for domain in "${!DOMAINS[@]}"; do
        echo -n "   $domain: "
        if timeout 10 curl --socks5 vip1:123456@127.0.0.1:$SOCKS_PORT -s "http://$domain" -o /dev/null 2>/dev/null; then
            echo "✅ 代理连接成功"
        else
            echo "❌ 代理连接失败"
        fi
    done
fi

echo ""
echo "📋 DNS配置检查:"
echo "当前DNS服务器:"
cat /etc/resolv.conf | grep nameserver
DNSTESTSCRIPT

sudo chmod +x /usr/local/bin/beanfun-dns-test.sh

# 启动服务
echo "=========================================="
echo "🚀 启动SOCKS5服务..."
echo "=========================================="

sudo systemctl daemon-reload
sudo systemctl enable xray
sudo systemctl start xray

# 获取服务器IP
echo "获取服务器IP地址..."
SERVER_IP=$(curl -s -4 ifconfig.me --connect-timeout 10 2>/dev/null || curl -s -4 ipinfo.io/ip --connect-timeout 10 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)

# 验证服务状态
echo "验证服务状态..."
sleep 5

SERVICE_STATUS="未知"
PROXY_TEST="未测试"

# 检查端口监听
if sudo netstat -tlnp | grep -q ":$SOCKS5_PORT "; then
    echo "✅ SOCKS5代理服务正常运行在端口$SOCKS5_PORT"
    SERVICE_STATUS="运行正常"
    
    # 测试代理连接
    echo "测试代理连接..."
    if timeout 15 curl --socks5 vip1:123456@127.0.0.1:$SOCKS5_PORT -s https://httpbin.org/ip --connect-timeout 10 >/dev/null 2>&1; then
        echo "✅ 代理连接测试成功"
        PROXY_TEST="测试成功"
    else
        echo "⚠️ 代理连接测试失败，但服务已启动"
        PROXY_TEST="服务已启动，但连接测试失败"
    fi
else
    echo "❌ 警告: SOCKS5代理可能未正常启动"
    SERVICE_STATUS="状态异常，请检查日志"
    PROXY_TEST="服务启动失败"
    
    # 显示服务状态
    echo "服务状态:"
    sudo systemctl status xray --no-pager -l || true
    
    echo "端口监听状态:"
    sudo netstat -tlnp | grep $SOCKS5_PORT || echo "端口$SOCKS5_PORT未监听"
fi

# 检查HTTP端口
HTTP_PORT=$((SOCKS5_PORT + 1))
if sudo netstat -tlnp | grep -q ":$HTTP_PORT "; then
    echo "✅ HTTP代理服务正常运行在端口$HTTP_PORT"
else
    echo "⚠️ HTTP代理端口$HTTP_PORT未监听"
fi

# 执行DNS测试
echo ""
echo "=========================================="
echo "🧪 执行Beanfun DNS测试..."
echo "=========================================="
/usr/local/bin/beanfun-dns-test.sh

# 创建用户配置文件
tee ~/Sk5_User_Password.txt > /dev/null << USERCONFIG
#############################################################################
🎯 SOCKS5代理安装完成 - Beanfun游戏优化版

📡 服务器信息:
IP地址: $SERVER_IP
SOCKS5端口: $SOCKS5_PORT
HTTP端口: $HTTP_PORT

👤 用户账号:
用户名: vip1  密码: 123456
用户名: vip2  密码: 123456  
用户名: vip3  密码: 123456

📊 服务状态: $SERVICE_STATUS
🔗 连接测试: $PROXY_TEST

🌐 Beanfun DNS优化:
✅ hk.beanfun.com -> 112.121.124.11
✅ csp.hk.beanfun.com -> 18.167.13.186
✅ tw.beanfun.com -> 202.80.107.11
✅ beanfun.com -> 52.147.74.109

🔧 端口管理（全局生效）:
修改端口: ~/change_socks5_port.sh <新端口>
例如: ~/change_socks5_port.sh 1080

🧪 DNS测试工具:
命令: sudo /usr/local/bin/beanfun-dns-test.sh

⚙️ 服务管理:
启动: sudo systemctl start xray
停止: sudo systemctl stop xray
重启: sudo systemctl restart xray
状态: sudo systemctl status xray
日志: sudo journalctl -u xray -f

🔌 连接测试:
SOCKS5: curl --socks5 vip1:123456@$SERVER_IP:$SOCKS5_PORT https://httpbin.org/ip
HTTP: curl --proxy http://vip1:123456@$SERVER_IP:$HTTP_PORT https://httpbin.org/ip

🎮 游戏配置建议:
1. 游戏登录器设置SOCKS5代理
2. 启用"代理DNS查询"选项
3. 如不支持SOCKS5，使用HTTP代理
4. 定期运行DNS测试检查解析状态

🚨 故障排除:
1. 检查服务: sudo systemctl status xray
2. 查看日志: sudo journalctl -u xray -n 50
3. 检查端口: sudo netstat -tlnp | grep $SOCKS5_PORT
4. DNS测试: sudo /usr/local/bin/beanfun-dns-test.sh
5. 修改端口: ~/change_socks5_port.sh <新端口>

安装时间: $(date)
#############################################################################
USERCONFIG

# 显示最终结果
echo ""
echo "=========================================="
echo "🎉 SOCKS5代理安装完成！"
echo "=========================================="
echo "🌐 服务器IP: $SERVER_IP"
echo "🔌 SOCKS5端口: $SOCKS5_PORT" 
echo "🔌 HTTP端口: $HTTP_PORT"
echo "👤 用户名: vip1, vip2, vip3"
echo "🔑 密码: 123456"
echo "📊 服务状态: $SERVICE_STATUS"
echo "📄 详细信息: ~/Sk5_User_Password.txt"
echo ""
echo "🔧 高级功能:"
echo "   端口管理: ~/change_socks5_port.sh"
echo "   DNS测试: sudo /usr/local/bin/beanfun-dns-test.sh"
echo ""
echo "🎮 Beanfun游戏优化:"
echo "   ✅ 已优化4个核心域名DNS解析"
echo "   ✅ 防DNS污染配置完成"
echo "   ✅ 智能路由规则已配置"
echo ""

if [ "$SERVICE_STATUS" = "运行正常" ]; then
    echo "🎯 安装成功！可以开始使用代理服务"
    echo ""
    echo "🧪 快速测试:"
    echo "   curl --socks5 vip1:123456@$SERVER_IP:$SOCKS5_PORT https://httpbin.org/ip"
    echo ""
    echo "🌐 DNS测试:"
    echo "   sudo /usr/local/bin/beanfun-dns-test.sh"
    echo ""
    echo "💡 端口修改示例:"
    echo "   ~/change_socks5_port.sh 1080"
else
    echo "⚠️ 服务可能存在问题，请检查:"
    echo "   sudo journalctl -u xray -f"
    echo "   sudo systemctl status xray"
fi

# 清理临时文件
cd /
rm -rf $TEMP_DIR

echo ""
echo "🎊 享受优化后的游戏体验！"
echo "🔗 如需技术支持，请查看配置文件: ~/Sk5_User_Password.txt"

#!/bin/bash

# SOCKS5 环境自动安装脚本 - 集成DNS优化和端口管理
# 使用方法: 
# 默认端口: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install.sh | bash
# 自定义端口: SOCKS5_PORT=1080 curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install.sh | bash
# 或者: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install.sh | bash -s -- 1080

set -e

# ====== 端口配置区域 ======
# 默认端口为18889，可通过以下方式自定义：
# 1. 环境变量: SOCKS5_PORT=1080 bash install.sh
# 2. 命令行参数: bash install.sh 1080
# 3. 交互式输入

# ====== 端口配置逻辑修复 ======
# 首先检查环境变量
if [ -n "$SOCKS5_PORT" ]; then
    echo "检测到环境变量端口: $SOCKS5_PORT"
# 然后检查命令行参数
elif [ -n "$1" ]; then
    SOCKS5_PORT="$1"
    echo "检测到命令行参数端口: $SOCKS5_PORT"
else
    # 如果通过管道执行且没有环境变量，使用默认端口
    if [ ! -t 0 ]; then
        echo "检测到管道执行，使用默认端口"
        SOCKS5_PORT=18889
    else
        # 交互式询问用户（仅在终端直接执行时）
        echo "请选择SOCKS5端口配置："
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
fi

# 验证端口号
if ! [[ "$SOCKS5_PORT" =~ ^[0-9]+$ ]] || [ "$SOCKS5_PORT" -lt 1024 ] || [ "$SOCKS5_PORT" -gt 65535 ]; then
    echo "错误: 无效的端口号 '$SOCKS5_PORT'，使用默认端口 18889"
    SOCKS5_PORT=18889
fi

echo "=========================================="
echo "SOCKS5 代理端口设置: $SOCKS5_PORT"
echo "=========================================="

# 检查端口是否被占用
if netstat -tlnp | grep -q ":$SOCKS5_PORT "; then
    echo "警告: 端口 $SOCKS5_PORT 已被占用"
    netstat -tlnp | grep ":$SOCKS5_PORT "
    read -p "是否继续安装？这将停止现有服务 (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "安装已取消"
        exit 1
    fi
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
curl -sSL $BASE_URL/repos/epel.repo -o epel.repo
curl -sSL $BASE_URL/repos/CentOS7-ctyun.repo -o CentOS7-ctyun.repo  
curl -sSL $BASE_URL/repos/epel-testing.repo -o epel-testing.repo

sudo mv epel.repo /etc/yum.repos.d/
sudo mv CentOS7-ctyun.repo /etc/yum.repos.d/
sudo mv epel-testing.repo /etc/yum.repos.d/

# 下载并安装GPG密钥
echo "安装GPG密钥..."
curl -sSL $BASE_URL/keys/RPM-GPG-KEY-EPEL-7 -o RPM-GPG-KEY-EPEL-7
sudo mv RPM-GPG-KEY-EPEL-7 /etc/pki/rpm-gpg/

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
echo "开始配置DNS优化（防污染）..."
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
HOSTSCONFIG

echo "✓ DNS优化配置完成"

# 配置SOCKS5服务
echo "配置SOCKS5服务..."

# 方法1: 尝试安装dante-server
if yum list available dante-server >/dev/null 2>&1; then
    echo "使用Dante服务器..."
    sudo yum -y install dante-server
    SOCKS_METHOD="dante"
    
    # 配置dante（使用变量端口）
    sudo tee /etc/sockd.conf > /dev/null << DANTEEOF
logoutput: /var/log/sockd.log
internal: 0.0.0.0 port = $SOCKS5_PORT
external: eth0
method: username
user.privileged: root
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error connect disconnect
}

user.libwrap: nobody

pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    method: username
    log: error connect disconnect
}
DANTEEOF

    # 创建SOCKS用户
    sudo useradd -M -s /usr/sbin/nologin vip1 2>/dev/null || true
    sudo useradd -M -s /usr/sbin/nologin vip2 2>/dev/null || true
    sudo useradd -M -s /usr/sbin/nologin vip3 2>/dev/null || true
    echo "vip1:123456" | sudo chpasswd
    echo "vip2:123456" | sudo chpasswd
    echo "vip3:123456" | sudo chpasswd
    
else
    # 方法2: 使用xray作为SOCKS5代理
    echo "使用xray配置SOCKS5代理..."
    
    # 下载xray
    echo "下载xray..."
    
    # 获取最新版本的下载链接
    XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
    XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"
    
    echo "下载xray版本: $XRAY_VERSION"
    wget -O xray.zip "$XRAY_URL"
    
    if [ $? -ne 0 ]; then
        echo "主下载地址失败，尝试备用地址..."
        # 备用下载地址
        wget -O xray.zip "https://vip.123pan.cn/1816473155/%E6%8F%92%E4%BB%B6%E6%B3%A8%E5%86%8CIP/xray"
    fi
    
    # 解压xray
    echo "解压xray..."
    unzip -o xray.zip
    
    # 检查解压是否成功
    if [ ! -f "xray" ]; then
        echo "错误: xray文件未找到，解压失败"
        ls -la
        exit 1
    fi
    
    # 移动到正确位置并设置权限
    sudo mv xray /usr/local/bin/
    sudo chmod +x /usr/local/bin/xray
    
    # 验证xray文件
    echo "验证xray安装..."
    if ! /usr/local/bin/xray version >/dev/null 2>&1; then
        echo "错误: xray安装验证失败"
        /usr/local/bin/xray version || true
        exit 1
    fi
    
    echo "xray安装成功"
    
    # 创建xray配置目录
    sudo mkdir -p /etc/xray
    sudo mkdir -p /var/log/xray
    
    # 创建增强版xray配置文件（集成DNS优化和使用变量端口）
    sudo tee /etc/xray/config.json > /dev/null << XRAYEOF
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
          "csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com"
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
XRAYEOF
    
    # 创建systemd服务文件
    sudo tee /etc/systemd/system/xray.service > /dev/null << 'SYSTEMDEOF'
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
SYSTEMDEOF
    
    SOCKS_METHOD="xray"
fi

# ====== 配置防火墙（增强版） ======
echo "=========================================="
echo "配置防火墙（增强版）..."
echo "=========================================="

sudo systemctl stop firewalld 2>/dev/null || true
sudo systemctl disable firewalld 2>/dev/null || true

# 清理现有规则
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X

# 设置默认策略
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT  
sudo iptables -P OUTPUT ACCEPT

# 基础规则
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 开放代理端口（使用变量端口）
echo "开放端口 $SOCKS5_PORT (SOCKS5) 和 $((SOCKS5_PORT + 1)) (HTTP)..."
sudo iptables -A INPUT -p tcp --dport $SOCKS5_PORT -j ACCEPT
sudo iptables -A INPUT -p udp --dport $SOCKS5_PORT -j ACCEPT
sudo iptables -A INPUT -p tcp --dport $((SOCKS5_PORT + 1)) -j ACCEPT

# DNS端口
sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT

# SSH端口
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# 保存iptables规则
sudo service iptables save 2>/dev/null || sudo iptables-save > /etc/sysconfig/iptables 2>/dev/null || true

echo "✓ 防火墙配置完成"

# 启用IP转发
echo "启用IP转发..."
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# ====== 创建高级端口修改脚本（全局生效） ======
echo "创建高级端口修改工具..."
tee ~/change_socks5_port.sh > /dev/null << 'PORTSCRIPTEOF'
#!/bin/bash

# SOCKS5端口修改脚本 - 全局生效版本
# 使用方法: ./change_socks5_port.sh <新端口号>

if [ -z "$1" ]; then
    echo "=========================================="
    echo "SOCKS5端口修改工具"
    echo "=========================================="
    echo "用法: $0 <新端口号>"
    echo "例如: $0 1080"
    echo ""
    echo "当前配置:"
    if [ -f "/etc/xray/config.json" ]; then
        CURRENT_PORT=$(grep '"port":' /etc/xray/config.json | head -1 | grep -o '[0-9]\+')
        echo "当前SOCKS5端口: $CURRENT_PORT"
        echo "当前HTTP端口: $((CURRENT_PORT + 1))"
    elif [ -f "/etc/sockd.conf" ]; then
        CURRENT_PORT=$(grep 'port =' /etc/sockd.conf | grep -o '[0-9]\+')
        echo "当前端口: $CURRENT_PORT"
    else
        echo "未找到代理配置文件"
    fi
    exit 1
fi

NEW_PORT=$1

# 验证端口号
if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
    echo "错误: 无效的端口号 '$NEW_PORT'"
    echo "端口号必须在 1024-65535 之间"
    exit 1
fi

# 检查端口是否被占用
if netstat -tlnp | grep -q ":$NEW_PORT "; then
    echo "错误: 端口 $NEW_PORT 已被其他服务占用"
    netstat -tlnp | grep ":$NEW_PORT "
    exit 1
fi

echo "=========================================="
echo "开始修改SOCKS5端口为: $NEW_PORT"
echo "=========================================="

# 获取当前端口（用于清理防火墙规则）
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
    
    # 修改xray配置中的两个端口
    echo "修改SOCKS5端口: $OLD_PORT -> $NEW_PORT"
    sudo sed -i "0,/\"port\": $OLD_PORT/{s/\"port\": $OLD_PORT/\"port\": $NEW_PORT/}" $CONFIG_FILE
    
    echo "修改HTTP端口: $((OLD_PORT + 1)) -> $((NEW_PORT + 1))"
    sudo sed -i "0,/\"port\": $((OLD_PORT + 1))/{s/\"port\": $((OLD_PORT + 1))/\"port\": $((NEW_PORT + 1))/}" $CONFIG_FILE
    
elif [ -f "/etc/sockd.conf" ]; then
    OLD_PORT=$(grep 'port =' /etc/sockd.conf | grep -o '[0-9]\+')
    SERVICE_NAME="sockd"
    CONFIG_FILE="/etc/sockd.conf"
    
    echo "当前端口: $OLD_PORT"
    
    # 停止服务
    echo "停止sockd服务..."
    sudo systemctl stop sockd
    
    # 备份配置
    sudo cp $CONFIG_FILE ${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)
    
    # 修改dante配置
    echo "修改端口: $OLD_PORT -> $NEW_PORT"
    sudo sed -i "s/port = $OLD_PORT/port = $NEW_PORT/" $CONFIG_FILE
    
else
    echo "错误: 未找到SOCKS5配置文件"
    exit 1
fi

# 更新防火墙规则（全局生效）
echo "更新防火墙规则..."

# 移除旧端口规则
if [ ! -z "$OLD_PORT" ]; then
    echo "移除旧端口规则..."
    sudo iptables -D INPUT -p tcp --dport $OLD_PORT -j ACCEPT 2>/dev/null || true
    sudo iptables -D INPUT -p udp --dport $OLD_PORT -j ACCEPT 2>/dev/null || true
    if [ "$SERVICE_NAME" = "xray" ]; then
        sudo iptables -D INPUT -p tcp --dport $((OLD_PORT + 1)) -j ACCEPT 2>/dev/null || true
    fi
fi

# 添加新端口规则
echo "添加新端口规则..."
sudo iptables -I INPUT -p tcp --dport $NEW_PORT -j ACCEPT
sudo iptables -I INPUT -p udp --dport $NEW_PORT -j ACCEPT

if [ "$SERVICE_NAME" = "xray" ]; then
    sudo iptables -I INPUT -p tcp --dport $((NEW_PORT + 1)) -j ACCEPT
fi

# 保存防火墙规则（全局持久化）
echo "保存防火墙规则..."
sudo service iptables save 2>/dev/null || sudo iptables-save > /etc/sysconfig/iptables 2>/dev/null || true

# 重启服务
echo "重启${SERVICE_NAME}服务..."
sudo systemctl restart $SERVICE_NAME

# 等待服务启动
echo "等待服务启动..."
sleep 5

# 验证端口监听
echo "=========================================="
echo "验证新端口配置..."
echo "=========================================="

if sudo netstat -tlnp | grep -q ":$NEW_PORT "; then
    echo "✓ SOCKS5端口修改成功！"
    echo "新SOCKS5端口: $NEW_PORT"
    
    if [ "$SERVICE_NAME" = "xray" ] && sudo netstat -tlnp | grep -q ":$((NEW_PORT + 1)) "; then
        echo "✓ HTTP代理端口也修改成功！"
        echo "新HTTP端口: $((NEW_PORT + 1))"
    fi
    
    # 更新配置文件中的端口信息
    if [ -f ~/Sk5_User_Password.txt ]; then
        sed -i "s/端口: [0-9]\+/端口: $NEW_PORT/" ~/Sk5_User_Password.txt
        if [ "$SERVICE_NAME" = "xray" ]; then
            sed -i "s/HTTP端口: [0-9]\+/HTTP端口: $((NEW_PORT + 1))/" ~/Sk5_User_Password.txt
        fi
    fi
    
    # 显示当前监听端口
    echo ""
    echo "当前监听的端口:"
    sudo netstat -tlnp | grep "$NEW_PORT"
    
    # 测试连接
    echo ""
    echo "测试代理连接..."
    SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)
    
    if timeout 10 curl --socks5 vip1:123456@127.0.0.1:$NEW_PORT -s https://httpbin.org/ip >/dev/null 2>&1; then
        echo "✓ SOCKS5代理连接测试成功"
    else
        echo "⚠ SOCKS5代理连接测试失败"
    fi
    
    echo ""
    echo "=========================================="
    echo "端口修改完成！"
    echo "=========================================="
    echo "服务器IP: $SERVER_IP"
    echo "SOCKS5端口: $NEW_PORT"
    if [ "$SERVICE_NAME" = "xray" ]; then
        echo "HTTP端口: $((NEW_PORT + 1))"
    fi
    echo "用户名: vip1, vip2, vip3"
    echo "密码: 123456"
    
else
    echo "✗ 端口修改失败，请检查日志"
    echo ""
    echo "服务状态:"
    sudo systemctl status $SERVICE_NAME --no-pager -l
    
    echo ""
    echo "检查配置文件:"
    if [ "$SERVICE_NAME" = "xray" ]; then
        grep -n "port" $CONFIG_FILE
    else
        grep -n "port" $CONFIG_FILE
    fi
fi
PORTSCRIPTEOF

chmod +x ~/change_socks5_port.sh

# ====== 创建DNS测试工具 ======
echo "创建DNS测试工具..."
sudo tee /usr/local/bin/beanfun-dns-test.sh > /dev/null << 'DNSTESTEOF'
#!/bin/bash

echo "=========================================="
echo "Beanfun DNS解析测试工具"
echo "=========================================="

# 定义要测试的域名和预期IP
declare -A DOMAINS
DOMAINS["hk.beanfun.com"]="112.121.124.11"
DOMAINS["csp.hk.beanfun.com"]="18.167.13.186,18.163.12.31"
DOMAINS["tw.beanfun.com"]="202.80.107.11"
DOMAINS["beanfun.com"]="52.147.74.109"

echo "测试DNS解析结果:"
echo ""

for domain in "${!DOMAINS[@]}"; do
    echo "域名: $domain"
    echo "预期IP: ${DOMAINS[$domain]}"
    
    # 本地DNS解析
    echo -n "本地解析: "
    local_ip=$(dig +short $domain 2>/dev/null | head -1)
    if [ -n "$local_ip" ]; then
        echo "$local_ip"
    else
        echo "解析失败"
    fi
    
    # Google DNS解析
    echo -n "Google DNS: "
    google_ip=$(dig @8.8.8.8 +short $domain 2>/dev/null | head -1)
    if [ -n "$google_ip" ]; then
        echo "$google_ip"
    else
        echo "解析失败"
    fi
    
    # hosts文件检查
    echo -n "hosts文件: "
    hosts_ip=$(grep "$domain" /etc/hosts 2>/dev/null | grep -v '^#' | awk '{print $1}' | head -1)
    if [ -n "$hosts_ip" ]; then
        echo "$hosts_ip"
    else
        echo "未配置"
    fi
    
    # 连接测试
    echo -n "连接测试: "
    if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$domain/80" 2>/dev/null; then
        echo "✓ 可连接"
    else
        echo "✗ 连接失败"
    fi
    
    echo "----------------------------------------"
done

echo ""
echo "代理DNS测试:"
# 如果xray在运行，测试通过代理的DNS解析
if systemctl is-active --quiet xray; then
    SOCKS_PORT=$(grep '"port":' /etc/xray/config.json | head -1 | grep -o '[0-9]\+')
    echo "通过SOCKS5代理($SOCKS_PORT)测试DNS解析:"
    
    for domain in "${!DOMAINS[@]}"; do
        echo -n "$domain: "
        if timeout 10 curl --socks5 vip1:123456@127.0.0.1:$SOCKS_PORT -s "http://$domain" -o /dev/null 2>/dev/null; then
            echo "✓ 代理连接成功"
        else
            echo "✗ 代理连接失败"
        fi
    done
fi

echo ""
echo "DNS配置检查:"
echo "当前DNS服务器:"
cat /etc/resolv.conf | grep nameserver

echo ""
echo "系统DNS缓存刷新命令:"
echo "sudo systemctl restart systemd-resolved"
echo "sudo systemctl restart NetworkManager"
DNSTESTEOF

sudo chmod +x /usr/local/bin/beanfun-dns-test.sh

# 启动服务
echo "=========================================="
echo "启动SOCKS5服务..."
echo "=========================================="

if [ "$SOCKS_METHOD" = "dante" ]; then
    sudo systemctl daemon-reload
    sudo systemctl enable sockd
    sudo systemctl start sockd
    echo "Dante SOCKS5代理已启动"
    SERVICE_NAME="sockd"
else
    sudo systemctl daemon-reload
    sudo systemctl enable xray
    sudo systemctl start xray
    echo "Xray SOCKS5代理已启动"
    SERVICE_NAME="xray"
fi

# 获取服务器IP
echo "获取服务器IP地址..."
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 ipinfo.io/ip 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)

# 验证服务是否正常启动
echo "验证服务状态..."
sleep 5

# 检查端口监听（使用变量端口）
if sudo netstat -tlnp | grep -q ":$SOCKS5_PORT "; then
    echo "✓ SOCKS5代理服务正常运行在端口$SOCKS5_PORT"
    SERVICE_STATUS="运行正常"
    
    # 进一步测试代理连接
    echo "测试代理连接..."
    if timeout 10 curl --socks5 vip1:123456@127.0.0.1:$SOCKS5_PORT -s https://httpbin.org/ip >/dev/null 2>&1; then
        echo "✓ 代理连接测试成功"
        PROXY_TEST="测试成功"
    else
        echo "⚠ 代理连接测试失败，但服务已启动"
        PROXY_TEST="服务已启动，但连接测试失败"
    fi
else
    echo "✗ 警告: SOCKS5代理可能未正常启动"
    SERVICE_STATUS="状态异常，请检查日志"
    PROXY_TEST="服务启动失败"
    
    # 显示服务状态用于调试
    echo "服务状态:"
    sudo systemctl status $SERVICE_NAME --no-pager -l || true
    
    echo "端口监听状态:"
    sudo netstat -tlnp | grep $SOCKS5_PORT || echo "端口$SOCKS5_PORT未监听"
fi

# 执行DNS测试
echo ""
echo "=========================================="
echo "执行Beanfun DNS测试..."
echo "=========================================="
/usr/local/bin/beanfun-dns-test.sh

# 创建用户信息文件
tee ~/Sk5_User_Password.txt > /dev/null << CONFIGEOF
#############################################################################
SOCKS5代理安装完成 - 集成DNS优化版本

服务器信息:
IP地址: $SERVER_IP
SOCKS5端口: $SOCKS5_PORT
HTTP端口: $((SOCKS5_PORT + 1))
协议: SOCKS5

用户账号:
用户名: vip1  密码: 123456
用户名: vip2  密码: 123456  
用户名: vip3  密码: 123456

服务状态: $SERVICE_STATUS
连接测试: $PROXY_TEST
使用方法: $SOCKS_METHOD

=== Beanfun DNS优化 ===
已优化域名:
- hk.beanfun.com -> 112.121.124.11
- csp.hk.beanfun.com -> 18.167.13.186
- tw.beanfun.com -> 202.80.107.11
- beanfun.com -> 52.147.74.109

DNS测试命令: sudo /usr/local/bin/beanfun-dns-test.sh

=== 端口管理（全局生效） ===
修改端口命令: ~/change_socks5_port.sh <新端口>
例如: ~/change_socks5_port.sh 1080

支持的端口修改:
- 自动更新配置文件
- 自动更新防火墙规则
- 自动重启服务
- 自动验证新端口

=== 服务管理命令 ===
启动服务: sudo systemctl start $SERVICE_NAME
停止服务: sudo systemctl stop $SERVICE_NAME
重启服务: sudo systemctl restart $SERVICE_NAME
查看状态: sudo systemctl status $SERVICE_NAME
查看日志: sudo journalctl -u $SERVICE_NAME -f

=== 连接测试命令 ===
基础测试: curl --socks5 vip1:123456@$SERVER_IP:$SOCKS5_PORT https://httpbin.org/ip
本地测试: curl --socks5 vip1:123456@127.0.0.1:$SOCKS5_PORT https://httpbin.org/ip
DNS测试: sudo /usr/local/bin/beanfun-dns-test.sh

=== 客户端配置示例 ===
代理类型: SOCKS5
服务器: $SERVER_IP
端口: $SOCKS5_PORT
用户名: vip1 (或vip2, vip3)
密码: 123456

HTTP代理配置:
服务器: $SERVER_IP
端口: $((SOCKS5_PORT + 1))
用户名: vip1 (或vip2, vip3)
密码: 123456

=== 游戏优化建议 ===
1. 游戏登录器设置SOCKS5代理
2. 启用"代理DNS查询"选项
3. 如果游戏不支持SOCKS5，使用HTTP代理
4. 定期运行DNS测试检查解析状态

=== 常用端口推荐 ===
1080  - SOCKS标准端口
3128  - HTTP代理常用端口  
8080  - 备用代理端口
18889 - 原默认端口

=== 高级功能 ===
✓ DNS污染防护
✓ 多域名优化
✓ 智能路由规则
✓ 全局端口管理
✓ 自动防火墙配置
✓ 实时连接测试

=== 故障排除 ===
1. 检查服务状态: sudo systemctl status $SERVICE_NAME
2. 查看错误日志: sudo journalctl -u $SERVICE_NAME -n 50
3. 检查端口监听: sudo netstat -tlnp | grep $SOCKS5_PORT
4. 检查防火墙: sudo iptables -L | grep $SOCKS5_PORT
5. DNS解析测试: sudo /usr/local/bin/beanfun-dns-test.sh
6. 修改端口: ~/change_socks5_port.sh <新端口>
7. 重新安装: 重新运行此安装脚本

安装时间: $(date)
#############################################################################
CONFIGEOF

# 显示安装结果
echo ""
echo "=========================================="
echo "SOCKS5代理安装完成！(集成DNS优化版)"
echo "=========================================="
echo "服务器IP: $SERVER_IP"
echo "SOCKS5端口: $SOCKS5_PORT" 
echo "HTTP端口: $((SOCKS5_PORT + 1))"
echo "用户名: vip1, vip2, vip3"
echo "密码: 123456"
echo "服务状态: $SERVICE_STATUS"
echo "详细信息: ~/Sk5_User_Password.txt"
echo ""
echo "🔧 高级端口管理: ~/change_socks5_port.sh"
echo "   用法: ~/change_socks5_port.sh 1080"
echo ""
echo "🌐 DNS测试工具: sudo /usr/local/bin/beanfun-dns-test.sh"
echo ""
echo "🎮 Beanfun域名优化:"
echo "   ✓ hk.beanfun.com -> 112.121.124.11"
echo "   ✓ csp.hk.beanfun.com -> 18.167.13.186"
echo "   ✓ tw.beanfun.com -> 202.80.107.11"
echo "   ✓ beanfun.com -> 52.147.74.109"
echo ""

if [ "$SERVICE_STATUS" = "运行正常" ]; then
    echo "✓ 安装成功！可以开始使用代理服务"
    echo ""
    echo "快速测试命令:"
    echo "curl --socks5 vip1:123456@$SERVER_IP:$SOCKS5_PORT https://httpbin.org/ip"
    echo ""
    echo "DNS测试命令:"
    echo "sudo /usr/local/bin/beanfun-dns-test.sh"
else
    echo "⚠ 安装可能存在问题，请检查日志:"
    echo "sudo journalctl -u $SERVICE_NAME -f"
fi

# 清理临时文件
cd /
rm -rf $TEMP_DIR

echo ""
echo "🎯 特别优化: Beanfun游戏平台DNS解析"
echo "🔒 安全加固: 防火墙规则自动配置"  
echo "⚙️ 智能管理: 全局端口修改功能"
echo ""
echo "安装完成！享受优化后的游戏体验！"

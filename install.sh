#!/bin/bash

# SOCKS5 环境自动安装脚本
# 使用方法: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install.sh | bash

set -e

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
sudo yum -y install jq

# 配置SOCKS5服务
echo "配置SOCKS5服务..."

# 方法1: 尝试安装dante-server
if yum list available dante-server >/dev/null 2>&1; then
    sudo yum -y install dante-server
    SOCKS_METHOD="dante"
else
    # 方法2: 使用xray作为SOCKS5代理
    echo "使用xray配置SOCKS5代理..."
    
    # 下载xray
    wget -O /usr/local/bin/xray https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
    if [ $? -ne 0 ]; then
        # 备用下载地址
        wget -O /tmp/xray.zip https://vip.123pan.cn/1816473155/%E6%8F%92%E4%BB%B6%E6%B3%A8%E5%86%8CIP/xray
        sudo mv /tmp/xray.zip /usr/local/bin/xray
    fi
    
    sudo chmod +x /usr/local/bin/xray
    
    # 创建xray配置目录
    sudo mkdir -p /etc/xray
    
    # 创建xray配置文件
    sudo tee /etc/xray/config.json > /dev/null << 'EOF'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 18889,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "vip1",
            "pass": "123456"
          },
          {
            "user": "vip2", 
            "pass": "123456"
          },
          {
            "user": "vip3",
            "pass": "123456"
          }
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
EOF
    
    # 创建systemd服务文件
    sudo tee /etc/systemd/system/xray.service > /dev/null << 'EOF'
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
EOF
    
    SOCKS_METHOD="xray"
fi

# 配置防火墙
echo "配置防火墙..."
sudo systemctl stop firewalld 2>/dev/null || true
sudo systemctl disable firewalld 2>/dev/null || true

# 开放端口
sudo iptables -I INPUT -p tcp --dport 18889 -j ACCEPT
sudo iptables-save > /etc/sysconfig/iptables 2>/dev/null || true

# 启动服务
if [ "$SOCKS_METHOD" = "dante" ]; then
    sudo systemctl enable sockd
    sudo systemctl start sockd
    echo "Dante SOCKS5代理已启动"
else
    sudo systemctl daemon-reload
    sudo systemctl enable xray
    sudo systemctl start xray
    echo "Xray SOCKS5代理已启动"
fi

# 获取服务器IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')

# 创建用户信息文件
tee Sk5_User_Password.txt > /dev/null << EOF
#############################################################################
SOCKS5代理信息:
服务器IP: $SERVER_IP
端口: 18889
用户名: vip1, vip2, vip3
密码: 123456

服务管理命令:
启动服务: sudo systemctl start $([ "$SOCKS_METHOD" = "dante" ] && echo "sockd" || echo "xray")
停止服务: sudo systemctl stop $([ "$SOCKS_METHOD" = "dante" ] && echo "sockd" || echo "xray")  
重启服务: sudo systemctl restart $([ "$SOCKS_METHOD" = "dante" ] && echo "sockd" || echo "xray")
查看状态: sudo systemctl status $([ "$SOCKS_METHOD" = "dante" ] && echo "sockd" || echo "xray")
#############################################################################
EOF

echo "SOCKS5代理安装完成！"
echo "服务器IP: $SERVER_IP"
echo "端口: 18889" 
echo "用户名: vip1, vip2, vip3"
echo "密码: 123456"
echo "详细信息保存在: Sk5_User_Password.txt"

# 清理临时文件
cd /
rm -rf $TEMP_DIR

echo "安装完成！"

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
sudo yum -y install jq unzip wget curl net-tools

# 配置SOCKS5服务
echo "配置SOCKS5服务..."

# 方法1: 尝试安装dante-server
if yum list available dante-server >/dev/null 2>&1; then
    echo "使用Dante服务器..."
    sudo yum -y install dante-server
    SOCKS_METHOD="dante"
    
    # 配置dante
    sudo tee /etc/sockd.conf > /dev/null << 'DANTEEOF'
logoutput: /var/log/sockd.log
internal: 0.0.0.0 port = 18889
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
    
    # 创建xray配置文件
    sudo tee /etc/xray/config.json > /dev/null << 'XRAYEOF'
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 18889,
      "protocol": "socks",
      "listen": "0.0.0.0",
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
        ],
        "udp": true
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

# 配置防火墙
echo "配置防火墙..."
sudo systemctl stop firewalld 2>/dev/null || true
sudo systemctl disable firewalld 2>/dev/null || true

# 开放端口
echo "开放端口..."
sudo iptables -I INPUT -p tcp --dport 18889 -j ACCEPT 2>/dev/null || true
sudo iptables -I INPUT -p udp --dport 18889 -j ACCEPT 2>/dev/null || true

# 保存iptables规则
sudo service iptables save 2>/dev/null || sudo iptables-save > /etc/sysconfig/iptables 2>/dev/null || true

# 启动服务
echo "启动SOCKS5服务..."
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

# 检查端口监听
if sudo netstat -tlnp | grep -q ":18889 "; then
    echo "✓ SOCKS5代理服务正常运行在端口18889"
    SERVICE_STATUS="运行正常"
    
    # 进一步测试代理连接
    echo "测试代理连接..."
    if timeout 10 curl --socks5 vip1:123456@127.0.0.1:18889 -s https://httpbin.org/ip >/dev/null 2>&1; then
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
    sudo netstat -tlnp | grep 18889 || echo "端口18889未监听"
fi

# 创建用户信息文件
tee ~/Sk5_User_Password.txt > /dev/null << CONFIGEOF
#############################################################################
SOCKS5代理安装完成

服务器信息:
IP地址: $SERVER_IP
端口: 18889
协议: SOCKS5

用户账号:
用户名: vip1  密码: 123456
用户名: vip2  密码: 123456  
用户名: vip3  密码: 123456

服务状态: $SERVICE_STATUS
连接测试: $PROXY_TEST
使用方法: $SOCKS_METHOD

=== 服务管理命令 ===
启动服务: sudo systemctl start $SERVICE_NAME
停止服务: sudo systemctl stop $SERVICE_NAME
重启服务: sudo systemctl restart $SERVICE_NAME
查看状态: sudo systemctl status $SERVICE_NAME
查看日志: sudo journalctl -u $SERVICE_NAME -f

=== 连接测试命令 ===
curl --socks5 vip1:123456@$SERVER_IP:18889 https://httpbin.org/ip
curl --socks5 vip1:123456@127.0.0.1:18889 https://httpbin.org/ip

=== 客户端配置示例 ===
代理类型: SOCKS5
服务器: $SERVER_IP
端口: 18889
用户名: vip1 (或vip2, vip3)
密码: 123456

=== 故障排除 ===
1. 检查服务状态: sudo systemctl status $SERVICE_NAME
2. 查看错误日志: sudo journalctl -u $SERVICE_NAME -n 50
3. 检查端口监听: sudo netstat -tlnp | grep 18889
4. 检查防火墙: sudo iptables -L | grep 18889
5. 重新安装: 重新运行此安装脚本

安装时间: $(date)
#############################################################################
CONFIGEOF

# 显示安装结果
echo ""
echo "======================================"
echo "SOCKS5代理安装完成！"
echo "======================================"
echo "服务器IP: $SERVER_IP"
echo "端口: 18889" 
echo "用户名: vip1, vip2, vip3"
echo "密码: 123456"
echo "服务状态: $SERVICE_STATUS"
echo "详细信息: ~/Sk5_User_Password.txt"
echo ""

if [ "$SERVICE_STATUS" = "运行正常" ]; then
    echo "✓ 安装成功！可以开始使用代理服务"
    echo ""
    echo "快速测试命令:"
    echo "curl --socks5 vip1:123456@$SERVER_IP:18889 https://httpbin.org/ip"
else
    echo "⚠ 安装可能存在问题，请检查日志:"
    echo "sudo journalctl -u $SERVICE_NAME -f"
fi

# 清理临时文件
cd /
rm -rf $TEMP_DIR

echo ""
echo "安装完成！"

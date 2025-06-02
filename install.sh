#!/bin/bash

# SOCKS5 环境自动安装脚本 - 支持自定义端口
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

# 检查命令行参数
if [ -n "$1" ]; then
    SOCKS5_PORT="$1"
elif [ -n "$SOCKS5_PORT" ]; then
    # 使用环境变量
    SOCKS5_PORT="$SOCKS5_PORT"
else
    # 交互式询问用户
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
sudo yum -y install jq unzip wget curl net-tools

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
    
    # 创建xray配置文件（使用变量端口）
    sudo tee /etc/xray/config.json > /dev/null << XRAYEOF
{
  "log": {
    "loglevel": "warning"
  },
  "dns": {
    "servers": [
      "8.8.8.8",
      "1.1.1.1"
    ]
  },
  "inbounds": [
    {
      "port": $SOCKS5_PORT,
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

# 开放端口（使用变量端口）
echo "开放端口 $SOCKS5_PORT..."
sudo iptables -I INPUT -p tcp --dport $SOCKS5_PORT -j ACCEPT 2>/dev/null || true
sudo iptables -I INPUT -p udp --dport $SOCKS5_PORT -j ACCEPT 2>/dev/null || true

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

# 创建端口修改脚本
tee ~/change_socks5_port.sh > /dev/null << 'PORTSCRIPTEOF'
#!/bin/bash

# SOCKS5端口修改脚本

if [ -z "$1" ]; then
    echo "用法: $0 <新端口号>"
    echo "例如: $0 1080"
    exit 1
fi

NEW_PORT=$1

# 验证端口号
if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
    echo "错误: 无效的端口号 '$NEW_PORT'"
    exit 1
fi

echo "正在修改SOCKS5端口为: $NEW_PORT"

# 检查服务类型
if [ -f "/etc/xray/config.json" ]; then
    # 修改xray配置
    sudo sed -i "s/\"port\": [0-9]\+/\"port\": $NEW_PORT/" /etc/xray/config.json
    SERVICE_NAME="xray"
elif [ -f "/etc/sockd.conf" ]; then
    # 修改dante配置
    sudo sed -i "s/port = [0-9]\+/port = $NEW_PORT/" /etc/sockd.conf
    SERVICE_NAME="sockd"
else
    echo "错误: 未找到SOCKS5配置文件"
    exit 1
fi

# 更新防火墙规则
echo "更新防火墙规则..."
sudo iptables -I INPUT -p tcp --dport $NEW_PORT -j ACCEPT 2>/dev/null || true
sudo iptables -I INPUT -p udp --dport $NEW_PORT -j ACCEPT 2>/dev/null || true
sudo service iptables save 2>/dev/null || sudo iptables-save > /etc/sysconfig/iptables 2>/dev/null || true

# 重启服务
echo "重启SOCKS5服务..."
sudo systemctl restart $SERVICE_NAME

# 验证
sleep 3
if sudo netstat -tlnp | grep -q ":$NEW_PORT "; then
    echo "✓ 端口修改成功！新端口: $NEW_PORT"
    
    # 更新配置文件
    sed -i "s/端口: [0-9]\+/端口: $NEW_PORT/" ~/Sk5_User_Password.txt 2>/dev/null || true
else
    echo "✗ 端口修改失败，请检查日志"
    sudo systemctl status $SERVICE_NAME
fi
PORTSCRIPTEOF

chmod +x ~/change_socks5_port.sh

# 创建用户信息文件
tee ~/Sk5_User_Password.txt > /dev/null << CONFIGEOF
#############################################################################
SOCKS5代理安装完成

服务器信息:
IP地址: $SERVER_IP
端口: $SOCKS5_PORT
协议: SOCKS5

用户账号:
用户名: vip1  密码: 123456
用户名: vip2  密码: 123456  
用户名: vip3  密码: 123456

服务状态: $SERVICE_STATUS
连接测试: $PROXY_TEST
使用方法: $SOCKS_METHOD

=== 端口修改 ===
修改端口命令: ~/change_socks5_port.sh <新端口>
例如: ~/change_socks5_port.sh 1080

=== 服务管理命令 ===
启动服务: sudo systemctl start $SERVICE_NAME
停止服务: sudo systemctl stop $SERVICE_NAME
重启服务: sudo systemctl restart $SERVICE_NAME
查看状态: sudo systemctl status $SERVICE_NAME
查看日志: sudo journalctl -u $SERVICE_NAME -f

=== 连接测试命令 ===
curl --socks5 vip1:123456@$SERVER_IP:$SOCKS5_PORT https://httpbin.org/ip
curl --socks5 vip1:123456@127.0.0.1:$SOCKS5_PORT https://httpbin.org/ip

=== 客户端配置示例 ===
代理类型: SOCKS5
服务器: $SERVER_IP
端口: $SOCKS5_PORT
用户名: vip1 (或vip2, vip3)
密码: 123456

=== 常用端口推荐 ===
1080  - SOCKS标准端口
3128  - HTTP代理常用端口
8080  - 备用代理端口
18889 - 原默认端口

=== 故障排除 ===
1. 检查服务状态: sudo systemctl status $SERVICE_NAME
2. 查看错误日志: sudo journalctl -u $SERVICE_NAME -n 50
3. 检查端口监听: sudo netstat -tlnp | grep $SOCKS5_PORT
4. 检查防火墙: sudo iptables -L | grep $SOCKS5_PORT
5. 修改端口: ~/change_socks5_port.sh <新端口>
6. 重新安装: 重新运行此安装脚本

安装时间: $(date)
#############################################################################
CONFIGEOF

# 显示安装结果
echo ""
echo "=========================================="
echo "SOCKS5代理安装完成！"
echo "=========================================="
echo "服务器IP: $SERVER_IP"
echo "端口: $SOCKS5_PORT" 
echo "用户名: vip1, vip2, vip3"
echo "密码: 123456"
echo "服务状态: $SERVICE_STATUS"
echo "详细信息: ~/Sk5_User_Password.txt"
echo ""
echo "🔧 端口修改工具: ~/change_socks5_port.sh"
echo "   用法: ~/change_socks5_port.sh 1080"
echo ""

if [ "$SERVICE_STATUS" = "运行正常" ]; then
    echo "✓ 安装成功！可以开始使用代理服务"
    echo ""
    echo "快速测试命令:"
    echo "curl --socks5 vip1:123456@$SERVER_IP:$SOCKS5_PORT https://httpbin.org/ip"
else
    echo "⚠ 安装可能存在问题，请检查日志:"
    echo "sudo journalctl -u $SERVICE_NAME -f"
fi

# 清理临时文件
cd /
rm -rf $TEMP_DIR

echo ""
echo "安装完成！"

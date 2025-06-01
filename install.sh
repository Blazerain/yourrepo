#!/bin/bash

# 综合游戏代理安装配置脚本
# 功能: SOCKS5安装 + DNS污染修复 + UDP转发优化 + 游戏代理配置
# 使用方法: curl -sSL [你的脚本地址] | bash
# 或者: chmod +x script.sh && sudo ./script.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用root权限运行此脚本"
        log_info "使用方法: sudo $0"
        exit 1
    fi
}

# 系统检测
detect_system() {
    log_step "检测系统环境..."
    
    if [ -f /etc/redhat-release ]; then
        OS="centos"
        log_info "检测到CentOS/RHEL系统"
    elif [ -f /etc/lsb-release ]; then
        OS="ubuntu"
        log_info "检测到Ubuntu系统"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        log_info "检测到Debian系统"
    else
        log_warn "未知系统，将尝试通用配置"
        OS="unknown"
    fi
}

# 配置YUM源（CentOS）
setup_repos() {
    if [ "$OS" = "centos" ]; then
        log_step "配置YUM源..."
        
        # 备份现有配置
        mkdir -p /etc/yum.repos.d.backup
        cp -r /etc/yum.repos.d/* /etc/yum.repos.d.backup/ 2>/dev/null || true
        
        # 清理现有repo
        rm -rf /etc/yum.repos.d/*
        
        # 创建基础repo配置
        tee /etc/yum.repos.d/CentOS-Base.repo > /dev/null << 'REPOEOF'
[base]
name=CentOS-$releasever - Base
baseurl=http://vault.centos.org/centos/$releasever/os/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1

[updates]
name=CentOS-$releasever - Updates
baseurl=http://vault.centos.org/centos/$releasever/updates/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1

[extras]
name=CentOS-$releasever - Extras
baseurl=http://vault.centos.org/centos/$releasever/extras/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1
REPOEOF

        # EPEL源
        tee /etc/yum.repos.d/epel.repo > /dev/null << 'EPELEOF'
[epel]
name=Extra Packages for Enterprise Linux 7 - $basearch
baseurl=http://download.fedoraproject.org/pub/epel/7/$basearch
failovermethod=priority
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
EPELEOF

        # 清理并更新缓存
        yum clean all
        yum makecache
    fi
}

# 安装依赖软件
install_dependencies() {
    log_step "安装依赖软件..."
    
    if [ "$OS" = "centos" ]; then
        yum -y install curl wget unzip jq net-tools iptables-services
    elif [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get update
        apt-get -y install curl wget unzip jq net-tools iptables-persistent
    fi
    
    log_info "依赖软件安装完成"
}

# 安装和配置Xray
install_xray() {
    log_step "安装Xray代理..."
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    cd $TEMP_DIR
    
    # 下载xray
    log_info "下载Xray..."
    if ! wget -O xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip; then
        log_warn "主下载地址失败，尝试备用地址..."
        if ! wget -O xray.zip https://vip.123pan.cn/1816473155/%E6%8F%92%E4%BB%B6%E6%B3%A8%E5%86%8CIP/xray; then
            log_error "下载Xray失败"
            exit 1
        fi
    fi
    
    # 解压并安装
    log_info "解压Xray..."
    unzip -o xray.zip
    
    if [ ! -f "xray" ]; then
        log_error "Xray文件未找到，解压失败"
        exit 1
    fi
    
    # 移动到系统目录
    mv xray /usr/local/bin/
    chmod +x /usr/local/bin/xray
    
    # 验证安装
    if ! /usr/local/bin/xray version >/dev/null 2>&1; then
        log_error "Xray安装验证失败"
        exit 1
    fi
    
    log_info "Xray安装成功"
    
    # 清理临时文件
    cd /
    rm -rf $TEMP_DIR
}

# 配置Xray (综合版本，包含DNS修复)
configure_xray() {
    log_step "配置Xray代理..."
    
    # 创建配置目录和日志目录
    mkdir -p /etc/xray
    mkdir -p /var/log/xray
    chown root:root /var/log/xray
    
    # 停止现有服务
    systemctl stop xray 2>/dev/null || true
    
    # 创建综合配置文件
    tee /etc/xray/config.json > /dev/null << 'XRAYEOF'
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
XRAYEOF

    # 创建systemd服务文件
    tee /etc/systemd/system/xray.service > /dev/null << 'SERVICEEOF'
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
SERVICEEOF

    log_info "Xray配置完成"
}

# DNS修复配置
fix_dns() {
    log_step "修复DNS污染问题..."
    
    # 备份原始DNS配置
    cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    
    # 创建新的DNS配置
    tee /etc/resolv.conf > /dev/null << 'DNSEOF'
# DNS配置 - 防污染版本
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
options timeout:2
options attempts:3
options rotate
DNSEOF

    # 修复hosts文件
    cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d_%H%M%S)
    
    # 移除旧的beanfun条目
    sed -i '/beanfun/d' /etc/hosts
    
    # 添加正确的IP映射
    tee -a /etc/hosts > /dev/null << 'HOSTSEOF'

# Beanfun游戏平台 - 防DNS污染
18.167.13.186 csp.hk.beanfun.com
18.163.12.31 csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com
HOSTSEOF

    log_info "DNS修复完成"
}

# 网络优化配置
configure_network() {
    log_step "配置网络优化..."
    
    # 启用IP转发
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
    sysctl -p
    
    # 网络优化参数
    tee -a /etc/sysctl.conf > /dev/null << 'NETEOF'
# 网络优化参数
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 30000
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_congestion_control = bbr
NETEOF

    sysctl -p
    log_info "网络优化配置完成"
}

# 防火墙配置
configure_firewall() {
    log_step "配置防火墙..."
    
    # 停止firewalld
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
    
    # 清理现有规则
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    
    # 基本规则
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT  
    iptables -P OUTPUT ACCEPT
    
    # 开放代理端口（TCP和UDP）
    iptables -A INPUT -p tcp --dport 18889 -j ACCEPT
    iptables -A INPUT -p udp --dport 18889 -j ACCEPT
    iptables -A INPUT -p tcp --dport 18890 -j ACCEPT
    iptables -A INPUT -p tcp --dport 12345 -j ACCEPT
    
    # DNS端口
    iptables -A INPUT -p tcp --dport 53 -j ACCEPT
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    
    # SSH端口
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    
    # 允许已建立的连接
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    
    # 保存规则
    if [ "$OS" = "centos" ]; then
        service iptables save 2>/dev/null || iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
    else
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
    
    log_info "防火墙配置完成"
}

# 创建管理脚本
create_management_scripts() {
    log_step "创建管理脚本..."
    
    # DNS测试脚本
    tee /usr/local/bin/dns-test.sh > /dev/null << 'TESTEOF'
#!/bin/bash

echo "========== DNS解析测试 =========="
echo "测试beanfun域名解析:"

echo ""
echo "1. 本地DNS解析:"
dig +short csp.hk.beanfun.com 2>/dev/null || nslookup csp.hk.beanfun.com | grep Address | tail -1

echo ""
echo "2. 使用8.8.8.8解析:"
dig @8.8.8.8 +short csp.hk.beanfun.com 2>/dev/null || nslookup csp.hk.beanfun.com 8.8.8.8

echo ""
echo "3. hosts文件映射:"
grep beanfun /etc/hosts

echo ""
echo "4. 连接测试:"
echo "测试18.167.13.186:443..."
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/18.167.13.186/443' && echo "✓ 连接成功" || echo "✗ 连接失败"

echo "测试18.163.12.31:443..."
timeout 5 bash -c 'cat < /dev/null > /dev/tcp/18.163.12.31/443' && echo "✓ 连接成功" || echo "✗ 连接失败"

echo ""
echo "========== 代理测试 =========="
echo "SOCKS5代理测试:"
timeout 10 curl --socks5 vip1:123456@127.0.0.1:18889 -I https://httpbin.org/ip 2>/dev/null | head -1 && echo "✓ SOCKS5代理正常" || echo "✗ SOCKS5代理异常"

echo ""
echo "HTTP代理测试:"
timeout 10 curl --proxy http://vip1:123456@127.0.0.1:18890 -I https://httpbin.org/ip 2>/dev/null | head -1 && echo "✓ HTTP代理正常" || echo "✗ HTTP代理异常"
TESTEOF

    chmod +x /usr/local/bin/dns-test.sh
    
    # 游戏代理启动脚本
    tee /usr/local/bin/game-proxy.sh > /dev/null << 'GAMEEOF'
#!/bin/bash

echo "启动游戏代理环境..."

# 检查并启动xray
if ! systemctl is-active --quiet xray; then
    echo "启动xray服务..."
    systemctl start xray
    sleep 3
fi

# 检查端口状态
echo "检查端口状态:"
netstat -tuln | grep -E "(18889|18890|12345)"

# 执行DNS和代理测试
echo "执行测试..."
/usr/local/bin/dns-test.sh

# 显示代理信息
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)

echo ""
echo "=========================================="
echo "游戏代理已就绪!"
echo "=========================================="
echo "服务器IP: $SERVER_IP"
echo "SOCKS5: $SERVER_IP:18889 (用户名:vip1 密码:123456)"
echo "HTTP: $SERVER_IP:18890 (用户名:vip1 密码:123456)"
echo ""
echo "请在游戏登录器中设置代理"
GAMEEOF

    chmod +x /usr/local/bin/game-proxy.sh
    
    log_info "管理脚本创建完成"
}

# 启动服务
start_services() {
    log_step "启动服务..."
    
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray
    
    # 等待服务启动
    sleep 5
    
    # 检查服务状态
    if systemctl is-active --quiet xray; then
        log_info "Xray服务启动成功"
    else
        log_error "Xray服务启动失败"
        log_info "请查看日志: journalctl -u xray -f"
        exit 1
    fi
}

# 生成配置信息
generate_config_info() {
    log_step "生成配置信息..."
    
    # 获取服务器IP
    SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 ipinfo.io/ip 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)
    
    # 生成配置文件
    tee ~/Game_Proxy_Complete_Config.txt > /dev/null << CONFIGEOF
#############################################################################
游戏代理完整配置信息

服务器IP: $SERVER_IP
安装时间: $(date)

=== 代理设置 ===
SOCKS5代理: $SERVER_IP:18889 (支持UDP)
HTTP代理: $SERVER_IP:18890
用户名: vip1, vip2, vip3
密码: 123456

=== 游戏登录器设置建议 ===
1. 优先使用SOCKS5代理（支持UDP，适合游戏）
2. 如果不支持SOCKS5，使用HTTP代理
3. 启用"代理DNS查询"或"通过代理解析域名"
4. 设置代理认证：用户名vip1，密码123456

=== DNS修复信息 ===
已修复的域名：
- csp.hk.beanfun.com -> 18.167.13.186
- csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com -> 18.163.12.31

=== 服务管理命令 ===
启动游戏代理: /usr/local/bin/game-proxy.sh
DNS和代理测试: /usr/local/bin/dns-test.sh
查看服务状态: systemctl status xray
查看实时日志: journalctl -u xray -f
重启服务: systemctl restart xray

=== 连接测试命令 ===
SOCKS5测试: curl --socks5 vip1:123456@$SERVER_IP:18889 https://httpbin.org/ip
HTTP测试: curl --proxy http://vip1:123456@$SERVER_IP:18890 https://httpbin.org/ip

=== 本地客户端DNS修复（可选）===
Windows用户可以在管理员CMD中执行：
ipconfig /flushdns
netsh winsock reset

然后重启电脑，或修改hosts文件：
C:\Windows\System32\drivers\etc\hosts
添加：
18.167.13.186 csp.hk.beanfun.com
18.163.12.31 csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com

=== 故障排除 ===
1. 服务无法启动：journalctl -u xray -f
2. 代理连接失败：检查防火墙和端口
3. 游戏仍无法连接：清除本地DNS缓存
4. DNS解析错误：运行 /usr/local/bin/dns-test.sh

=== 功能特性 ===
✓ SOCKS5/HTTP双协议支持
✓ UDP转发支持（游戏专用）
✓ DNS污染修复
✓ 多用户认证
✓ 网络优化配置
✓ 自动化管理脚本

#############################################################################
CONFIGEOF

    log_info "配置信息已保存到: ~/Game_Proxy_Complete_Config.txt"
}

# 执行最终测试
final_test() {
    log_step "执行最终测试..."
    
    echo ""
    echo "========== 服务状态检查 =========="
    systemctl status xray --no-pager -l
    
    echo ""
    echo "========== 端口监听检查 =========="
    netstat -tuln | grep -E "(18889|18890|12345)"
    
    echo ""
    echo "========== 代理连接测试 =========="
    /usr/local/bin/dns-test.sh
}

# 主函数
main() {
    echo -e "${GREEN}"
    echo "========================================"
    echo "     综合游戏代理安装配置脚本"
    echo "========================================"
    echo -e "${NC}"
    echo "功能包括："
    echo "• SOCKS5/HTTP代理安装"
    echo "• DNS污染修复"  
    echo "• UDP转发优化"
    echo "• 游戏代理配置"
    echo "• 网络优化"
    echo ""
    
    # 检查权限
    check_root
    
    # 系统检测
    detect_system
    
    # 配置YUM源
    setup_repos
    
    # 安装依赖
    install_dependencies
    
    # 安装Xray
    install_xray
    
    # 配置Xray
    configure_xray
    
    # DNS修复
    fix_dns
    
    # 网络优化
    configure_network
    
    # 防火墙配置
    configure_firewall
    
    # 创建管理脚本
    create_management_scripts
    
    # 启动服务
    start_services
    
    # 生成配置信息
    generate_config_info
    
    # 最终测试
    final_test
    
    # 获取服务器IP
    SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)
    
    echo ""
    echo -e "${GREEN}========================================"
    echo "          安装配置完成！"
    echo "========================================${NC}"
    echo -e "${BLUE}服务器IP:${NC} $SERVER_IP"
    echo -e "${BLUE}SOCKS5端口:${NC} 18889 (支持UDP)"
    echo -e "${BLUE}HTTP端口:${NC} 18890"
    echo -e "${BLUE}用户名:${NC} vip1, vip2, vip3"
    echo -e "${BLUE}密码:${NC} 123456"
    echo ""
    echo -e "${YELLOW}快速启动命令:${NC}"
    echo "  /usr/local/bin/game-proxy.sh"
    echo ""
    echo -e "${YELLOW}配置文件位置:${NC}"
    echo "  ~/Game_Proxy_Complete_Config.txt"
    echo ""
    echo -e "${GREEN}现在可以在游戏登录器中配置代理了！${NC}"
}

# 执行主函数
main "$@"

#!/bin/bash

# 综合游戏代理一键安装脚本 (IP自动发现版)
# 功能: 自动获取游戏IP + SOCKS5安装 + DNS修复 + Hosts配置
# 使用方法: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install.sh | bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo -e "${GREEN}"
echo "========================================"
echo "   游戏代理一键安装脚本 (增强版)"
echo "========================================"
echo -e "${NC}"
echo "功能包括："
echo "• 自动获取游戏官网所有IP地址"
echo "• SOCKS5/HTTP代理安装配置"
echo "• DNS污染自动修复"  
echo "• 系统hosts文件自动配置"
echo "• 网络优化和防火墙配置"
echo ""

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    log_error "请使用root权限运行此脚本"
    exit 1
fi

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

# 配置YUM源
setup_repos() {
    if [ "$OS" = "centos" ]; then
        log_step "配置YUM源..."
        
        mkdir -p /etc/yum.repos.d.backup
        cp -r /etc/yum.repos.d/* /etc/yum.repos.d.backup/ 2>/dev/null || true
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

        tee /etc/yum.repos.d/epel.repo > /dev/null << 'EPELEOF'
[epel]
name=Extra Packages for Enterprise Linux 7 - $basearch
baseurl=http://download.fedoraproject.org/pub/epel/7/$basearch
failovermethod=priority
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
EPELEOF

        yum clean all
        yum makecache
    fi
}

# 安装依赖软件
install_dependencies() {
    log_step "安装依赖软件..."
    
    if [ "$OS" = "centos" ]; then
        yum -y install curl wget unzip jq net-tools iptables-services bind-utils
    elif [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get update
        apt-get -y install curl wget unzip jq net-tools iptables-persistent dnsutils
    fi
    
    log_info "依赖软件安装完成"
}

# 自动发现游戏IP地址
discover_game_ips() {
    log_step "自动发现游戏官网IP地址..."
    
    # 游戏相关域名列表
    GAME_DOMAINS=(
        "hk.beanfun.com"
        "bfweb.hk.beanfun.com"
        "csp.hk.beanfun.com"
        "account.hk.beanfun.com"
        "auth.hk.beanfun.com"
        "tw.beanfun.com"
        "bfweb.tw.beanfun.com"
        "csp.tw.beanfun.com"
        "account.tw.beanfun.com"
        "beanfun.com"
        "www.beanfun.com"
        "login.beanfun.com"
        "maplestory.beanfun.com"
        "api.beanfun.com"
        "cdn.beanfun.com"
    )
    
    # DNS服务器列表
    DNS_SERVERS=("8.8.8.8" "1.1.1.1" "223.5.5.5" "208.67.222.222")
    
    # 创建临时文件
    TEMP_HOSTS="/tmp/beanfun_discovered_hosts.txt"
    > $TEMP_HOSTS
    
    # 存储发现的IP
    declare -A discovered_ips
    declare -A domain_ip_map
    
    log_info "开始DNS解析，这可能需要几分钟..."
    
    for domain in "${GAME_DOMAINS[@]}"; do
        echo -n "正在查询 $domain ... "
        
        found_ip=""
        for dns in "${DNS_SERVERS[@]}"; do
            if command -v dig >/dev/null 2>&1; then
                ip=$(dig @$dns +short $domain A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
            elif command -v nslookup >/dev/null 2>&1; then
                ip=$(nslookup $domain $dns 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
            fi
            
            if [ ! -z "$ip" ] && [ "$ip" != "" ]; then
                found_ip="$ip"
                break
            fi
        done
        
        if [ ! -z "$found_ip" ]; then
            echo "✓ $found_ip"
            discovered_ips["$found_ip"]=1
            domain_ip_map["$domain"]="$found_ip"
            echo "$found_ip $domain" >> $TEMP_HOSTS
        else
            echo "✗ 解析失败"
        fi
    done
    
    # 验证连通性
    log_info "验证IP连通性..."
    valid_ips=()
    
    for ip in "${!discovered_ips[@]}"; do
        echo -n "测试 $ip ... "
        if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$ip/80" 2>/dev/null || \
           timeout 5 bash -c "cat < /dev/null > /dev/tcp/$ip/443" 2>/dev/null; then
            echo "✓ 可连通"
            valid_ips+=("$ip")
        else
            echo "✗ 无响应"
        fi
    done
    
    log_info "发现 ${#discovered_ips[@]} 个IP地址，其中 ${#valid_ips[@]} 个可连通"
    
    # 保存结果到全局变量
    DISCOVERED_IPS=($(printf '%s\n' "${!discovered_ips[@]}" | sort))
    VALID_IPS=($(printf '%s\n' "${valid_ips[@]}" | sort))
}

# 安装Xray
install_xray() {
    log_step "安装Xray代理服务器..."
    
    TEMP_DIR=$(mktemp -d)
    cd $TEMP_DIR
    
    log_info "下载Xray..."
    if ! wget -O xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip; then
        log_warn "主下载地址失败，尝试备用地址..."
        if ! wget -O xray.zip https://vip.123pan.cn/1816473155/%E6%8F%92%E4%BB%B6%E6%B3%A8%E5%86%8CIP/xray; then
            log_error "下载Xray失败"
            exit 1
        fi
    fi
    
    log_info "解压安装Xray..."
    unzip -o xray.zip
    
    if [ ! -f "xray" ]; then
        log_error "Xray文件未找到"
        exit 1
    fi
    
    mv xray /usr/local/bin/
    chmod +x /usr/local/bin/xray
    
    if ! /usr/local/bin/xray version >/dev/null 2>&1; then
        log_error "Xray安装验证失败"
        exit 1
    fi
    
    log_info "Xray安装成功"
    
    cd /
    rm -rf $TEMP_DIR
}

# 配置Xray（集成IP发现结果）
configure_xray() {
    log_step "配置Xray代理服务器..."
    
    mkdir -p /etc/xray
    mkdir -p /var/log/xray
    chown root:root /var/log/xray
    
    systemctl stop xray 2>/dev/null || true
    
    # 生成域名列表（用于DNS配置）
    DOMAIN_LIST=""
    for domain in "domain:beanfun.com" "domain:gamania.com" "domain:gnjoy.com"; do
        DOMAIN_LIST="$DOMAIN_LIST\"$domain\","
    done
    DOMAIN_LIST=${DOMAIN_LIST%,}  # 移除最后的逗号
    
    # 生成IP列表（用于路由配置）
    IP_LIST=""
    for ip in "${VALID_IPS[@]}"; do
        IP_LIST="$IP_LIST\"$ip/32\","
    done
    IP_LIST=${IP_LIST%,}  # 移除最后的逗号
    
    # 创建Xray配置文件
    tee /etc/xray/config.json > /dev/null << XRAYEOF
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
          $DOMAIN_LIST
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
        "domainsExcluded": ["courier.push.apple.com"]
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
        "response": {"type": "http"}
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
          "domain:gnjoy.com"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": [
          $IP_LIST
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

# 配置系统DNS和hosts
configure_dns_hosts() {
    log_step "配置系统DNS和hosts文件..."
    
    # 备份原始配置
    cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d_%H%M%S)
    
    # 配置DNS
    tee /etc/resolv.conf > /dev/null << 'DNSEOF'
# DNS配置 - 防污染版本
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
options timeout:2
options attempts:3
options rotate
DNSEOF

    # 清理旧的游戏域名条目
    sed -i '/beanfun\|gamania\|gnjoy/d' /etc/hosts
    
    # 添加新的hosts条目
    echo "" >> /etc/hosts
    echo "# 游戏域名映射 - 自动生成 $(date)" >> /etc/hosts
    
    if [ -f "/tmp/beanfun_discovered_hosts.txt" ]; then
        cat /tmp/beanfun_discovered_hosts.txt >> /etc/hosts
        rm -f /tmp/beanfun_discovered_hosts.txt
    fi
    
    # 添加已知的关键IP映射
    cat >> /etc/hosts << 'HOSTSEOF'
# 已知游戏服务器IP
18.167.13.186 csp.hk.beanfun.com
18.163.12.31 csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com
HOSTSEOF

    log_info "DNS和hosts配置完成"
}

# 网络优化配置
configure_network() {
    log_step "配置网络优化..."
    
    # 启用IP转发
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
    
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
    log_info "网络优化完成"
}

# 配置防火墙
configure_firewall() {
    log_step "配置防火墙..."
    
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
    
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT  
    iptables -P OUTPUT ACCEPT
    
    # 开放代理端口
    iptables -A INPUT -p tcp --dport 18889 -j ACCEPT
    iptables -A INPUT -p udp --dport 18889 -j ACCEPT
    iptables -A INPUT -p tcp --dport 18890 -j ACCEPT
    iptables -A INPUT -p tcp --dport 12345 -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p tcp --dport 53 -j ACCEPT
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    
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
    
    # 游戏代理测试脚本
    tee /usr/local/bin/test-game-proxy.sh > /dev/null << 'TESTEOF'
#!/bin/bash

echo "========== 游戏代理测试 =========="

# 检查服务状态
echo "1. 检查Xray服务状态:"
if systemctl is-active --quiet xray; then
    echo "   ✓ Xray服务运行正常"
else
    echo "   ✗ Xray服务未运行"
    exit 1
fi

# 检查端口监听
echo ""
echo "2. 检查端口监听:"
netstat -tuln | grep -E "(18889|18890|12345)" | while read line; do
    echo "   ✓ $line"
done

# 测试DNS解析
echo ""
echo "3. 测试DNS解析:"
for domain in "hk.beanfun.com" "csp.hk.beanfun.com" "tw.beanfun.com"; do
    ip=$(dig +short $domain 2>/dev/null | head -1)
    if [ ! -z "$ip" ]; then
        echo "   ✓ $domain -> $ip"
    else
        echo "   ✗ $domain -> 解析失败"
    fi
done

# 测试代理连接
echo ""
echo "4. 测试代理连接:"
echo "   SOCKS5代理测试:"
if timeout 10 curl --socks5 vip1:123456@127.0.0.1:18889 -s https://httpbin.org/ip >/dev/null 2>&1; then
    echo "   ✓ SOCKS5代理正常"
else
    echo "   ✗ SOCKS5代理异常"
fi

echo "   HTTP代理测试:"
if timeout 10 curl --proxy http://vip1:123456@127.0.0.1:18890 -s https://httpbin.org/ip >/dev/null 2>&1; then
    echo "   ✓ HTTP代理正常"
else
    echo "   ✗ HTTP代理异常"
fi

echo ""
echo "========== 测试完成 =========="
TESTEOF

    chmod +x /usr/local/bin/test-game-proxy.sh
    
    # 更新IP脚本
    tee /usr/local/bin/update-game-ips.sh > /dev/null << 'UPDATEEOF'
#!/bin/bash

echo "更新游戏IP地址..."

# 重新发现IP
DOMAINS=("hk.beanfun.com" "csp.hk.beanfun.com" "tw.beanfun.com" "beanfun.com")
TEMP_HOSTS="/tmp/new_game_hosts.txt"
> $TEMP_HOSTS

for domain in "${DOMAINS[@]}"; do
    echo "查询 $domain ..."
    ip=$(dig @8.8.8.8 +short $domain 2>/dev/null | head -1)
    if [ ! -z "$ip" ]; then
        echo "$ip $domain" >> $TEMP_HOSTS
        echo "  ✓ $ip"
    fi
done

# 更新hosts文件
if [ -s "$TEMP_HOSTS" ]; then
    # 备份并清理
    cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d_%H%M%S)
    sed -i '/beanfun\|gamania\|gnjoy/d' /etc/hosts
    
    # 添加新条目
    echo "" >> /etc/hosts
    echo "# 游戏域名映射 - 更新 $(date)" >> /etc/hosts
    cat $TEMP_HOSTS >> /etc/hosts
    
    echo "hosts文件已更新"
    rm -f $TEMP_HOSTS
    
    # 重启xray服务
    if systemctl is-active --quiet xray; then
        echo "重启Xray服务..."
        systemctl restart xray
    fi
    
    echo "IP更新完成"
else
    echo "未发现新IP，保持现有配置"
fi
UPDATEEOF

    chmod +x /usr/local/bin/update-game-ips.sh
    
    log_info "管理脚本创建完成"
}

# 启动服务
start_services() {
    log_step "启动服务..."
    
    systemctl daemon-reload
    systemctl enable xray
    systemctl restart xray
    
    sleep 5
    
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
    
    SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 ipinfo.io/ip 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)
    
    tee ~/Game_Proxy_Complete_Config.txt > /dev/null << CONFIGEOF
#############################################################################
游戏代理完整配置信息 (IP自动发现版)

服务器IP: $SERVER_IP
安装时间: $(date)
发现的游戏IP数量: ${#DISCOVERED_IPS[@]}
有效IP数量: ${#VALID_IPS[@]}

=== 代理设置 ===
SOCKS5代理: $SERVER_IP:18889 (支持UDP，推荐游戏使用)
HTTP代理: $SERVER_IP:18890
用户名: vip1, vip2, vip3
密码: 123456

=== 发现的游戏IP地址 ===
$(printf '%s\n' "${DISCOVERED_IPS[@]}")

=== 有效IP地址 ===
$(printf '%s\n' "${VALID_IPS[@]}")

=== 游戏客户端设置建议 ===
1. 优先使用SOCKS5代理（支持UDP和DNS代理）
2. 代理地址: $SERVER_IP:18889
3. 用户名: vip1  密码: 123456
4. 启用"代理DNS查询"或"通过代理解析域名"
5. 如果有"UDP转发"选项，请启用

=== 自动化功能 ===
✓ 已自动发现 ${#DISCOVERED_IPS[@]} 个游戏IP地址
✓ 已自动配置系统hosts文件
✓ 已自动配置DNS防污染
✓ 已自动优化网络参数
✓ 已自动配置防火墙规则

=== 管理命令 ===
测试代理状态: /usr/local/bin/test-game-proxy.sh
更新游戏IP: /usr/local/bin/update-game-ips.sh
查看服务状态: systemctl status xray
查看实时日志: journalctl -u xray -f
重启服务: systemctl restart xray

=== 连接测试命令 ===
SOCKS5测试: curl --socks5 vip1:123456@$SERVER_IP:18889 https://httpbin.org/ip
HTTP测试: curl --proxy http://vip1:123456@$SERVER_IP:18890 https://httpbin.org/ip
DNS测试: dig @$SERVER_IP csp.hk.beanfun.com

=== 故障排除 ===
1. 代理连接失败：检查防火墙和用户名密码
2. 游戏无法连接：运行IP更新脚本
3. DNS解析错误：检查hosts文件配置
4. 服务启动失败：查看Xray日志

=== 定期维护 ===
建议每周运行一次IP更新: /usr/local/bin/update-game-ips.sh
这将确保始终使用最新的游戏服务器IP地址

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
    echo "========== 自动代理测试 =========="
    /usr/local/bin/test-game-proxy.sh
}

# 主函数
main() {
    detect_system
    setup_repos
    install_dependencies
    discover_game_ips  # 新增：自动发现IP
    install_xray
    configure_xray     # 集成发现的IP
    configure_dns_hosts # 新增：配置DNS和hosts
    configure_network
    configure_firewall
    create_management_scripts
    start_services
    generate_config_info
    final_test
    
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
    echo -e "${YELLOW}自动发现功能:${NC}"
    echo "✓ 发现 ${#DISCOVERED_IPS[@]} 个游戏IP地址"
    echo "✓ 自动配置hosts文件"
    echo "✓ 自动配置DNS防污染"
    echo ""
    echo -e "${YELLOW}管理命令:${NC}"
    echo "  测试代理: /usr/local/bin/test-game-proxy.sh"
    echo "  更新IP: /usr/local/bin/update-game-ips.sh"
    echo ""
    echo -e "${GREEN}现在可以在游戏客户端中配置SOCKS5代理了！${NC}"
    echo -e "${GREEN}推荐使用SOCKS5代理，支持UDP和自动DNS解析${NC}"
}

# 执行主函数
main "$@"

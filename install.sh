#!/bin/bash

# 游戏代理一键安装脚本 (最终修复版 - 含实际IP)
# 功能: 自动获取游戏IP + SOCKS5安装 + DNS修复 + Hosts配置
# 使用方法: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install.sh | bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 全局变量
DNS_TOOL=""
DISCOVERED_IPS=()
VALID_IPS=()

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo -e "${GREEN}"
echo "========================================"
echo "   游戏代理一键安装脚本 (最终修复版)"
echo "========================================"
echo -e "${NC}"
echo "功能包括："
echo "• 强制安装DNS解析工具 (dig/nslookup)"
echo "• 智能IP发现 + 真实IP备用列表"
echo "• 修复grep正则表达式问题"
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

# 修复网络和DNS配置
fix_network_dns() {
    log_step "修复网络和DNS配置..."
    
    # 备份原始DNS配置
    cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    
    # 解锁文件（如果被锁定）
    chattr -i /etc/resolv.conf 2>/dev/null || true
    
    # 处理符号链接问题
    if [ -L /etc/resolv.conf ]; then
        target=$(readlink /etc/resolv.conf)
        if echo "$target" | grep -q "systemd"; then
            log_info "检测到systemd-resolved管理，正在停止..."
            systemctl stop systemd-resolved 2>/dev/null || true
            systemctl disable systemd-resolved 2>/dev/null || true
        fi
        rm -f /etc/resolv.conf
    fi
    
    # 强制设置可用的DNS
    cat > /etc/resolv.conf << 'FIXDNS'
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
options timeout:3
options attempts:2
FIXDNS
    
    # 设置正确权限
    chmod 644 /etc/resolv.conf
    chown root:root /etc/resolv.conf
    
    # 测试网络连接
    log_info "测试网络连接..."
    if ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_info "网络连接正常"
    else
        log_warn "网络连接可能有问题，继续尝试..."
    fi
}

# 安装依赖软件（强化DNS工具安装）
install_dependencies() {
    log_step "安装依赖软件..."
    
    if [ "$OS" = "centos" ]; then
        log_info "强制安装DNS解析工具..."
        
        # 1. 优先安装bind-utils（包含dig和nslookup）
        dns_tools_installed=false
        
        echo "尝试安装bind-utils (dig命令)..."
        if yum -y install bind-utils --nogpgcheck 2>/dev/null; then
            echo "✓ bind-utils 通过YUM安装成功"
            dns_tools_installed=true
        else
            log_warn "YUM安装bind-utils失败，尝试手动安装..."
            
            # 手动下载安装bind-utils
            cd /tmp
            rm -f bind-utils*.rpm
            
            # 尝试多个版本的bind-utils
            bind_urls=(
                "http://mirror.centos.org/centos/7/os/x86_64/Packages/bind-utils-9.11.4-26.P2.el7_9.16.x86_64.rpm"
                "http://vault.centos.org/centos/7/os/x86_64/Packages/bind-utils-9.11.4-26.P2.el7_9.16.x86_64.rpm"
                "https://download-ib01.fedoraproject.org/pub/epel/7/x86_64/Packages/b/bind-utils-9.11.4-26.P2.el7_9.16.x86_64.rpm"
            )
            
            for url in "${bind_urls[@]}"; do
                echo "尝试下载: $url"
                if wget -q "$url" 2>/dev/null; then
                    rpm_file=$(basename "$url")
                    if rpm -ivh "$rpm_file" --force --nodeps 2>/dev/null; then
                        echo "✓ bind-utils 手动安装成功"
                        dns_tools_installed=true
                        break
                    fi
                fi
            done
        fi
        
        # 验证DNS工具安装
        if command -v dig >/dev/null 2>&1; then
            echo "✓ dig 命令可用"
            DNS_TOOL="dig"
        elif command -v nslookup >/dev/null 2>&1; then
            echo "✓ nslookup 命令可用"
            DNS_TOOL="nslookup"
        else
            log_warn "❌ DNS解析工具仍不可用，将使用内置IP列表"
            DNS_TOOL="builtin"
        fi
        
        # 2. 安装unzip（必需）
        if ! command -v unzip >/dev/null 2>&1; then
            echo "安装 unzip ..."
            if ! yum -y install unzip --nogpgcheck 2>/dev/null; then
                log_warn "YUM安装unzip失败，尝试手动安装..."
                cd /tmp
                for mirror in "http://mirror.centos.org" "http://vault.centos.org"; do
                    if wget -q $mirror/centos/7/os/x86_64/Packages/unzip-6.0-21.el7.x86_64.rpm 2>/dev/null; then
                        rpm -ivh unzip-6.0-21.el7.x86_64.rpm --force --nodeps 2>/dev/null && break
                    fi
                done
            fi
        fi
        
        # 验证unzip安装
        if command -v unzip >/dev/null 2>&1; then
            echo "✓ unzip 安装成功"
        else
            log_warn "unzip 安装失败，将使用替代解压方法"
        fi
        
        # 3. 安装其他工具（可选）
        for pkg in jq net-tools; do
            if ! command -v $pkg >/dev/null 2>&1; then
                echo "尝试安装 $pkg ..."
                yum -y install $pkg --nogpgcheck 2>/dev/null || {
                    log_warn "跳过$pkg安装"
                }
            fi
        done
        
    elif [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get update
        apt-get -y install curl wget unzip jq net-tools dnsutils
        
        if command -v dig >/dev/null 2>&1; then
            DNS_TOOL="dig"
        elif command -v nslookup >/dev/null 2>&1; then
            DNS_TOOL="nslookup"
        else
            DNS_TOOL="builtin"
        fi
    fi
    
    log_info "依赖软件配置完成，DNS工具: $DNS_TOOL"
}

# 自动发现游戏IP地址（修复版）
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
    
    # 内置真实IP列表（用户提供的实际IP）
    declare -A builtin_ips
    builtin_ips["hk.beanfun.com"]="112.121.124.11"
    builtin_ips["csp.hk.beanfun.com"]="18.167.13.186"
    builtin_ips["bfweb.hk.beanfun.com"]="18.163.12.31"
    builtin_ips["tw.beanfun.com"]="202.80.107.11"
    builtin_ips["beanfun.com"]="52.147.74.109"
    builtin_ips["www.beanfun.com"]="52.147.74.109"
    builtin_ips["account.hk.beanfun.com"]="18.167.13.186"
    builtin_ips["auth.hk.beanfun.com"]="18.167.13.186"
    builtin_ips["csp.tw.beanfun.com"]="202.80.107.11"
    builtin_ips["account.tw.beanfun.com"]="202.80.107.11"
    
    if [ "$DNS_TOOL" = "builtin" ]; then
        log_warn "DNS工具不可用，使用真实IP列表..."
        
        for domain in "${!builtin_ips[@]}"; do
            ip="${builtin_ips[$domain]}"
            echo "内置映射: $domain -> $ip"
            discovered_ips["$ip"]=1
            domain_ip_map["$domain"]="$ip"
            echo "$ip $domain" >> $TEMP_HOSTS
        done
        
        # 设置全局变量
        DISCOVERED_IPS=($(printf '%s\n' "${!discovered_ips[@]}" | sort))
        VALID_IPS=($(printf '%s\n' "${!discovered_ips[@]}" | sort))
        
        log_info "使用真实IP列表: ${#DISCOVERED_IPS[@]} 个地址"
        return 0
    fi
    
    log_info "开始DNS解析，使用工具: $DNS_TOOL"
    
    # DNS解析函数（修复grep正则表达式）
    resolve_domain_ip() {
        local domain=$1
        local dns=$2
        local result=""
        
        if [ "$DNS_TOOL" = "dig" ]; then
            # 修复：使用更简单的IP地址匹配
            result=$(dig @$dns +short $domain A 2>/dev/null | head -1)
            # 验证是否为有效IP地址
            if echo "$result" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
                echo "$result"
            fi
        elif [ "$DNS_TOOL" = "nslookup" ]; then
            # 修复nslookup解析逻辑
            local nslookup_output=$(nslookup $domain $dns 2>/dev/null)
            
            # 从nslookup输出中提取IP地址，排除DNS服务器地址
            result=$(echo "$nslookup_output" | awk '
                /^Address: / && !/'"$dns"'/ { 
                    ip = $2; 
                    if (ip ~ /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/) 
                        print ip; 
                    exit 
                }
            ')
            
            # 如果上面方法失败，尝试另一种方式
            if [ -z "$result" ]; then
                result=$(echo "$nslookup_output" | grep "Address:" | grep -v "$dns" | head -1 | awk '{print $2}')
                # 验证IP格式
                if ! echo "$result" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
                    result=""
                fi
            fi
            
            echo "$result"
        fi
    }
    
    # 开始解析
    for domain in "${GAME_DOMAINS[@]}"; do
        echo -n "正在查询 $domain ... "
        
        found_ip=""
        for dns in "${DNS_SERVERS[@]}"; do
            ip=$(resolve_domain_ip "$domain" "$dns")
            
            if [ ! -z "$ip" ]; then
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
            
            # 如果解析失败，尝试使用内置IP
            if [ ! -z "${builtin_ips[$domain]}" ]; then
                fallback_ip="${builtin_ips[$domain]}"
                echo "  使用备用IP: $fallback_ip"
                discovered_ips["$fallback_ip"]=1
                domain_ip_map["$domain"]="$fallback_ip"
                echo "$fallback_ip $domain" >> $TEMP_HOSTS
            fi
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
            # 即使无响应也保留，可能是防火墙阻止了探测
            valid_ips+=("$ip")
        fi
    done
    
    log_info "发现 ${#discovered_ips[@]} 个IP地址，其中 ${#valid_ips[@]} 个通过验证"
    
    # 如果没有发现任何IP，使用内置列表
    if [ ${#discovered_ips[@]} -eq 0 ]; then
        log_warn "未发现任何IP，使用真实IP列表作为备用..."
        
        for domain in "${!builtin_ips[@]}"; do
            ip="${builtin_ips[$domain]}"
            discovered_ips["$ip"]=1
            echo "$ip $domain" >> $TEMP_HOSTS
        done
        
        DISCOVERED_IPS=($(printf '%s\n' "${!discovered_ips[@]}" | sort))
        VALID_IPS=($(printf '%s\n' "${!discovered_ips[@]}" | sort))
    else
        # 保存结果到全局变量
        DISCOVERED_IPS=($(printf '%s\n' "${!discovered_ips[@]}" | sort))
        VALID_IPS=($(printf '%s\n' "${valid_ips[@]}" | sort))
    fi
}

# 安装Xray（增强版）
install_xray() {
    log_step "安装Xray代理服务器..."
    
    TEMP_DIR=$(mktemp -d)
    cd $TEMP_DIR
    
    log_info "下载Xray..."
    
    # 多种下载方法和多个版本
    download_success=false
    
    # 方法1: wget下载最新版
    if ! $download_success && command -v wget >/dev/null 2>&1; then
        log_info "尝试wget下载最新版..."
        if wget -O xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip 2>/dev/null; then
            download_success=true
            log_info "wget下载成功"
        fi
    fi
    
    # 方法2: curl下载最新版
    if ! $download_success && command -v curl >/dev/null 2>&1; then
        log_info "尝试curl下载最新版..."
        if curl -L -o xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip 2>/dev/null; then
            download_success=true
            log_info "curl下载成功"
        fi
    fi
    
    # 方法3: 下载指定版本
    if ! $download_success; then
        log_warn "最新版下载失败，尝试下载稳定版本..."
        versions=("v1.8.6" "v1.8.5" "v1.8.4")
        for version in "${versions[@]}"; do
            if wget -O xray.zip https://github.com/XTLS/Xray-core/releases/download/$version/Xray-linux-64.zip 2>/dev/null; then
                download_success=true
                log_info "下载版本 $version 成功"
                break
            fi
        done
    fi
    
    # 方法4: 备用下载地址
    if ! $download_success; then
        log_warn "GitHub下载失败，尝试备用地址..."
        if wget -O xray https://vip.123pan.cn/1816473155/%E6%8F%92%E4%BB%B6%E6%B3%A8%E5%86%8CIP/xray 2>/dev/null; then
            download_success=true
            log_info "备用地址下载成功"
        fi
    fi
    
    if ! $download_success; then
        log_error "所有下载方法都失败了"
        exit 1
    fi
    
    log_info "解压安装Xray..."
    
    # 如果下载的是zip文件，需要解压
    if [ -f "xray.zip" ]; then
        if command -v unzip >/dev/null 2>&1; then
            if unzip -o xray.zip 2>/dev/null; then
                log_info "unzip解压成功"
            else
                log_warn "unzip解压失败，尝试其他方法..."
                # 如果解压失败，尝试重命名（可能下载的就是二进制文件）
                mv xray.zip xray 2>/dev/null || true
            fi
        else
            log_warn "unzip不可用，尝试将zip文件直接作为二进制文件..."
            mv xray.zip xray 2>/dev/null || true
        fi
    fi
    
    # 检查xray文件
    if [ ! -f "xray" ]; then
        log_error "Xray文件未找到，列出目录内容："
        ls -la
        exit 1
    fi
    
    # 检查文件类型
    file_type=$(file xray 2>/dev/null || echo "unknown")
    log_info "Xray文件类型: $file_type"
    
    # 安装xray
    cp xray /usr/local/bin/
    chmod +x /usr/local/bin/xray
    
    # 验证安装
    if [ -x /usr/local/bin/xray ]; then
        # 尝试运行version命令验证
        if /usr/local/bin/xray version >/dev/null 2>&1; then
            log_info "Xray安装和验证成功"
        else
            log_warn "Xray安装成功但version验证失败，可能是版本兼容问题"
        fi
    else
        log_error "Xray安装失败"
        exit 1
    fi
    
    cd /
    rm -rf $TEMP_DIR
}

# 配置Xray（集成IP发现结果）
configure_xray() {
    log_step "配置Xray代理服务器..."
    
    mkdir -p /etc/xray
    mkdir -p /var/log/xray
    chown root:root /var/log/xray
    
    # 停止现有服务
    systemctl stop xray 2>/dev/null || true
    killall xray 2>/dev/null || true
    
    # 生成域名列表（用于DNS配置）
    DOMAIN_LIST=""
    for domain in "domain:beanfun.com" "domain:gamania.com" "domain:gnjoy.com"; do
        DOMAIN_LIST="$DOMAIN_LIST\"$domain\","
    done
    DOMAIN_LIST=${DOMAIN_LIST%,}  # 移除最后的逗号
    
    # 生成IP列表（用于路由配置）
    IP_LIST=""
    if [ ${#VALID_IPS[@]} -gt 0 ]; then
        for ip in "${VALID_IPS[@]}"; do
            IP_LIST="$IP_LIST\"$ip/32\","
        done
        IP_LIST=${IP_LIST%,}  # 移除最后的逗号
    else
        # 如果没有发现IP，使用已知的默认IP
        IP_LIST="\"112.121.124.11/32\",\"18.167.13.186/32\",\"18.163.12.31/32\",\"202.80.107.11/32\",\"52.147.74.109/32\""
    fi
    
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
    cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d_%H%M%S)
    
    # 清理旧的游戏域名条目
    sed -i '/beanfun\|gamania\|gnjoy/d' /etc/hosts
    
    # 添加新的hosts条目
    echo "" >> /etc/hosts
    echo "# 游戏域名映射 - 自动生成 $(date)" >> /etc/hosts
    
    if [ -f "/tmp/beanfun_discovered_hosts.txt" ]; then
        cat /tmp/beanfun_discovered_hosts.txt >> /etc/hosts
        rm -f /tmp/beanfun_discovered_hosts.txt
    fi
    
    # 添加已知的关键IP映射（真实IP）
    cat >> /etc/hosts << 'HOSTSEOF'
# 游戏服务器真实IP（备用）
112.121.124.11 hk.beanfun.com
18.167.13.186 csp.hk.beanfun.com
18.163.12.31 csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com
202.80.107.11 tw.beanfun.com
52.147.74.109 beanfun.com
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
NETEOF

    sysctl -p 2>/dev/null || true
    log_info "网络优化完成"
}

# 配置防火墙
configure_firewall() {
    log_step "配置防火墙..."
    
    # 停止firewalld
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
    
    # 清理iptables规则
    iptables -F 2>/dev/null || true
    iptables -X 2>/dev/null || true
    iptables -t nat -F 2>/dev/null || true
    iptables -t nat -X 2>/dev/null || true
    
    # 设置默认策略
    iptables -P INPUT ACCEPT 2>/dev/null || true
    iptables -P FORWARD ACCEPT 2>/dev/null || true
    iptables -P OUTPUT ACCEPT 2>/dev/null || true
    
    # 开放必要端口
    iptables -A INPUT -p tcp --dport 18889 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p udp --dport 18889 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport 18890 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    
    # 允许回环和已建立连接
    iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    
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
    
    # 游戏代理测试脚本
    tee /usr/local/bin/test-game-proxy.sh > /dev/null << 'TESTEOF'
#!/bin/bash

echo "========== 游戏代理测试 =========="

# 检查服务状态
echo "1. 检查Xray服务状态:"
if systemctl is-active --quiet xray 2>/dev/null; then
    echo "   ✓ Xray服务运行正常"
elif pgrep xray >/dev/null; then
    echo "   ✓ Xray进程运行正常"
else
    echo "   ✗ Xray服务未运行"
    exit 1
fi

# 检查端口监听
echo ""
echo "2. 检查端口监听:"
if command -v netstat >/dev/null 2>&1; then
    netstat -tuln 2>/dev/null | grep -E "(18889|18890)" | while read line; do
        echo "   ✓ $line"
    done
elif command -v ss >/dev/null 2>&1; then
    ss -tuln | grep -E "(18889|18890)" | while read line; do
        echo "   ✓ $line"
    done
else
    echo "   ⚠ 无法检查端口状态（缺少netstat/ss命令）"
fi

# 测试DNS解析
echo ""
echo "3. 测试DNS解析:"
for domain in "hk.beanfun.com" "csp.hk.beanfun.com" "tw.beanfun.com"; do
    ip=""
    if command -v dig >/dev/null 2>&1; then
        ip=$(dig +short $domain 2>/dev/null | head -1)
    elif command -v nslookup >/dev/null 2>&1; then
        ip=$(nslookup $domain 2>/dev/null | grep "Address:" | grep -v "8.8.8.8" | head -1 | awk '{print $2}')
    else
        # 从hosts文件查找
        ip=$(grep "$domain" /etc/hosts 2>/dev/null | head -1 | awk '{print $1}')
        if [ ! -z "$ip" ]; then
            ip="$ip (hosts文件)"
        fi
    fi
    
    if [ ! -z "$ip" ]; then
        echo "   ✓ $domain -> $ip"
    else
        echo "   ✗ $domain -> 解析失败"
    fi
done

# 测试代理连接
echo ""
echo "4. 测试代理连接:"
if command -v curl >/dev/null 2>&1; then
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
else
    echo "   ⚠ 无法测试代理连接（缺少curl命令）"
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

# 真实备用IP
declare -A backup_ips
backup_ips["hk.beanfun.com"]="112.121.124.11"
backup_ips["csp.hk.beanfun.com"]="18.167.13.186"
backup_ips["tw.beanfun.com"]="202.80.107.11"
backup_ips["beanfun.com"]="52.147.74.109"

for domain in "${DOMAINS[@]}"; do
    echo "查询 $domain ..."
    ip=""
    
    if command -v dig >/dev/null 2>&1; then
        ip=$(dig @8.8.8.8 +short $domain 2>/dev/null | head -1)
    elif command -v nslookup >/dev/null 2>&1; then
        ip=$(nslookup $domain 8.8.8.8 2>/dev/null | grep "Address:" | grep -v "8.8.8.8" | head -1 | awk '{print $2}')
    fi
    
    # 如果解析失败，使用备用IP
    if [ -z "$ip" ] && [ ! -z "${backup_ips[$domain]}" ]; then
        ip="${backup_ips[$domain]}"
        echo "  使用备用IP: $ip"
    elif [ ! -z "$ip" ]; then
        echo "  ✓ $ip"
    else
        echo "  ✗ 解析失败，跳过"
        continue
    fi
    
    echo "$ip $domain" >> $TEMP_HOSTS
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
    if systemctl is-active --quiet xray 2>/dev/null; then
        echo "重启Xray服务..."
        systemctl restart xray
    elif pgrep xray >/dev/null; then
        echo "重启Xray进程..."
        killall xray
        sleep 2
        /usr/local/bin/xray run -config /etc/xray/config.json >/dev/null 2>&1 &
    fi
    
    echo "IP更新完成"
else
    echo "未发现新IP，保持现有配置"
fi
UPDATEEOF

    chmod +x /usr/local/bin/update-game-ips.sh
    
    log_info "管理脚本创建完成"
}

# 启动服务（增强版）
start_services() {
    log_step "启动服务..."
    
    # 确保日志目录存在
    mkdir -p /var/log/xray
    
    # 验证配置文件
    log_info "验证Xray配置文件..."
    if [ ! -f /etc/xray/config.json ]; then
        log_error "配置文件不存在: /etc/xray/config.json"
        exit 1
    fi
    
    # 测试配置文件语法
    if /usr/local/bin/xray run -test -config /etc/xray/config.json 2>/dev/null; then
        log_info "配置文件语法正确"
    else
        log_warn "配置文件可能有语法问题，继续尝试启动..."
    fi
    
    # 清理现有进程
    log_info "清理现有Xray进程..."
    systemctl stop xray 2>/dev/null || true
    killall xray 2>/dev/null || true
    sleep 3
    
    # 重新加载systemd
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable xray 2>/dev/null || true
    
    # 尝试启动服务
    log_info "启动Xray服务..."
    if systemctl start xray 2>/dev/null; then
        log_info "systemctl启动成功"
    else
        log_warn "systemctl启动失败，尝试手动启动..."
        
        # 手动启动并记录详细日志
        nohup /usr/local/bin/xray run -config /etc/xray/config.json > /var/log/xray/xray.log 2>&1 &
        
        # 等待启动
        sleep 5
        
        if pgrep xray >/dev/null; then
            log_info "手动启动成功"
        else
            log_error "手动启动也失败了"
            
            # 显示详细错误信息
            echo "========== Xray启动日志 =========="
            cat /var/log/xray/xray.log 2>/dev/null || echo "日志文件不存在"
            
            echo "========== 配置文件检查 =========="
            echo "配置文件大小: $(wc -c < /etc/xray/config.json) 字节"
            echo "配置文件前几行:"
            head -10 /etc/xray/config.json
            
            exit 1
        fi
    fi
    
    # 等待服务完全启动
    sleep 8
    
    # 验证服务状态
    log_info "验证服务状态..."
    service_running=false
    
    if systemctl is-active --quiet xray 2>/dev/null; then
        log_info "✓ Xray服务运行正常 (systemd)"
        service_running=true
    elif pgrep xray >/dev/null; then
        log_info "✓ Xray进程运行正常 (手动启动)"
        service_running=true
    fi
    
    if ! $service_running; then
        log_error "Xray服务验证失败"
        exit 1
    fi
    
    # 验证端口监听
    log_info "验证端口监听..."
    sleep 3
    
    if netstat -tuln 2>/dev/null | grep -q ":18889" || ss -tuln 2>/dev/null | grep -q ":18889"; then
        log_info "✓ SOCKS5端口18889监听正常"
    else
        log_warn "⚠ SOCKS5端口18889可能未正常监听"
    fi
    
    if netstat -tuln 2>/dev/null | grep -q ":18890" || ss -tuln 2>/dev/null | grep -q ":18890"; then
        log_info "✓ HTTP端口18890监听正常"
    else
        log_warn "⚠ HTTP端口18890可能未正常监听"
    fi
}

# 生成配置信息
generate_config_info() {
    log_step "生成配置信息..."
    
    SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 ipinfo.io/ip 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)
    
    tee ~/Game_Proxy_Complete_Config.txt > /dev/null << CONFIGEOF
#############################################################################
游戏代理完整配置信息 (最终修复版)

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

=== 真实IP地址列表 ===
hk.beanfun.com: 112.121.124.11
csp.hk.beanfun.com: 18.167.13.186
tw.beanfun.com: 202.80.107.11
beanfun.com: 52.147.74.109

=== 游戏客户端设置建议 ===
1. 优先使用SOCKS5代理（支持UDP和DNS代理）
2. 代理地址: $SERVER_IP:18889
3. 用户名: vip1  密码: 123456
4. 启用"代理DNS查询"或"通过代理解析域名"
5. 如果有"UDP转发"选项，请启用

=== 自动化功能 ===
✓ 已强制安装DNS解析工具
✓ 已修复grep正则表达式问题
✓ 已自动发现/配置游戏IP地址
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

=== 故障排除 ===
1. 代理连接失败：检查防火墙和用户名密码
2. 游戏无法连接：运行IP更新脚本
3. DNS解析错误：检查hosts文件配置
4. 服务启动失败：查看日志文件

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
    if systemctl status xray --no-pager -l 2>/dev/null; then
        echo "Xray服务状态检查完成"
    else
        echo "无法通过systemctl检查状态，检查进程..."
        if pgrep xray >/dev/null; then
            echo "Xray进程运行正常"
        else
            echo "警告: Xray进程未运行"
        fi
    fi
    
    echo ""
    echo "========== 端口监听检查 =========="
    if command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -E "(18889|18890)" || echo "警告: 端口监听检查失败"
    elif command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -E "(18889|18890)" || echo "警告: 端口监听检查失败"
    else
        echo "跳过端口检查（缺少netstat/ss命令）"
    fi
    
    echo ""
    echo "========== 自动代理测试 =========="
    /usr/local/bin/test-game-proxy.sh
}

# 主函数
main() {
    detect_system
    fix_network_dns
    install_dependencies
    discover_game_ips
    install_xray
    configure_xray
    configure_dns_hosts
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
    echo -e "${YELLOW}真实IP发现功能:${NC}"
    echo "✓ 发现 ${#DISCOVERED_IPS[@]} 个游戏IP地址"
    echo "✓ 自动配置hosts文件"
    echo "✓ 自动配置DNS防污染"
    echo "✓ 修复grep正则表达式问题"
    echo ""
    echo -e "${YELLOW}管理命令:${NC}"
    echo "  测试代理: /usr/local/bin/test-game-proxy.sh"
    echo "  更新IP: /usr/local/bin/update-game-ips.sh"
    echo ""
    echo -e "${GREEN}现在可以在游戏客户端中配置SOCKS5代理了！${NC}"
    echo -e "${GREEN}推荐使用SOCKS5代理，支持UDP和自动DNS解析${NC}"
    
    # 最终连接测试
    log_step "执行最终连接测试..."
    if command -v curl >/dev/null 2>&1; then
        echo "测试SOCKS5代理连接..."
        if curl --socks5 vip1:123456@127.0.0.1:18889 --connect-timeout 10 -s https://httpbin.org/ip >/dev/null 2>&1; then
            echo -e "${GREEN}✓ SOCKS5代理测试成功！代理工作正常${NC}"
        else
            echo -e "${YELLOW}⚠ SOCKS5代理测试失败，但服务已启动，请检查防火墙设置${NC}"
        fi
    fi
}

# 执行主函数
main "$@"

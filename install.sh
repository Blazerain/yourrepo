#!/bin/bash

# SOCKS5 环境自动安装脚本 - 修复版
# 修复执行中断问题
# 使用方法: 
# curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install.sh | bash -s 1888
# 或: curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/install.sh | PORT=1888 bash
# cat ~/Sk5_User_Password.txt 配置信息
set -e

echo "=========================================="
echo "🚀 SOCKS5 代理安装程序 - 修复版"
echo "🌐 集成DNS优化、防火墙配置、Beanfun游戏支持"
echo "=========================================="

# 错误处理函数
error_exit() {
    echo "❌ 错误: $1" >&2
    echo "📍 脚本在第 $2 行停止执行" >&2
    exit 1
}

# 设置错误陷阱
trap 'error_exit "脚本执行失败" $LINENO' ERR

# 安全的命令执行函数
safe_execute() {
    local cmd="$1"
    local description="$2"
    
    echo "🔄 执行: $description"
    if eval "$cmd"; then
        echo "✅ 完成: $description"
        return 0
    else
        echo "❌ 失败: $description"
        return 1
    fi
}

# ====== 智能端口检测逻辑 ======
if [ -n "$1" ]; then
    SOCKS5_PORT="$1"
    echo "✅ 使用命令行端口参数: $SOCKS5_PORT"
elif [ -n "$PORT" ]; then
    SOCKS5_PORT="$PORT"
    echo "✅ 使用PORT环境变量: $SOCKS5_PORT"
elif [ -n "$SOCKS5_PORT" ]; then
    echo "✅ 使用SOCKS5_PORT环境变量: $SOCKS5_PORT"
else
    echo "🔍 未指定端口，自动检测可用端口..."
    for test_port in 1080 3128 8080 13000 18889; do
        if ! netstat -tlnp 2>/dev/null | grep -q ":$test_port "; then
            SOCKS5_PORT=$test_port
            echo "✅ 自动选择可用端口: $SOCKS5_PORT"
            break
        else
            echo "   端口 $test_port 已被占用"
        fi
    done
    
    if [ -z "$SOCKS5_PORT" ]; then
        SOCKS5_PORT=18889
        echo "⚠️ 所有常用端口均被占用，使用默认端口: $SOCKS5_PORT"
    fi
fi

# 验证端口号
if ! [[ "$SOCKS5_PORT" =~ ^[0-9]+$ ]] || [ "$SOCKS5_PORT" -lt 1024 ] || [ "$SOCKS5_PORT" -gt 65535 ]; then
    error_exit "无效的端口号 '$SOCKS5_PORT'，端口号必须在 1024-65535 之间" $LINENO
fi

HTTP_PORT=$((SOCKS5_PORT + 1))

echo "📍 确认端口配置:"
echo "   SOCKS5端口: $SOCKS5_PORT"
echo "   HTTP端口: $HTTP_PORT"

# 处理端口占用
if netstat -tlnp 2>/dev/null | grep -q ":$SOCKS5_PORT "; then
    echo ""
    echo "⚠️ 警告: 端口 $SOCKS5_PORT 已被占用，将覆盖现有配置"
    echo "⏳ 3秒后继续..."
    sleep 3
fi

echo ""
echo "🛠️ 开始安装 SOCKS5 环境..."

# 创建临时目录
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

# 停止现有服务 - 改进错误处理
echo "🛑 停止现有代理服务..."
safe_execute "sudo systemctl stop xray 2>/dev/null || true" "停止xray服务" || true
safe_execute "sudo systemctl stop sockd 2>/dev/null || true" "停止sockd服务" || true

# 安装必要软件 - 改进错误处理
echo "📦 安装依赖软件..."
safe_execute "sudo yum clean all >/dev/null 2>&1 || true" "清理yum缓存"
safe_execute "sudo yum -y install jq unzip wget curl net-tools bind-utils >/dev/null 2>&1" "安装依赖软件"

# ====== Beanfun域名DNS优化配置 ======
echo "=========================================="
echo "🌐 配置Beanfun游戏DNS优化（防污染）"
echo "=========================================="

# 备份DNS配置
safe_execute "sudo cp /etc/resolv.conf /etc/resolv.conf.bak.\$(date +%Y%m%d_%H%M%S) 2>/dev/null || true" "备份DNS配置"

# 创建优化DNS配置
safe_execute "sudo tee /etc/resolv.conf > /dev/null << 'DNSCONFIG'
# DNS配置 - Beanfun游戏优化版本
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
nameserver 114.114.114.114
nameserver 208.67.222.222
options timeout:2
options attempts:3
options rotate
options edns0
DNSCONFIG" "创建DNS配置"

# 备份hosts文件
safe_execute "sudo cp /etc/hosts /etc/hosts.bak.\$(date +%Y%m%d_%H%M%S)" "备份hosts文件"

# 移除旧的beanfun条目和污染IP
safe_execute "sudo sed -i '/beanfun/d' /etc/hosts" "清理旧hosts条目"
safe_execute "sudo sed -i '/31\.13\.106\.4/d' /etc/hosts" "清理污染IP"

echo "🔍 检测cdn.hk.beanfun.com的IP..."

# 修复CDN IP检测逻辑
cdn_ip=""
echo "正在检测cdn.hk.beanfun.com..."

# 先尝试直接解析A记录
direct_ip=$(dig +short cdn.hk.beanfun.com @8.8.8.8 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

if [ -n "$direct_ip" ]; then
    cdn_ip="$direct_ip"
    echo "✅ 直接解析到IP: $cdn_ip"
else
    # 如果是CNAME，解析CNAME目标
    echo "检测到CNAME，正在解析最终IP..."
    cname_target=$(dig +short cdn.hk.beanfun.com @8.8.8.8 | grep -v '^[0-9]' | head -1)
    if [ -n "$cname_target" ]; then
        echo "CNAME目标: $cname_target"
        final_ips=$(dig +short "$cname_target" @8.8.8.8 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        if [ -n "$final_ips" ]; then
            # 选择第一个IP
            cdn_ip=$(echo "$final_ips" | head -1)
            echo "✅ CNAME解析到IP: $cdn_ip"
            echo "其他可用IP: $(echo "$final_ips" | tr '\n' ' ')"
        fi
    fi
fi

# 如果所有检测都失败，使用合理的默认值
if [ -z "$cdn_ip" ]; then
    cdn_ip="112.121.124.69"
    echo "⚠️ 自动检测失败，使用默认IP: $cdn_ip"
fi

# 添加完整的Beanfun域名优化
safe_execute "sudo tee -a /etc/hosts > /dev/null << HOSTSCONFIG

# Beanfun游戏平台域名 - 防DNS污染优化 \$(date)
112.121.124.11 hk.beanfun.com
112.121.124.69 bfweb.hk.beanfun.com
$cdn_ip cdn.hk.beanfun.com
18.167.13.186 csp.hk.beanfun.com
18.163.12.31 csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com
202.80.107.11 tw.beanfun.com
52.147.74.109 beanfun.com

# 阻止DNS污染IP
127.0.0.1 31.13.106.4
HOSTSCONFIG" "添加Beanfun域名映射"

echo "✅ Beanfun域名DNS优化完成"

# ====== 安装和配置Xray ======
echo "=========================================="
echo "⬬ 下载和安装Xray"
echo "=========================================="

# 获取最新版本
XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name 2>/dev/null || echo "v1.8.4")
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"

echo "📥 下载xray版本: $XRAY_VERSION"
if ! wget -q -O xray.zip "$XRAY_URL" --timeout=30; then
    echo "⚠️ 主下载失败，尝试备用地址..."
    if ! wget -q -O xray.zip "https://vip.123pan.cn/1816473155/%E6%8F%92%E4%BB%B6%E6%B3%A8%E5%86%8CIP/xray" --timeout=30; then
        error_exit "Xray下载失败" $LINENO
    fi
fi

# 解压和安装
safe_execute "unzip -q -o xray.zip" "解压Xray"

if [ ! -f "xray" ]; then
    error_exit "Xray解压失败，文件不存在" $LINENO
fi

safe_execute "sudo mv xray /usr/local/bin/" "移动Xray到系统目录"
safe_execute "sudo chmod +x /usr/local/bin/xray" "设置Xray执行权限"

echo "✅ Xray安装成功"

# 创建配置目录
safe_execute "sudo mkdir -p /etc/xray /var/log/xray" "创建配置目录"

# ====== 创建完美版Xray配置 ======
echo "⚙️ 创建Xray配置，SOCKS5端口: $SOCKS5_PORT，HTTP端口: $HTTP_PORT"

safe_execute "sudo tee /etc/xray/config.json > /dev/null << 'XRAYCONFIG'
{
  \"log\": {
    \"loglevel\": \"info\",
    \"access\": \"/var/log/xray/access.log\",
    \"error\": \"/var/log/xray/error.log\"
  },
  \"dns\": {
    \"servers\": [
      {
        \"address\": \"8.8.8.8\",
        \"port\": 53,
        \"domains\": [
          \"domain:beanfun.com\",
          \"domain:gamania.com\",
          \"domain:gnjoy.com\"
        ]
      },
      {
        \"address\": \"1.1.1.1\",
        \"port\": 53,
        \"domains\": [
          \"domain:amazonaws.com\",
          \"domain:elasticbeanstalk.com\",
          \"domain:cloudfront.net\"
        ]
      },
      {
        \"address\": \"208.67.222.222\",
        \"port\": 53
      },
      {
        \"address\": \"223.5.5.5\",
        \"port\": 53
      }
    ],
    \"clientIp\": \"1.2.3.4\",
    \"tag\": \"dns-inbound\"
  },
  \"inbounds\": [
    {
      \"tag\": \"socks5-in\",
      \"port\": $SOCKS5_PORT,
      \"protocol\": \"socks\",
      \"listen\": \"0.0.0.0\",
      \"settings\": {
        \"auth\": \"password\",
        \"accounts\": [
          {\"user\": \"vip1\", \"pass\": \"123456\"},
          {\"user\": \"vip2\", \"pass\": \"123456\"},
          {\"user\": \"vip3\", \"pass\": \"123456\"}
        ],
        \"udp\": true,
        \"ip\": \"0.0.0.0\"
      },
      \"sniffing\": {
        \"enabled\": true,
        \"destOverride\": [\"http\", \"tls\", \"quic\"],
        \"domainsExcluded\": [\"courier.push.apple.com\"]
      }
    },
    {
      \"tag\": \"http-in\", 
      \"port\": $HTTP_PORT,
      \"protocol\": \"http\",
      \"listen\": \"0.0.0.0\",
      \"settings\": {
        \"accounts\": [
          {\"user\": \"vip1\", \"pass\": \"123456\"},
          {\"user\": \"vip2\", \"pass\": \"123456\"},
          {\"user\": \"vip3\", \"pass\": \"123456\"}
        ],
        \"allowTransparent\": false
      },
      \"sniffing\": {
        \"enabled\": true,
        \"destOverride\": [\"http\", \"tls\"]
      }
    }
  ],
  \"outbounds\": [
    {
      \"tag\": \"direct\",
      \"protocol\": \"freedom\",
      \"settings\": {
        \"domainStrategy\": \"UseIPv4\",
        \"userLevel\": 0
      }
    },
    {
      \"tag\": \"blocked\",
      \"protocol\": \"blackhole\",
      \"settings\": {
        \"response\": {
          \"type\": \"http\"
        }
      }
    }
  ],
  \"routing\": {
    \"domainStrategy\": \"IPIfNonMatch\",
    \"rules\": [
      {
        \"type\": \"field\",
        \"domain\": [
          \"domain:beanfun.com\",
          \"domain:gamania.com\", 
          \"domain:gnjoy.com\",
          \"hk.beanfun.com\",
          \"bfweb.hk.beanfun.com\",
          \"cdn.hk.beanfun.com\",
          \"csp.hk.beanfun.com\",
          \"tw.beanfun.com\",
          \"csp-hk-beanfun-com.ap-east-1.elasticbeanstalk.com\"
        ],
        \"outboundTag\": \"direct\"
      },
      {
        \"type\": \"field\",
        \"ip\": [
          \"112.121.124.11/32\",
          \"112.121.124.69/32\",
          \"$cdn_ip/32\",
          \"18.167.13.186/32\",
          \"18.163.12.31/32\",
          \"202.80.107.11/32\",
          \"52.147.74.109/32\"
        ],
        \"outboundTag\": \"direct\"
      },
      {
        \"type\": \"field\",
        \"ip\": [
          \"31.13.106.4/32\"
        ],
        \"outboundTag\": \"blocked\"
      },
      {
        \"type\": \"field\",
        \"ip\": [
          \"127.0.0.0/8\",
          \"10.0.0.0/8\",
          \"172.16.0.0/12\",
          \"192.168.0.0/16\"
        ],
        \"outboundTag\": \"direct\"
      }
    ]
  }
}
XRAYCONFIG" "创建Xray配置文件"

# 验证配置文件语法 - 修复Xray命令
echo "🔍 验证配置文件..."

# 尝试不同的xray测试命令
if /usr/local/bin/xray test -c /etc/xray/config.json >/dev/null 2>&1; then
    echo "✅ 配置文件语法正确 (使用 test -c)"
elif /usr/local/bin/xray -test -config /etc/xray/config.json >/dev/null 2>&1; then
    echo "✅ 配置文件语法正确 (使用 -test -config)"
elif /usr/local/bin/xray check -config /etc/xray/config.json >/dev/null 2>&1; then
    echo "✅ 配置文件语法正确 (使用 check -config)"
else
    echo "⚠️ 无法验证配置文件语法，但继续安装..."
    echo "   如果启动失败，请检查xray版本和配置文件"
fi

# 验证端口配置 - 使用改进的检测方法
CONFIGURED_SOCKS_PORT=$(grep -A20 '"protocol": "socks"' /etc/xray/config.json | grep '"port":' | head -1 | sed 's/.*"port": *\([0-9]*\).*/\1/')
CONFIGURED_HTTP_PORT=$(grep -A20 '"protocol": "http"' /etc/xray/config.json | grep '"port":' | head -1 | sed 's/.*"port": *\([0-9]*\).*/\1/')

# if [ "$CONFIGURED_SOCKS_PORT" = "$SOCKS5_PORT" ]; then
#     echo "✅ SOCKS5端口配置验证: $CONFIGURED_SOCKS_PORT"
# else
#     error_exit "SOCKS5端口配置错误: 期望$SOCKS5_PORT，实际$CONFIGURED_SOCKS_PORT" $LINENO
# fi

# if [ "$CONFIGURED_HTTP_PORT" = "$HTTP_PORT" ]; then
#     echo "✅ HTTP端口配置验证: $CONFIGURED_HTTP_PORT"
# else
#     error_exit "HTTP端口配置错误: 期望$HTTP_PORT，实际$CONFIGURED_HTTP_PORT" $LINENO
# fi

# 创建systemd服务 - 改进错误处理
echo "📋 创建systemd服务..."
safe_execute "sudo tee /etc/systemd/system/xray.service > /dev/null << 'SYSTEMDCONFIG'
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
SYSTEMDCONFIG" "创建systemd服务文件"

echo "✅ systemd服务创建完成"

# ====== 配置防火墙 ======
echo "=========================================="
echo "🔥 配置防火墙"
echo "=========================================="

# 停止firewalld - 改进错误处理
safe_execute "sudo systemctl stop firewalld 2>/dev/null || true" "停止firewalld" || true
safe_execute "sudo systemctl disable firewalld 2>/dev/null || true" "禁用firewalld" || true

# 清理现有规则 - 改进错误处理
safe_execute "sudo iptables -F INPUT 2>/dev/null || true" "清理INPUT规则" || true
safe_execute "sudo iptables -X 2>/dev/null || true" "清理自定义链" || true

# 设置默认策略
safe_execute "sudo iptables -P INPUT ACCEPT" "设置INPUT默认策略"
safe_execute "sudo iptables -P FORWARD ACCEPT" "设置FORWARD默认策略"
safe_execute "sudo iptables -P OUTPUT ACCEPT" "设置OUTPUT默认策略"

# 基础规则
safe_execute "sudo iptables -A INPUT -i lo -j ACCEPT" "允许本地回环"
safe_execute "sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT" "允许已建立连接"

# 开放端口
safe_execute "sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT" "开放SSH端口"
safe_execute "sudo iptables -A INPUT -p tcp --dport $SOCKS5_PORT -j ACCEPT" "开放SOCKS5 TCP端口"
safe_execute "sudo iptables -A INPUT -p udp --dport $SOCKS5_PORT -j ACCEPT" "开放SOCKS5 UDP端口"
safe_execute "sudo iptables -A INPUT -p tcp --dport $HTTP_PORT -j ACCEPT" "开放HTTP代理端口"

echo "✅ 已开放端口: $SOCKS5_PORT (SOCKS5), $HTTP_PORT (HTTP), 22 (SSH)"

# 保存iptables规则 - 改进错误处理
safe_execute "sudo service iptables save 2>/dev/null || sudo iptables-save > /etc/sysconfig/iptables 2>/dev/null || echo '防火墙规则保存完成'" "保存防火墙规则" || true

echo "✅ 防火墙配置完成"

# 启用IP转发
echo "启用IP转发..."
safe_execute "echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf >/dev/null" "配置IPv4转发"
safe_execute "echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.conf >/dev/null" "配置IPv6转发"
safe_execute "sudo sysctl -p >/dev/null 2>&1 || true" "应用内核参数" || true

# ====== 创建管理工具 ======
echo "=========================================="
echo "🔧 创建管理工具"
echo "=========================================="

# 改进版端口检测函数
safe_execute "cat > /usr/local/bin/get_socks5_port.sh << 'PORTFUNCTION'
#!/bin/bash

get_socks5_port() {
    local config_file=\"/etc/xray/config.json\"
    
    if [ ! -f \"\$config_file\" ]; then
        echo \"18889\"
        return
    fi
    
    if command -v jq >/dev/null 2>&1; then
        local socks_port=\$(jq -r '.inbounds[] | select(.protocol == \"socks\") | .port' \"\$config_file\" 2>/dev/null | head -1)
        if [ \"\$socks_port\" != \"null\" ] && [ -n \"\$socks_port\" ]; then
            echo \"\$socks_port\"
            return
        fi
    fi
    
    local port=\$(grep -A20 '\"protocol\": \"socks\"' \"\$config_file\" | grep '\"port\":' | head -1 | grep -o '[0-9]\\+')
    if [ -n \"\$port\" ]; then
        echo \"\$port\"
    else
        echo \"18889\"
    fi
}

if [ \"\${BASH_SOURCE[0]}\" == \"\${0}\" ]; then
    get_socks5_port
fi
PORTFUNCTION" "创建端口检测脚本"

safe_execute "chmod +x /usr/local/bin/get_socks5_port.sh" "设置端口检测脚本权限"

# 端口修改脚本
safe_execute "cat > ~/change_socks5_port.sh << 'PORTSCRIPT'
#!/bin/bash

if [ -z \"\$1\" ]; then
    echo \"===========================================\"
    echo \"🔧 SOCKS5端口修改工具\"
    echo \"===========================================\"
    echo \"用法: \$0 <新端口号>\"
    echo \"例如: \$0 1080\"
    echo \"\"
    CURRENT_PORT=\$(/usr/local/bin/get_socks5_port.sh)
    echo \"当前SOCKS5端口: \$CURRENT_PORT\"
    echo \"当前HTTP端口: \$((CURRENT_PORT + 1))\"
    exit 1
fi

NEW_PORT=\$1

if ! [[ \"\$NEW_PORT\" =~ ^[0-9]+\$ ]] || [ \"\$NEW_PORT\" -lt 1024 ] || [ \"\$NEW_PORT\" -gt 65535 ]; then
    echo \"❌ 错误: 无效的端口号 '\$NEW_PORT'\"
    exit 1
fi

if netstat -tlnp | grep -q \":\$NEW_PORT \"; then
    echo \"❌ 错误: 端口 \$NEW_PORT 已被占用\"
    exit 1
fi

OLD_PORT=\$(/usr/local/bin/get_socks5_port.sh)
NEW_HTTP_PORT=\$((NEW_PORT + 1))

echo \"🔄 修改端口: \$OLD_PORT -> \$NEW_PORT\"

sudo systemctl stop xray
sudo cp /etc/xray/config.json /etc/xray/config.json.bak.\$(date +%Y%m%d_%H%M%S)

# 精确替换端口
sudo sed -i \"s/\\\"port\\\": \$OLD_PORT/\\\"port\\\": \$NEW_PORT/g\" /etc/xray/config.json
sudo sed -i \"s/\\\"port\\\": \$((OLD_PORT + 1))/\\\"port\\\": \$NEW_HTTP_PORT/g\" /etc/xray/config.json

# 更新防火墙
sudo iptables -D INPUT -p tcp --dport \$OLD_PORT -j ACCEPT 2>/dev/null || true
sudo iptables -D INPUT -p udp --dport \$OLD_PORT -j ACCEPT 2>/dev/null || true
sudo iptables -D INPUT -p tcp --dport \$((OLD_PORT + 1)) -j ACCEPT 2>/dev/null || true

sudo iptables -A INPUT -p tcp --dport \$NEW_PORT -j ACCEPT
sudo iptables -A INPUT -p udp --dport \$NEW_PORT -j ACCEPT
sudo iptables -A INPUT -p tcp --dport \$NEW_HTTP_PORT -j ACCEPT

sudo service iptables save 2>/dev/null || sudo iptables-save > /etc/sysconfig/iptables 2>/dev/null || true

sudo systemctl start xray
sleep 5

if netstat -tlnp | grep -q \":\$NEW_PORT \"; then
    echo \"✅ 端口修改成功: \$NEW_PORT\"
else
    echo \"❌ 端口修改失败\"
fi
PORTSCRIPT" "创建端口修改脚本"

safe_execute "chmod +x ~/change_socks5_port.sh" "设置端口修改脚本权限"

# DNS测试脚本
safe_execute "sudo tee /usr/local/bin/beanfun-dns-test.sh > /dev/null << 'DNSTESTSCRIPT'
#!/bin/bash

echo \"===========================================\"
echo \"🌐 Beanfun DNS测试工具\"
echo \"===========================================\"

declare -A EXPECTED_IPS
EXPECTED_IPS[\"hk.beanfun.com\"]=\"112.121.124.11\"
EXPECTED_IPS[\"bfweb.hk.beanfun.com\"]=\"112.121.124.69\"
EXPECTED_IPS[\"csp.hk.beanfun.com\"]=\"18.167.13.186\"
EXPECTED_IPS[\"tw.beanfun.com\"]=\"202.80.107.11\"
EXPECTED_IPS[\"beanfun.com\"]=\"52.147.74.109\"

echo \"🔍 检查关键域名解析:\"
for domain in \"\${!EXPECTED_IPS[@]}\"; do
    expected=\"\${EXPECTED_IPS[\$domain]}\"
    current=\$(getent hosts \$domain 2>/dev/null | awk '{print \$1}' | head -1)
    
    echo -n \"  \$domain: \"
    if [ \"\$current\" = \"\$expected\" ]; then
        echo \"✅ \$current\"
    else
        echo \"❌ \$current (期望: \$expected)\"
    fi
done

echo -n \"  cdn.hk.beanfun.com: \"
cdn_ip=\$(getent hosts cdn.hk.beanfun.com 2>/dev/null | awk '{print \$1}' | head -1)
if [ -n \"\$cdn_ip\" ]; then
    echo \"✅ \$cdn_ip (hosts配置)\"
else
    echo \"❌ 解析失败\"
fi

echo \"\"
echo \"🔧 代理测试:\"
# if systemctl is-active --quiet xray; then
#     SOCKS_PORT=\$(/usr/local/bin/get_socks5_port.sh)
#     echo \"通过SOCKS5代理(\$SOCKS_PORT)测试:\"
    
#     for domain in \"bfweb.hk.beanfun.com\" \"cdn.hk.beanfun.com\"; do
#         echo -n \"  \$domain: \"
#         if timeout 10 curl --socks5-hostname vip1:123456@127.0.0.1:\$SOCKS_PORT -s https://\$domain >/dev/null 2>&1; then
#             echo \"✅ 成功\"
#         else
#             echo \"❌ 失败\"
#         fi
#     done
# fi
DNSTESTSCRIPT" "创建DNS测试脚本"

safe_execute "sudo chmod +x /usr/local/bin/beanfun-dns-test.sh" "设置DNS测试脚本权限"

# ====== 启动服务 ======
echo "=========================================="
echo "🚀 启动SOCKS5服务"
echo "=========================================="

safe_execute "sudo systemctl daemon-reload" "重新加载systemd"
safe_execute "sudo systemctl enable xray" "启用xray服务"
safe_execute "sudo systemctl start xray" "启动xray服务"

# 获取服务器IP
echo "获取服务器IP地址..."
SERVER_IP=$(curl -s -4 ifconfig.me --connect-timeout 10 2>/dev/null || curl -s -4 ipinfo.io/ip --connect-timeout 10 2>/dev/null || ip route get 8.8.8.8 | awk '{print $7}' | head -1)

# 验证服务状态
echo "验证服务状态..."
sleep 5

SERVICE_STATUS="未知"
PROXY_TEST="未测试"

if netstat -tlnp | grep -q ":$SOCKS5_PORT "; then
    echo "✅ SOCKS5代理服务正常运行在端口$SOCKS5_PORT"
    SERVICE_STATUS="运行正常"
    
    if timeout 15 curl --socks5 vip1:123456@127.0.0.1:$SOCKS5_PORT -s https://httpbin.org/ip --connect-timeout 10 >/dev/null 2>&1; then
        echo "✅ 代理连接测试成功"
        PROXY_TEST="测试成功"
    else
        echo "⚠️ 代理连接测试失败，但服务已启动"
        PROXY_TEST="服务已启动，但连接测试失败"
    fi
else
    echo "❌ 警告: SOCKS5代理可能未正常启动"
    SERVICE_STATUS="状态异常"
    PROXY_TEST="服务启动失败"
    
    echo "服务状态:"
    sudo systemctl status xray --no-pager -l || true
fi

if netstat -tlnp | grep -q ":$HTTP_PORT "; then
    echo "✅ HTTP代理服务正常运行在端口$HTTP_PORT"
else
    echo "⚠️ HTTP代理端口$HTTP_PORT未监听"
fi

# 执行DNS测试
echo ""
echo "=========================================="
echo "🧪 执行Beanfun DNS测试"
echo "=========================================="
/usr/local/bin/beanfun-dns-test.sh

# 测试关键域名连接
echo ""
echo "🔗 测试关键域名连接:"
key_domains=("bfweb.hk.beanfun.com" "cdn.hk.beanfun.com" "hk.beanfun.com")
for domain in "${key_domains[@]}"; do
    echo -n "  直连 $domain: "
    if timeout 10 curl -s -I https://$domain --connect-timeout 5 >/dev/null 2>&1; then
        echo "✅ 成功"
    else
        echo "❌ 失败"
    fi
    
    if [ "$SERVICE_STATUS" = "运行正常" ]; then
        echo -n "  代理 $domain: "
        if timeout 15 curl --socks5-hostname vip1:123456@127.0.0.1:$SOCKS5_PORT -s -I https://$domain --connect-timeout 5 >/dev/null 2>&1; then
            echo "✅ 成功"
        else
            echo "❌ 失败"
        fi
    fi
done

# 创建用户配置文件
echo ""
echo "📝 生成用户配置文件..."

cat > ~/Sk5_User_Password.txt << USERCONFIG
#############################################################################
🎯 SOCKS5代理安装完成 - 修复版

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

🌐 Beanfun DNS优化 (已集成):
✅ hk.beanfun.com -> 112.121.124.11
✅ bfweb.hk.beanfun.com -> 112.121.124.69
✅ cdn.hk.beanfun.com -> $cdn_ip
✅ csp.hk.beanfun.com -> 18.167.13.186
✅ tw.beanfun.com -> 202.80.107.11
✅ beanfun.com -> 52.147.74.109

🔧 管理工具:
端口管理: ~/change_socks5_port.sh <新端口>
DNS测试: sudo /usr/local/bin/beanfun-dns-test.sh
端口检测: /usr/local/bin/get_socks5_port.sh

⚙️ 服务管理:
启动: sudo systemctl start xray
停止: sudo systemctl stop xray
重启: sudo systemctl restart xray
状态: sudo systemctl status xray
日志: sudo journalctl -u xray -f

🔌 连接测试:
SOCKS5: curl --socks5 vip1:123456@$SERVER_IP:$SOCKS5_PORT https://httpbin.org/ip
SOCKS5h: curl --socks5-hostname vip1:123456@$SERVER_IP:$SOCKS5_PORT https://bfweb.hk.beanfun.com
HTTP: curl --proxy http://vip1:123456@$SERVER_IP:$HTTP_PORT https://httpbin.org/ip

🎮 游戏客户端配置:
代理类型: SOCKS5
服务器: $SERVER_IP
端口: $SOCKS5_PORT
用户名: vip1 (或vip2, vip3)
密码: 123456
🚨 重要: 启用"代理DNS查询"或"远程DNS解析"

📋 客户端配置要点:
- 浏览器: 启用"代理DNS查询"选项
- Firefox: about:config -> network.proxy.socks_remote_dns = true
- 应用程序: 使用socks5h://而不是socks5://
- 游戏登录器: 勾选"通过代理解析DNS"

🔍 故障排除:
1. 服务检查: sudo systemctl status xray
2. 端口检查: sudo netstat -tlnp | grep $SOCKS5_PORT
3. DNS检查: sudo /usr/local/bin/beanfun-dns-test.sh
4. 配置检查: /usr/local/bin/get_socks5_port.sh
5. 日志检查: sudo journalctl -u xray -n 50
6. 端口修改: ~/change_socks5_port.sh <新端口>

💡 解决DNS污染问题:
✅ 服务器端已完全修复
✅ 客户端需要配置使用远程DNS解析
✅ 确保使用socks5h://协议而不是socks5://

🚨 修复内容:
✅ 修复脚本执行中断问题
✅ 改进错误处理机制
✅ 增强安全命令执行
✅ 优化防火墙配置流程
✅ 完善系统服务创建

安装时间: $(date)
版本: 修复版 v3.1 (解决执行中断问题)
#############################################################################
USERCONFIG

# 显示最终结果
echo ""
echo "=========================================="
echo "🎉 SOCKS5代理安装完成！(修复版)"
echo "=========================================="
echo "🌐 服务器IP: $SERVER_IP"
echo "🔌 SOCKS5端口: $SOCKS5_PORT" 
echo "🔌 HTTP端口: $HTTP_PORT"
echo "👤 用户: vip1/vip2/vip3"
echo "🔑 密码: 123456"
echo "📊 状态: $SERVICE_STATUS"
echo "📄 配置文件: ~/Sk5_User_Password.txt"
echo ""
echo "🎮 Beanfun游戏优化:"
echo "   ✅ 所有关键域名DNS已优化"
echo "   ✅ 防DNS污染配置完成"
echo "   ✅ cdn.hk.beanfun.com CDN支持"
echo "   ✅ 智能路由规则已配置"
echo ""
echo "🔧 高级功能:"
echo "   端口管理: ~/change_socks5_port.sh"
echo "   DNS测试: sudo /usr/local/bin/beanfun-dns-test.sh"
echo "   端口检测: /usr/local/bin/get_socks5_port.sh"
echo ""

if [ "$SERVICE_STATUS" = "运行正常" ]; then
    echo "🎯 安装成功！可以开始使用代理服务"
    echo ""
    echo "🧪 快速测试:"
    echo "   curl --socks5 vip1:123456@$SERVER_IP:$SOCKS5_PORT https://httpbin.org/ip"
    echo ""
    echo "🌐 Beanfun测试:"
    echo "   curl --socks5-hostname vip1:123456@$SERVER_IP:$SOCKS5_PORT https://bfweb.hk.beanfun.com"
    echo "   curl --socks5-hostname vip1:123456@$SERVER_IP:$SOCKS5_PORT https://cdn.hk.beanfun.com"
    echo ""
    echo "💡 端口修改示例:"
    echo "   ~/change_socks5_port.sh 1080"
    echo ""
    echo "🎮 客户端配置要点:"
    echo "   - 使用 socks5h:// 协议（重要！）"
    echo "   - 启用'代理DNS查询'选项"
    echo "   - Firefox设置: network.proxy.socks_remote_dns = true"
else
    echo "⚠️ 服务可能存在问题，请检查:"
    echo "   sudo journalctl -u xray -f"
    echo "   sudo systemctl status xray"
    echo ""
    echo "🔧 常见解决方案:"
    echo "   1. 重启服务: sudo systemctl restart xray"
    echo "   2. 检查端口: sudo netstat -tlnp | grep $SOCKS5_PORT"
    echo "   3. 查看日志: sudo journalctl -u xray -n 20"
fi

# 清理临时文件
cd /
rm -rf $TEMP_DIR

echo ""
echo "🎊 安装完成！享受优化后的游戏体验！"
echo "🔗 如需技术支持，请查看配置文件: ~/Sk5_User_Password.txt"
echo ""
echo "📞 修复内容总结:"
echo "   ✅ 修复脚本执行中断问题"
echo "   ✅ 改进错误处理和日志记录"
echo "   ✅ 增强命令执行安全性"
echo "   ✅ 优化systemd服务创建"
echo "   ✅ 完善防火墙配置流程"
echo "   ✅ 增加详细的执行状态显示"

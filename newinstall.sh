#!/bin/bash

# 正确的单进程多IP SOCKS5代理安装脚本
# 基于成功案例的TOML配置格式
# 单进程，每个IP使用相同端口，不同用户
# 使用方法:   curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/newinstall.sh | bash 

set -e

echo "=========================================="
echo "🚀 正确版单进程多IP SOCKS5安装"
echo "🌐 基于成功案例的TOML配置"
echo "🔌 每IP相同端口18889，不同用户"
echo "👥 用户: vip1, vip2, vip3 密码: 123456"
echo "=========================================="

# 检查root权限
if [[ $EUID -ne 0 ]]; then
   echo "❌ 需要root权限运行"
   exit 1
fi

# 简化的IP获取函数
get_ip() {
    local interface=$1
    ifconfig "$interface" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1 | tr -d ' \n\r\t'
}

echo "🔍 检测网卡配置..."
eth0_ip=$(get_ip "eth0")
eth1_ip=$(get_ip "eth1")
eth1_1_ip=$(get_ip "eth1:1")

# 配置IP和用户映射
declare -A CONFIG
if [[ -n "$eth0_ip" ]]; then
    CONFIG["eth0"]="$eth0_ip:vip1"
    echo "✅ eth0: $eth0_ip -> 用户vip1"
fi
if [[ -n "$eth1_ip" ]]; then
    CONFIG["eth1"]="$eth1_ip:vip2"
    echo "✅ eth1: $eth1_ip -> 用户vip2"
fi
if [[ -n "$eth1_1_ip" ]] && [[ "$eth1_1_ip" != "$eth1_ip" ]]; then
    CONFIG["eth1:1"]="$eth1_1_ip:vip3"
    echo "✅ eth1:1: $eth1_1_ip -> 用户vip3"
fi

if [[ ${#CONFIG[@]} -lt 2 ]]; then
    echo "❌ 检测到的IP少于2个，退出"
    exit 1
fi

# 停止现有服务
echo "🛑 停止现有服务..."
systemctl stop xray 2>/dev/null || true
systemctl stop xray-multi 2>/dev/null || true
pkill -f xray 2>/dev/null || true
sleep 2

# 安装依赖
echo "📦 安装必要软件..."
yum -y install wget unzip bind-utils net-tools >/dev/null 2>&1

# ====== DNS优化配置 ======
echo "=========================================="
echo "🌐 配置DNS优化"
echo "=========================================="

# 备份DNS配置
cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

# 创建DNS配置
cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 223.5.5.5
options timeout:2
options attempts:3
options rotate
EOF

# hosts文件优化
cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d_%H%M%S)
sed -i '/beanfun/d' /etc/hosts
sed -i '/31\.13\.106\.4/d' /etc/hosts

cdn_ip=$(dig +short cdn.hk.beanfun.com @8.8.8.8 2>/dev/null | head -1)
if [[ ! "$cdn_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    cdn_ip="112.121.124.69"
fi

cat >> /etc/hosts << EOF

# Beanfun优化 $(date)
112.121.124.11 hk.beanfun.com
112.121.124.69 bfweb.hk.beanfun.com
$cdn_ip cdn.hk.beanfun.com
18.167.13.186 csp.hk.beanfun.com
202.80.107.11 tw.beanfun.com
52.147.74.109 beanfun.com
127.0.0.1 31.13.106.4
EOF

echo "✅ DNS优化完成"

# ====== 下载安装Xray ======
echo "📥 下载和安装Xray..."

cd /tmp
rm -f xray.zip xray

if ! wget -q -O xray.zip "https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-64.zip" --timeout=30; then
    if ! wget -q -O xray.zip "https://vip.123pan.cn/1816473155/%E6%8F%92%E4%BB%B6%E6%B3%A8%E5%86%8CIP/xray" --timeout=30; then
        echo "❌ Xray下载失败"
        exit 1
    fi
fi

unzip -q -o xray.zip
if [ ! -f "xray" ]; then
    echo "❌ Xray解压失败"
    exit 1
fi

mv xray /usr/local/bin/
chmod +x /usr/local/bin/xray
rm -f xray.zip

echo "✅ Xray安装成功"

# 创建目录
mkdir -p /etc/xray

# ====== 创建正确的TOML配置 ======
echo "=========================================="
echo "⚙️ 创建单进程多IP TOML配置"
echo "=========================================="

# 获取外网IP用于注释
SERVER_IP=$(curl -s -4 ifconfig.me --timeout=10 2>/dev/null || echo "未知")

# 生成TOML配置文件
cat > /etc/xray/serve.toml << TOMLEOF
# 单进程多IP SOCKS5配置 - 基于成功案例
# 服务器外网IP: $SERVER_IP
# 生成时间: $(date)

TOMLEOF

# 为每个IP创建配置块
tag_counter=1
for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip user <<< "${CONFIG[$interface]}"
    
    echo "✅ 配置: $interface ($ip) -> 用户$user 端口18889"
    
    cat >> /etc/xray/serve.toml << TOMLEOF

[[inbounds]] # $interface - $ip
listen = "$ip"
port = 18889
protocol = "socks"
tag = "$tag_counter"

[inbounds.settings]
auth = "password"
udp = true
ip = "$ip"

[[inbounds.settings.accounts]]
user = "$user"
pass = "123456"
Waiwangip = "$SERVER_IP"

[[routing.rules]]
type = "field"
inboundTag = "$tag_counter"
outboundTag = "$tag_counter"

[[outbounds]]
sendThrough = "$ip"
protocol = "freedom"
tag = "$tag_counter"

TOMLEOF

    ((tag_counter++))
done

echo "✅ TOML配置文件生成完成"

# ====== 创建systemd服务 ======
echo "📋 创建systemd服务..."

cat > /etc/systemd/system/xray.service << 'SERVICEEOF'
[Unit]
Description=The Xray Proxy Serve
After=network-online.target

[Service]
ExecStart=/usr/local/bin/xray -c /etc/xray/serve.toml
ExecStop=/bin/kill -s QUIT $MAINPID
Restart=always
RestartSec=15s
User=root

[Install]
WantedBy=multi-user.target
SERVICEEOF

# ====== 配置防火墙 (简化版) ======
echo "🔥 配置防火墙..."
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true

# 使用简单的默认接受策略 (学习别人的方式)
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT  
iptables -P OUTPUT ACCEPT
iptables -F

# 只保留基本规则
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

echo "✅ 防火墙配置完成 (使用默认ACCEPT策略)"

# ====== 启动服务 ======
echo "=========================================="
echo "🚀 启动单进程SOCKS5服务"
echo "=========================================="

systemctl daemon-reload
systemctl enable xray

echo "启动服务..."
systemctl start xray

# 等待服务启动
sleep 5

if systemctl is-active --quiet xray; then
    echo "✅ 服务启动成功"
else
    echo "❌ 服务启动失败"
    echo "查看日志: journalctl -u xray -n 20"
    exit 1
fi

# 检查端口监听
echo ""
echo "🔍 检查端口监听状态..."
listening_count=0

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip user <<< "${CONFIG[$interface]}"
    
    if netstat -tlnp 2>/dev/null | grep -q "$ip:18889"; then
        echo "✅ $interface ($ip:18889) 正常监听"
        ((listening_count++))
    else
        echo "❌ $interface ($ip:18889) 未监听"
    fi
done

# 检查进程
echo ""
echo "📊 进程状态:"
xray_processes=$(ps aux | grep -c "[x]ray.*serve.toml")
echo "Xray进程数: $xray_processes (应该是1个)"

if [ $xray_processes -eq 1 ]; then
    echo "✅ 单进程运行正常"
    ps aux | grep "[x]ray.*serve.toml"
else
    echo "⚠️ 进程数异常"
fi

# 生成使用说明
echo ""
echo "📝 生成配置文件..."
cat > ~/Single_Process_SOCKS5_Config.txt << CONFIGEOF
#############################################################################
🎯 正确版单进程多IP SOCKS5代理配置

📡 服务器信息:
外网IP: $SERVER_IP
内网IP数量: ${#CONFIG[@]}
监听端口: 18889 (所有IP相同端口)
进程数: 1 (单进程管理所有连接)

👥 用户账号 (每个IP一个用户):
CONFIGEOF

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip user <<< "${CONFIG[$interface]}"
    
    cat >> ~/Single_Process_SOCKS5_Config.txt << CONFIGEOF2
📌 $interface ($ip):
   代理地址: $SERVER_IP:18889
   用户名: $user
   密码: 123456
   测试: curl --socks5 $user:123456@$SERVER_IP:18889 https://httpbin.org/ip
   
CONFIGEOF2
done

cat >> ~/Single_Process_SOCKS5_Config.txt << CONFIGEOF3

🌐 Beanfun DNS优化 (已集成):
✅ 所有游戏域名已优化，防DNS污染

⚙️ 服务管理:
启动: systemctl start xray
停止: systemctl stop xray
重启: systemctl restart xray
状态: systemctl status xray
配置: /etc/xray/serve.toml

🎮 客户端配置:
- 代理类型: SOCKS5
- 服务器: $SERVER_IP
- 端口: 18889
- 用户名: vip1/vip2/vip3 (根据需要选择)
- 密码: 123456
- 启用: 代理DNS查询

💡 使用建议:
1. 不同机器使用不同用户 (vip1, vip2, vip3)
2. 所有用户使用相同端口 18889
3. 单进程管理，连接稳定，不会锁死
4. 基于成功案例配置，经过验证

🧪 连接测试:
curl --socks5 vip1:123456@$SERVER_IP:18889 https://httpbin.org/ip
curl --socks5 vip2:123456@$SERVER_IP:18889 https://httpbin.org/ip
curl --socks5 vip3:123456@$SERVER_IP:18889 https://httpbin.org/ip

🌐 Beanfun测试:
curl --socks5-hostname vip1:123456@$SERVER_IP:18889 https://bfweb.hk.beanfun.com

安装时间: $(date)
版本: 正确版 v7.0 (基于成功案例的单进程TOML配置)
#############################################################################
CONFIGEOF3

# 创建管理工具
cat > /usr/local/bin/xray-status.sh << 'STATUSEOF'
#!/bin/bash

echo "🔍 SOCKS5服务状态检查"
echo "======================"

echo "📊 基本信息:"
echo "  配置文件: /etc/xray/serve.toml"
echo "  服务状态: $(systemctl is-active xray)"
echo "  进程数量: $(ps aux | grep -c '[x]ray.*serve.toml')"

echo ""
echo "🔌 端口监听:"
netstat -tlnp | grep xray | while read line; do
    echo "  $line"
done

echo ""
echo "💾 配置概览:"
grep -E "(listen|user|port)" /etc/xray/serve.toml | head -10

echo ""
echo "🧪 测试命令:"
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "你的服务器IP")
echo "  curl --socks5 vip1:123456@$SERVER_IP:18889 https://httpbin.org/ip"
echo "  curl --socks5 vip2:123456@$SERVER_IP:18889 https://httpbin.org/ip"
echo "  curl --socks5 vip3:123456@$SERVER_IP:18889 https://httpbin.org/ip"
STATUSEOF

chmod +x /usr/local/bin/xray-status.sh

# 最终报告
echo ""
echo "=========================================="
echo "🎉 正确版单进程SOCKS5安装完成！"
echo "=========================================="
echo "🌐 外网IP: $SERVER_IP"
echo "🔌 监听端口: 18889"
echo "👥 用户数量: ${#CONFIG[@]}"
echo "📊 工作端口: $listening_count/${#CONFIG[@]}"
echo ""

for interface in "${!CONFIG[@]}"; do
    IFS=':' read -r ip user <<< "${CONFIG[$interface]}"
    
    if netstat -tlnp 2>/dev/null | grep -q "$ip:18889"; then
        status="✅ 正常"
    else
        status="❌ 异常"
    fi
    
    echo "📌 $interface ($ip): 用户$user $status"
done

echo ""
echo "📄 详细配置: ~/Single_Process_SOCKS5_Config.txt"
echo "🔧 状态检查: /usr/local/bin/xray-status.sh"
echo ""

if [ $listening_count -eq ${#CONFIG[@]} ]; then
    echo "🎯 安装成功！单进程管理，不会出现端口锁死问题！"
    echo ""
    echo "🧪 快速测试:"
    for interface in "${!CONFIG[@]}"; do
        IFS=':' read -r ip user <<< "${CONFIG[$interface]}"
        echo "   curl --socks5 $user:123456@$SERVER_IP:18889 https://httpbin.org/ip"
        break
    done
else
    echo "⚠️ 部分端口异常，请检查:"
    echo "   systemctl status xray"
    echo "   /usr/local/bin/xray-status.sh"
fi

# 清理
cd /
rm -rf /tmp/xray*

echo ""
echo "🎊 现在使用和别人一样的配置方式！"
echo "💡 单进程，多IP，相同端口，不同用户，绝对不会锁死！"
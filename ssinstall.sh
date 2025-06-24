#!/bin/bash

# Shadowsocks多内网IP配置脚本
# 固定端口11000/12000/13000，密码qwe123

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo "错误：需要root权限运行此脚本"
    exit 1
fi

# 检查shadowsocks是否安装
if [[ ! -f /etc/init.d/shadowsocks ]]; then
    echo "错误：shadowsocks未安装，请先安装shadowsocks-go"
    exit 1
fi

echo "=== Shadowsocks多内网IP配置脚本 ==="
echo "固定端口：11000/12000/13000"
echo "统一密码：qwe123"
echo ""

# 使用你提供的命令检测所有内网IP
echo "正在检测网卡IP..."
INTERNAL_IPS=($(ip -br addr show | grep -v "127.0.0.1" | awk '{for(i=3;i<=NF;i++) print $i}' | cut -d'/' -f1 | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'))

if [[ ${#INTERNAL_IPS[@]} -eq 0 ]]; then
    echo "错误：未检测到内网IP"
    exit 1
fi

echo "检测到 ${#INTERNAL_IPS[@]} 个内网IP："
for i in "${!INTERNAL_IPS[@]}"; do
    echo "  IP$((i+1)): ${INTERNAL_IPS[i]}"
done

# 固定配置
PORTS=(11000 12000 13000)
PASSWORD="qwe123"

echo ""
echo "=== 配置信息 ==="
echo "密码: $PASSWORD"
echo "加密: aes-256-cfb"
echo "监听模式: 0.0.0.0 (所有接口)"
echo ""

# 显示端口配置
MAX_COUNT=$((${#PORTS[@]} < ${#INTERNAL_IPS[@]} ? ${#PORTS[@]} : ${#INTERNAL_IPS[@]}))

for ((i=0; i<MAX_COUNT; i++)); do
    echo "端口${PORTS[i]} -> 可通过 ${INTERNAL_IPS[i]} 访问"
done

# 如果IP数量超过端口数量，显示剩余IP
if [[ ${#INTERNAL_IPS[@]} -gt ${#PORTS[@]} ]]; then
    echo ""
    echo "注意：以下IP也可以通过所有端口访问："
    for ((i=${#PORTS[@]}; i<${#INTERNAL_IPS[@]}; i++)); do
        echo "  ${INTERNAL_IPS[i]}"
    done
fi

echo ""
read -p "确认配置并继续？ [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# 备份原配置
if [[ -f /etc/shadowsocks/config.json ]]; then
    cp /etc/shadowsocks/config.json "/etc/shadowsocks/config.json.backup.$(date +%Y%m%d_%H%M%S)"
    echo "原配置已备份"
fi

mkdir -p /etc/shadowsocks

# 生成端口密码配置
PORT_CONFIG=""
for ((i=0; i<${#PORTS[@]}; i++)); do
    if [[ -n "$PORT_CONFIG" ]]; then
        PORT_CONFIG+=","
    fi
    PORT_CONFIG+="\n    \"${PORTS[i]}\":\"$PASSWORD\""
done

# 创建配置文件 - 监听所有接口
cat > /etc/shadowsocks/config.json << EOF
{
    "server": "0.0.0.0",
    "port_password": {$PORT_CONFIG
    },
    "method": "aes-256-cfb",
    "timeout": 600
}
EOF

echo "配置文件已创建"

# 配置防火墙
echo "配置防火墙..."
for port in "${PORTS[@]}"; do
    # iptables
    if command -v iptables >/dev/null 2>&1; then
        iptables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport $port -j ACCEPT
        iptables -C INPUT -p udp --dport $port -j ACCEPT 2>/dev/null || iptables -I INPUT -p udp --dport $port -j ACCEPT
    fi
    
    # firewalld
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port=$port/tcp >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port=$port/udp >/dev/null 2>&1 || true
    fi
    
    # ufw
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $port >/dev/null 2>&1 || true
    fi
done

# 重载firewalld
if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
    firewall-cmd --reload >/dev/null 2>&1 || true
fi

echo "防火墙配置完成"

# 保存连接信息
cat > /etc/shadowsocks/connection_info.txt << EOF
Shadowsocks连接信息 - $(date)
密码: $PASSWORD
加密: aes-256-cfb
监听: 0.0.0.0 (所有接口)

可用连接地址：
EOF

for ip in "${INTERNAL_IPS[@]}"; do
    for port in "${PORTS[@]}"; do
        echo "$ip:$port" >> /etc/shadowsocks/connection_info.txt
    done
done

# 检查配置文件
echo "检查配置文件..."
if command -v python >/dev/null 2>&1; then
    if ! python -m json.tool /etc/shadowsocks/config.json >/dev/null 2>&1; then
        echo "配置文件格式错误："
        cat /etc/shadowsocks/config.json
        exit 1
    fi
fi

# 重启shadowsocks
echo "重启shadowsocks服务..."
/etc/init.d/shadowsocks stop >/dev/null 2>&1 || true
sleep 3

if /etc/init.d/shadowsocks start; then
    echo "shadowsocks启动成功！"
    sleep 2
    /etc/init.d/shadowsocks status
else
    echo "shadowsocks启动失败，配置文件内容："
    cat /etc/shadowsocks/config.json
    exit 1
fi

# 显示结果
echo ""
echo "=== 配置完成 ==="
echo ""
echo "检测到的内网IP："
for ip in "${INTERNAL_IPS[@]}"; do
    echo "  $ip"
done

echo ""
echo "开放的端口："
for port in "${PORTS[@]}"; do
    echo "  $port"
done

echo ""
echo "所有可用连接组合："
for ip in "${INTERNAL_IPS[@]}"; do
    for port in "${PORTS[@]}"; do
        echo "  $ip:$port (密码: $PASSWORD)"
    done
done

echo ""
echo "配置文件："
echo "  主配置: /etc/shadowsocks/config.json"
echo "  连接信息: /etc/shadowsocks/connection_info.txt"

echo ""
echo "管理命令："
echo "  启动: /etc/init.d/shadowsocks start"
echo "  停止: /etc/init.d/shadowsocks stop"
echo "  重启: /etc/init.d/shadowsocks restart"
echo "  状态: /etc/init.d/shadowsocks status"

echo ""
echo "多内网IP shadowsocks配置完成！"
echo "现在所有内网IP都可以通过端口11000/12000/13000提供shadowsocks服务"

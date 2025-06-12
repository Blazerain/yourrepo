#!/bin/bash

# 多公网IP型服务器路由配置脚本
# 用途：配置每个网卡的入出流量都走自己的网卡
# 适用于阿里云多公网IP型规格族
# curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/setup_routes.sh | sudo bash
set -e

echo "=========================================="
echo "多公网IP路由配置脚本"
echo "=========================================="

# 检查是否为root用户
if [[ $EUID -ne 0 ]]; then
   echo "错误：此脚本需要root权限运行"
   echo "请使用: sudo $0"
   exit 1
fi

# 获取网关地址（假设在同一网段）
get_gateway() {
    local ip=$1
    local gateway
    
    # 从路由表获取默认网关
    gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    
    if [[ -z "$gateway" ]]; then
        # 如果没有找到，根据IP计算网关（通常是网段的最后一个地址减2）
        local subnet=$(echo $ip | cut -d'.' -f1-3)
        gateway="${subnet}.253"
    fi
    
    echo $gateway
}

# 检测当前网卡配置
echo "正在检测当前网卡配置..."

# 更可靠的IP获取方法
get_interface_ip() {
    local interface=$1
    local ip
    
    # 先尝试ifconfig（对虚拟接口更准确）
    if command -v ifconfig >/dev/null 2>&1; then
        ip=$(ifconfig "$interface" 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
    fi
    
    # 如果ifconfig失败，尝试ip命令
    if [[ -z "$ip" ]]; then
        ip=$(ip addr show "$interface" 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -1)
    fi
    
    # 清理可能的空格和换行符
    ip=$(echo "$ip" | tr -d ' \n\r\t')
    
    echo "$ip"
}

eth0_ip=$(get_interface_ip "eth0")
eth1_ip=$(get_interface_ip "eth1")  
eth1_1_ip=$(get_interface_ip "eth1:1")

echo "检测到的网卡配置："
[[ -n "$eth0_ip" ]] && echo "  eth0: $eth0_ip"
[[ -n "$eth1_ip" ]] && echo "  eth1: $eth1_ip"
[[ -n "$eth1_1_ip" ]] && echo "  eth1:1: $eth1_1_ip"

# 调试信息
echo ""
echo "调试信息："
echo "  eth0_ip变量: '$eth0_ip'"
echo "  eth1_ip变量: '$eth1_ip'"
echo "  eth1_1_ip变量: '$eth1_1_ip'"
echo ""

# 检查IP地址是否有效
check_ip_valid() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# 获取网关
gateway=$(get_gateway "$eth0_ip")
echo "使用网关: $gateway"

# 备份当前路由配置
echo "正在备份当前路由配置..."
ip route show > /tmp/route_backup_$(date +%Y%m%d_%H%M%S).txt
ip rule show > /tmp/rule_backup_$(date +%Y%m%d_%H%M%S).txt

# 清理可能存在的旧配置
echo "正在清理旧的路由配置..."
[[ -n "$eth1_ip" ]] && check_ip_valid "$eth1_ip" && ip rule del from $eth1_ip lookup 1001 2>/dev/null || true
[[ -n "$eth1_1_ip" ]] && check_ip_valid "$eth1_1_ip" && ip rule del from $eth1_1_ip lookup 1002 2>/dev/null || true
ip route flush table 1001 2>/dev/null || true
ip route flush table 1002 2>/dev/null || true

# 配置eth1路由
if [[ -n "$eth1_ip" ]] && check_ip_valid "$eth1_ip"; then
    echo "正在配置 eth1 ($eth1_ip) 路由..."
    ip route add default via $gateway dev eth1 table 1001
    ip rule add from $eth1_ip lookup 1001
    echo "  ✓ eth1 路由配置完成"
else
    echo "  ⚠ 跳过eth1配置：IP地址无效或为空"
fi

# 配置eth1:1路由
if [[ -n "$eth1_1_ip" ]] && check_ip_valid "$eth1_1_ip" && [[ "$eth1_1_ip" != "$eth1_ip" ]]; then
    echo "正在配置 eth1:1 ($eth1_1_ip) 路由..."
    ip route add default via $gateway dev eth1 table 1002
    ip rule add from $eth1_1_ip lookup 1002
    echo "  ✓ eth1:1 路由配置完成"
else
    echo "  ⚠ 跳过eth1:1配置：IP地址无效、为空或与eth1相同"
fi

# 创建开机自动加载脚本
echo "正在配置开机自动加载..."
cat > /etc/rc.local << EOF
#!/bin/bash
# 多公网IP路由配置 - 开机自动加载
# 自动生成于: $(date)

# 等待网络初始化
sleep 10

# 获取当前IP（开机时重新获取，防止IP变化）
eth1_ip=\$(ip addr show eth1 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d'/' -f1 | head -1)
eth1_1_ip=\$(ifconfig eth1:1 2>/dev/null | grep 'inet ' | awk '{print \$2}')

# 清理可能存在的旧配置
[[ -n "\$eth1_ip" ]] && ip rule del from \$eth1_ip lookup 1001 2>/dev/null || true
[[ -n "\$eth1_1_ip" ]] && ip rule del from \$eth1_1_ip lookup 1002 2>/dev/null || true
ip route flush table 1001 2>/dev/null || true
ip route flush table 1002 2>/dev/null || true

# 配置eth1路由
if [[ -n "\$eth1_ip" ]]; then
    ip route add default via $gateway dev eth1 table 1001
    ip rule add from \$eth1_ip lookup 1001
fi

# 配置eth1:1路由  
if [[ -n "\$eth1_1_ip" ]] && [[ "\$eth1_1_ip" != "\$eth1_ip" ]]; then
    ip route add default via $gateway dev eth1 table 1002
    ip rule add from \$eth1_1_ip lookup 1002
fi

exit 0
EOF

chmod +x /etc/rc.local

# 启用rc.local服务（针对systemd系统）
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable rc-local 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo "配置完成！"
echo "=========================================="
echo ""
echo "当前路由规则："
ip rule show | grep -E "(1001|1002)" || echo "  无自定义路由规则"
echo ""
echo "路由表状态："
echo "  表1001 (eth1):"
ip route show table 1001 | sed 's/^/    /' || echo "    未配置"
echo "  表1002 (eth1:1):"  
ip route show table 1002 | sed 's/^/    /' || echo "    未配置"
echo ""

# 测试连通性
echo "正在测试网络连通性..."
test_connectivity() {
    local ip=$1
    local name=$2
    echo -n "  测试 $name ($ip): "
    if ping -c 1 -W 3 -I $ip 8.8.8.8 >/dev/null 2>&1; then
        echo "✓ 通过"
    else
        echo "✗ 失败"
    fi
}

[[ -n "$eth0_ip" ]] && test_connectivity "$eth0_ip" "eth0"
[[ -n "$eth1_ip" ]] && test_connectivity "$eth1_ip" "eth1" 
[[ -n "$eth1_1_ip" ]] && test_connectivity "$eth1_1_ip" "eth1:1"

echo ""
echo "配置说明："
echo "  - eth0: 入出流量都走 eth0（默认路由）"
echo "  - eth1: 入出流量都走 eth1（使用路由表1001）"
echo "  - eth1:1: 入出流量都走 eth1（使用路由表1002）"
echo "  - 配置已写入 /etc/rc.local，重启后自动生效"
echo ""
echo "如需恢复默认配置，请运行："
[[ -n "$eth1_ip" ]] && check_ip_valid "$eth1_ip" && echo "  ip rule del from $eth1_ip lookup 1001"
[[ -n "$eth1_1_ip" ]] && check_ip_valid "$eth1_1_ip" && echo "  ip rule del from $eth1_1_ip lookup 1002"
echo ""

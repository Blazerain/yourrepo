#!/bin/bash

# 阿里云多公网IP配置脚本
# 适用于CentOS 7/8
# 功能：自动配置额外的公网IP地址到独立网卡
# 使用方法：curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/aliyun.sh | bash

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "错误：此脚本必须以root权限运行。"
    echo "请使用 'sudo bash $0' 或 'sudo ./$0' 运行。"
    exit 1
fi

# 检查是否提供了IP地址
if [ $# -eq 0 ]; then
    echo "用法: $0 <IP地址1> <IP地址2> ... <IP地址N>"
    echo "示例: $0 203.0.113.1 203.0.113.2"
    exit 1
fi

# 安装必要工具
yum install -y net-tools

# 获取主网卡名称（通常是eth0）
MAIN_IFACE=$(ip route get 8.8.8.8 | awk '{print $5}' | head -n 1)
if [ -z "$MAIN_IFACE" ]; then
    MAIN_IFACE="eth0"
fi

# 获取主网卡的子网掩码
NETMASK=$(ifconfig $MAIN_IFACE | grep -w inet | awk '{print $4}' | cut -d ":" -f 2)
if [ -z "$NETMASK" ]; then
    NETMASK="255.255.255.0"
fi

# 获取网关
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n 1)
if [ -z "$GATEWAY" ]; then
    GATEWAY=$(ip route | grep via | grep $MAIN_IFACE | awk '{print $3}' | head -n 1)
fi

# 配置每个额外的IP地址
IP_COUNT=0
for IP in "$@"; do
    # 验证IP地址格式
    if ! [[ $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "错误：$IP 不是有效的IP地址"
        continue
    fi
    
    IP_COUNT=$((IP_COUNT+1))
    NEW_IFACE="${MAIN_IFACE}:$IP_COUNT"
    
    echo "正在配置IP: $IP 到 $NEW_IFACE..."
    
    # 创建ifcfg文件
    cat > /etc/sysconfig/network-scripts/ifcfg-$NEW_IFACE <<EOF
DEVICE=$NEW_IFACE
BOOTPROTO=static
IPADDR=$IP
NETMASK=$NETMASK
GATEWAY=$GATEWAY
ONBOOT=yes
TYPE=Ethernet
EOF
    
    # 启用新接口
    ifup $NEW_IFACE
    
    # 检查是否配置成功
    if ifconfig $NEW_IFACE | grep -q $IP; then
        echo "成功配置 $IP 到 $NEW_IFACE"
    else
        echo "警告：$IP 可能没有正确配置到 $NEW_IFACE"
    fi
done

# 重启网络服务
systemctl restart network

echo ""
echo "配置完成！以下是当前网络接口信息："
echo "---------------------------------"
ip addr show
echo "---------------------------------"
echo "您可以通过以下命令SSH连接到各个IP："
for IP in "$@"; do
    echo "ssh root@$IP"
done

#!/bin/bash

# 阿里云多公网IP配置脚本
# 适用于CentOS 7/8
# 功能：自动配置额外的公网IP地址到独立网卡
# 使用方法：curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/aliyun.sh | bash

#!/bin/bash

# 阿里云多公网IP配置脚本（3个IP版本）
# 适用于CentOS 7.6多公网IP型实例
# 严格按照阿里云官方文档规范配置

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "错误：此脚本必须以root权限运行。"
    echo "请使用 'sudo bash $0' 运行。"
    exit 1
fi

# 安装必要工具
yum install -y net-tools

# 获取网络信息
ETH0_IP=$(ip addr show eth0 | grep -w inet | awk '{print $2}' | cut -d '/' -f 1)
ETH1_IP=$(ip addr show eth1 | grep -w inet | awk '{print $2}' | cut -d '/' -f 1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n 1)
NETMASK="255.255.192.0"  # 阿里云VPC默认子网掩码

# 配置eth0（主网卡）
cat > /etc/sysconfig/network-scripts/ifcfg-eth0 <<EOF
DEVICE=eth0
BOOTPROTO=dhcp
ONBOOT=yes
EOF

# 配置eth1（辅助网卡）
cat > /etc/sysconfig/network-scripts/ifcfg-eth1 <<EOF
DEVICE=eth1
BOOTPROTO=dhcp
ONBOOT=yes
TYPE=Ethernet
HWADDR=$(cat /sys/class/net/eth1/address)
DEFROUTE=no
EOF

# 配置eth1:1（第三个IP）
cat > /etc/sysconfig/network-scripts/ifcfg-eth1:1 <<EOF
DEVICE=eth1:1
TYPE=Ethernet
BOOTPROTO=static
ONBOOT=yes
IPADDR=$ETH1_IP
NETMASK=$NETMASK
EOF

# 配置路由表（使eth1出流量走eth1）
echo "配置路由规则..."
ETH1_GATEWAY=$GATEWAY  # 通常与eth0相同

# 创建eth1专用路由表
echo "1001 eth1_route" >> /etc/iproute2/rt_tables

# 添加路由规则
ip route add default via $ETH1_GATEWAY dev eth1 table eth1_route
ip rule add from $ETH1_IP lookup eth1_route

# 使配置永久生效
cat >> /etc/rc.local <<EOF
ip route add default via $ETH1_GATEWAY dev eth1 table eth1_route
ip rule add from $ETH1_IP lookup eth1_route
EOF

chmod +x /etc/rc.d/rc.local

# 重启网络服务
systemctl restart network

echo ""
echo "多公网IP配置完成！"
echo "当前网络配置状态："
echo "---------------------------------"
echo "eth0 IP: $ETH0_IP"
echo "eth1 IP: $ETH1_IP"
echo "eth1:1 IP: $ETH1_IP"
echo "---------------------------------"
echo "路由规则："
ip route show
echo ""
ip rule show
echo "---------------------------------"
echo "您可以通过以下公网IP访问服务器："
echo "1. ssh root@[eth0公网IP]"
echo "2. ssh root@[eth1公网IP]"
echo "3. ssh root@[eth1:1公网IP]"

#!/bin/bash

# Xray多出口配置自动生成脚本 - 使用Python生成JSON
# 实现一个IP入口对应一个IP出口

echo "=== Xray多出口配置自动生成脚本 ==="

# 检查Python是否可用
if ! command -v python3 &> /dev/null; then
    echo "错误: 需要Python3来生成JSON配置"
    echo "请安装Python3: yum install python3 或 apt install python3"
    exit 1
fi

# 获取内网IP列表（排除127.0.0.1）
echo "正在获取内网IP..."
IPS=($(ip -br addr show | grep -v "127.0.0.1" | awk '{for(i=3;i<=NF;i++) print $i}' | cut -d'/' -f1))

echo "获取到 ${#IPS[@]} 个内网IP:"
for i in "${!IPS[@]}"; do
    echo "  IP$((i+1)): ${IPS[i]}"
done

# 检查是否获取到IP
if [ ${#IPS[@]} -eq 0 ]; then
    echo "错误: 未获取到任何内网IP"
    exit 1
fi

# 使用前3个IP，如果不足3个则只配置现有的
NUM_IPS=${#IPS[@]}
if [ $NUM_IPS -gt 3 ]; then
    NUM_IPS=3
    echo "使用前3个IP进行配置"
fi

# 获取网络接口信息
echo "正在获取网络接口信息..."
declare -A IP_INTERFACES
for ip in "${IPS[@]:0:$NUM_IPS}"; do
    interface=$(ip route get "$ip" 2>/dev/null | grep -oP 'dev \K\w+' | head -1)
    if [ -n "$interface" ]; then
        IP_INTERFACES[$ip]=$interface
        echo "  $ip -> $interface"
    else
        echo "  $ip -> 未找到对应接口，将使用默认路由"
        IP_INTERFACES[$ip]="default"
    fi
done

# 生成UUID
echo "正在生成UUID..."
UUIDS=()
for ((i=0; i<NUM_IPS; i++)); do
    UUIDS[i]=$(uuidgen | tr '[:upper:]' '[:lower:]')
    echo "  UUID$((i+1)): ${UUIDS[i]}"
done

# 生成配置文件
CONFIG_FILE="/etc/xray/config.json"
BACKUP_FILE="/etc/xray/config.json.backup.$(date +%Y%m%d_%H%M%S)"

# 备份原配置文件
if [ -f "$CONFIG_FILE" ]; then
    echo "备份原配置文件到: $BACKUP_FILE"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
fi

echo "正在生成新的配置文件..."

# 使用Python生成JSON配置
python3 << EOF > "$CONFIG_FILE"
import json
import sys

# 从bash传入的数据
ips = [$(printf '"%s",' "${IPS[@]:0:$NUM_IPS}" | sed 's/,$//')] 
uuids = [$(printf '"%s",' "${UUIDS[@]:0:$NUM_IPS}" | sed 's/,$//')] 
interfaces = {$(for ip in "${IPS[@]:0:$NUM_IPS}"; do echo "\"$ip\": \"${IP_INTERFACES[$ip]}\","; done | sed 's/,$//')}

# 构建基础配置
config = {
    "log": {
        "access": "/var/log/xray/access.log",
        "error": "/var/log/xray/error.log",
        "loglevel": "warning"
    },
    "dns": {},
    "api": {
        "tag": "api",
        "services": [
            "HandlerService",
            "LoggerService",
            "StatsService"
        ]
    },
    "stats": {},
    "policy": {
        "levels": {
            "0": {
                "handshake": 2,
                "connIdle": 147,
                "uplinkOnly": 8,
                "downlinkOnly": 9,
                "statsUserUplink": True,
                "statsUserDownlink": True
            }
        },
        "system": {
            "statsInboundUplink": True,
            "statsInboundDownlink": True,
            "statsOutboundUplink": True,
            "statsOutboundDownlink": True
        }
    },
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "inboundTag": ["api"],
                "outboundTag": "api"
            }
        ]
    },
    "inbounds": [
        {
            "tag": "api",
            "port": 1476,
            "listen": "127.0.0.1",
            "protocol": "dokodemo-door",
            "settings": {
                "address": "127.0.0.1"
            }
        }
    ],
    "outbounds": []
}

# 添加每个IP的路由规则
for i, ip in enumerate(ips):
    # 添加路由规则
    config["routing"]["rules"].insert(-1 if len(config["routing"]["rules"]) > 1 else 0, {
        "type": "field",
        "inboundTag": [f"vmess-ip{i+1}"],
        "outboundTag": f"out-ip{i+1}"
    })
    
    # 添加入站配置
    config["inbounds"].append({
        "tag": f"vmess-ip{i+1}",
        "port": 10001 + i,
        "listen": ip,
        "protocol": "vmess",
        "settings": {
            "clients": [
                {
                    "id": uuids[i],
                    "email": f"user{i+1}@example.com"
                }
            ]
        },
        "streamSettings": {
            "network": "tcp"
        }
    })
    
    # 添加出站配置
    outbound = {
        "tag": f"out-ip{i+1}",
        "protocol": "freedom",
        "settings": {
            "domainStrategy": "UseIP"
        }
    }
    
    # 如果有特定接口，添加sockopt
    if interfaces[ip] != "default":
        outbound["streamSettings"] = {
            "sockopt": {
                "interface": interfaces[ip]
            }
        }
    
    config["outbounds"].append(outbound)

# 添加其他路由规则
config["routing"]["rules"].extend([
    {
        "type": "field",
        "protocol": ["bittorrent"],
        "marktag": "ban_bt",
        "outboundTag": "block"
    },
    {
        "type": "field",
        "ip": ["geoip:cn"],
        "marktag": "ban_geoip_cn",
        "outboundTag": "block"
    },
    {
        "type": "field",
        "domain": ["geosite:openai"],
        "marktag": "fix_openai",
        "outboundTag": "direct"
    },
    {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
    }
])

# 添加默认出站
config["outbounds"].extend([
    {
        "tag": "direct",
        "protocol": "freedom"
    },
    {
        "tag": "block",
        "protocol": "blackhole"
    }
])

# 输出JSON
print(json.dumps(config, indent=2, ensure_ascii=False))
EOF

# 检查Python脚本是否成功执行
if [ $? -ne 0 ]; then
    echo "✗ Python脚本执行失败"
    if [ -f "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" "$CONFIG_FILE"
    fi
    exit 1
fi

echo "配置文件已生成: $CONFIG_FILE"

# 验证JSON格式
echo "正在验证JSON格式..."
if command -v jq &> /dev/null; then
    if jq . "$CONFIG_FILE" > /dev/null 2>&1; then
        echo "✓ JSON格式验证通过"
    else
        echo "✗ JSON格式错误，正在显示错误信息:"
        jq . "$CONFIG_FILE"
        echo "恢复备份文件..."
        if [ -f "$BACKUP_FILE" ]; then
            cp "$BACKUP_FILE" "$CONFIG_FILE"
        fi
        exit 1
    fi
else
    # 使用python验证JSON
    if python3 -c "import json; json.load(open('$CONFIG_FILE'))" 2>/dev/null; then
        echo "✓ JSON格式验证通过 (使用python验证)"
    else
        echo "✗ JSON格式错误"
        echo "恢复备份文件..."
        if [ -f "$BACKUP_FILE" ]; then
            cp "$BACKUP_FILE" "$CONFIG_FILE"
        fi
        exit 1
    fi
fi

# 显示配置摘要
echo ""
echo "=== 多出口配置摘要 ==="
for ((i=0; i<NUM_IPS; i++)); do
    interface=${IP_INTERFACES[${IPS[i]}]}
    echo "入口$((i+1)): ${IPS[i]}:$((10001+i)) -> 出口$((i+1)): $interface"
    echo "  UUID: ${UUIDS[i]}"
done

# 生成客户端连接信息
echo ""
echo "=== 客户端连接信息 ==="
for ((i=0; i<NUM_IPS; i++)); do
    echo "线路$((i+1)):"
    echo "  地址: ${IPS[i]}"
    echo "  端口: $((10001+i))"
    echo "  UUID: ${UUIDS[i]}"
    echo "  协议: VMess"
    echo "  传输: TCP"
    echo "  出口: ${IP_INTERFACES[${IPS[i]}]}"
    echo ""
done

# 显示路由策略
echo "=== 路由策略说明 ==="
echo "每个入口IP都有独立的出口路由："
for ((i=0; i<NUM_IPS; i++)); do
    echo "• 连接到 ${IPS[i]}:$((10001+i)) 的流量将从 ${IP_INTERFACES[${IPS[i]}]} 出口"
done

# 检查防火墙端口
echo ""
echo "=== 端口检查 ==="
echo "需要开放的端口:"
for ((i=0; i<NUM_IPS; i++)); do
    port=$((10001+i))
    echo "  端口 $port (绑定到 ${IPS[i]})"
    
    # 检查端口是否被占用
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        echo "    警告: 端口 $port 可能已被占用"
    fi
done

echo ""
echo "防火墙配置建议:"
for ((i=0; i<NUM_IPS; i++)); do
    port=$((10001+i))
    echo "  iptables -A INPUT -p tcp --dport $port -j ACCEPT"
done

# 语法检查
echo ""
echo "=== 配置语法检查 ==="
if xray -test -confdir /etc/xray 2>/dev/null; then
    echo "✓ Xray配置语法检查通过"
else
    echo "✗ Xray配置语法检查失败"
    echo "正在显示错误信息:"
    xray -test -confdir /etc/xray
    echo "恢复备份文件..."
    if [ -f "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" "$CONFIG_FILE"
    fi
    exit 1
fi

# 重启服务选项
echo ""
read -p "是否重启Xray服务？(y/N): " restart_choice
if [[ "$restart_choice" =~ ^[Yy]$ ]]; then
    echo "正在重启Xray服务..."
    systemctl restart xray
    sleep 2
    if systemctl is-active --quiet xray; then
        echo "✓ Xray服务重启成功"
        echo "✓ 多出口配置已生效"
        
        # 显示服务状态
        echo ""
        echo "=== 服务状态 ==="
        systemctl status xray --no-pager -l
    else
        echo "✗ Xray服务启动失败，请检查配置"
        echo "错误日志:"
        journalctl -u xray --no-pager -l --since "1 minute ago"
        if [ -f "$BACKUP_FILE" ]; then
            echo "如需恢复原配置，请执行: cp $BACKUP_FILE $CONFIG_FILE"
        fi
    fi
else
    echo "提示: 请手动执行 'systemctl restart xray' 来重启服务"
fi

echo ""
echo "=== 测试建议 ==="
echo "1. 分别连接不同的入口IP测试路由是否正确"
echo "2. 使用 https://ipinfo.io 等网站检查出口IP"
echo "3. 检查日志: tail -f /var/log/xray/error.log"
echo ""
echo "脚本执行完成！"

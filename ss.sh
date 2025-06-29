#!/bin/bash

# 多IP Shadowsocks一键安装脚本
# 要求：入口IP=出口IP，使用origin模式
# 作者：自定义版本基于233boy/Xray  curl -sSL https://raw.githubusercontent.com/Blazerain/yourrepo/main/ss.sh| bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 获取服务器所有IP地址
get_server_ips() {
    log_info "检测服务器IP地址..."
    
    # 获取所有网卡IP（排除lo、docker等）
    SERVER_IPS=($(ip -4 addr show | grep -oE 'inet [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | awk '{print $2}' | grep -v '^127\.' | grep -v '^172\.17\.' | grep -v '^172\.18\.'))
    
    if [ ${#SERVER_IPS[@]} -eq 0 ]; then
        log_error "未检测到可用的IP地址"
        exit 1
    fi
    
    log_info "检测到IP地址："
    for i in "${!SERVER_IPS[@]}"; do
        echo "  $((i+1)). ${SERVER_IPS[$i]}"
    done
}

# 安装233boy Xray脚本
install_xray_script() {
    log_info "安装233boy Xray脚本..."
    
    if command -v xray >/dev/null 2>&1; then
        log_warn "检测到Xray已安装，跳过安装步骤"
        return
    fi
    
    bash <(wget -qO- -o- https://github.com/233boy/Xray/raw/main/install.sh)
    
    if ! command -v xray >/dev/null 2>&1; then
        log_error "Xray安装失败"
        exit 1
    fi
    
    log_info "Xray安装完成"
}

# 创建Shadowsocks配置
create_shadowsocks_configs() {
    log_info "创建Shadowsocks配置..."
    
    local password="123"
    local method="aes-256-gcm"
    local ports=(11000 12000 13000)
    
    # 删除默认配置（如果存在）
    xray del reality >/dev/null 2>&1 || true
    
    # 为前三个IP创建SS配置
    for i in {0..2}; do
        if [ $i -lt ${#SERVER_IPS[@]} ]; then
            local ip=${SERVER_IPS[$i]}
            local port=${ports[$i]}
            
            log_info "为IP ${ip} 创建SS配置，端口：${port}"
            
            # 使用233boy脚本创建SS配置
            xray add ss ${port} ${password} ${method}
            
            log_info "IP ${ip}:${port} SS配置创建完成"
        fi
    done
}

# 修改配置文件添加sendThrough支持
modify_config_for_origin() {
    log_info "修改配置文件以支持origin模式..."
    
    local config_file="/etc/xray/conf/config.json"
    local backup_file="/etc/xray/conf/config.json.backup"
    
    if [ ! -f "$config_file" ]; then
        log_error "配置文件不存在：$config_file"
        exit 1
    fi
    
    # 备份原配置
    cp "$config_file" "$backup_file"
    log_info "原配置已备份到：$backup_file"
    
    # 使用Python修改JSON配置（如果有python）
    if command -v python3 >/dev/null 2>&1; then
        python3 << 'EOF'
import json
import sys

config_file = "/etc/xray/conf/config.json"

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
    
    # 修改所有outbound添加sendThrough: "origin"
    if 'outbounds' in config:
        for outbound in config['outbounds']:
            outbound['sendThrough'] = 'origin'
        
        # 确保第一个outbound是direct
        if len(config['outbounds']) > 0:
            # 添加一个direct outbound作为默认
            direct_outbound = {
                "sendThrough": "origin",
                "protocol": "freedom",
                "settings": {},
                "tag": "direct"
            }
            
            # 将direct outbound插入到第一位
            config['outbounds'].insert(0, direct_outbound)
    
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)
    
    print("配置文件修改完成")
    
except Exception as e:
    print(f"修改配置文件失败: {e}")
    sys.exit(1)
EOF
    else
        log_warn "未找到Python3，需要手动修改配置文件"
        log_info "请在每个outbound中添加: \"sendThrough\": \"origin\""
    fi
}

# 重启服务
restart_services() {
    log_info "重启Xray服务..."
    
    xray restart
    
    if [ $? -eq 0 ]; then
        log_info "Xray服务重启成功"
    else
        log_error "Xray服务重启失败"
        exit 1
    fi
}

# 显示配置信息
show_config_info() {
    log_info "配置完成！以下是连接信息："
    echo ""
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}    Shadowsocks 配置信息${NC}"
    echo -e "${BLUE}================================${NC}"
    
    local password="123"
    local method="aes-256-gcm"
    local ports=(11000 12000 13000)
    
    for i in {0..2}; do
        if [ $i -lt ${#SERVER_IPS[@]} ]; then
            local ip=${SERVER_IPS[$i]}
            local port=${ports[$i]}
            
            echo ""
            echo -e "${GREEN}配置 $((i+1)):${NC}"
            echo -e "  服务器: ${ip}"
            echo -e "  端口: ${port}"
            echo -e "  密码: ${password}"
            echo -e "  加密: ${method}"
            echo -e "  模式: Origin (入口IP=出口IP)"
        fi
    done
    
    echo ""
    echo -e "${BLUE}================================${NC}"
    echo -e "${YELLOW}注意：${NC}"
    echo -e "1. 此配置实现了入口IP=出口IP功能"
    echo -e "2. 客户端连接哪个IP，出站流量就从哪个IP发出"
    echo -e "3. 管理命令：xray (查看管理面板)"
    echo -e "4. 查看配置：xray info"
    echo -e "5. 查看日志：xray log"
    echo ""
}

# 主函数
main() {
    echo -e "${BLUE}"
    echo "=================================="
    echo "   多IP Shadowsocks 一键安装脚本"
    echo "   入口IP=出口IP 模式"
    echo "=================================="
    echo -e "${NC}"
    
    check_root
    get_server_ips
    
    # 确认信息
    echo ""
    read -p "检测到 ${#SERVER_IPS[@]} 个IP地址，将为前3个IP创建SS配置。是否继续？[y/N]: " confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_info "安装已取消"
        exit 0
    fi
    
    install_xray_script
    create_shadowsocks_configs
    modify_config_for_origin
    restart_services
    show_config_info
    
    log_info "安装完成！"
}

# 运行主函数
main "$@"

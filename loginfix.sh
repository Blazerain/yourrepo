#!/bin/bash

echo "🌍 修复CDN地区限制问题"
echo "=========================================="
echo "目标: 让cdn.hk.beanfun.com通过代理访问，绕过地区限制"
echo ""

# 1. 检查xray服务状态
echo "1️⃣ 检查代理服务状态"
echo "----------------------------------------"

if systemctl is-active --quiet xray; then
    echo "✅ xray服务正在运行"
    
    # 获取端口
    SOCKS_PORT=$(sudo netstat -tlnp | grep xray | awk '{print $4}' | cut -d: -f2 | head -1)
    if [ -n "$SOCKS_PORT" ]; then
        echo "📍 检测到SOCKS5端口: $SOCKS_PORT"
    else
        echo "❌ 无法检测端口"
        exit 1
    fi
else
    echo "❌ xray服务未运行"
    echo "尝试启动服务..."
    sudo systemctl start xray
    sleep 3
    if systemctl is-active --quiet xray; then
        echo "✅ 服务启动成功"
        SOCKS_PORT=$(sudo netstat -tlnp | grep xray | awk '{print $4}' | cut -d: -f2 | head -1)
    else
        echo "❌ 服务启动失败"
        sudo systemctl status xray --no-pager -l
        exit 1
    fi
fi

echo ""

# 2. 测试当前代理功能
echo "2️⃣ 测试代理基本功能"
echo "----------------------------------------"

echo "🧪 测试代理连接到httpbin.org:"
if timeout 15 curl --socks5 vip1:123456@127.0.0.1:$SOCKS_PORT -s https://httpbin.org/ip --connect-timeout 5 >/dev/null 2>&1; then
    echo "✅ 代理基本功能正常"
    
    # 获取代理IP
    proxy_ip=$(timeout 15 curl --socks5 vip1:123456@127.0.0.1:$SOCKS_PORT -s https://httpbin.org/ip --connect-timeout 5 2>/dev/null | grep -o '"origin": "[^"]*"' | cut -d'"' -f4)
    if [ -n "$proxy_ip" ]; then
        echo "  代理IP: $proxy_ip"
    fi
else
    echo "❌ 代理基本功能异常"
    echo "请先修复代理服务"
    exit 1
fi

echo ""

# 3. 测试当前cdn.hk.beanfun.com访问情况
echo "3️⃣ 测试当前CDN访问情况"
echo "----------------------------------------"

echo "🔗 直连测试 cdn.hk.beanfun.com/www/ip.html:"
direct_result=$(timeout 10 curl -s https://cdn.hk.beanfun.com/www/ip.html --connect-timeout 5 2>/dev/null)
if echo "$direct_result" | grep -q "國家或地區"; then
    echo "❌ 直连被地区限制（符合预期）"
else
    echo "🤔 直连结果异常: $(echo "$direct_result" | head -1)"
fi

echo ""
echo "🔗 代理测试 cdn.hk.beanfun.com/www/ip.html:"
proxy_result=$(timeout 15 curl --socks5-hostname vip1:123456@127.0.0.1:$SOCKS_PORT -s https://cdn.hk.beanfun.com/www/ip.html --connect-timeout 5 2>/dev/null)
if echo "$proxy_result" | grep -q "國家或地區"; then
    echo "❌ 代理仍被地区限制 - cdn.hk.beanfun.com 可能在直连配置中"
    cdn_needs_proxy=true
elif [ -n "$proxy_result" ] && ! echo "$proxy_result" | grep -q "Error"; then
    echo "✅ 代理访问成功 - cdn.hk.beanfun.com 已正确配置"
    cdn_needs_proxy=false
    echo "  内容长度: $(echo "$proxy_result" | wc -c) 字节"
else
    echo "❌ 代理访问失败: $proxy_result"
    cdn_needs_proxy=true
fi

echo ""

# 4. 检查当前路由配置
echo "4️⃣ 检查当前路由配置"
echo "----------------------------------------"

CONFIG_FILE="/etc/xray/config.json"
if [ -f "$CONFIG_FILE" ]; then
    echo "🔍 检查cdn.hk.beanfun.com的路由配置:"
    
    # 检查是否在直连域名列表中
    if grep -q "cdn\.hk\.beanfun\.com" "$CONFIG_FILE"; then
        echo "❌ cdn.hk.beanfun.com 在直连域名列表中"
        echo "  需要移除以让其走代理"
        cdn_in_direct_domain=true
    else
        echo "✅ cdn.hk.beanfun.com 不在直连域名列表中"
        cdn_in_direct_domain=false
    fi
    
    # 检查IP是否在直连列表中
    cdn_ip=$(getent hosts cdn.hk.beanfun.com | awk '{print $1}' | head -1)
    if [ -n "$cdn_ip" ]; then
        echo "  cdn.hk.beanfun.com 解析IP: $cdn_ip"
        if grep -q "${cdn_ip}/32" "$CONFIG_FILE"; then
            echo "❌ cdn IP ($cdn_ip) 在直连IP列表中"
            cdn_ip_in_direct=true
        else
            echo "✅ cdn IP ($cdn_ip) 不在直连IP列表中"
            cdn_ip_in_direct=false
        fi
    else
        echo "⚠️ 无法解析cdn.hk.beanfun.com IP"
        cdn_ip_in_direct=false
    fi
else
    echo "❌ 配置文件不存在"
    exit 1
fi

echo ""

# 5. 修复配置（如果需要）
if [ "$cdn_needs_proxy" = true ] && ([ "$cdn_in_direct_domain" = true ] || [ "$cdn_ip_in_direct" = true ]); then
    echo "5️⃣ 修复路由配置"
    echo "----------------------------------------"
    
    echo "🛑 停止xray服务..."
    sudo systemctl stop xray
    
    # 备份配置
    backup_file="/etc/xray/config.json.cdn_fix.$(date +%Y%m%d_%H%M%S)"
    echo "💾 备份配置到: $backup_file"
    sudo cp "$CONFIG_FILE" "$backup_file"
    
    # 移除cdn.hk.beanfun.com的直连配置
    if [ "$cdn_in_direct_domain" = true ]; then
        echo "📝 从直连域名列表移除 cdn.hk.beanfun.com"
        sudo sed -i '/cdn\.hk\.beanfun\.com/d' "$CONFIG_FILE"
    fi
    
    # 移除cdn IP的直连配置
    if [ "$cdn_ip_in_direct" = true ] && [ -n "$cdn_ip" ]; then
        echo "📝 从直连IP列表移除 $cdn_ip"
        sudo sed -i "/${cdn_ip//./\\.}\/32/d" "$CONFIG_FILE"
    fi
    
    # 验证配置
    echo "🔍 验证修改后的配置..."
    if /usr/local/bin/xray test -c "$CONFIG_FILE" >/dev/null 2>&1 || /usr/local/bin/xray -test -config "$CONFIG_FILE" >/dev/null 2>&1; then
        echo "✅ 配置文件验证通过"
    else
        echo "❌ 配置文件验证失败，恢复备份"
        sudo cp "$backup_file" "$CONFIG_FILE"
        echo "配置已恢复，请手动检查"
        exit 1
    fi
    
    # 重启服务
    echo "🚀 重启xray服务..."
    sudo systemctl start xray
    sleep 5
    
    if systemctl is-active --quiet xray; then
        echo "✅ 服务重启成功"
    else
        echo "❌ 服务重启失败"
        sudo systemctl status xray --no-pager -l
        exit 1
    fi
    
    echo "✅ 路由配置修复完成"
    echo ""
else
    echo "5️⃣ 配置检查结果"
    echo "----------------------------------------"
    if [ "$cdn_needs_proxy" = false ]; then
        echo "✅ cdn.hk.beanfun.com 已正确通过代理访问"
    else
        echo "⚠️ cdn.hk.beanfun.com 仍需要配置优化"
    fi
fi

# 6. 最终测试
echo "6️⃣ 最终测试"
echo "=========================================="

echo "🧪 完整流程测试:"
echo ""

# 测试login重定向
echo "1. 测试 login.hk.beanfun.com 重定向:"
login_response=$(curl -s -I https://login.hk.beanfun.com --connect-timeout 10 2>/dev/null)
if echo "$login_response" | grep -q "302"; then
    redirect_url=$(echo "$login_response" | grep "Location:" | awk '{print $2}' | tr -d '\r\n')
    echo "✅ 重定向正常 → $redirect_url"
else
    echo "❌ 重定向异常"
fi

echo ""

# 测试直连cdn
echo "2. 测试直连 cdn.hk.beanfun.com/www/ip.html:"
direct_result=$(timeout 10 curl -s https://cdn.hk.beanfun.com/www/ip.html --connect-timeout 5 2>/dev/null)
if echo "$direct_result" | grep -q "國家或地區"; then
    echo "❌ 地区限制（正常，需要代理）"
elif [ -n "$direct_result" ]; then
    echo "✅ 直连成功"
    echo "  内容长度: $(echo "$direct_result" | wc -c) 字节"
else
    echo "❌ 连接失败"
fi

echo ""

# 测试代理cdn
echo "3. 测试代理 cdn.hk.beanfun.com/www/ip.html:"
proxy_result=$(timeout 15 curl --socks5-hostname vip1:123456@127.0.0.1:$SOCKS_PORT -s https://cdn.hk.beanfun.com/www/ip.html --connect-timeout 5 2>/dev/null)
if echo "$proxy_result" | grep -q "國家或地區"; then
    echo "❌ 代理仍被地区限制"
    echo "  可能需要进一步配置调整"
elif [ -n "$proxy_result" ] && ! echo "$proxy_result" | grep -q "Error"; then
    echo "✅ 代理成功绕过地区限制"
    echo "  内容长度: $(echo "$proxy_result" | wc -c) 字节"
    echo "  内容预览: $(echo "$proxy_result" | head -2 | tr '\n' ' ')"
    SUCCESS=true
else
    echo "❌ 代理访问失败"
    echo "  错误: $proxy_result"
fi

echo ""

# 测试完整重定向跟随
echo "4. 测试完整流程（跟随重定向）:"
echo "命令: curl --socks5-hostname vip1:123456@127.0.0.1:$SOCKS_PORT -L https://login.hk.beanfun.com"
full_result=$(timeout 15 curl --socks5-hostname vip1:123456@127.0.0.1:$SOCKS_PORT -s -L https://login.hk.beanfun.com --connect-timeout 5 2>/dev/null)

if echo "$full_result" | grep -q "國家或地區"; then
    echo "❌ 完整流程仍遇到地区限制"
elif [ -n "$full_result" ] && ! echo "$full_result" | grep -q "Error"; then
    echo "✅ 完整流程成功！"
    echo "  最终内容长度: $(echo "$full_result" | wc -c) 字节"
    SUCCESS=true
else
    echo "❌ 完整流程失败"
fi

echo ""

# 7. 总结和建议
echo "7️⃣ 总结和后续建议"
echo "=========================================="

if [ "$SUCCESS" = true ]; then
    echo "🎉 问题解决成功！"
    echo ""
    echo "✅ 现在可以正常使用:"
    echo "  - login.hk.beanfun.com 正常重定向"
    echo "  - cdn.hk.beanfun.com 通过代理绕过地区限制"
    echo "  - 完整的Beanfun访问流程工作正常"
    echo ""
    echo "🎮 游戏客户端配置:"
    echo "  代理类型: SOCKS5"
    echo "  服务器: 127.0.0.1 (本地) 或您的服务器IP"
    echo "  端口: $SOCKS_PORT"
    echo "  用户名: vip1"
    echo "  密码: 123456"
    echo "  ⚠️ 重要: 启用'代理DNS查询'或'远程DNS解析'"
else
    echo "⚠️ 仍存在问题，建议:"
    echo ""
    echo "🔧 手动测试命令:"
    echo "  curl --socks5-hostname vip1:123456@127.0.0.1:$SOCKS_PORT https://cdn.hk.beanfun.com/www/ip.html"
    echo "  curl --socks5-hostname vip1:123456@127.0.0.1:$SOCKS_PORT -L https://login.hk.beanfun.com"
    echo ""
    echo "📋 检查项目:"
    echo "  1. 确认代理服务正常: sudo systemctl status xray"
    echo "  2. 检查端口监听: sudo netstat -tlnp | grep $SOCKS_PORT"
    echo "  3. 查看配置文件: grep -A10 -B10 cdn /etc/xray/config.json"
    echo "  4. 检查防火墙: sudo iptables -L INPUT -n | grep $SOCKS_PORT"
fi

echo ""
echo "💡 常用测试命令:"
echo "# 基础代理测试"
echo "curl --socks5 vip1:123456@127.0.0.1:$SOCKS_PORT https://httpbin.org/ip"
echo ""
echo "# Beanfun完整测试"
echo "curl --socks5-hostname vip1:123456@127.0.0.1:$SOCKS_PORT -L https://login.hk.beanfun.com"
echo ""
echo "# CDN单独测试" 
echo "curl --socks5-hostname vip1:123456@127.0.0.1:$SOCKS_PORT https://cdn.hk.beanfun.com/www/ip.html"

echo ""
echo "🎯 修复完成时间: $(date)"
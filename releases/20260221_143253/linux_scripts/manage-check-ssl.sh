#!/bin/bash
#
# SSL 证书检查脚本 (适配 Nginx ACME 模块)
# 检查证书有效期和状态
#
# 使用方法:
#   chmod +x manage-check-ssl.sh
#   ./manage-check-ssl.sh [domain]

set -e

# ============================================
# 颜色定义
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# 检查依赖
# ============================================
check_dependencies() {
    local missing=0
    for cmd in host timeout openssl; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}错误: 未找到命令 '$cmd'${NC}"
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        echo -e "${YELLOW}请安装缺失的工具 (例如: apt install dnsutils coreutils openssl)${NC}"
        exit 1
    fi
}

# ============================================
# 在线检查证书 (主要方法)
# ============================================
check_online() {
    local domain=$1

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}检查证书: $domain${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo

    # 检查域名解析
    if ! host "$domain" > /dev/null 2>&1; then
        echo -e "${RED}✗ 域名无法解析: $domain${NC}"
        return 1
    fi

    # 获取在线证书信息
    local cert_info
    cert_info=$(echo | timeout 10 openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null)

    if [ -z "$cert_info" ]; then
        echo -e "${RED}✗ 无法连接到 $domain:443${NC}"
        echo -e "${YELLOW}  可能原因: 域名未解析、防火墙阻止、或证书尚未申请${NC}"
        return 1
    fi

    # 提取证书信息
    local issuer=$(echo "$cert_info" | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//')
    local subject=$(echo "$cert_info" | openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//')
    local start_date=$(echo "$cert_info" | openssl x509 -noout -startdate 2>/dev/null | sed 's/notBefore=//')
    local end_date=$(echo "$cert_info" | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')

    if [ -z "$end_date" ]; then
        echo -e "${RED}✗ 无法获取证书信息${NC}"
        return 1
    fi

    # 计算剩余天数
    local end_epoch=$(date -d "$end_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$end_date" +%s 2>/dev/null)
    local now_epoch=$(date +%s)
    local days_left=$(( ($end_epoch - $now_epoch) / 86400 ))

    echo -e "${GREEN}✓ HTTPS 可访问${NC}"
    echo
    echo "域名: $domain"
    echo "颁发者: $issuer"
    echo "主题: $subject"
    echo
    echo "生效时间: $start_date"
    echo "到期时间: $end_date"
    echo

    # 判断证书状态
    if [ $days_left -lt 0 ]; then
        echo -e "${RED}✗ 证书已过期 ($days_left 天)${NC}"
        echo -e "${YELLOW}  建议: 访问 https://$domain 触发 ACME 模块自动续期${NC}"
    elif [ $days_left -lt 7 ]; then
        echo -e "${RED}⚠ 证书即将过期 (剩余 $days_left 天)${NC}"
        echo -e "${YELLOW}  Nginx ACME 模块应该会自动续期${NC}"
    elif [ $days_left -lt 30 ]; then
        echo -e "${YELLOW}⚠ 证书将在 $days_left 天后过期${NC}"
        echo -e "${GREEN}  Nginx ACME 模块会自动续期${NC}"
    else
        echo -e "${GREEN}✓ 证书有效 (剩余 $days_left 天)${NC}"
    fi

    echo
}

# ============================================
# 从 Nginx 配置提取域名
# ============================================
get_configured_domains() {
    local domains=()
    
    # 从 sites-enabled 提取 server_name
    if [ -d "/etc/nginx/sites-enabled" ]; then
        for conf in /etc/nginx/sites-enabled/*.conf; do
            if [ -f "$conf" ]; then
                local domain=$(grep -oP 'server_name\s+\K[^;]+' "$conf" 2>/dev/null | head -1 | awk '{print $1}')
                if [ -n "$domain" ] && [ "$domain" != "_" ]; then
                    domains+=("$domain")
                fi
            fi
        done
    fi

    # 去重并输出
    printf '%s\n' "${domains[@]}" | sort -u
}

# ============================================
# 检查所有配置的域名
# ============================================
check_all() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════╗"
    echo "║     SSL 证书检查工具 (ACME 模块)           ║"
    echo "╚════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo

    # 检查 Nginx 状态
    echo -e "${BLUE}Nginx 状态:${NC}"
    if systemctl is-active --quiet nginx; then
        echo -e "  ${GREEN}✓ Nginx 运行中${NC}"
        echo "  版本: $(nginx -v 2>&1 | grep -oP '\d+\.\d+\.\d+')"
    else
        echo -e "  ${RED}✗ Nginx 未运行${NC}"
        echo
        return 1
    fi
    echo

    # 获取配置的域名
    local domains=($(get_configured_domains))

    if [ ${#domains[@]} -eq 0 ]; then
        echo -e "${YELLOW}未找到配置的域名${NC}"
        echo "检查目录: /etc/nginx/sites-enabled/"
        echo
        return
    fi

    echo -e "${BLUE}发现 ${#domains[@]} 个配置的域名:${NC}"
    for d in "${domains[@]}"; do
        echo "  - $d"
    done
    echo

    # 检查每个域名的证书
    for domain in "${domains[@]}"; do
        check_online "$domain"
    done
}

# ============================================
# 触发证书续期
# ============================================
trigger_renewal() {
    local domain=$1

    echo -e "${YELLOW}触发证书更新: $domain${NC}"
    echo

    echo "Nginx ACME 模块会在以下情况自动申请/续期证书:"
    echo "  1. 首次访问 HTTPS 时"
    echo "  2. 证书过期前 30 天内"
    echo

    read -p "是否立即访问 $domain 触发? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo
        echo "正在访问 https://$domain ..."
        if curl -Ik --max-time 30 "https://$domain" 2>&1 | head -5; then
            echo
            echo -e "${GREEN}已触发，请稍后再次检查证书状态${NC}"
        else
            echo -e "${RED}访问失败，请检查域名解析和防火墙设置${NC}"
        fi
    fi
}

# ============================================
# 显示帮助
# ============================================
show_help() {
    cat << 'EOF'
SSL 证书检查脚本 (适配 Nginx ACME 模块)

使用方法:
    ./manage-check-ssl.sh              # 检查所有配置的域名
    ./manage-check-ssl.sh <domain>     # 检查指定域名
    ./manage-check-ssl.sh --renew <domain>  # 触发续期

说明:
    此脚本适配 Nginx ACME 模块 (acme_certificate letsencrypt)
    证书由 Nginx 自动管理，无需手动操作
    脚本通过在线连接验证证书状态

示例:
    ./manage-check-ssl.sh
    ./manage-check-ssl.sh www.sharptier.com
    ./manage-check-ssl.sh --renew www.sharptier.com

EOF
}

# ============================================
# 主函数
# ============================================
main() {
    check_dependencies
    local action=$1
    local domain=$2

    case $action in
        --help|-h|help)
            show_help
            ;;
        --renew)
            if [ -z "$domain" ]; then
                echo "请指定域名"
                exit 1
            fi
            trigger_renewal "$domain"
            ;;
        "")
            check_all
            ;;
        *)
            check_online "$action"
            ;;
    esac
}

# 运行主函数
main "$@"

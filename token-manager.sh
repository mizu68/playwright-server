#!/bin/bash

# Playwright Token管理脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 生成强随机Token
generate_token() {
    local device_name=$1
    if [ -z "$device_name" ]; then
        device_name="device"
    fi
    
    # 生成32字符的随机字符串
    local random_part=$(openssl rand -hex 16)
    local timestamp=$(date +%y%m%d)
    echo "${device_name}-${timestamp}-${random_part}"
}

# 读取当前Token列表
get_current_tokens() {
    if [ -f .env ]; then
        grep "^ALLOWED_TOKENS=" .env | cut -d'=' -f2 | tr ',' '\n' | grep -v '^$'
    else
        echo ""
    fi
}

# 更新.env文件中的Token列表
update_tokens_in_env() {
    local new_tokens="$1"
    
    if [ -f .env ]; then
        # 备份原文件
        cp .env .env.backup
        
        # 更新ALLOWED_TOKENS
        if grep -q "^ALLOWED_TOKENS=" .env; then
            sed -i.bak "s|^ALLOWED_TOKENS=.*|ALLOWED_TOKENS=$new_tokens|" .env
        else
            echo "ALLOWED_TOKENS=$new_tokens" >> .env
        fi
        
        rm -f .env.bak
    else
        print_error ".env 文件不存在"
        exit 1
    fi
}

# 列出所有Token
list_tokens() {
    print_info "当前活跃的Token列表："
    echo ""
    
    local tokens=$(get_current_tokens)
    if [ -z "$tokens" ]; then
        print_warning "没有配置任何Token"
        return
    fi
    
    local index=1
    echo "$tokens" | while read -r token; do
        if [ ! -z "$token" ]; then
            # 提取设备名称（假设格式为 device-date-random）
            local device_name=$(echo "$token" | cut -d'-' -f1)
            local masked_token="${token:0:12}...${token: -8}"
            echo "  $index. 设备: $device_name"
            echo "     Token: $masked_token"
            echo "     完整: $token"
            echo ""
            index=$((index + 1))
        fi
    done
}

# 添加新Token
add_token() {
    local device_name=$1
    
    if [ -z "$device_name" ]; then
        read -p "请输入设备名称 (如: laptop, phone, tablet): " device_name
    fi
    
    if [ -z "$device_name" ]; then
        print_error "设备名称不能为空"
        exit 1
    fi
    
    # 生成新Token
    local new_token=$(generate_token "$device_name")
    
    # 获取当前Token列表
    local current_tokens=$(get_current_tokens | tr '\n' ',' | sed 's/,$//')
    
    # 添加新Token
    if [ -z "$current_tokens" ]; then
        local updated_tokens="$new_token"
    else
        local updated_tokens="$current_tokens,$new_token"
    fi
    
    # 更新配置文件
    update_tokens_in_env "$updated_tokens"
    
    print_success "新Token已添加："
    echo "  设备: $device_name"
    echo "  Token: $new_token"
    echo ""
    print_info "请将此Token保存到你的设备中，并重启服务使配置生效"
}

# 删除Token
remove_token() {
    local token_to_remove=$1
    
    if [ -z "$token_to_remove" ]; then
        list_tokens
        echo ""
        read -p "请输入要删除的Token（完整或前12位）: " token_to_remove
    fi
    
    if [ -z "$token_to_remove" ]; then
        print_error "Token不能为空"
        exit 1
    fi
    
    # 获取当前Token列表
    local current_tokens=$(get_current_tokens)
    local updated_tokens=""
    local found=false
    
    echo "$current_tokens" | while read -r token; do
        if [ ! -z "$token" ]; then
            # 检查是否匹配（完整匹配或前缀匹配）
            if [ "$token" != "$token_to_remove" ] && [ "${token:0:${#token_to_remove}}" != "$token_to_remove" ]; then
                if [ -z "$updated_tokens" ]; then
                    updated_tokens="$token"
                else
                    updated_tokens="$updated_tokens,$token"
                fi
            else
                found=true
                print_info "找到匹配的Token: $token"
            fi
        fi
    done
    
    if [ "$found" = true ]; then
        update_tokens_in_env "$updated_tokens"
        print_success "Token已删除"
        print_info "请重启服务使配置生效"
    else
        print_error "未找到匹配的Token"
    fi
}

# 重新生成所有Token
regenerate_all() {
    print_warning "这将重新生成所有Token，旧Token将失效"
    read -p "确认继续? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        return
    fi
    
    # 获取当前设备名称
    local current_tokens=$(get_current_tokens)
    local new_tokens=""
    
    echo "$current_tokens" | while read -r token; do
        if [ ! -z "$token" ]; then
            local device_name=$(echo "$token" | cut -d'-' -f1)
            local new_token=$(generate_token "$device_name")
            
            if [ -z "$new_tokens" ]; then
                new_tokens="$new_token"
            else
                new_tokens="$new_tokens,$new_token"
            fi
            
            print_info "设备 $device_name: $new_token"
        fi
    done
    
    update_tokens_in_env "$new_tokens"
    print_success "所有Token已重新生成"
}

# 测试Token
test_token() {
    local token=$1
    local port=${EXTERNAL_PORT:-3000}
    
    if [ -z "$token" ]; then
        read -p "请输入要测试的Token: " token
    fi
    
    print_info "测试Token: ${token:0:12}..."
    
    local response=$(curl -s -w "%{http_code}" -H "Authorization: Bearer $token" "http://localhost:$port/health")
    local http_code="${response: -3}"
    local body="${response%???}"
    
    if [ "$http_code" = "200" ]; then
        print_success "Token验证成功"
        echo "响应: $body"
    else
        print_error "Token验证失败 (HTTP $http_code)"
        echo "响应: $body"
    fi
}

# 显示帮助
show_help() {
    echo "Playwright Token管理脚本"
    echo ""
    echo "用法: $0 [命令] [参数]"
    echo ""
    echo "命令:"
    echo "  list                   显示所有Token"
    echo "  add [device_name]      添加新Token"
    echo "  remove [token]         删除指定Token"
    echo "  regenerate             重新生成所有Token"
    echo "  test [token]           测试Token是否有效"
    echo "  help                   显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 list                # 显示所有Token"
    echo "  $0 add laptop          # 为laptop设备添加Token"
    echo "  $0 remove laptop-      # 删除以laptop-开头的Token"
    echo "  $0 test abc123...      # 测试Token是否有效"
}

# 主逻辑
main() {
    case "${1:-help}" in
        list|ls)
            list_tokens
            ;;
        add|create)
            add_token "$2"
            ;;
        remove|delete|rm)
            remove_token "$2"
            ;;
        regenerate|regen)
            regenerate_all
            ;;
        test)
            test_token "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "未知命令: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
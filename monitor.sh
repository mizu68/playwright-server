#!/bin/bash

# Playwright 服务器自动监控和恢复脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志文件
MONITOR_LOG="monitor.log"
MAX_LOG_SIZE=10485760  # 10MB

print_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[$timestamp][INFO]${NC} $1" | tee -a "$MONITOR_LOG"
}

print_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[$timestamp][SUCCESS]${NC} $1" | tee -a "$MONITOR_LOG"
}

print_warning() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[$timestamp][WARNING]${NC} $1" | tee -a "$MONITOR_LOG"
}

print_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[$timestamp][ERROR]${NC} $1" | tee -a "$MONITOR_LOG"
}

# 读取配置
load_config() {
    if [ -f .env ]; then
        source .env
    fi
    
    # 设置默认值
    EXTERNAL_PORT=${EXTERNAL_PORT:-3000}
    HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-30}
    HEALTH_CHECK_RETRIES=${HEALTH_CHECK_RETRIES:-3}
    HEALTH_CHECK_TIMEOUT=${HEALTH_CHECK_TIMEOUT:-10}
}

# 日志轮转
rotate_log() {
    if [ -f "$MONITOR_LOG" ] && [ $(stat -c%s "$MONITOR_LOG" 2>/dev/null || stat -f%z "$MONITOR_LOG") -gt $MAX_LOG_SIZE ]; then
        mv "$MONITOR_LOG" "${MONITOR_LOG}.old"
        print_info "日志文件已轮转"
    fi
}

# 检查服务健康状态
check_health() {
    local service_name="$1"
    local endpoint="$2"
    local timeout=${3:-10}
    
    if curl -sf --max-time "$timeout" "$endpoint" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 检查容器状态
check_container_status() {
    local container_name="$1"
    
    if docker compose ps "$container_name" | grep -q "Up"; then
        return 0
    else
        return 1
    fi
}

# 获取容器健康状态
get_container_health() {
    local container_name="$1"
    docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "unknown"
}

# 重启服务
restart_service() {
    local service_name="$1"
    
    print_warning "正在重启服务: $service_name"
    
    if docker compose restart "$service_name"; then
        print_success "服务 $service_name 重启成功"
        sleep 10  # 等待服务启动
        return 0
    else
        print_error "服务 $service_name 重启失败"
        return 1
    fi
}

# 完整重启集群
restart_cluster() {
    print_error "执行完整集群重启..."
    
    if ./start.sh restart; then
        print_success "集群重启成功"
        return 0
    else
        print_error "集群重启失败"
        return 1
    fi
}

# 发送通知（可扩展）
send_notification() {
    local level="$1"
    local message="$2"
    
    # 这里可以集成邮件、Webhook、Slack等通知方式
    print_info "通知 [$level]: $message"
    
    # 示例：写入系统日志
    logger -t playwright-monitor "[$level] $message"
}

# 收集系统信息
collect_system_info() {
    local info_file="/tmp/playwright-system-info.txt"
    
    {
        echo "=== 系统信息收集 $(date) ==="
        echo ""
        echo "--- Docker 状态 ---"
        docker compose ps
        echo ""
        echo "--- 容器健康状态 ---"
        for container in playwright-nginx playwright-1; do
            if docker ps --format "table {{.Names}}" | grep -q "$container"; then
                health=$(get_container_health "$container")
                echo "$container: $health"
            fi
        done
        echo ""
        echo "--- 系统资源 ---"
        echo "内存使用:"
        docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.CPUPerc}}"
        echo ""
        echo "磁盘使用:"
        df -h
        echo ""
        echo "--- 最近错误日志 ---"
        docker compose logs --tail=20 nginx 2>&1 || echo "无法获取nginx日志"
        docker compose logs --tail=20 playwright-1 2>&1 || echo "无法获取playwright-1日志"
    } > "$info_file"
    
    echo "$info_file"
}

# 主监控循环
monitor_loop() {
    local consecutive_failures=0
    local max_failures=3
    
    while true; do
        rotate_log
        
        print_info "开始健康检查..."
        
        # 检查主服务端点
        if check_health "main-service" "http://localhost:$EXTERNAL_PORT/health" "$HEALTH_CHECK_TIMEOUT"; then
            print_success "主服务健康检查通过"
            consecutive_failures=0
        else
            consecutive_failures=$((consecutive_failures + 1))
            print_error "主服务健康检查失败 (连续失败: $consecutive_failures/$max_failures)"
            
            # 收集诊断信息
            if [ $consecutive_failures -eq 1 ]; then
                info_file=$(collect_system_info)
                print_info "系统信息已收集到: $info_file"
            fi
            
            # 检查各个容器状态
            if ! check_container_status "nginx"; then
                print_error "Nginx容器异常，尝试重启..."
                if restart_service "nginx"; then
                    consecutive_failures=0
                fi
            elif ! check_container_status "playwright-1"; then
                print_error "Playwright-1容器异常，尝试重启..."
                if restart_service "playwright-1"; then
                    consecutive_failures=0
                fi
            fi
            
            # 达到最大失败次数，执行完整重启
            if [ $consecutive_failures -ge $max_failures ]; then
                send_notification "CRITICAL" "服务连续失败${max_failures}次，执行完整重启"
                
                if restart_cluster; then
                    consecutive_failures=0
                    send_notification "INFO" "集群重启成功，服务已恢复"
                else
                    send_notification "CRITICAL" "集群重启失败，需要人工干预"
                    print_error "自动恢复失败，退出监控"
                    exit 1
                fi
            fi
        fi
        
        # WebSocket健康检查
        if check_health "websocket" "http://localhost:$EXTERNAL_PORT/ws-health" "$HEALTH_CHECK_TIMEOUT"; then
            print_success "WebSocket端点健康检查通过"
        else
            print_warning "WebSocket端点异常，但主服务正常"
        fi
        
        # 检查资源使用情况
        check_resource_usage
        
        # 等待下一次检查
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

# 检查资源使用情况
check_resource_usage() {
    # 检查内存使用
    local memory_stats=$(docker stats --no-stream --format "{{.Container}}\t{{.MemPerc}}" | grep playwright)
    
    while IFS=$'\t' read -r container mem_perc; do
        if [ -n "$container" ]; then
            # 提取数字部分
            mem_num=$(echo "$mem_perc" | sed 's/%//')
            
            if [ "${mem_num%%.*}" -gt 90 ]; then
                print_warning "容器 $container 内存使用率过高: $mem_perc"
                send_notification "WARNING" "容器 $container 内存使用率: $mem_perc"
            fi
        fi
    done <<< "$memory_stats"
}

# 清理函数
cleanup() {
    print_info "监控服务正在停止..."
    exit 0
}

# 显示帮助信息
show_help() {
    echo "Playwright 服务器监控脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  start         启动监控服务"
    echo "  status        显示当前状态"
    echo "  test          执行一次健康检查"
    echo "  logs          显示监控日志"
    echo "  cleanup       清理日志文件"
    echo "  help          显示此帮助信息"
    echo ""
    echo "环境变量:"
    echo "  HEALTH_CHECK_INTERVAL  健康检查间隔（秒，默认30）"
    echo "  HEALTH_CHECK_RETRIES   重试次数（默认3）"
    echo "  HEALTH_CHECK_TIMEOUT   超时时间（秒，默认10）"
}

# 执行单次健康检查
test_health() {
    load_config
    
    print_info "执行单次健康检查..."
    
    echo "主服务检查:"
    if check_health "main-service" "http://localhost:$EXTERNAL_PORT/health" "$HEALTH_CHECK_TIMEOUT"; then
        print_success "✓ 主服务正常"
    else
        print_error "✗ 主服务异常"
    fi
    
    echo "WebSocket检查:"
    if check_health "websocket" "http://localhost:$EXTERNAL_PORT/ws-health" "$HEALTH_CHECK_TIMEOUT"; then
        print_success "✓ WebSocket正常"
    else
        print_warning "⚠ WebSocket异常"
    fi
    
    echo "容器状态:"
    for container in nginx playwright-1; do
        if check_container_status "$container"; then
            health=$(get_container_health "$container")
            print_success "✓ $container: 运行中 ($health)"
        else
            print_error "✗ $container: 异常"
        fi
    done
    
    echo "资源使用:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
}

# 主函数
main() {
    load_config
    
    # 设置信号处理
    trap cleanup SIGINT SIGTERM
    
    case "${1:-help}" in
        start)
            print_info "启动 Playwright 监控服务..."
            print_info "健康检查间隔: ${HEALTH_CHECK_INTERVAL}秒"
            print_info "按 Ctrl+C 停止监控"
            monitor_loop
            ;;
        test)
            test_health
            ;;
        status)
            if [ -f "$MONITOR_LOG" ]; then
                echo "最近的监控日志:"
                tail -20 "$MONITOR_LOG"
            else
                echo "监控日志不存在"
            fi
            ;;
        logs)
            if [ -f "$MONITOR_LOG" ]; then
                less "$MONITOR_LOG"
            else
                echo "监控日志不存在"
            fi
            ;;
        cleanup)
            rm -f "$MONITOR_LOG" "${MONITOR_LOG}.old" /tmp/playwright-system-info.txt
            print_success "日志文件已清理"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "未知命令: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
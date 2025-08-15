#!/bin/bash

# Playwright Docker 集群启动脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印彩色信息
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

# 检查Docker和Docker Compose
check_requirements() {
    print_info "检查系统要求..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装或不在PATH中"
        exit 1
    fi
    
    if ! docker compose version &> /dev/null; then
        print_error "Docker Compose 未安装或不在PATH中"
        exit 1
    fi
    
    print_success "系统要求检查通过"
}

# 检查环境配置
check_config() {
    print_info "检查配置文件..."
    
    if [ ! -f .env ]; then
        print_warning ".env 文件不存在，将使用默认配置"
    else
        source .env
        if [ "${PLAYWRIGHT_TOKEN}" = "your-secure-token-here" ]; then
            print_warning "检测到默认Token，建议在生产环境中更改"
        fi
    fi
    
    print_success "配置检查完成"
}

# 显示帮助信息
show_help() {
    echo "Playwright Docker 集群管理脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  start [instances]    启动集群 (默认1个实例)"
    echo "  stop                 停止集群"
    echo "  restart              重启集群"
    echo "  status               显示集群状态"
    echo "  logs [service]       显示日志"
    echo "  scale <number>       扩缩容到指定实例数"
    echo "  health               健康检查"
    echo "  monitor              启动自动监控服务"
    echo "  test-health          执行一次健康检查测试"
    echo "  diagnose             诊断问题（显示详细状态和日志）"
    echo "  clean                清理所有容器和网络"
    echo "  help                 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 start           # 启动1个实例"
    echo "  $0 start 3         # 启动3个实例"
    echo "  $0 scale 5         # 扩容到5个实例"
    echo "  $0 logs nginx      # 查看nginx日志"
}

# 生成nginx配置
generate_nginx_config() {
    local instances=${1:-1}
    print_info "生成nginx配置文件 (${instances} 个实例)..."
    
    # 检查模板文件是否存在
    if [ ! -f nginx.conf.template ]; then
        print_error "nginx.conf.template 文件不存在，请检查项目文件"
        exit 1
    fi
    
    # 定义变量替换函数（纯bash实现，不依赖envsubst）
    replace_template_variables() {
        local template_file="$1"
        local output_file="$2"
        local internal_port="$3"
        local allowed_tokens="$4"
        
        # 使用 sed 进行变量替换
        sed -e "s|\${INTERNAL_PORT}|$internal_port|g" \
            -e "s|\${ALLOWED_TOKENS}|$allowed_tokens|g" \
            "$template_file" > "$output_file"
    }
    
    # 读取环境变量
    if [ -f .env ]; then
        source .env
    fi
    
    # 设置默认值
    local internal_port=${INTERNAL_PORT:-3000}
    local allowed_tokens=${ALLOWED_TOKENS:-"default-token"}
    
    # 检查Token配置
    if [ "$allowed_tokens" = "default-token" ]; then
        print_warning "使用默认Token，建议在生产环境中使用 ./token-manager.sh add 生成安全Token"
    fi
    
    # 生成upstream配置
    local upstream_config="    upstream playwright_backend {\n"
    upstream_config+="        server playwright-1:$internal_port max_fails=3 fail_timeout=30s;\n"
    
    # 如果有多个实例，添加worker节点
    if [ "$instances" -gt 1 ]; then
        upstream_config+="        server playwright-worker:$internal_port max_fails=3 fail_timeout=30s;\n"
    fi
    
    upstream_config+="    }"
    
    # 准备所有环境变量
    local worker_connections=${WORKER_CONNECTIONS:-1024}
    local worker_processes=${WORKER_PROCESSES:-auto}
    local rate_limit_zone_size=${RATE_LIMIT_ZONE_SIZE:-10m}
    local rate_limit_rate=${RATE_LIMIT_RATE:-20r/s}
    local rate_limit_burst=${RATE_LIMIT_BURST:-50}
    local proxy_connect_timeout=${PROXY_CONNECT_TIMEOUT:-30}
    local proxy_send_timeout=${PROXY_SEND_TIMEOUT:-300}
    local proxy_read_timeout=${PROXY_READ_TIMEOUT:-600}
    local log_level=${LOG_LEVEL:-info}
    
    # 使用纯bash方式替换环境变量
    sed -e "s|\${INTERNAL_PORT}|$internal_port|g" \
        -e "s|\${ALLOWED_TOKENS}|$allowed_tokens|g" \
        -e "s|\${WORKER_CONNECTIONS}|$worker_connections|g" \
        -e "s|\${WORKER_PROCESSES}|$worker_processes|g" \
        -e "s|\${RATE_LIMIT_ZONE_SIZE}|$rate_limit_zone_size|g" \
        -e "s|\${RATE_LIMIT_RATE}|$rate_limit_rate|g" \
        -e "s|\${RATE_LIMIT_BURST}|$rate_limit_burst|g" \
        -e "s|\${PROXY_CONNECT_TIMEOUT}|$proxy_connect_timeout|g" \
        -e "s|\${PROXY_SEND_TIMEOUT}|$proxy_send_timeout|g" \
        -e "s|\${PROXY_READ_TIMEOUT}|$proxy_read_timeout|g" \
        -e "s|\${LOG_LEVEL}|$log_level|g" \
        nginx.conf.template > nginx.conf.tmp
    
    # 替换upstream配置（支持多实例）
    sed "/upstream playwright_backend {/,/}/c\\
$upstream_config" nginx.conf.tmp > nginx.conf
    
    # 清理临时文件
    rm -f nginx.conf.tmp
    
    print_success "nginx配置已生成 (内部端口: $internal_port, 实例数: $instances)"
    
    # 显示Token信息（安全显示，只显示前12个字符）
    local token_count=$(echo "$allowed_tokens" | tr ',' '\n' | wc -l | tr -d ' ')
    local first_token=$(echo "$allowed_tokens" | cut -d',' -f1)
    print_info "配置的Token数量: $token_count 个，首个Token: ${first_token:0:12}..."
}

# 启动集群
start_cluster() {
    local instances=${1:-1}
    
    print_info "启动 Playwright 集群 (${instances} 个实例)..."
    
    # 生成nginx配置
    generate_nginx_config "$instances"
    
    if [ "$instances" -eq 1 ]; then
        # 先启动playwright-1
        print_info "启动 playwright-1..."
        if ! docker compose up -d playwright-1; then
            print_error "playwright-1 启动失败"
            print_info "查看 playwright-1 日志："
            docker compose logs playwright-1
            exit 1
        fi
        
        # 等待playwright-1就绪并检查状态
        print_info "等待 playwright-1 就绪..."
        for i in {1..12}; do
            if docker compose ps playwright-1 | grep -q "Up"; then
                print_success "playwright-1 启动成功"
                break
            fi
            if [ $i -eq 12 ]; then
                print_error "playwright-1 启动超时"
                print_info "playwright-1 日志："
                docker compose logs playwright-1
                exit 1
            fi
            sleep 5
            print_info "等待中... ($i/12)"
        done
        
        # 再启动nginx
        print_info "启动 nginx..."
        if ! docker compose up -d nginx; then
            print_error "nginx 启动失败"
            print_info "查看 nginx 日志："
            docker compose logs nginx
            exit 1
        fi
        
        # 检查nginx状态
        sleep 3
        if ! docker compose ps nginx | grep -q "Up"; then
            print_error "nginx 未正常运行"
            print_info "nginx 日志："
            docker compose logs nginx
            exit 1
        fi
        
    else
        # 计算worker实例数 (总数-1，因为已有playwright-1)
        local workers=$((instances - 1))
        
        # 先启动playwright-1
        print_info "启动 playwright-1..."
        if ! docker compose up -d playwright-1; then
            print_error "playwright-1 启动失败"
            docker compose logs playwright-1
            exit 1
        fi
        
        # 等待playwright-1就绪
        print_info "等待 playwright-1 就绪..."
        for i in {1..12}; do
            if docker compose ps playwright-1 | grep -q "Up"; then
                break
            fi
            if [ $i -eq 12 ]; then
                print_error "playwright-1 启动超时"
                docker compose logs playwright-1
                exit 1
            fi
            sleep 5
        done
        
        # 启动worker实例
        print_info "启动 $workers 个worker实例..."
        if ! docker compose up -d --scale playwright-worker=$workers playwright-worker; then
            print_error "worker 实例启动失败"
            docker compose logs playwright-worker
            exit 1
        fi
        
        # 等待worker就绪
        print_info "等待 worker 就绪..."
        sleep 10
        
        # 最后启动nginx
        print_info "启动 nginx..."
        if ! docker compose up -d nginx; then
            print_error "nginx 启动失败"
            docker compose logs nginx
            exit 1
        fi
        
        # 检查nginx状态
        sleep 3
        if ! docker compose ps nginx | grep -q "Up"; then
            print_error "nginx 未正常运行"
            docker compose logs nginx
            exit 1
        fi
    fi
    
    print_success "集群启动成功"
    
    # 显示当前状态
    print_info "当前服务状态："
    docker compose ps
    
    print_info "最近的日志："
    docker compose logs --tail=10
    
    # 执行健康检查
    health_check
}

# 停止集群
stop_cluster() {
    print_info "停止 Playwright 集群..."
    docker compose down
    print_success "集群已停止"
}

# 重启集群
restart_cluster() {
    print_info "重启 Playwright 集群..."
    docker compose restart
    print_success "集群重启完成"
}

# 显示状态
show_status() {
    print_info "Playwright 集群状态:"
    docker compose ps
}

# 显示日志
show_logs() {
    local service=$1
    
    if [ -z "$service" ]; then
        print_info "显示所有服务日志:"
        docker compose logs -f
    else
        print_info "显示 ${service} 服务日志:"
        docker compose logs -f "$service"
    fi
}

# 扩缩容
scale_cluster() {
    local target_instances=$1
    
    if [ -z "$target_instances" ] || [ "$target_instances" -lt 1 ]; then
        print_error "实例数量必须大于等于1"
        exit 1
    fi
    
    print_info "扩缩容到 ${target_instances} 个实例..."
    
    # 重新生成nginx配置
    generate_nginx_config "$target_instances"
    
    if [ "$target_instances" -eq 1 ]; then
        # 停止所有worker，只保留playwright-1
        docker compose stop playwright-worker
        docker compose rm -f playwright-worker
        # 重启nginx以应用新配置
        docker compose restart nginx
    else
        # 确保playwright-1运行
        docker compose up -d playwright-1
        # 计算worker实例数
        local workers=$((target_instances - 1))
        docker compose up -d --scale playwright-worker=$workers playwright-worker
        # 重启nginx以应用新配置
        docker compose restart nginx
    fi
    
    print_success "扩缩容完成"
}

# 健康检查
health_check() {
    enhanced_health_check
}

# 诊断问题
diagnose_issues() {
    print_info "🔍 Playwright 集群诊断"
    echo "================================"
    
    # 1. 检查Docker
    print_info "1. Docker 环境检查："
    docker --version
    docker compose version
    echo ""
    
    # 2. 检查容器状态
    print_info "2. 容器状态："
    docker compose ps
    echo ""
    
    # 3. 检查网络
    print_info "3. 网络状态："
    docker network ls | grep playwright
    echo ""
    
    # 4. 检查端口
    print_info "4. 端口占用检查："
    if [ -f .env ]; then
        source .env
        local port=${EXTERNAL_PORT:-3000}
        if netstat -tln 2>/dev/null | grep ":$port "; then
            echo "端口 $port 已占用"
        else
            echo "端口 $port 可用"
        fi
    fi
    echo ""
    
    # 5. 检查配置文件
    print_info "5. 配置文件检查："
    if [ -f nginx.conf ]; then
        echo "✓ nginx.conf 存在"
        echo "upstream 配置："
        grep -A 5 "upstream playwright_backend" nginx.conf
    else
        echo "✗ nginx.conf 缺失"
    fi
    echo ""
    
    # 6. 显示所有日志
    print_info "6. 服务日志："
    echo "--- playwright-1 日志 ---"
    docker compose logs --tail=20 playwright-1 2>/dev/null || echo "playwright-1 未运行"
    echo ""
    echo "--- nginx 日志 ---"
    docker compose logs --tail=20 nginx 2>/dev/null || echo "nginx 未运行"
    echo ""
    
    # 7. 网络连通性测试
    print_info "7. 网络连通性测试："
    if docker compose ps nginx | grep -q "Up" && docker compose ps playwright-1 | grep -q "Up"; then
        echo "测试 nginx -> playwright-1 连接："
        docker compose exec nginx ping -c 2 playwright-1 2>/dev/null || echo "连接失败"
    else
        echo "服务未完全启动，跳过连通性测试"
    fi
    
    echo ""
    print_info "诊断完成！"
}

# 启动监控服务
start_monitor() {
    print_info "启动 Playwright 监控服务..."
    
    # 检查监控脚本是否存在
    if [ ! -f monitor.sh ]; then
        print_error "monitor.sh 脚本不存在"
        print_info "请确保 monitor.sh 文件在当前目录中"
        exit 1
    fi
    
    # 检查服务是否运行
    if ! docker compose ps | grep -q "Up"; then
        print_warning "检测到服务未运行，是否先启动服务？(y/N)"
        read -p "> " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            start_cluster
        else
            print_info "监控需要服务运行才能生效"
        fi
    fi
    
    # 启动监控
    ./monitor.sh start
}

# 执行健康检查测试
test_health_check() {
    print_info "执行健康检查测试..."
    
    if [ ! -f monitor.sh ]; then
        print_error "monitor.sh 脚本不存在"
        exit 1
    fi
    
    ./monitor.sh test
}

# 增强的健康检查
enhanced_health_check() {
    local port=${EXTERNAL_PORT:-3000}
    
    print_info "执行增强健康检查..."
    
    # 1. 基本健康检查
    if curl -s "http://localhost:${port}/health" > /dev/null; then
        print_success "✓ 主服务健康检查通过"
    else
        print_error "✗ 主服务健康检查失败"
        return 1
    fi
    
    # 2. WebSocket健康检查  
    if curl -s "http://localhost:${port}/ws-health" > /dev/null; then
        print_success "✓ WebSocket健康检查通过"
    else
        print_warning "⚠ WebSocket健康检查失败"
    fi
    
    # 3. 容器健康状态
    print_info "容器健康状态："
    for container in playwright-nginx playwright-1; do
        if docker ps --format "{{.Names}}" | grep -q "$container"; then
            local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")
            if [ "$health" = "healthy" ] || [ "$health" = "no-healthcheck" ]; then
                print_success "✓ $container: $health"
            else
                print_warning "⚠ $container: $health"
            fi
        else
            print_error "✗ $container: 未运行"
        fi
    done
    
    # 4. 资源使用检查
    print_info "资源使用情况："
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | head -5
    
    # 5. 网络连通性
    print_info "网络连通性测试："
    if docker compose exec -T nginx ping -c 1 playwright-1 > /dev/null 2>&1; then
        print_success "✓ nginx -> playwright-1 连接正常"
    else
        print_warning "⚠ nginx -> playwright-1 连接异常"
    fi
    
    # 显示访问信息
    echo ""
    print_info "服务访问信息："
    echo "  健康检查: http://localhost:${port}/health"
    echo "  WebSocket: http://localhost:${port}/ws-health" 
    echo "  主服务:   http://localhost:${port}/"
    echo ""
    
    # 如果有Token配置，显示第一个Token
    if [ -f .env ]; then
        source .env
        if [ -n "$ALLOWED_TOKENS" ]; then
            local first_token=$(echo "$ALLOWED_TOKENS" | cut -d',' -f1)
            echo "  测试命令: curl -H \"Authorization: Bearer ${first_token:0:12}...\" http://localhost:${port}/health"
        fi
    fi
}

# 清理
clean_cluster() {
    print_warning "这将删除所有容器、网络和卷"
    read -p "确认继续? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "清理集群资源..."
        docker compose down -v --remove-orphans
        print_success "清理完成"
    else
        print_info "操作已取消"
    fi
}

# 主逻辑
main() {
    check_requirements
    check_config
    
    case "${1:-help}" in
        start)
            start_cluster "$2"
            ;;
        stop)
            stop_cluster
            ;;
        restart)
            restart_cluster
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "$2"
            ;;
        scale)
            scale_cluster "$2"
            ;;
        health)
            health_check
            ;;
        monitor)
            start_monitor
            ;;
        test-health)
            test_health_check
            ;;
        clean)
            clean_cluster
            ;;
        diagnose|diag)
            diagnose_issues
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
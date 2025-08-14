# Playwright Docker 集群部署

基于 Playwright 官方 Docker 镜像的高可用集群部署方案，支持 Token 认证、负载均衡和网络访问控制。

> 📍 **执行位置重要提醒**  
> ✅ **所有管理操作在宿主机执行**（Token管理、扩容、配置等）  
> ❌ **不要进入容器执行管理命令**  
> 📖 详见：[OPERATIONS-GUIDE.md](./OPERATIONS-GUIDE.md) | [QUICK-REFERENCE.md](./QUICK-REFERENCE.md)

## 功能特性

- 🚀 基于官方 Playwright Docker 镜像
- 🔐 多Token认证保护
- ⚖️ Nginx 负载均衡
- 🌐 完全Token认证（支持任何网络）
- 📊 动态集群扩缩容
- 🛡️ Seccomp 安全配置
- 📈 健康检查和监控

## 快速开始

> ⚠️ **重要：所有管理操作都在宿主机上执行，不要进入容器！**

### 1. 生成安全Token

```bash
# 🖥️ 在宿主机执行
./token-manager.sh add server-main
./token-manager.sh add laptop-dev
```

### 2. 启动服务

```bash
# 🖥️ 在宿主机执行
./start.sh start              # 启动1个实例
./start.sh start 3            # 启动3个实例
```

### 3. 验证服务

```bash
# 🖥️ 在宿主机执行
./start.sh health

# 使用生成的Token测试
curl -H "Authorization: Bearer your-generated-token" http://localhost:3000/health
```

## 配置说明

### 集群规模

- **默认**：1个实例（playwright-1）
- **扩展**：最多5个实例（使用 `--profile scale`）

### 网络访问控制

**默认配置**：已禁用IP限制，完全依赖Token认证
- ✅ 任何IP + 有效Token = 允许访问
- ✅ 支持局域网和互联网访问
- ✅ 无需额外配置即可使用

**可选IP白名单**：如需额外IP限制保护

```bash
# 启用IP白名单（仅局域网）
./toggle-internet.sh enable-ip-filter

# 禁用IP限制（默认，推荐）
./toggle-internet.sh disable-ip-filter
```

### 多Token 认证

支持为不同设备配置独立Token，提供更好的安全控制：

**配置多个Token：**
```bash
# 在 .env 文件中配置（逗号分隔）
ALLOWED_TOKENS=laptop-token-abc123,phone-token-def456,tablet-token-ghi789
```

**使用Token认证：**

1. **Header 认证：**
   ```bash
   curl -H "Authorization: Bearer laptop-token-abc123" http://localhost:3000/
   ```

2. **Query 参数：**
   ```bash
   curl "http://localhost:3000/?token=laptop-token-abc123"
   ```

**Token管理：**
```bash
# 🖥️ 在宿主机执行
./token-manager.sh list                    # 查看所有Token
./token-manager.sh add laptop             # 添加新设备Token
./token-manager.sh remove laptop-token-abc123  # 删除Token
./token-manager.sh test your-token        # 测试Token有效性
```

## 管理命令

```bash
# 🖥️ 在宿主机执行 - 推荐使用脚本
./start.sh status         # 查看运行状态
./start.sh logs           # 查看日志
./start.sh stop           # 停止服务
./start.sh restart        # 重启服务
./start.sh scale 3        # 扩容到3个实例

# 🖥️ 在宿主机执行 - 原生Docker命令
docker compose ps                 # 查看容器状态
docker compose logs -f           # 实时查看日志
docker compose down             # 停止所有服务
docker compose restart nginx   # 重启特定服务
```

## 监控和维护

### 健康检查
```bash
# 🖥️ 在宿主机执行
./start.sh health                                    # 使用脚本检查
curl http://localhost:3000/health                   # 直接检查健康端点
```

### 查看服务日志
```bash
# 🖥️ 在宿主机执行
./start.sh logs                     # 查看所有服务日志
./start.sh logs nginx              # 查看nginx日志
./start.sh logs playwright-1       # 查看特定实例日志

# 或使用原生命令
docker compose logs nginx          # 查看nginx日志
docker compose logs playwright-1   # 查看playwright实例日志
```

## 安全建议

1. **使用强Token**：生产环境使用 `./token-manager.sh add` 生成强随机Token
2. **定期轮换Token**：建议定期更新Token增强安全
3. **HTTPS配置**：生产环境建议配置SSL证书
4. **监控访问日志**：定期检查访问记录
5. **最小权限原则**：只为需要的设备分配Token

## 详细部署运维指南

### 📦 Docker Compose 部署

#### 初始部署
```bash
# 1. 克隆或下载项目文件到服务器
cd /opt/playwright-server

# 2. 检查文件结构
ls -la
# 应包含: docker compose.yml, nginx.conf, .env, start.sh, token-manager.sh

# 3. 配置环境变量
cp .env.example .env
nano .env

# 4. 生成设备Token
./token-manager.sh add server-main
./token-manager.sh add laptop-dev  
./token-manager.sh add mobile-test

# 5. 启动服务
./start.sh start

# 6. 验证部署
./start.sh health
```

#### 生产环境部署
```bash
# 1. 创建专用用户
sudo useradd -m -s /bin/bash playwright
sudo usermod -aG docker playwright

# 2. 部署到生产目录
sudo mkdir -p /opt/playwright-server
sudo chown playwright:playwright /opt/playwright-server
cd /opt/playwright-server

# 3. 配置systemd服务
sudo tee /etc/systemd/system/playwright-server.service << EOF
[Unit]
Description=Playwright Server
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/playwright-server
ExecStart=/opt/playwright-server/start.sh start
ExecStop=/usr/bin/docker compose down
User=playwright
Group=playwright

[Install]
WantedBy=multi-user.target
EOF

# 4. 启用服务
sudo systemctl daemon-reload
sudo systemctl enable playwright-server
sudo systemctl start playwright-server
```

### 🔧 集群规模控制

#### 动态扩容
```bash
# 查看当前实例数
docker compose ps

# 扩容到3个实例
./start.sh scale 3

# 扩容到5个实例（最大支持）
./start.sh scale 5

# 实时监控扩容过程
watch -n 2 'docker compose ps'
```

#### 动态缩容
```bash
# 缩容到2个实例
./start.sh scale 2

# 缩容到1个实例（最小配置）
./start.sh scale 1

# 验证缩容结果
docker compose ps | grep playwright
```

#### 手动精细控制
```bash
# 启动特定服务
docker compose up -d nginx playwright-1

# 手动扩展worker实例
docker compose up -d --scale playwright-worker=3 playwright-worker

# 查看详细状态
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# 查看资源使用
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

#### 滚动更新
```bash
# 不停机更新配置
docker compose restart nginx

# 逐个重启worker实例
for i in {1..3}; do
  docker compose restart playwright-worker
  sleep 10
  ./start.sh health
done

# 完整服务更新
docker compose pull
docker compose up -d --force-recreate
```

### 🔑 Token 管理详解

#### Token 生成策略
```bash
# 为不同环境生成Token
./token-manager.sh add prod-server
./token-manager.sh add staging-env
./token-manager.sh add dev-local

# 为特定用户生成Token
./token-manager.sh add user-alice
./token-manager.sh add user-bob

# 为临时访问生成Token
./token-manager.sh add temp-$(date +%Y%m%d)
```

#### Token 维护操作
```bash
# 查看所有Token详情
./token-manager.sh list

# 删除特定Token
./token-manager.sh remove user-alice-241220-abc123

# 删除过期或不用的Token
./token-manager.sh remove temp-20241215

# 批量重新生成Token（安全轮换）
./token-manager.sh regenerate

# 测试Token有效性
./token-manager.sh test prod-server-241220-def456
```

#### Token 安全最佳实践
```bash
# 1. 定期轮换Token（建议每90天）
# 创建轮换脚本
cat > rotate-tokens.sh << 'EOF'
#!/bin/bash
echo "开始Token轮换..."
./token-manager.sh regenerate
echo "重启服务应用新配置..."
docker compose restart nginx
echo "Token轮换完成"
EOF
chmod +x rotate-tokens.sh

# 2. 监控Token使用
tail -f logs/nginx/access.log | grep "Access granted"

# 3. 审计Token访问
docker compose logs nginx | grep "Access granted" | tail -20
```

### 🌐 网络访问配置

#### 端口和防火墙配置
```bash
# 检查端口占用
sudo netstat -tlnp | grep :3000

# 配置防火墙（Ubuntu/Debian）
sudo ufw allow 3000/tcp
sudo ufw reload

# 配置防火墙（CentOS/RHEL）
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --reload

# 测试端口连通性
nc -zv your-server-ip 3000
```

#### SSL/HTTPS 配置
```bash
# 使用Let's Encrypt获取SSL证书
sudo apt install certbot
sudo certbot certonly --standalone -d your-domain.com

# 修改nginx配置支持HTTPS
cat >> nginx-ssl.conf << 'EOF'
server {
    listen 443 ssl;
    server_name your-domain.com;
    
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    location / {
        proxy_pass http://playwright_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF
```

### 📊 监控和日志

#### 服务监控
```bash
# 实时监控服务状态
watch -n 5 './start.sh status'

# 监控容器资源使用
docker stats $(docker compose ps -q)

# 检查服务健康状态
curl -f http://localhost:3000/health || echo "服务异常"

# 监控脚本
cat > monitor.sh << 'EOF'
#!/bin/bash
while true; do
  if ! curl -sf http://localhost:3000/health > /dev/null; then
    echo "$(date): 服务异常，尝试重启..."
    ./start.sh restart
    sleep 30
  fi
  sleep 60
done
EOF
```

#### 日志管理
```bash
# 查看所有服务日志
./start.sh logs

# 查看特定服务日志
./start.sh logs nginx
./start.sh logs playwright-1

# 实时跟踪日志
docker compose logs -f --tail=100

# 日志轮换配置
cat > /etc/logrotate.d/playwright << 'EOF'
/opt/playwright-server/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    copytruncate
    notifempty
}
EOF
```

### 🐍 Python 客户端使用示例

#### 安装依赖
```bash
pip install playwright requests
playwright install
```

#### 局域网访问示例
```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Playwright局域网访问示例
适用于在同一局域网内访问Playwright服务
"""

import asyncio
import os
from playwright.async_api import async_playwright

class PlaywrightLocalClient:
    def __init__(self, server_url="http://192.168.1.100:3000", token=None):
        """
        初始化本地客户端
        
        Args:
            server_url: Playwright服务地址（局域网IP）
            token: 认证Token
        """
        self.server_url = server_url
        self.token = token or os.getenv('PLAYWRIGHT_TOKEN')
        self.ws_endpoint = server_url.replace('http', 'ws')
    
    async def connect_browser(self, browser_type='chromium'):
        """连接到远程浏览器"""
        playwright = await async_playwright().start()
        
        # 获取浏览器类型
        if browser_type == 'chromium':
            browser_launcher = playwright.chromium
        elif browser_type == 'firefox':
            browser_launcher = playwright.firefox
        elif browser_type == 'webkit':
            browser_launcher = playwright.webkit
        else:
            raise ValueError(f"不支持的浏览器类型: {browser_type}")
        
        # 连接到远程浏览器
        browser = await browser_launcher.connect(
            ws_endpoint=self.ws_endpoint,
            headers={'Authorization': f'Bearer {self.token}'}
        )
        
        return playwright, browser
    
    async def simple_screenshot(self, url, output_path="screenshot.png"):
        """简单截图示例"""
        playwright, browser = await self.connect_browser()
        
        try:
            # 创建页面
            context = await browser.new_context()
            page = await context.new_page()
            
            # 访问页面
            print(f"访问页面: {url}")
            await page.goto(url)
            
            # 等待页面加载
            await page.wait_for_load_state('networkidle')
            
            # 截图
            await page.screenshot(path=output_path, full_page=True)
            print(f"截图已保存: {output_path}")
            
            # 获取页面标题
            title = await page.title()
            print(f"页面标题: {title}")
            
            return title
            
        finally:
            await browser.close()
            await playwright.stop()
    
    async def extract_data(self, url, selectors):
        """数据提取示例"""
        playwright, browser = await self.connect_browser()
        
        try:
            context = await browser.new_context()
            page = await context.new_page()
            
            await page.goto(url)
            await page.wait_for_load_state('domcontentloaded')
            
            results = {}
            for name, selector in selectors.items():
                try:
                    element = await page.query_selector(selector)
                    if element:
                        results[name] = await element.text_content()
                    else:
                        results[name] = None
                except Exception as e:
                    results[name] = f"错误: {e}"
            
            return results
            
        finally:
            await browser.close()
            await playwright.stop()

# 使用示例
async def main():
    # 配置客户端
    client = PlaywrightLocalClient(
        server_url="http://192.168.1.100:3000",
        token="laptop-dev-241220-abc123def456"
    )
    
    # 截图示例
    await client.simple_screenshot(
        url="https://example.com",
        output_path="local_example.png"
    )
    
    # 数据提取示例
    data = await client.extract_data(
        url="https://httpbin.org/html",
        selectors={
            "title": "title",
            "heading": "h1",
            "first_paragraph": "p"
        }
    )
    print("提取的数据:", data)

if __name__ == "__main__":
    asyncio.run(main())
```

#### 互联网访问示例
```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Playwright互联网访问示例
适用于从任何网络位置访问Playwright服务
"""

import asyncio
import os
import ssl
from playwright.async_api import async_playwright

class PlaywrightRemoteClient:
    def __init__(self, server_url="https://playwright.yourdomain.com", token=None):
        """
        初始化远程客户端
        
        Args:
            server_url: Playwright服务地址（公网域名或IP）
            token: 认证Token
        """
        self.server_url = server_url
        self.token = token or os.getenv('PLAYWRIGHT_TOKEN')
        
        # 处理WebSocket端点
        if server_url.startswith('https://'):
            self.ws_endpoint = server_url.replace('https://', 'wss://')
        else:
            self.ws_endpoint = server_url.replace('http://', 'ws://')
    
    async def connect_browser_with_retry(self, browser_type='chromium', max_retries=3):
        """带重试机制的浏览器连接"""
        for attempt in range(max_retries):
            try:
                playwright = await async_playwright().start()
                
                if browser_type == 'chromium':
                    browser_launcher = playwright.chromium
                elif browser_type == 'firefox':
                    browser_launcher = playwright.firefox
                elif browser_type == 'webkit':
                    browser_launcher = playwright.webkit
                else:
                    raise ValueError(f"不支持的浏览器类型: {browser_type}")
                
                # 连接配置
                connect_options = {
                    'ws_endpoint': self.ws_endpoint,
                    'headers': {'Authorization': f'Bearer {self.token}'}
                }
                
                # 如果是HTTPS，可能需要处理SSL
                if self.server_url.startswith('https://'):
                    # 对于自签名证书，可以设置忽略SSL错误
                    # connect_options['ignore_https_errors'] = True
                    pass
                
                browser = await browser_launcher.connect(**connect_options)
                print(f"成功连接到远程浏览器 (尝试 {attempt + 1})")
                
                return playwright, browser
                
            except Exception as e:
                print(f"连接失败 (尝试 {attempt + 1}/{max_retries}): {e}")
                if attempt == max_retries - 1:
                    raise
                await asyncio.sleep(2 ** attempt)  # 指数退避
    
    async def batch_screenshots(self, urls, output_dir="screenshots"):
        """批量截图功能"""
        import os
        os.makedirs(output_dir, exist_ok=True)
        
        playwright, browser = await self.connect_browser_with_retry()
        
        try:
            # 创建上下文
            context = await browser.new_context(
                viewport={'width': 1920, 'height': 1080},
                user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            )
            
            results = []
            
            for i, url in enumerate(urls):
                try:
                    print(f"处理 {i+1}/{len(urls)}: {url}")
                    
                    page = await context.new_page()
                    
                    # 设置超时
                    page.set_default_timeout(30000)
                    
                    # 访问页面
                    await page.goto(url, wait_until='networkidle')
                    
                    # 截图文件名
                    filename = f"screenshot_{i+1}_{url.replace('://', '_').replace('/', '_')}.png"
                    filepath = os.path.join(output_dir, filename)
                    
                    # 截图
                    await page.screenshot(path=filepath, full_page=True)
                    
                    # 获取页面信息
                    title = await page.title()
                    
                    results.append({
                        'url': url,
                        'title': title,
                        'screenshot': filepath,
                        'status': 'success'
                    })
                    
                    await page.close()
                    
                except Exception as e:
                    print(f"处理 {url} 时出错: {e}")
                    results.append({
                        'url': url,
                        'error': str(e),
                        'status': 'failed'
                    })
            
            return results
            
        finally:
            await browser.close()
            await playwright.stop()
    
    async def web_scraping_example(self, base_url, pagination_selector=None):
        """网页爬取示例（支持分页）"""
        playwright, browser = await self.connect_browser_with_retry()
        
        try:
            context = await browser.new_context()
            page = await context.new_page()
            
            # 启用请求拦截（可选）
            await page.route("**/*.{jpg,jpeg,png,gif,svg,ico}", lambda route: route.abort())
            
            all_data = []
            current_url = base_url
            page_num = 1
            
            while current_url and page_num <= 10:  # 最多爬取10页
                print(f"爬取第 {page_num} 页: {current_url}")
                
                await page.goto(current_url)
                await page.wait_for_load_state('networkidle')
                
                # 提取数据（根据具体网站调整选择器）
                items = await page.evaluate('''
                    () => {
                        const items = [];
                        // 这里根据具体网站结构调整
                        document.querySelectorAll('.item, .product, .post').forEach(el => {
                            const title = el.querySelector('h1, h2, h3, .title')?.textContent?.trim();
                            const link = el.querySelector('a')?.href;
                            const description = el.querySelector('.description, .summary')?.textContent?.trim();
                            
                            if (title) {
                                items.push({ title, link, description });
                            }
                        });
                        return items;
                    }
                ''')
                
                all_data.extend(items)
                print(f"第 {page_num} 页提取到 {len(items)} 个项目")
                
                # 查找下一页链接
                if pagination_selector:
                    next_link = await page.query_selector(pagination_selector)
                    if next_link:
                        current_url = await next_link.get_attribute('href')
                        if current_url and not current_url.startswith('http'):
                            current_url = base_url + current_url
                    else:
                        break
                else:
                    break
                
                page_num += 1
                await asyncio.sleep(1)  # 礼貌性延迟
            
            return all_data
            
        finally:
            await browser.close()
            await playwright.stop()

# 配置和使用示例
async def main():
    # 配置远程客户端
    client = PlaywrightRemoteClient(
        server_url="https://playwright.yourdomain.com",  # 或 http://your-ip:3000
        token="prod-server-241220-xyz789abc123"
    )
    
    # 批量截图示例
    urls = [
        "https://example.com",
        "https://httpbin.org/html",
        "https://github.com",
    ]
    
    print("开始批量截图...")
    results = await client.batch_screenshots(urls)
    
    print("\n截图结果:")
    for result in results:
        if result['status'] == 'success':
            print(f"✓ {result['url']}: {result['title']}")
        else:
            print(f"✗ {result['url']}: {result['error']}")
    
    # 网页爬取示例
    print("\n开始网页爬取...")
    data = await client.web_scraping_example(
        base_url="https://example.com",
        pagination_selector=".next-page"  # 根据具体网站调整
    )
    
    print(f"爬取完成，共获取 {len(data)} 个项目")
    for item in data[:5]:  # 显示前5个
        print(f"- {item.get('title', 'N/A')}")

if __name__ == "__main__":
    asyncio.run(main())
```

#### 错误处理和重试机制
```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Playwright错误处理和重试机制示例
"""

import asyncio
import time
from playwright.async_api import async_playwright
from typing import Optional, Dict, Any

class RobustPlaywrightClient:
    def __init__(self, server_url: str, token: str):
        self.server_url = server_url
        self.token = token
        self.ws_endpoint = server_url.replace('http', 'ws')
    
    async def execute_with_retry(self, operation, max_retries=3, delay=1):
        """通用重试装饰器"""
        for attempt in range(max_retries):
            try:
                return await operation()
            except Exception as e:
                print(f"操作失败 (尝试 {attempt + 1}/{max_retries}): {e}")
                if attempt == max_retries - 1:
                    raise
                await asyncio.sleep(delay * (2 ** attempt))
    
    async def safe_page_operation(self, url: str, operation_func):
        """安全的页面操作"""
        async def _operation():
            playwright = await async_playwright().start()
            browser = None
            
            try:
                # 连接浏览器
                browser = await playwright.chromium.connect(
                    ws_endpoint=self.ws_endpoint,
                    headers={'Authorization': f'Bearer {self.token}'}
                )
                
                # 创建上下文和页面
                context = await browser.new_context()
                page = await context.new_page()
                
                # 设置超时和错误处理
                page.set_default_timeout(30000)
                
                # 监听页面错误
                page.on("pageerror", lambda error: print(f"页面错误: {error}"))
                page.on("requestfailed", lambda request: print(f"请求失败: {request.url}"))
                
                # 访问页面
                await page.goto(url, wait_until='domcontentloaded')
                
                # 执行自定义操作
                result = await operation_func(page)
                
                return result
                
            finally:
                if browser:
                    await browser.close()
                await playwright.stop()
        
        return await self.execute_with_retry(_operation)
    
    async def health_check(self) -> Dict[str, Any]:
        """健康检查"""
        try:
            import aiohttp
            async with aiohttp.ClientSession() as session:
                headers = {'Authorization': f'Bearer {self.token}'}
                async with session.get(f"{self.server_url}/health", headers=headers) as response:
                    return {
                        'status': 'healthy' if response.status == 200 else 'unhealthy',
                        'status_code': response.status,
                        'response_time': time.time()
                    }
        except Exception as e:
            return {
                'status': 'unhealthy',
                'error': str(e),
                'response_time': time.time()
            }

# 使用示例
async def robust_example():
    client = RobustPlaywrightClient(
        server_url="http://your-server:3000",
        token="your-token"
    )
    
    # 健康检查
    health = await client.health_check()
    print(f"服务健康状态: {health}")
    
    # 安全的页面操作
    async def screenshot_operation(page):
        await page.screenshot(path="robust_example.png")
        return await page.title()
    
    title = await client.safe_page_operation(
        url="https://example.com",
        operation_func=screenshot_operation
    )
    print(f"页面标题: {title}")

if __name__ == "__main__":
    asyncio.run(robust_example())
```

### 🚨 故障排除指南

#### 常见问题诊断
```bash
# 🖥️ 在宿主机执行以下所有诊断命令

# 1. 服务无法启动
./start.sh status                    # 使用脚本检查
docker compose logs                  # 查看详细日志

# 2. Token认证失败
./token-manager.sh test your-token   # 测试Token有效性
curl -H "Authorization: Bearer your-token" http://localhost:3000/health

# 3. 网络连接问题
nc -zv your-server-ip 3000          # 测试端口连通性
ping your-server-ip                  # 测试网络连接

# 4. 资源不足
docker stats                         # 查看容器资源使用
df -h                               # 查看磁盘使用
free -m                             # 查看内存使用

# 5. 端口冲突
sudo netstat -tlnp | grep :3000    # 检查端口占用
sudo lsof -i :3000                 # 查看占用进程
```

#### 性能优化
```bash
# 1. 调整Docker资源限制
# 在docker compose.yml中添加:
cat >> docker compose.yml << 'EOF'
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '1.0'
        reservations:
          memory: 1G
          cpus: '0.5'
EOF

# 2. 优化Nginx配置
# 增加worker进程数
sed -i 's/worker_connections 1024/worker_connections 2048/' nginx.conf

# 3. 调整Playwright设置
# 在.env中添加性能参数
echo "PLAYWRIGHT_BROWSERS_PATH=/tmp/browsers" >> .env
```

#### 备份和恢复
```bash
# 备份配置
tar -czf playwright-backup-$(date +%Y%m%d).tar.gz \
  .env docker compose.yml nginx.conf *.sh

# 恢复配置
tar -xzf playwright-backup-20241220.tar.gz

# 备份Token配置
cp .env .env.backup-$(date +%Y%m%d)

# 数据迁移
scp -r /opt/playwright-server user@new-server:/opt/
```

这个详细指南涵盖了部署、运维、使用的各个方面，你可以根据实际需求参考相应章节。

## 故障排除

### 常见问题

1. **无法访问服务**
   - 检查防火墙设置
   - 验证Token是否正确
   - 确认IP是否在允许范围内

2. **性能问题**
   - 增加实例数量
   - 调整Nginx工作进程数
   - 监控系统资源使用

3. **认证失败**
   - 确认Token格式正确
   - 检查环境变量配置
   - 查看Nginx错误日志

### 日志查看

```bash
# 查看所有服务日志
docker compose logs

# 查看特定服务日志
docker compose logs nginx
docker compose logs playwright-1

# 实时日志
docker compose logs -f
```
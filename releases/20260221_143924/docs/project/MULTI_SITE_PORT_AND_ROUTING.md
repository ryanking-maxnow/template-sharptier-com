# 多站点端口与服务名路由说明

## 1. 背景与结论
在同一台主机上并行运行多个网站时，`3001` 作为 `template-sharptier-cms` 端口是合理且专业的做法。

截至 2026-02-21，本机规划为：
- `/home/sharptier-cms` -> `127.0.0.1:3000`
- `/home/template-sharptier-cms` -> `127.0.0.1:3001`
- 公网统一由 Nginx 监听 `80/443`，按域名转发

这属于常见的“反向代理 + 内网端口分配”模式，适合当前单机运维阶段。

## 2. 单机多站点的标准做法
专业互联网公司的基础原则通常是：
- 公网仅开放 `80/443`
- 应用仅监听 `127.0.0.1:<port>`（不直接暴露公网）
- 按 `server_name` 做域名路由
- 端口分配写入文档与环境变量，不靠口头约定

在本项目中，对应关系是：
- `www.sharptier.com` -> upstream `127.0.0.1:3000`
- `template.sharptier.com` -> upstream `127.0.0.1:3001`

## 3. 为什么站点变多后不建议继续手工维护端口
当站点数量增加时，手工端口管理会出现：
- 端口冲突概率上升（新项目抢占既有端口）
- 配置分散（PM2、Nginx、脚本、文档不同步）
- 扩容困难（一个站点多实例时端口策略复杂化）

因此，大型团队会逐步转向“容器/K8s + 服务名路由”。

## 4. 容器化后如何避免手工端口管理（以两项目为例）
### 4.1 Docker Compose 思路
- `sharptier-cms` 容器内监听 `3000`
- `template-sharptier-cms` 容器内也监听 `3000`
- 网关（Nginx/Traefik）只对外暴露 `80/443`
- 网关按服务名转发：
  - `http://sharptier-cms:3000`
  - `http://template-sharptier-cms:3000`

关键点：两个容器都可以使用 `3000`，因为容器网络隔离，互不冲突。

### 4.2 路由示意
```nginx
upstream sharptier_upstream { server sharptier-cms:3000; }
upstream template_upstream  { server template-sharptier-cms:3000; }

server {
  server_name www.sharptier.com;
  location / { proxy_pass http://sharptier_upstream; }
}

server {
  server_name template.sharptier.com;
  location / { proxy_pass http://template_upstream; }
}
```

这时你维护的是“域名 -> 服务名”，而不是“域名 -> 主机端口号”。

## 5. K8s 模式下的服务名路由
在 Kubernetes 中，常规结构是：
- 每个站点一个 `Deployment`
- 每个站点一个 `Service`（稳定服务名）
- 一个 `Ingress` 按域名转发到对应 `Service`

对应本项目可命名为：
- Service: `sharptier-cms`
- Service: `template-sharptier-cms`

Ingress 仅关心：
- `www.sharptier.com` -> `sharptier-cms`
- `template.sharptier.com` -> `template-sharptier-cms`

不再需要手工规划大量主机端口。

## 6. 建议的演进路线
1. 当前阶段：保持单机 Nginx + PM2，继续使用 `3000/3001`（已稳定）。
2. 下一阶段：把两个项目容器化，内部统一 `3000`，网关按服务名转发。
3. 规模阶段：迁移到 K8s，以 Ingress + Service 做标准化域名路由、扩容和灰度发布。

## 7. 运维注意事项
- 主机层始终只开放 `80/443`，应用端口仅本机回环可访问。
- 端口/服务映射必须同时更新：
  - `shared/deploy.env`
  - PM2 配置
  - Nginx 配置模板
  - 项目文档
- 发布后固定做健康检查：
  - `https://template.sharptier.com/api/health`
  - `https://template.sharptier.com/admin`

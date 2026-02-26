# ISSUE TRACKER

## 当前阶段
- [x] 基于 `reusable-content-example` 初始化项目
- [x] 切换数据库方案为 PostgreSQL
- [x] 迁移并改写运维脚本模板
- [x] 配置域名 `template.sharptier.com`
- [x] 初始化独立数据库
- [ ] 完成线上 DNS 与证书联调
- [ ] 完成首轮真实业务内容导入

## 高优先级
1. 验证公网 DNS 是否已指向当前服务器
2. 验证 443 证书自动签发链路
3. 验证内容发布后前台 on-demand revalidation 的实时性

## 已解决
1. 官方示例默认 MongoDB，不符合当前部署体系
   - 处理：改为 PostgreSQL 适配器并落地新数据库

2. 原脚本依赖 Astro 双发布目录
   - 处理：改为单应用发布脚本（仅 Payload + Next）

3. 原文档路径与域名不一致
   - 处理：统一改为 `/home/template-sharptier-cms` 与 `template.sharptier.com`

## 待观察
1. Nginx ACME 模块在当前机器的兼容性
2. 大版本升级（Payload / Next）后迁移脚本兼容性

## 变更记录
- 2026-02-21：项目初始化、脚本迁移与文档重写。

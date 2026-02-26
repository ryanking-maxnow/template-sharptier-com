#!/bin/bash

# ============================================
# 设置 16GB Swap 虚拟内存
# Setup 16GB Swap Virtual Memory
# ============================================

set -e

SWAP_SIZE="16G"
SWAP_FILE="/swapfile"

echo "======================================"
echo "🔧 设置 ${SWAP_SIZE} 虚拟内存 (Swap)"
echo "======================================"

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误: 请使用 root 权限运行此脚本"
    echo "   使用: sudo bash $0"
    exit 1
fi

# 检查是否已存在 swap 文件
if [ -f "$SWAP_FILE" ]; then
    echo "⚠️  发现已存在的 swap 文件"
    echo "   正在关闭并删除旧的 swap..."
    swapoff "$SWAP_FILE" 2>/dev/null || true
    rm -f "$SWAP_FILE"
fi

# 显示当前内存和 swap 状态
echo ""
echo "📊 当前内存状态:"
free -h

echo ""
echo "📝 创建 ${SWAP_SIZE} swap 文件..."
# 使用 fallocate 快速创建文件（更快）
# 如果 fallocate 不支持，则使用 dd
if ! fallocate -l 16G "$SWAP_FILE" 2>/dev/null; then
    echo "   使用 dd 命令创建..."
    dd if=/dev/zero of="$SWAP_FILE" bs=1G count=16 status=progress
fi

echo "🔒 设置文件权限..."
chmod 600 "$SWAP_FILE"

echo "⚙️  格式化 swap 文件..."
mkswap "$SWAP_FILE"

echo "✅ 启用 swap..."
swapon "$SWAP_FILE"

# 验证 swap 是否已启用
if swapon --show | grep -q "$SWAP_FILE"; then
    echo ""
    echo "✅ Swap 已成功启用!"
    echo ""
    echo "📊 更新后的内存状态:"
    free -h
    echo ""
    echo "📋 Swap 详情:"
    swapon --show
else
    echo "❌ Swap 启用失败"
    exit 1
fi

# 配置系统自动挂载 swap
echo ""
echo "📝 配置系统启动时自动挂载 swap..."

# 备份 fstab
cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)

# 检查 fstab 是否已包含 swap 配置
if grep -q "$SWAP_FILE" /etc/fstab; then
    echo "   fstab 中已存在 swap 配置"
else
    echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab
    echo "   已添加到 /etc/fstab"
fi

# 优化 swap 使用策略
echo ""
echo "⚙️  优化 swap 性能参数..."
echo "   设置 swappiness = 10 (仅在内存不足时使用 swap)"

# 临时设置
sysctl vm.swappiness=10

# 永久设置
if grep -q "^vm.swappiness" /etc/sysctl.conf; then
    sed -i 's/^vm.swappiness.*/vm.swappiness=10/' /etc/sysctl.conf
else
    echo "vm.swappiness=10" >> /etc/sysctl.conf
fi

echo "   设置 vfs_cache_pressure = 50 (减少缓存回收压力)"
sysctl vm.vfs_cache_pressure=50

if grep -q "^vm.vfs_cache_pressure" /etc/sysctl.conf; then
    sed -i 's/^vm.vfs_cache_pressure.*/vm.vfs_cache_pressure=50/' /etc/sysctl.conf
else
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
fi

echo ""
echo "======================================"
echo "✅ 虚拟内存设置完成!"
echo "======================================"
echo ""
echo "💡 提示:"
echo "   - Swap 大小: 16GB"
echo "   - Swap 文件: $SWAP_FILE"
echo "   - 已配置开机自动挂载"
echo "   - Swappiness: 10 (优先使用物理内存)"
echo ""
echo "📋 查看状态命令:"
echo "   free -h          # 查看内存和 swap"
echo "   swapon --show    # 查看 swap 详情"
echo "   htop             # 实时监控"
echo ""

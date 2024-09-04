#!/bin/bash

# 获取当前脚本的绝对路径
SCRIPT_PATH=$(realpath "$0")

# 保存流量数据的文件
TRAFFIC_FILE="/var/tmp/network_traffic.dat"
CURRENT_MONTH=$(date +"%Y-%m")
SHUTDOWN_THRESHOLD=$((9 * 1024 * 1024 * 1024 + 512 * 1024 * 1024))  # 9.5GB 转换为字节的整数表示

# 自动检测活跃的网络接口（排除 lo 环回接口）
INTERFACES=$(ls /sys/class/net | grep -v lo)

# 如果流量文件不存在或者月份不同，则创建并初始化
if [ ! -f $TRAFFIC_FILE ]; then
    echo "$CURRENT_MONTH 0 0" > $TRAFFIC_FILE
else
    saved_month=$(awk '{print $1}' $TRAFFIC_FILE)
    if [ "$saved_month" != "$CURRENT_MONTH" ]; then
        echo "$CURRENT_MONTH 0 0" > $TRAFFIC_FILE
    fi
fi

# 读取之前的接收和发送累计流量
read saved_month last_total_in last_total_out < $TRAFFIC_FILE

# 初始化本次启动后的累计流量
current_total_in=0
current_total_out=0

# 遍历每个接口，获取并输出流量信息
for INTERFACE in $INTERFACES; do
    # 获取当前接收和发送的字节数
    in_bytes=$(cat /proc/net/dev | grep $INTERFACE | awk '{print $2}')
    out_bytes=$(cat /proc/net/dev | grep $INTERFACE | awk '{print $10}')

    # 本次启动后的累计流量
    current_total_in=$((current_total_in + in_bytes))
    current_total_out=$((current_total_out + out_bytes))
done

# 计算启动前后的累计流量
total_in=$((last_total_in + current_total_in))
total_out=$((last_total_out + current_total_out))
total_bytes=$((total_in + total_out))

# 检查是否达到9.5GB的阈值
if [ "$total_bytes" -ge "$SHUTDOWN_THRESHOLD" ]; then
    echo "总流量已达到 9.5GB，系统即将关机..."
    sudo shutdown -h now
fi

# 自适应单位输出
if [ $total_bytes -lt 1024 ]; then
    total="$total_bytes bytes"
elif [ $total_bytes -lt $((1024 * 1024)) ]; then
    total=$(echo "scale=2; $total_bytes / 1024" | bc)
    total="$total KB"
elif [ $total_bytes -lt $((1024 * 1024 * 1024)) ]; then
    total=$(echo "scale=2; $total_bytes / 1024 / 1024" | bc)
    total="$total MB"
else
    total=$(echo "scale=2; $total_bytes / 1024 / 1024 / 1024" | bc)
    total="$total GB"
fi

# 输出结果
echo "In+Out Total This Month: $total"
echo "------------------------------"

# 将累计的流量数据保存到文件
echo "$CURRENT_MONTH $total_in $total_out" > $TRAFFIC_FILE

# 检查是否已经存在cron任务
CRON_CMD="*/5 * * * * $SCRIPT_PATH"
(crontab -l | grep -F "$CRON_CMD") || {
    # 尝试添加cron任务，并捕获错误
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab - 2>/tmp/cron_error.log

    # 检查是否出现了权限错误
    if grep -q "you are not allowed to use this program" /tmp/cron_error.log; then
        echo "无法添加定时任务：没有权限。请以root用户或管理员权限运行此脚本。" >&2
    elif grep -q "permission denied" /tmp/cron_error.log; then
        echo "无法添加定时任务：权限被拒绝。请以root用户或管理员权限运行此脚本。" >&2
    fi

    # 删除错误日志
    rm -f /tmp/cron_error.log
}

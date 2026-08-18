#!/system/bin/sh
# 开机写入限频（等待 boot 完成后执行一次，写入后锁定权限）
MODDIR=${0%/*}
LOG_FILE="$MODDIR/运行日志.log"

# 等待系统启动完成
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 3
done
sleep 10

CONFIG_FILE="$MODDIR/config/freq.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

. "$MODDIR/common.sh"
SOC=$(detect_soc)

case "$SOC" in
    g3)
        P01_FREQ="${P01_FREQ:-1132800}"
        P24_FREQ="${P24_FREQ:-1920000}"
        P56_FREQ="${P56_FREQ:-960000}"
        P7_FREQ="${P7_FREQ:-1939200}"
        GPU_FREQ="${GPU_FREQ:-578000000}"
        ;;
    e8)
        P0_FREQ="${P0_FREQ:-1996800}"
        P6_FREQ="${P6_FREQ:-1689600}"
        GPU_FREQ="${GPU_FREQ:-607000000}"
        ;;
esac

apply_limits
ok=$?

{
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] 开机限频完成 (SOC=$SOC)，成功写入 $ok 个节点"
    case "$SOC" in
        g3)
            echo "  policy0(cpu0-1): $P01_FREQ kHz"
            echo "  policy2(cpu2-4): $P24_FREQ kHz"
            echo "  policy5(cpu5-6): $P56_FREQ kHz"
            echo "  policy7(cpu7):   $P7_FREQ kHz"
            ;;
        e8)
            echo "  policy0(cpu0-5): $P0_FREQ kHz"
            echo "  policy6(cpu6-7): $P6_FREQ kHz"
            ;;
    esac
    echo "  GPU(max_gpuclk): $GPU_FREQ Hz"
} >> "$LOG_FILE" 2>/dev/null

exit 0

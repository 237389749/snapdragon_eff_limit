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
    b62)
        B0_FREQ="${B0_FREQ:-1305600}"
        B4_FREQ="${B4_FREQ:-1536000}"
        GPU_FREQ="${GPU_FREQ:-465000000}"
        ;;
    8p)
        C0_FREQ="${C0_FREQ:-1132800}"
        C4_FREQ="${C4_FREQ:-1881600}"
        C7_FREQ="${C7_FREQ:-1996800}"
        GPU_FREQ="${GPU_FREQ:-580000000}"
        ;;
    8g1)
        D0_FREQ="${D0_FREQ:-1401600}"
        D4_FREQ="${D4_FREQ:-1766400}"
        D7_FREQ="${D7_FREQ:-1900800}"
        GPU_FREQ="${GPU_FREQ:-491000000}"
        ;;
    8g2)
        E0_FREQ="${E0_FREQ:-1555200}"
        E3_FREQ="${E3_FREQ:-2054400}"
        E7_FREQ="${E7_FREQ:-2092800}"
        GPU_FREQ="${GPU_FREQ:-475000000}"
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
        b62)
            echo "  policy0(cpu0-3): $B0_FREQ kHz"
            echo "  policy4(cpu4-7): $B4_FREQ kHz"
            ;;
        8p)
            echo "  policy0(cpu0-3): $C0_FREQ kHz"
            echo "  policy4(cpu4-6): $C4_FREQ kHz"
            echo "  policy7(cpu7):   $C7_FREQ kHz"
            ;;
        8g1)
            echo "  policy0(cpu0-3): $D0_FREQ kHz"
            echo "  policy4(cpu4-6): $D4_FREQ kHz"
            echo "  policy7(cpu7):   $D7_FREQ kHz"
            ;;
        8g2)
            echo "  policy0(cpu0-2): $E0_FREQ kHz"
            echo "  policy3(cpu3-6): $E3_FREQ kHz"
            echo "  policy7(cpu7):   $E7_FREQ kHz"
            ;;
    esac
    echo "  GPU(max_gpuclk): $GPU_FREQ Hz"
} >> "$LOG_FILE" 2>/dev/null

exit 0

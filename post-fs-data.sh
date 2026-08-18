#!/system/bin/sh
# 早期尽力写入一次（此阶段 cpufreq 节点可能未就绪，未生效时由 service.sh 补写）
MODDIR=${0%/*}
CONFIG_FILE="$MODDIR/config/freq.conf"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

[ -f "$MODDIR/common.sh" ] && . "$MODDIR/common.sh"
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
exit 0

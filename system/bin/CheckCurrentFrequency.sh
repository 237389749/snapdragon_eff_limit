#!/system/bin/sh
# 查看当前各集群与 GPU 的频率限制 / 实时频率（一次性输出，自动识别机型）
SOC=$(cat /sys/devices/soc0/chip_id 2>/dev/null | tr -d '\n\r')
case "$SOC" in
    SM8650) POLICIES="0 2 5 7"; TITLE="骁龙8Gen3 频率状态" ;;
    SM8750) POLICIES="0 6";     TITLE="骁龙8Elite 频率状态" ;;
    *)      POLICIES="0 2 5 7"; TITLE="频率状态 (未识别机型, 按8G3显示)" ;;
esac

echo "======================================"
echo "  $TITLE (policy: $POLICIES)"
echo "======================================"
for p in $POLICIES; do
    d=/sys/devices/system/cpu/cpufreq/policy$p
    [ -d "$d" ] || continue
    rel=$(cat "$d/related_cpus" 2>/dev/null)
    max=$(cat "$d/scaling_max_freq" 2>/dev/null)
    cur=$(cat "$d/scaling_cur_freq" 2>/dev/null)
    gov=$(cat "$d/scaling_governor" 2>/dev/null)
    max_m="?"; cur_m="?"
    [ -n "$max" ] && max_m=$((max/1000))
    [ -n "$cur" ] && cur_m=$((cur/1000))
    echo "policy$p (cpu$rel):"
    echo "  限频上限: ${max_m} MHz   实时: ${cur_m} MHz   governor: $gov"
done
echo "--------------------------------------"
g=/sys/class/kgsl/kgsl-3d0
if [ -d "$g" ]; then
    gmax=$(cat "$g/max_gpuclk" 2>/dev/null)
    gcur=$(cat "$g/gpuclk" 2>/dev/null)
    gmax_m="?"; gcur_m="?"
    [ -n "$gmax" ] && gmax_m=$((gmax/1000000))
    [ -n "$gcur" ] && gcur_m=$((gcur/1000000))
    echo "GPU (Adreno):"
    echo "  限频上限: ${gmax_m} MHz   实时: ${gcur_m} MHz"
fi
echo "======================================"

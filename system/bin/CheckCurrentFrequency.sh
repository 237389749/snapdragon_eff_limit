#!/system/bin/sh
# 查看当前各集群与 GPU 的频率限制 / 实时频率（一次性输出，自动识别机型）
# 多来源识别：chip_id / soc.model → platform/machine → policy 节点探测
ID=$(cat /sys/devices/soc0/chip_id 2>/dev/null | tr -d '\n\r')
SMODEL=$(getprop ro.soc.model 2>/dev/null)
PLAT=$(getprop ro.board.platform 2>/dev/null)
MACHINE=$(cat /sys/devices/soc0/machine 2>/dev/null)
# 888 与 8Gen1 必须靠 machine 区分（都是 taro 世代 1+3+4），所以 machine 优先
case "$MACHINE" in
    SM8350|SM8350-AC|lahaina|LAHAINA) SOC="8g1" ;;
    SM8450|SM8475|CAPE|cape) SOC="8p" ;;
    SM8550|SM_KAILUA|kailua|KAILUA|kalama|KALAMA) SOC="8g2" ;;
    *) SOC="" ;;
esac
if [ -z "$SOC" ]; then
case "$ID" in
    SM8650|SM_LANAI|SM_PINEAPPLE) SOC="g3" ;;
    SM8750|SM_SUN) SOC="e8" ;;
    SM8350|SM8350-AC|SM_LAHAINA) SOC="8g1" ;;
    SM8550|SM_KALAMA|SM_KAILUA) SOC="8g2" ;;
    SM8475|SM8450|SM_CAPE) SOC="8p" ;;
    *)
        case "$SMODEL" in
            SM8350|SM8350-AC) SOC="8g1"; ;;
            SM8550) SOC="8g2"; ;;
            SM8475|SM8450) SOC="8p"; ;;
            *)
                case "$PLAT|$MACHINE" in
                    pineapple*|*PINEAPPLE*) SOC="g3" ;;
                    sun*|*SUN*) SOC="e8" ;;
                    bengal*|*BENGAL*) SOC="b62" ;;
                    lahaina*|*LAHAINA*) SOC="8g1" ;;
                    kalama*|*KALAMA*|kailua*|*KAILUA*) SOC="8g2" ;;
                    taro*|*TARO*|cape*|*CAPE*) SOC="8p" ;;
                    *)
                        if [ -d /sys/devices/system/cpu/cpufreq/policy2 ]; then SOC="g3"
                        elif [ -d /sys/devices/system/cpu/cpufreq/policy6 ]; then SOC="e8"
                        elif [ -d /sys/devices/system/cpu/cpufreq/policy3 ]; then SOC="8g2"
                        elif [ -d /sys/devices/system/cpu/cpufreq/policy4 ]; then
                            case "$(cat /sys/devices/system/cpu/cpufreq/policy4/related_cpus 2>/dev/null)" in
                                *" 6 "*) SOC="8p" ;;
                                *) SOC="b62" ;;
                            esac
                        else SOC="unknown"; fi
                        ;;
                esac
                ;;
        esac
        ;;
esac
fi
case "$SOC" in
    g3) POLICIES="0 2 5 7"; TITLE="骁龙8Gen3 频率状态" ;;
    e8) POLICIES="0 6";     TITLE="骁龙8Elite 频率状态" ;;
    b62) POLICIES="0 4";    TITLE="骁龙662 频率状态" ;;
    8p) POLICIES="0 4 7";   TITLE="骁龙8/8+Gen1 频率状态" ;;
    8g1) POLICIES="0 4 7";  TITLE="骁龙888/888+ 频率状态" ;;
    8g2) POLICIES="0 3 7";  TITLE="骁龙8Gen2 频率状态" ;;
    *)  POLICIES="";        TITLE="频率状态 (未识别机型)" ;;
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
    # 实际生效上限：kgsl 会按 max_pwrlevel 换算出 devfreq/max_freq，
    # 而 max_gpuclk 可能被热控/系统服务回写成一个更高的显示值（不构成约束），
    # 所以优先用 devfreq/max_freq 判定真实天花板。
    geff=$(cat "$g/devfreq/max_freq" 2>/dev/null)
    [ -n "$geff" ] || geff="$gmax"
    gpwr=$(cat "$g/max_pwrlevel" 2>/dev/null)
    gcur=$(cat "$g/gpuclk" 2>/dev/null)
    gmax_m="?"; geff_m="?"; gcur_m="?"
    [ -n "$gmax" ] && gmax_m=$((gmax/1000000))
    [ -n "$geff" ] && geff_m=$((geff/1000000))
    [ -n "$gcur" ] && gcur_m=$((gcur/1000000))
    echo "GPU (Adreno):"
    echo "  实际上限: ${geff_m} MHz   (max_pwrlevel=${gpwr:-?}, max_gpuclk=${gmax_m} MHz)"
    echo "  实时: ${gcur_m} MHz"
fi
echo "======================================"

#!/system/bin/sh
# ============================================================
#  骁龙8Gen3 / 8Elite 能效限频 - 公共函数库
#  被 post-fs-data.sh / service.sh source 使用
#
#  detect_soc 输出：
#    g3 = 骁龙8Gen3 (SM8650): policy0(cpu0-1) policy2(cpu2-4)
#                             policy5(cpu5-6) policy7(cpu7)
#    e8 = 骁龙8Elite (SM8750): policy0(cpu0-5) policy6(cpu6-7)
# ============================================================

# 检测芯片型号，输出 g3 / e8 / unknown
# 多来源检测（兼容不同系统 chip_id 格式）：
#   1) chip_id 精确/代号匹配  2) ro.board.platform  3) CPU policy 节点探测
detect_soc() {
    local id="" plat="" rel=""
    if [ -f /sys/devices/soc0/chip_id ]; then
        id=$(cat /sys/devices/soc0/chip_id 2>/dev/null | tr -d '\n\r')
    fi
    # 1) chip_id 精确匹配 + 平台代号匹配（SM_LANAI / SM_PINEAPPLE = 8G3，SM_SUN = 8E）
    case "$id" in
        SM8650|SM_LANAI|SM_PINEAPPLE) echo "g3"; return 0 ;;
        SM8750|SM_SUN) echo "e8"; return 0 ;;
    esac
    # 2) 平台代号（pineapple=8G3，sun=8E）
    plat=$(getprop ro.board.platform 2>/dev/null)
    case "$plat" in
        pineapple) echo "g3"; return 0 ;;
        sun) echo "e8"; return 0 ;;
    esac
    # 3) CPU policy 节点探测兜底：8G3 有 policy7（无 policy6），8E 有 policy6（无 policy7）
    if [ -d /sys/devices/system/cpu/cpufreq/policy7 ]; then
        echo "g3"; return 0
    fi
    if [ -d /sys/devices/system/cpu/cpufreq/policy6 ]; then
        rel=$(cat /sys/devices/system/cpu/cpufreq/policy6/related_cpus 2>/dev/null)
        case " $rel " in
            *" 6 "*|*" 7 "*) echo "e8"; return 0 ;;
        esac
    fi
    echo "unknown"
}

# 取「≤ 目标值」的最大可用档位；无可用表则原样返回
# $1: 可用频率节点(如 scaling_available_frequencies), $2: 目标频率
align_freq() {
    local avail_file="$1" target="$2" list f best="" lowest=""
    # 目标必须为纯数字
    case "$target" in
        ''|*[!0-9]*) echo "$target"; return 0 ;;
    esac
    [ -f "$avail_file" ] || { echo "$target"; return 0; }
    list=$(cat "$avail_file" 2>/dev/null | tr ',' ' ')
    [ -z "$list" ] && { echo "$target"; return 0; }
    for f in $list; do
        case "$f" in *[!0-9]*) continue ;; esac
        if [ -z "$lowest" ] || [ "$f" -lt "$lowest" ]; then
            lowest="$f"
        fi
        if [ "$f" -le "$target" ]; then
            if [ -z "$best" ] || [ "$f" -gt "$best" ]; then
                best="$f"
            fi
        fi
    done
    # 目标低于最低档时取最低档
    [ -n "$best" ] && echo "$best" || echo "$lowest"
}

# 写入并锁定节点：先 644 写入，成功后再锁 444 防止被覆盖
# $1: 节点路径, $2: 写入值
write_lock() {
    local node="$1" val="$2"
    [ -f "$node" ] || return 1
    chmod 644 "$node" 2>/dev/null
    if ! echo "$val" > "$node" 2>/dev/null; then
        chmod 444 "$node" 2>/dev/null
        return 1
    fi
    sync
    chmod 444 "$node" 2>/dev/null
    return 0
}

# 唤醒所有核心
wake_cpus() {
    local cpu
    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        [ -f "$cpu/online" ] && echo 1 > "$cpu/online" 2>/dev/null
    done
}

# ---- 骁龙8Gen3 (SM8650)：4 集群 ----
# 依赖变量：P01_FREQ / P24_FREQ / P56_FREQ / P7_FREQ
apply_g3() {
    local ok=0 v
    # policy0: cpu0-1 小核 A520
    if [ -d /sys/devices/system/cpu/cpufreq/policy0 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies "$P01_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    # policy2: cpu2-4 中核 A720 高频版
    if [ -d /sys/devices/system/cpu/cpufreq/policy2 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy2/scaling_available_frequencies "$P24_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy2/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    # policy5: cpu5-6 中核 A720 低频版（锁低频，防止拉高 X4 电压）
    if [ -d /sys/devices/system/cpu/cpufreq/policy5 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy5/scaling_available_frequencies "$P56_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy5/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    # policy7: cpu7 大核 X4
    if [ -d /sys/devices/system/cpu/cpufreq/policy7 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy7/scaling_available_frequencies "$P7_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    return $ok
}

# ---- 骁龙8Elite (SM8750)：2 集群 ----
# 依赖变量：P0_FREQ / P6_FREQ
apply_e8() {
    local ok=0 v
    # policy0: cpu0-5 大核
    if [ -d /sys/devices/system/cpu/cpufreq/policy0 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies "$P0_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    # policy6: cpu6-7 超大核（能效黑洞，锁低频）
    if [ -d /sys/devices/system/cpu/cpufreq/policy6 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy6/scaling_available_frequencies "$P6_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    return $ok
}

# GPU: Adreno (两平台共用节点，依赖变量 GPU_FREQ)
# 双保险：1) 写 max_gpuclk（旧系统/无 perf 接管时有效）
#         2) 写 max_pwrlevel（新系统 perf 接管 max_gpuclk 时依然有效，实测有效）
#            max_pwrlevel = 允许的最高功耗档索引(0=最高频档)，从 freq_table_mhz 降序表计算
apply_gpu() {
    local v idx f mhz ok1=0 ok2=0 g=/sys/class/kgsl/kgsl-3d0
    [ -d "$g" ] || { echo 0; return; }
    # 1) max_gpuclk
    v=$(align_freq "$g/gpu_available_frequencies" "$GPU_FREQ")
    write_lock "$g/max_gpuclk" "$v" && ok1=1
    # 2) max_pwrlevel：在降序档位表中找「≤ 目标」的第一档，其索引即上限档
    idx=0
    if [ -f "$g/freq_table_mhz" ]; then
        for f in $(cat "$g/freq_table_mhz" 2>/dev/null | tr ',' ' '); do
            case "$f" in *[!0-9]*) continue ;; esac
            [ $((f * 1000000)) -le "$GPU_FREQ" ] && break
            idx=$((idx+1))
        done
        write_lock "$g/max_pwrlevel" "$idx" && ok2=1
    fi
    [ "$ok1" = "1" ] || [ "$ok2" = "1" ] && echo 1 || echo 0
}

# 按 SOC 应用全部限频，返回成功写入的节点数
# 依赖外部变量：SOC（g3/e8）+ 对应平台频率变量 + GPU_FREQ
apply_limits() {
    local ok=0 gpu_ok
    wake_cpus
    case "$SOC" in
        g3) apply_g3; ok=$? ;;
        e8) apply_e8; ok=$? ;;
        *) return 0 ;;
    esac
    gpu_ok=$(apply_gpu)
    [ "$gpu_ok" = "1" ] && ok=$((ok+1))
    return $ok
}

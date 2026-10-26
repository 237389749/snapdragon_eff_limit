#!/system/bin/sh
# ============================================================
#  骁龙多平台能效限频 - 公共函数库
#  被 post-fs-data.sh / service.sh source 使用
#
#  detect_soc 输出：
#    g3  = 骁龙8Gen3 (SM8650): policy0(cpu0-1) policy2(cpu2-4)
#                              policy5(cpu5-6) policy7(cpu7)
#    e8  = 骁龙8Elite (SM8750): policy0(cpu0-5) policy6(cpu6-7)
#    b62 = 骁龙662 (bengal):   policy0(cpu0-3) policy4(cpu4-7)
#    8p  = 骁龙8/8+Gen1 (SM8450/SM8475, cape/taro):
#                              policy0(cpu0-3) policy4(cpu4-6) policy7(cpu7)
#    8g1 = 骁龙888/888+ (SM8350/SM8350-AC, lahaina):
#                              policy0(cpu0-3) policy4(cpu4-6) policy7(cpu7)
#    8g2 = 骁龙8Gen2 (SM8550, kalama/kailua):
#                              policy0(cpu0-2) policy3(cpu3-6) policy7(cpu7)
# ============================================================

# 检测芯片型号，输出 g3 / e8 / b62 / 8p / 8g1 / 8g2 / unknown
# 多来源检测（兼容不同系统 chip_id 格式）：
#   1) chip_id / soc.model  2) ro.board.platform / soc machine  3) CPU policy 节点探测
#
# ⚠️ 骁龙888 与 8Gen1 都是 taro 世代、都是 policy0(4核)+policy4(3核)+policy7(1核)，
#    唯一可靠区别是 soc machine：LAHAINA=888，CAPE=8+Gen1；chip_id/model 上
#    SM8350/SM8350-AC=888，SM8450/SM8475=8Gen1。因此 888 必须放在 8p 之前判。
detect_soc() {
    local id="" plat="" rel="" machine="" smodel=""
    # 0) soc machine 优先（888 与 8Gen1 靠它区分，且部分内核禁止读 cpus/ 节点）
    machine=$(cat /sys/devices/soc0/machine 2>/dev/null)
    case "$machine" in
        SM8350|SM8350-AC|lahaina|LAHAINA) echo "8g1"; return 0 ;;
        SM8450|SM8475|CAPE|cape) echo "8p"; return 0 ;;
        SM8550|SM_KAILUA|kailua|KAILUA|kalama|KALAMA) echo "8g2"; return 0 ;;
        BENGAL|bengal) echo "b62"; return 0 ;;
    esac
    if [ -f /sys/devices/soc0/chip_id ]; then
        id=$(cat /sys/devices/soc0/chip_id 2>/dev/null | tr -d '\n\r')
    fi
    # 1) chip_id 精确匹配 + 平台代号匹配（SM_LANAI / SM_PINEAPPLE = 8G3，SM_SUN = 8E）
    case "$id" in
        SM8650|SM_LANAI|SM_PINEAPPLE) echo "g3"; return 0 ;;
        SM8750|SM_SUN) echo "e8"; return 0 ;;
        SM8350|SM8350-AC|SM_LAHAINA) echo "8g1"; return 0 ;;
        SM8550|SM_KALAMA|SM_KAILUA) echo "8g2"; return 0 ;;
        SM8475|SM8450|SM_CAPE) echo "8p"; return 0 ;;
    esac
    # 1.5) soc.model（部分设备 chip_id 为空但 soc.model 有值，如小米12S）
    smodel=$(getprop ro.soc.model 2>/dev/null)
    case "$smodel" in
        SM8350|SM8350-AC) echo "8g1"; return 0 ;;
        SM8550) echo "8g2"; return 0 ;;
        SM8475|SM8450) echo "8p"; return 0 ;;
    esac
    # 2) 平台代号（pineapple=8G3，sun=8E，bengal=骁龙662，lahaina=888，taro=骁龙8/8+Gen1，kalama=8Gen2）
    plat=$(getprop ro.board.platform 2>/dev/null)
    case "$plat" in
        pineapple) echo "g3"; return 0 ;;
        sun) echo "e8"; return 0 ;;
        bengal) echo "b62"; return 0 ;;
        lahaina) echo "8g1"; return 0 ;;
        kalama|kailua) echo "8g2"; return 0 ;;
        taro) echo "8p"; return 0 ;;
    esac
    # 3) CPU policy 节点探测兜底：
    #    8G3 有 policy2；8E 有 policy6；8Gen1/888 有 policy4(cpu4-6)+policy7（8核1+3+4）
    #    8Gen2 有 policy3(cpu3-6)+policy7（8核3+4+1）——policy3 是它独有的标志
    if [ -d /sys/devices/system/cpu/cpufreq/policy2 ]; then
        echo "g3"; return 0
    fi
    if [ -d /sys/devices/system/cpu/cpufreq/policy6 ]; then
        rel=$(cat /sys/devices/system/cpu/cpufreq/policy6/related_cpus 2>/dev/null)
        case " $rel " in
            *" 6 "*|*" 7 "*) echo "e8"; return 0 ;;
        esac
    fi
    if [ -d /sys/devices/system/cpu/cpufreq/policy3 ] && [ -d /sys/devices/system/cpu/cpufreq/policy7 ]; then
        rel=$(cat /sys/devices/system/cpu/cpufreq/policy3/related_cpus 2>/dev/null)
        case " $rel " in
            *" 3 "*|*" 4 "*) echo "8g2"; return 0 ;;
        esac
    fi
    if [ -d /sys/devices/system/cpu/cpufreq/policy4 ] && [ -d /sys/devices/system/cpu/cpufreq/policy7 ]; then
        rel=$(cat /sys/devices/system/cpu/cpufreq/policy4/related_cpus 2>/dev/null)
        case " $rel " in
            *" 6 "*) echo "8p"; return 0 ;;   # 3核(A710)→骁龙8/8+Gen1；4核(bengal)→上面已捕获
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
#
# ⚠️ 部分 Magisk 环境下，直接在当前 shell 里 echo 写 sysfs 会被 SELinux 拒绝，
#    而同一条命令经「sh -c 子 shell」执行却是允许的（实测骁龙888/lahaina 上如此）。
#    因此这里做一次子 shell 回退；两条都失败才判定为不可写。
write_lock() {
    local node="$1" val="$2"
    [ -f "$node" ] || return 1
    chmod 644 "$node" 2>/dev/null
    # 尝试 1：当前 shell 直接写
    if ! echo "$val" > "$node" 2>/dev/null; then
        # 尝试 2：经 sh -c 子 shell 写（绕开 Magisk su 上下文的写限制）
        sh -c "chmod 644 '$node' 2>/dev/null; echo '$val' > '$node' 2>/dev/null" || true
        if ! echo "$val" > "$node" 2>/dev/null; then
            chmod 444 "$node" 2>/dev/null
            return 1
        fi
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

# ---- 骁龙662 (bengal)：2 集群 ----
# 依赖变量：B0_FREQ (policy0 小核) / B4_FREQ (policy4 大核)
apply_b62() {
    local ok=0 v
    # policy0: cpu0-3 小核 A53
    if [ -d /sys/devices/system/cpu/cpufreq/policy0 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies "$B0_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    # policy4: cpu4-7 大核 A73
    if [ -d /sys/devices/system/cpu/cpufreq/policy4 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy4/scaling_available_frequencies "$B4_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    return $ok
}

# ---- 骁龙8/8+ Gen1 (SM8450/SM8475, cape/taro)：3 集群 ----
# 依赖变量：C0_FREQ (policy0 A510小核) / C4_FREQ (policy4 A710中核) / C7_FREQ (policy7 X2大核)
apply_8p() {
    local ok=0 v
    # policy0: cpu0-3 小核 A510
    if [ -d /sys/devices/system/cpu/cpufreq/policy0 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies "$C0_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    # policy4: cpu4-6 中核 A710
    if [ -d /sys/devices/system/cpu/cpufreq/policy4 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy4/scaling_available_frequencies "$C4_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    # policy7: cpu7 大核 X2
    if [ -d /sys/devices/system/cpu/cpufreq/policy7 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy7/scaling_available_frequencies "$C7_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    return $ok
}

# ---- 骁龙888/888+ (SM8350/SM8350-AC, lahaina)：3 集群 ----
# 依赖变量：D0_FREQ (policy0 A55小核) / D4_FREQ (policy4 A78中核) / D7_FREQ (policy7 X1大核)
# ⚠️ 本平台无 msm_performance 节点（Meizu/部分lahaina内核已裁掉），
#    只有 scaling_max_freq 单保险；写入后 chmod 444 防覆盖。
# ⚠️ 实测：Flyme 的 thermal-cpufreq-4 冷却设备可能把 policy4 压到 1.766GHz，
#    此时写入更高值会被内核夹回 1.766GHz（不报错），属正常现象，不是模块失效。
apply_8g1() {
    local ok=0 v
    # policy0: cpu0-3 小核 A55
    if [ -d /sys/devices/system/cpu/cpufreq/policy0 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies "$D0_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    # policy4: cpu4-6 中核 A78
    if [ -d /sys/devices/system/cpu/cpufreq/policy4 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy4/scaling_available_frequencies "$D4_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy4/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    # policy7: cpu7 大核 X1
    if [ -d /sys/devices/system/cpu/cpufreq/policy7 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy7/scaling_available_frequencies "$D7_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    return $ok
}

# ---- 骁龙8Gen2 (SM8550, kalama/kailua)：3 集群 3+4+1 ----
# 依赖变量：E0_FREQ (policy0 小核 A510×3) / E3_FREQ (policy3 中核 A715+A710×4)
#           E7_FREQ (policy7 大核 X3×1)
# ⚠️ 本平台集群号是 policy0 / policy3 / policy7，**不是** policy4：
#    policy3 是 8Gen2 独有的标志（8Gen1/888 用 policy4，8G3 用 policy2/policy5）。
# ⚠️ 有 scaling_boost_frequencies（中核 2803.2MHz、大核 3187.2MHz），
#    实测 scaling_max_freq 能把 boost 档一并压住，不会“漏档”。
# ⚠️ 有 msm_performance 节点，因此本平台走 scaling_max_freq + cpu_max_freq 双保险。
apply_8g2() {
    local ok=0 v
    # policy0: cpu0-2 小核 A510
    if [ -d /sys/devices/system/cpu/cpufreq/policy0 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy0/scaling_available_frequencies "$E0_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    # policy3: cpu3-6 中核 A715/A710
    if [ -d /sys/devices/system/cpu/cpufreq/policy3 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy3/scaling_available_frequencies "$E3_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy3/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    # policy7: cpu7 大核 X3
    if [ -d /sys/devices/system/cpu/cpufreq/policy7 ]; then
        v=$(align_freq /sys/devices/system/cpu/cpufreq/policy7/scaling_available_frequencies "$E7_FREQ")
        write_lock /sys/devices/system/cpu/cpufreq/policy7/scaling_max_freq "$v" && ok=$((ok+1))
    fi
    return $ok
}

# GPU: Adreno (各平台共用节点，依赖变量 GPU_FREQ)
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

# CPU 深层上限锁定：写 msm_performance 的 cpu_max_freq（比 scaling_max_freq 更底层，
# 实测 chmod 444 后系统无法覆盖，30 秒稳定——CPU 版 max_pwrlevel）
# 按 SOC 构建 "cpu:值" 串：8G3 按 4 集群、8E 按 2 集群
# 注意：888/888+ (8g1) 内核通常没有此节点，函数会在节点不存在时直接返回
apply_cpu_deep_limit() {
    local str="" cpu n
    case "$SOC" in
        g3)
            for cpu in 0 1; do str="$str $cpu:$P01_FREQ"; done
            for cpu in 2 3 4; do str="$str $cpu:$P24_FREQ"; done
            for cpu in 5 6; do str="$str $cpu:$P56_FREQ"; done
            str="$str 7:$P7_FREQ"
            ;;
        e8)
            for cpu in 0 1 2 3 4 5; do str="$str $cpu:$P0_FREQ"; done
            for cpu in 6 7; do str="$str $cpu:$P6_FREQ"; done
            ;;
        8p)
            for cpu in 0 1 2 3; do str="$str $cpu:$C0_FREQ"; done
            for cpu in 4 5 6; do str="$str $cpu:$C4_FREQ"; done
            str="$str 7:$C7_FREQ"
            ;;
        8g1)
            for cpu in 0 1 2 3; do str="$str $cpu:$D0_FREQ"; done
            for cpu in 4 5 6; do str="$str $cpu:$D4_FREQ"; done
            str="$str 7:$D7_FREQ"
            ;;
        8g2)
            for cpu in 0 1 2; do str="$str $cpu:$E0_FREQ"; done
            for cpu in 3 4 5 6; do str="$str $cpu:$E3_FREQ"; done
            str="$str 7:$E7_FREQ"
            ;;
        *) return 0 ;;
    esac
    n=/sys/kernel/msm_performance/parameters/cpu_max_freq
    [ -f "$n" ] || return 0
    chmod 644 "$n" 2>/dev/null
    echo "${str# }" > "$n" 2>/dev/null
    sync
    chmod 444 "$n" 2>/dev/null
}

# 按 SOC 应用全部限频，返回成功写入的节点数
# 依赖外部变量：SOC（g3/e8/b62/8p/8g1/8g2）+ 对应平台频率变量 + GPU_FREQ
apply_limits() {
    local ok=0 gpu_ok
    wake_cpus
    case "$SOC" in
        g3) apply_g3; ok=$? ;;
        e8) apply_e8; ok=$? ;;
        b62) apply_b62; ok=$? ;;
        8p) apply_8p; ok=$? ;;
        8g1) apply_8g1; ok=$? ;;
        8g2) apply_8g2; ok=$? ;;
        *) return 0 ;;
    esac
    apply_cpu_deep_limit
    gpu_ok=$(apply_gpu)
    [ "$gpu_ok" = "1" ] && ok=$((ok+1))
    return $ok
}

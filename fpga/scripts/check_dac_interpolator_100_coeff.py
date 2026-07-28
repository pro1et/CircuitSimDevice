"""重建并检查dac_interpolator_100的400抽头Q2.16系数及量化频响。

本脚本只读取RTL并向标准输出报告结果，不产生工程或临时文件。需要NumPy。
"""

from pathlib import Path
import re

import numpy as np


INTERP_FACTOR = 100
TAP_COUNT = 400
OUTPUT_FS_HZ = 30_000_000
CUTOFF_HZ = 125_000
KAISER_BETA = 5.65326
COEF_SCALE = 1 << 16


def design_quantized_coefficients() -> np.ndarray:
    """用与RTL固定系数相同的窗函数设计流程生成signed Q2.16整数。"""
    tap_index = np.arange(TAP_COUNT)
    centered = tap_index - (TAP_COUNT - 1) / 2
    normalized_cutoff = 2 * CUTOFF_HZ / OUTPUT_FS_HZ
    impulse = normalized_cutoff * np.sinc(normalized_cutoff * centered)
    impulse *= np.kaiser(TAP_COUNT, KAISER_BETA)
    impulse *= INTERP_FACTOR / impulse.sum()
    return np.rint(impulse * COEF_SCALE).astype(np.int64)


def read_rtl_coefficients(rtl_path: Path) -> np.ndarray:
    """解析RTL保存的前200个对称系数并重建完整400抽头序列。"""
    text = rtl_path.read_text(encoding="utf-8")
    matches = re.findall(
        r"8'd(\d+):\s+coefficient_half\s*=\s*(-?)18'sd(\d+)", text
    )
    first_half = np.zeros(TAP_COUNT // 2, dtype=np.int64)
    seen = set()
    for index_text, sign, value_text in matches:
        index = int(index_text)
        if index < TAP_COUNT // 2:
            first_half[index] = (-1 if sign else 1) * int(value_text)
            seen.add(index)
    if len(seen) != TAP_COUNT // 2:
        raise RuntimeError(f"RTL系数数量错误：找到{len(seen)}项，期望200项")
    return np.concatenate((first_half, first_half[::-1]))


def main() -> None:
    fpga_dir = Path(__file__).resolve().parents[1]
    rtl_path = fpga_dir / "src" / "hdl" / "dac_interpolator_100.sv"
    expected = design_quantized_coefficients()
    actual = read_rtl_coefficients(rtl_path)
    if not np.array_equal(actual, expected):
        mismatch = int(np.flatnonzero(actual != expected)[0])
        raise SystemExit(
            f"系数不一致：index={mismatch}，RTL={actual[mismatch]}，"
            f"参考={expected[mismatch]}"
        )

    fft_size = 1 << 20
    response = np.abs(np.fft.rfft(actual / COEF_SCALE, fft_size))
    frequencies = np.fft.rfftfreq(fft_size, 1 / OUTPUT_FS_HZ)
    dc_gain_db = 20 * np.log10(response[0])
    passband = 20 * np.log10(response[frequencies <= 25_000])
    stopband_db = 20 * np.log10(np.max(response[frequencies >= 275_000]))
    stopband_relative_db = stopband_db - dc_gain_db
    passband_droop_db = dc_gain_db - np.min(passband)

    if passband_droop_db > 0.20:
        raise SystemExit(f"通带下降超限：{passband_droop_db:.3f} dB")
    if stopband_relative_db > -60.0:
        raise SystemExit(f"镜像抑制不足：{stopband_relative_db:.3f} dB")

    print(f"直流增益：{dc_gain_db:.6f} dB（目标40 dB，即100倍）")
    print(f"0~25 kHz最大下降：{passband_droop_db:.6f} dB")
    print(f"275 kHz以上最大响应：{stopband_relative_db:.6f} dBc")
    print("COEFFICIENT CHECK PASSED")


if __name__ == "__main__":
    main()

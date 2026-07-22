#!/usr/bin/env python3
"""Analizador B1 para sesiones JSONL de ThermalBridge.

Lee uno o varios archivos JSONL del esquema de telemetría 2 y resume métricas
objetivas para comparar cambios del controlador sin exponer rutas ni datos de
usuario. No participa en el control en vivo.
"""
from __future__ import annotations

import argparse
import json
import math
import pathlib
import statistics
import sys
from dataclasses import dataclass, field
from typing import Any, Iterable


@dataclass
class SessionScore:
    path: pathlib.Path
    decisions: int = 0
    duration_seconds: float = 0.0
    cpu_target: float | None = None
    gpu_target: float | None = None
    cpu_overshoot_degree_seconds: float = 0.0
    gpu_overshoot_degree_seconds: float = 0.0
    cpu_max_overshoot_celsius: float = 0.0
    gpu_max_overshoot_celsius: float = 0.0
    emergency_samples: int = 0
    stale_sensor_samples: int = 0
    burst_samples: int = 0
    audio_safe_samples: int = 0
    applied_activity_values: list[int] = field(default_factory=list)
    direct_energy_nj: int = 0
    billed_energy_nj: int = 0
    serviced_energy_nj: int = 0
    qos_confirmed_samples: int = 0
    qos_observed_samples: int = 0
    parse_errors: int = 0
    frame_p50_values: list[float] = field(default_factory=list)
    frame_p95_values: list[float] = field(default_factory=list)
    frame_p99_values: list[float] = field(default_factory=list)
    one_percent_low_values: list[float] = field(default_factory=list)
    frame_over_50_events: float = 0.0
    frame_over_100_events: float = 0.0
    actuator_transitions: int = 0
    previous_actuator: str | None = None
    previous_control_level: float | None = None
    max_control_delta_per_second: float | None = None
    in_band_seconds: float = 0.0
    sensorless_seconds: float = 0.0
    suspension_count: int = 0
    suspension_duration_seconds: float = 0.0
    control_temperature_pairs: list[tuple[float, float]] = field(default_factory=list)
    control_power_pairs: list[tuple[float, float]] = field(default_factory=list)
    control_stutter_pairs: list[tuple[float, float]] = field(default_factory=list)

    @property
    def frame_p50(self) -> float | None:
        return mean_or_none(self.frame_p50_values)

    @property
    def frame_p95(self) -> float | None:
        return mean_or_none(self.frame_p95_values)

    @property
    def frame_p99(self) -> float | None:
        return mean_or_none(self.frame_p99_values)

    @property
    def one_percent_low_fps(self) -> float | None:
        return mean_or_none(self.one_percent_low_values)

    @property
    def actuator_transitions_per_minute(self) -> float | None:
        if self.duration_seconds <= 0:
            return None
        return self.actuator_transitions / (self.duration_seconds / 60.0)

    @property
    def frame_over_50_per_minute(self) -> float | None:
        if self.duration_seconds <= 0:
            return None
        return self.frame_over_50_events / (self.duration_seconds / 60.0)

    @property
    def frame_over_100_per_minute(self) -> float | None:
        if self.duration_seconds <= 0:
            return None
        return self.frame_over_100_events / (self.duration_seconds / 60.0)

    @property
    def in_band_percent(self) -> float:
        return percent_seconds(self.in_band_seconds, self.duration_seconds)

    @property
    def sensorless_percent(self) -> float:
        return percent_seconds(self.sensorless_seconds, self.duration_seconds)

    @property
    def thermal_peak_to_peak(self) -> float | None:
        values = []
        # Reconstructed from control-temperature pairs second element.
        values.extend(t for _, t in self.control_temperature_pairs)
        if not values:
            return None
        return max(values) - min(values)

    @property
    def control_temperature_correlation(self) -> float | None:
        return correlation(self.control_temperature_pairs)

    @property
    def control_power_correlation(self) -> float | None:
        return correlation(self.control_power_pairs)

    @property
    def control_stutter_correlation(self) -> float | None:
        return correlation(self.control_stutter_pairs)

    @property
    def mean_activity(self) -> float | None:
        if not self.applied_activity_values:
            return None
        return statistics.fmean(self.applied_activity_values)

    @property
    def activity_stddev(self) -> float:
        if len(self.applied_activity_values) < 2:
            return 0.0
        return statistics.pstdev(self.applied_activity_values)

    @property
    def burst_percent(self) -> float:
        return percent(self.burst_samples, self.decisions)

    @property
    def stale_sensor_percent(self) -> float:
        return percent(self.stale_sensor_samples, self.decisions)

    @property
    def emergency_percent(self) -> float:
        return percent(self.emergency_samples, self.decisions)

    @property
    def qos_confirmed_percent(self) -> float:
        return percent(self.qos_confirmed_samples, self.qos_observed_samples)


def percent(part: int, total: int) -> float:
    return 0.0 if total <= 0 else (100.0 * part / total)


def percent_seconds(part: float, total: float) -> float:
    return 0.0 if total <= 0 else (100.0 * part / total)


def mean_or_none(values: list[float]) -> float | None:
    return statistics.fmean(values) if values else None


def fmt(value: float | None, digits: int = 1) -> str:
    return 'no medido' if value is None else f'{value:.{digits}f}'


def correlation(pairs: list[tuple[float, float]]) -> float | None:
    if len(pairs) < 2:
        return None
    xs, ys = zip(*pairs)
    mx, my = statistics.fmean(xs), statistics.fmean(ys)
    num = sum((x - mx) * (y - my) for x, y in pairs)
    denx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    deny = math.sqrt(sum((y - my) ** 2 for y in ys))
    if denx == 0 or deny == 0:
        return None
    return num / (denx * deny)


def finite_number(value: Any) -> float | None:
    if isinstance(value, (int, float)):
        value = float(value)
        if math.isfinite(value):
            return value
    return None


def positive_int(value: Any) -> int:
    return int(value) if isinstance(value, int) and value > 0 else 0


def iter_jsonl(path: pathlib.Path) -> Iterable[dict[str, Any] | None]:
    with path.open('r', encoding='utf-8') as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                yield None
                continue
            yield data if isinstance(data, dict) else None


def score_file(path: pathlib.Path) -> SessionScore:
    score = SessionScore(path=path)
    previous_decision_ns: int | None = None

    for event in iter_jsonl(path):
        if event is None:
            score.parse_errors += 1
            continue

        configuration = event.get('configuration')
        if isinstance(configuration, dict):
            score.cpu_target = finite_number(configuration.get('cpuTargetCelsius')) or score.cpu_target
            score.gpu_target = finite_number(configuration.get('gpuTargetCelsius')) or score.gpu_target

        if event.get('kind') != 'decision':
            continue

        score.decisions += 1
        now_ns = positive_int(event.get('monotonicNanoseconds'))
        interval_seconds = 0.0
        if previous_decision_ns is not None and now_ns > previous_decision_ns:
            interval_seconds = min((now_ns - previous_decision_ns) / 1_000_000_000.0, 10.0)
            score.duration_seconds += interval_seconds
        previous_decision_ns = now_ns or previous_decision_ns

        cpu = finite_number(event.get('cpuTemperatureCelsius'))
        gpu = finite_number(event.get('gpuTemperatureCelsius'))
        if cpu is not None and score.cpu_target is not None:
            overshoot = max(0.0, cpu - score.cpu_target)
            score.cpu_max_overshoot_celsius = max(score.cpu_max_overshoot_celsius, overshoot)
            score.cpu_overshoot_degree_seconds += overshoot * interval_seconds
        if gpu is not None and score.gpu_target is not None:
            overshoot = max(0.0, gpu - score.gpu_target)
            score.gpu_max_overshoot_celsius = max(score.gpu_max_overshoot_celsius, overshoot)
            score.gpu_overshoot_degree_seconds += overshoot * interval_seconds

        if event.get('emergency') is True:
            score.emergency_samples += 1
        if event.get('sensorFresh') is False:
            score.stale_sensor_samples += 1
        if event.get('pulseMode') == 'burst':
            score.burst_samples += 1
        if event.get('pulseMode') == 'audioSafe':
            score.audio_safe_samples += 1

        applied = event.get('appliedActivityPercent')
        if isinstance(applied, int):
            score.applied_activity_values.append(applied)

        score.direct_energy_nj += positive_int(event.get('directEnergyNJ'))
        score.billed_energy_nj += positive_int(event.get('billedEnergyNJ'))
        score.serviced_energy_nj += positive_int(event.get('servicedEnergyNJ'))

        for key, output in [('frameTimeP50MS', score.frame_p50_values), ('frameTimeP95MS', score.frame_p95_values), ('frameTimeP99MS', score.frame_p99_values), ('onePercentLowFPS', score.one_percent_low_values)]:
            value = finite_number(event.get(key))
            if value is not None:
                output.append(value)
        score.frame_over_50_events += finite_number(event.get('frameTimeOver50MSPerMinute')) or 0.0
        score.frame_over_100_events += finite_number(event.get('frameTimeOver100MSPerMinute')) or 0.0
        score.suspension_count += positive_int(event.get('suspensionCount'))
        score.suspension_duration_seconds += finite_number(event.get('suspensionDurationSeconds')) or 0.0
        actuator = event.get('actuator')
        if isinstance(actuator, str):
            if score.previous_actuator is not None and actuator != score.previous_actuator:
                score.actuator_transitions += 1
            score.previous_actuator = actuator
        control = finite_number(event.get('controlLevelApplied'))
        if control is not None:
            if score.previous_control_level is not None and interval_seconds > 0:
                delta = abs(control - score.previous_control_level) / interval_seconds
                score.max_control_delta_per_second = max(score.max_control_delta_per_second or 0.0, delta)
            score.previous_control_level = control
            hottest = max([v for v in [cpu, gpu] if v is not None], default=None)
            if hottest is not None:
                score.control_temperature_pairs.append((control, hottest))
            power = sum(v for v in [finite_number(event.get('cpuPowerWatts')), finite_number(event.get('gpuPowerWatts'))] if v is not None)
            if power > 0:
                score.control_power_pairs.append((control, power))
            stutter = finite_number(event.get('frameTimeP99MS')) or finite_number(event.get('frameTimeOver50MSPerMinute'))
            if stutter is not None:
                score.control_stutter_pairs.append((control, stutter))
        if interval_seconds > 0:
            if event.get('sensorFresh') is False or event.get('sensorQuality') in ('stale', 'lost'):
                score.sensorless_seconds += interval_seconds
            if score.cpu_target is not None and score.gpu_target is not None:
                cpu_in_band = cpu is None or cpu <= score.cpu_target + 2
                gpu_in_band = gpu is None or gpu <= score.gpu_target + 2
                if cpu_in_band and gpu_in_band:
                    score.in_band_seconds += interval_seconds

        qos_state = event.get('qosEvidenceState')
        if isinstance(qos_state, str):
            score.qos_observed_samples += 1
            if qos_state == 'confirmed':
                score.qos_confirmed_samples += 1

    return score


def render(scores: list[SessionScore]) -> str:
    lines = [
        '# ThermalBridge B1 telemetry score',
        '',
        '| sesión | decisiones | duración s | CPU °C·s | GPU °C·s | sobrepaso máx | en banda % | sin sensor % | P50 ms | P95 ms | P99 ms | 1% low FPS | >50 ms/min | >100 ms/min | transiciones act/min | Δcontrol/s máx | suspensiones | suspensión s | corr ctrl-temp | corr ctrl-pot | corr ctrl-stutter | energía directa J | errores JSON |',
        '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
    ]
    for score in scores:
        mean_activity = score.mean_activity
        peak = max(score.cpu_max_overshoot_celsius, score.gpu_max_overshoot_celsius)
        lines.append(
            f'| {score.path.name} | {score.decisions} | {score.duration_seconds:.1f} | '
            f'{score.cpu_overshoot_degree_seconds:.1f} | {score.gpu_overshoot_degree_seconds:.1f} | {peak:.1f} | '
            f'{score.in_band_percent:.1f} | {score.sensorless_percent:.1f} | '
            f'{fmt(score.frame_p50)} | {fmt(score.frame_p95)} | {fmt(score.frame_p99)} | {fmt(score.one_percent_low_fps)} | '
            f'{fmt(score.frame_over_50_per_minute)} | {fmt(score.frame_over_100_per_minute)} | '
            f'{fmt(score.actuator_transitions_per_minute)} | {fmt(score.max_control_delta_per_second, 3)} | '
            f'{score.suspension_count} | {score.suspension_duration_seconds:.1f} | '
            f'{fmt(score.control_temperature_correlation, 3)} | {fmt(score.control_power_correlation, 3)} | {fmt(score.control_stutter_correlation, 3)} | '
            f'{score.direct_energy_nj / 1_000_000_000:.3f} | {score.parse_errors} |'
        )
    return '\n'.join(lines)


def expand_paths(arguments: list[str]) -> list[pathlib.Path]:
    paths: list[pathlib.Path] = []
    for raw in arguments:
        path = pathlib.Path(raw).expanduser()
        if path.is_dir():
            paths.extend(sorted(path.glob('*.jsonl')))
        else:
            paths.append(path)
    return paths


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description='Resume métricas B1 de telemetría JSONL de ThermalBridge.')
    parser.add_argument('paths', nargs='+', help='Archivos .jsonl o directorios con sesiones JSONL.')
    args = parser.parse_args(argv)

    paths = [path for path in expand_paths(args.paths) if path.is_file()]
    if not paths:
        print('ERROR: no se encontraron sesiones JSONL para analizar.', file=sys.stderr)
        return 1

    print(render([score_file(path) for path in paths]))
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))

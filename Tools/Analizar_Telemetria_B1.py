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
        '| sesión | decisiones | duración s | CPU °C·s | GPU °C·s | pico CPU | pico GPU | actividad media | σ actividad | emergencia % | sensor obsoleto % | burst % | QoS confirmado % | energía directa J | errores JSON |',
        '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|',
    ]
    for score in scores:
        mean_activity = score.mean_activity
        lines.append(
            f'| {score.path.name} | {score.decisions} | {score.duration_seconds:.1f} | '
            f'{score.cpu_overshoot_degree_seconds:.1f} | {score.gpu_overshoot_degree_seconds:.1f} | '
            f'{score.cpu_max_overshoot_celsius:.1f} | {score.gpu_max_overshoot_celsius:.1f} | '
            f'{(mean_activity if mean_activity is not None else 0.0):.1f} | '
            f'{score.activity_stddev:.1f} | {score.emergency_percent:.1f} | '
            f'{score.stale_sensor_percent:.1f} | {score.burst_percent:.1f} | '
            f'{score.qos_confirmed_percent:.1f} | {score.direct_energy_nj / 1_000_000_000:.3f} | '
            f'{score.parse_errors} |'
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

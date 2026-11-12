"""Durham Park Sandbox material physics v1.1: OFFLINE REFERENCE ONLY.

Deterministic, unit-bearing pure Python reference for conservation, porosity,
volume changes, mixed materials and a deliberately simplified force-gated cut.
Not a Godot/Jolt solver or a calibrated geotechnical model.

Run tests: python -m unittest discover -s tests -v
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Mapping, Optional
import json
import math

RHO_WATER = 1000.0  # kg/m3
GRAVITY = 9.81  # m/s2


def load_profiles(path: Optional[Path] = None) -> Dict[str, Mapping[str, float]]:
    if path is None:
        path = Path(__file__).resolve().parents[1] / "landworks/data/soil/material_profiles_v1_1.json"
    return json.loads(path.read_text(encoding="utf-8"))["materials"]


PROFILES = load_profiles()


def nonnegative(value: float, name: str) -> float:
    if not math.isfinite(value) or value < 0.0:
        raise ValueError(f"{name} must be finite and nonnegative: {value}")
    return value


@dataclass
class SoilBatch:
    """Mixture of mineral dry masses plus pore water and ponded/free water.

    e (void ratio) is V_void/V_solid. This reference assumes all components
    share a homogeneous representative void ratio; production stratigraphy
    must preserve layer boundaries and actual per-cell grading.
    """
    dry_kg: Dict[str, float] = field(default_factory=dict)
    pore_water_kg: float = 0.0
    void_ratio: float = 0.7
    damage: float = 0.0
    free_water_kg: float = 0.0

    def __post_init__(self) -> None:
        for name, mass in self.dry_kg.items():
            if name not in PROFILES:
                raise ValueError(f"Unknown material: {name}")
            nonnegative(mass, f"dry[{name}]")
        nonnegative(self.pore_water_kg, "pore_water_kg")
        nonnegative(self.free_water_kg, "free_water_kg")
        nonnegative(self.void_ratio, "void_ratio")
        if not (0.0 <= self.damage <= 1.0):
            raise ValueError("damage outside [0,1]")
        self._expel_excess_pore_water()

    @classmethod
    def bank(cls, material: str, bulk_volume_m3: float) -> SoilBatch:
        p = PROFILES[material]
        nonnegative(bulk_volume_m3, "bulk_volume_m3")
        e = p["void_ratio_bank"]
        vs = bulk_volume_m3 / (1.0 + e)
        ms = vs * p["grain_density"]
        water = ms * p["gravimetric_water"]
        return cls({material: ms}, water, e)

    @property
    def dry_mass_kg(self) -> float:
        return sum(self.dry_kg.values())

    @property
    def solid_volume_m3(self) -> float:
        return sum(kg / PROFILES[name]["grain_density"] for name, kg in self.dry_kg.items())

    @property
    def pore_volume_m3(self) -> float:
        return self.solid_volume_m3 * self.void_ratio

    @property
    def bulk_volume_m3(self) -> float:
        return self.solid_volume_m3 * (1.0 + self.void_ratio)

    @property
    def saturation(self) -> float:
        if self.pore_volume_m3 == 0.0:
            return 0.0
        return min(1.0, self.pore_water_kg / (RHO_WATER * self.pore_volume_m3))

    @property
    def porosity(self) -> float:
        return self.void_ratio / (1.0 + self.void_ratio)

    @property
    def wet_mass_kg(self) -> float:
        return self.dry_mass_kg + self.pore_water_kg + self.free_water_kg

    @property
    def wet_bulk_density_kg_m3(self) -> float:
        return self.dry_mass_kg / self.bulk_volume_m3 + self.pore_water_kg / self.bulk_volume_m3 if self.bulk_volume_m3 else 0.0

    @property
    def gravimetric_moisture(self) -> float:
        return self.pore_water_kg / self.dry_mass_kg if self.dry_mass_kg else 0.0

    def _weighted(self, key: str) -> float:
        vs = self.solid_volume_m3
        return sum((kg / PROFILES[name]["grain_density"]) * PROFILES[name][key]
                   for name, kg in self.dry_kg.items()) / vs if vs else 0.0

    def _expel_excess_pore_water(self) -> None:
        capacity_kg = RHO_WATER * self.pore_volume_m3
        if self.pore_water_kg > capacity_kg:
            extra = self.pore_water_kg - capacity_kg
            self.pore_water_kg -= extra
            self.free_water_kg += extra

    def clone(self) -> SoilBatch:
        return SoilBatch(dict(self.dry_kg), self.pore_water_kg, self.void_ratio,
                         self.damage, self.free_water_kg)

    def loosen(self) -> None:
        """Reduce density without changing either dry or water mass."""
        self.void_ratio = max(self.void_ratio, self._weighted("void_ratio_loose"))
        self._expel_excess_pore_water()

    def add_water(self, kg: float) -> None:
        nonnegative(kg, "added_water")
        self.pore_water_kg += kg
        self._expel_excess_pore_water()

    def compact(self, dissipated_energy_j: float) -> float:
        """Consume positive dissipation, lower e, expel overflow pore water.

        Moisture response is a *tunable* bell-shaped efficiency surrogate.
        It is not a Proctor-test law. Returns reduction in soil bulk volume.
        """
        nonnegative(dissipated_energy_j, "dissipated_energy_j")
        ms = self.dry_mass_kg
        if ms == 0.0:
            return 0.0
        e_min = self._weighted("void_ratio_min")
        if self.void_ratio <= e_min:
            return 0.0
        e0 = self.void_ratio
        clay_fraction = sum(kg * (PROFILES[name]["grading"]["clay"])
                            for name, kg in self.dry_kg.items()) / ms
        w_opt = 0.11 + 0.12 * clay_fraction
        spread = 0.10 + 0.06 * clay_fraction
        moisture_eff = 0.10 + 0.90 * math.exp(-((self.gravimetric_moisture - w_opt) / spread) ** 2)
        if self.saturation >= 0.98:
            moisture_eff = min(moisture_eff, 0.15)
        coeff = self._weighted("compaction_energy_coeff_kg_per_j")
        ratio = 1.0 - math.exp(-coeff * dissipated_energy_j / ms * moisture_eff)
        self.void_ratio = max(e_min, e0 - ratio * (e0 - e_min))
        self._expel_excess_pore_water()
        return self.solid_volume_m3 * (e0 - self.void_ratio)

    def remould(self, plastic_shear_strain: float) -> None:
        nonnegative(plastic_shear_strain, "plastic_shear_strain")
        scale = max(1e-5, self._weighted("disturbance_strain_scale"))
        self.damage = 1.0 - (1.0 - self.damage) * math.exp(-plastic_shear_strain / scale)

    def split_bulk_volume(self, bulk_volume_m3: float) -> SoilBatch:
        """Remove homogeneous representative material, preserving state.

        For production stratigraphy the split must use swept 3D layer volumes
        and cannot replace depth-order accounting.
        """
        nonnegative(bulk_volume_m3, "split_volume")
        if bulk_volume_m3 > self.bulk_volume_m3 + 1e-10:
            raise ValueError("Split larger than bank")
        fraction = min(1.0, bulk_volume_m3 / self.bulk_volume_m3) if self.bulk_volume_m3 else 0.0
        newdry = {k: v * fraction for k, v in self.dry_kg.items()}
        for k, v in newdry.items():
            self.dry_kg[k] -= v
        newpore = self.pore_water_kg * fraction
        newfree = self.free_water_kg * fraction
        self.pore_water_kg -= newpore
        self.free_water_kg -= newfree
        return SoilBatch(newdry, newpore, self.void_ratio, self.damage, newfree)

    def merge(self, other: SoilBatch) -> None:
        """Combine independent volumes conservatively. No energy or mass creation."""
        total_vs = self.solid_volume_m3 + other.solid_volume_m3
        combined_bulk = self.bulk_volume_m3 + other.bulk_volume_m3
        for name, mass in other.dry_kg.items():
            self.dry_kg[name] = self.dry_kg.get(name, 0.0) + mass
        self.pore_water_kg += other.pore_water_kg
        self.free_water_kg += other.free_water_kg
        old_vs = total_vs - other.solid_volume_m3
        self.damage = ((self.damage * old_vs) + (other.damage * other.solid_volume_m3)) / total_vs if total_vs else 0.0
        self.void_ratio = max(0.0, combined_bulk / total_vs - 1.0) if total_vs else 0.0
        self._expel_excess_pore_water()

    def face_resistance_n(self, tool_width_m: float, penetration_m: float,
                          surcharge_pa: float = 0.0,
                          n_gamma: float = 1.4, n_c: float = 1.8,
                          n_q: float = 1.0, n_adh: float = 0.5) -> float:
        """FEE-inspired first-order cutting estimate for a representative face.

        N factors require validation against tool geometry, failure wedge and
        material. This is not the complete Reece/McKyes solution. Pa*m*m -> N.
        """
        nonnegative(tool_width_m, "tool_width_m")
        nonnegative(penetration_m, "penetration_m")
        nonnegative(surcharge_pa, "surcharge_pa")
        if not (tool_width_m and penetration_m and self.bulk_volume_m3):
            return 0.0
        cohesion = (self._weighted("effective_cohesion_peak_pa") * (1.0 - self.damage)
                    + self._weighted("effective_cohesion_residual_pa") * self.damage)
        adh = self._weighted("steel_adhesion_pa")
        rho = self.wet_bulk_density_kg_m3
        d = penetration_m
        return tool_width_m * (rho * GRAVITY * d * d * n_gamma
                                + cohesion * d * n_c + surcharge_pa * d * n_q
                                + adh * d * n_adh)


@dataclass
class CutReceipt:
    bank_volume_m3: float
    loose_volume_m3: float
    dry_mass_kg: float
    water_mass_kg: float
    resisting_force_n: float
    work_consumed_j: float
    captured: SoilBatch


def cut_if_feasible(bank: SoilBatch, width_m: float, penetration_m: float,
                    actual_travel_m: float, available_force_n: float,
                    available_work_j: float, bucket_room_m3: float) -> CutReceipt:
    """Offline transaction demonstrator; replaces no Godot contact solver.

    Force gate is binary at the sampled cutting face; available work may
    limit partial extraction. Actual travel MUST come from solved motion.
    The full engine must use normal/tangential vector forces and real sweeps.
    """
    for key, value in (("width", width_m), ("penetration", penetration_m),
                       ("travel", actual_travel_m), ("force", available_force_n),
                       ("work", available_work_j), ("room", bucket_room_m3)):
        nonnegative(value, key)
    force = bank.face_resistance_n(width_m, penetration_m)
    if force <= 0.0 or available_force_n < force or actual_travel_m == 0.0 or bucket_room_m3 == 0.0:
        return CutReceipt(0.0, 0.0, 0.0, 0.0, force, 0.0, SoilBatch())
    volume_geometric = min(bank.bulk_volume_m3, width_m * penetration_m * actual_travel_m)
    loose_e = max(bank.void_ratio, bank._weighted("void_ratio_loose"))
    swell = (1.0 + loose_e) / (1.0 + bank.void_ratio)
    volume_allowed_by_bucket = bucket_room_m3 / swell
    volume_allowed_by_work = available_work_j / force / actual_travel_m * volume_geometric
    cut_vol = max(0.0, min(volume_geometric, volume_allowed_by_bucket, volume_allowed_by_work))
    if cut_vol <= 1e-12:
        return CutReceipt(0.0, 0.0, 0.0, 0.0, force, 0.0, SoilBatch())
    captured = bank.split_bulk_volume(cut_vol)
    captured.loosen()
    work = force * actual_travel_m * (cut_vol / volume_geometric)
    return CutReceipt(cut_vol, captured.bulk_volume_m3, captured.dry_mass_kg,
                      captured.pore_water_kg + captured.free_water_kg, force, work, captured)


def ledger(batches: Mapping[str, SoilBatch]) -> tuple[float, float]:
    """Return total dry solids and total water (including free water)."""
    return (sum(x.dry_mass_kg for x in batches.values()),
            sum(x.pore_water_kg + x.free_water_kg for x in batches.values()))

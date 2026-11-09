"""Independent dynamics surrogates for early physics screening (NOT Godot tests).

2D rigid 3-link arm constrained at fixed stick/bucket angles; 1D tractor+trailer
without hitch yaw or suspension. Numbers are screening only, not calibrated OEM data.
"""
from __future__ import annotations
import csv
import math
from pathlib import Path
from engineering_precheck import BOOM_L, STICK_L, BUCKET_L, G, BOOM_KG, STICK_KG, BUCKET_KG, boom_torque, towing_forces


def arm_moment_of_inertia(payload: float, theta: float, beta: float=-0.72, gamma: float=-0.24) -> float:
    # Point-mass discretisation at the link COMs, with link internal inertias.
    p1=(BOOM_L/2*math.cos(theta), BOOM_L/2*math.sin(theta))
    p2=(BOOM_L*math.cos(theta)+(STICK_L/2)*math.cos(theta+beta),
        BOOM_L*math.sin(theta)+(STICK_L/2)*math.sin(theta+beta))
    p3=(BOOM_L*math.cos(theta)+STICK_L*math.cos(theta+beta)+(BUCKET_L/2)*math.cos(theta+beta+gamma),
        BOOM_L*math.sin(theta)+STICK_L*math.sin(theta+beta)+(BUCKET_L/2)*math.sin(theta+beta+gamma))
    hook=(BOOM_L*math.cos(theta)+STICK_L*math.cos(theta+beta)+BUCKET_L*math.cos(theta+beta+gamma),
          BOOM_L*math.sin(theta)+STICK_L*math.sin(theta+beta)+BUCKET_L*math.sin(theta+beta+gamma))
    I=0.0
    for mass,pos,L in [(BOOM_KG,p1,BOOM_L),(STICK_KG,p2,STICK_L),(BUCKET_KG,p3,BUCKET_L)]:
        I+=mass*sum(v*v for v in pos)+mass*L*L/12
    I+=payload*sum(v*v for v in hook)
    return I


def hook_height(theta:float) ->float:
    return BOOM_L*math.sin(theta)+STICK_L*math.sin(theta-.72)+BUCKET_L*math.sin(theta-.96)


def simulate_boom(payload:float, outdir:Path) ->dict:
    dt=1/120
    theta=0.24
    w=0.0
    start_hook=hook_height(theta)
    # Ground contact: 0.56 m tall load at least 0.28 m above grade,
    # suspended 0.52 m below the bucket pin; boom hinge at y=2.12 m.
    min_hook_relative_height=0.28+0.52-2.12
    lo,hi=-0.7,1.15
    for _ in range(45):
        mid=(lo+hi)/2
        if hook_height(mid)<min_hook_relative_height: lo=mid
        else: hi=mid
    ground_stop_angle=hi
    best=0.0
    min_gain=0.0
    hold_drift=0.0
    hold_baseline=None
    out=outdir/f'surrogate_boom_{int(payload)}kg.csv'
    with out.open('w',newline='') as file:
        writer=csv.writer(file)
        writer.writerow(['time_s','theta_deg','omega_rad_s','hook_gain_m','motor_torque_kNm','gravity_torque_kNm'])
        for frame in range(int(20/dt)):
            t=frame*dt
            # Smooth target rises 2..10 s and then holds.
            s=max(0.0,min(1.0,(t-2.0)/8.0))
            s=s*s*(3-2*s)
            target=.24+.48*s
            gravity=boom_torque(payload,math.degrees(theta))
            inertia=arm_moment_of_inertia(payload,theta)
            # Gravity-compensated velocity/position controller, then realistic
            # motor *torque cap*, as used in the Godot test's design intent.
            commanded=gravity+110000*(target-theta)-33000*w
            applied=max(-75000.0,min(75000.0,commanded))
            acceleration=(applied-gravity-2000*w)/inertia
            w=max(-.55,min(.55,w+acceleration*dt))
            theta+=w*dt
            if theta<ground_stop_angle:
                theta=ground_stop_angle
                w=max(0,w)
            if theta>1.15:
                theta=1.15
                w=min(0,w)
            gain=hook_height(theta)-start_hook
            best=max(best,gain)
            min_gain=min(min_gain,gain)
            if t>=11.0 and hold_baseline is None:
                hold_baseline=gain
            if 11.0<=t<=13.0:
                hold_drift=max(hold_drift,abs(gain-hold_baseline))
            if frame%12==0:
                writer.writerow([round(t,3),round(math.degrees(theta),3),round(w,4),round(gain,3),
                                 round(applied/1000,2),round(gravity/1000,2)])
    return dict(case=f'boom_{int(payload)}kg',max_hook_gain_m=round(best,2),
                min_hook_gain_m=round(min_gain,2),
                final_angle_deg=round(math.degrees(theta),1),hold_drift_m=round(hold_drift,2))


def simulate_tow(payload:float,slope:float,outdir:Path)->dict:
    dt=1/120
    v=0.0
    distance=0.0
    peak=0.0
    brake_start=0
    m=573+320+payload
    angle=math.radians(slope)
    resist=towing_forces(payload,slope)
    rolling_and_gravity=resist['resistance_N']
    max_traction=resist['traction_ceiling_N']
    # Baseline's nominal request of 4250N, capped by front+rear tyre grip.
    out=outdir/f'surrogate_tow_{int(slope)}deg_{int(payload)}kg.csv'
    with out.open('w',newline='') as file:
        writer=csv.writer(file)
        writer.writerow(['time_s','speed_kmh','distance_m','net_force_N','phase'])
        for frame in range(int(22/dt)):
            t=frame*dt
            phase='SETTLE' if t<2 else 'PULL' if t<14 else 'BRAKE' if t<20 else 'IDLE'
            throttle=0.80 if phase=='PULL' else 0.0
            brake=1.0 if phase=='BRAKE' else 0.0
            # Input-side speed governor: no arbitrary velocity clamp.
            governor=max(0.0,min(1.0,(15.0/3.6 - v)/(2.0/3.6)))
            drive=min(max_traction,4250*throttle)*governor
            brakes=min(max_traction,brake*max_traction)
            aero_drag=0.4*v*v
            net=drive - rolling_and_gravity - aero_drag - brakes
            v=max(0.0,v+(net/m)*dt)
            distance+=v*dt
            peak=max(peak,v)
            if frame == int(14/dt):
                brake_start=distance
            if frame%12==0:
                writer.writerow([round(t,3),round(3.6*v,2),round(distance,2),round(net,1),phase])
    return dict(case=f'tow_{int(slope)}deg_{int(payload)}kg',peak_kmh=round(3.6*peak,1),
                total_m=round(distance,1),braking_m=round(distance-brake_start,1))


def main():
    import argparse
    ap=argparse.ArgumentParser()
    ap.add_argument('--out',default='surrogate_results')
    a=ap.parse_args()
    outdir=Path(a.out).resolve()
    outdir.mkdir(parents=True,exist_ok=True)
    results=[]
    for payload in [250,500,1000]:
        results.append(simulate_boom(payload,outdir))
    for payload,slope in [(0,0),(400,0),(400,6),(800,6)]:
        results.append(simulate_tow(payload,slope,outdir))
    with (outdir/'surrogate_summary.csv').open('w',newline='') as file:
        cols=['case','max_hook_gain_m','min_hook_gain_m','final_angle_deg','hold_drift_m','peak_kmh','total_m','braking_m']
        writer=csv.DictWriter(file,cols)
        writer.writeheader()
        writer.writerows(results)
    for r in results:print(r)
    print('These are simplified independent dynamics—not validated Godot results.')

if __name__=='__main__':
    main()

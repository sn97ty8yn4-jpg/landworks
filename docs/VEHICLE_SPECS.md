# Machine-size baseline — for model adaptation and physics calibration

These manufacturer/industry specifications constrain the *target Kubotas*, not the dimensions of the CC0 donors. Any target dimensions and engine parameters still require practical verification on a working model.

## Kubota B7100HST four-wheel drive, turf tyres

Source: https://www.tractordata.com/farm-tractors/005/1/4/5147-kubota-b7100hst-dimensions.html

| Parameter | Value |
|---|---:|
| Wheelbase | **1.39 m** |
| Overall length | **2.12 m** |
| Overall width | **1.01 m** |
| 4WD factory weight | **573 kg** |
| Front turf tyre nominal size | **20.5 × 8.00-10** |
| Rear turf tyre nominal size | **29 × 12.00-15** |
| Front tyre nominal outside diameter | **0.521 m** (20.5-inch conversion) |
| Rear tyre nominal outside diameter | **0.737 m** (29-inch conversion) |

The two turf tyre widths used in the v0.2 physics body are 8 in (0.203 m) front and 12 in (0.305 m) rear. This sets appropriate game-wheel sizes, not a manufacturer's exact rolling-radius-versus-load calibration. The owner may have variant tyres or attachments. Keep the total mass as a tuneable value when attachments are fitted.

## Kubota KX080-3 / close KX080-3S reference

Official model reference (KX080-3): https://kubota.com.mm/en/products/mini-excavator/kx080-3/index.html

Australian sibling reference (KX080-3S): https://kubota.com.au/product/excavator-kx080-3s

| Parameter | Target reference |
|---|---:|
| KX080-3 operating weight including operator | **8,170 kg** |
| KX080-3S operating weight with rubber tracks | **8,280 kg** |
| KX080-3S transport length | **6.45 m** |
| KX080-3S overall width | **2.20 m** |
| KX080-3S cab height | **2.54 m** |
| KX080-3S normal travel speed, low/high | **2.7 / 4.9 km/h** |
| KX080-3S swing speed | **9.5 rpm** |

The v0.2 physics body uses 8,170 kg as a placeholder for KX080-3 and a 2.2 m track outside width. Cylinder geometry, reach, collision mesh, hydraulic pressure and soil forces are **not calibrated**. The CC0 donor is a *much smaller* compact excavator and must be remade into the correct form rather than scaled by a single factor.

## Acceptance tests after importing proper visual parts

- Tractor front and rear turf tyres match the true size **relative to each other**, and all four wheel spin/steer pivots are centred.
- Tractor model front-rear axle spacing 1.39 m and outside tyre width near 1.01 m, with usable clearance for steering without body penetration.
- Excavator track width 2.2 m and no collision shapes rotate with its upper carriage.
- Boom, stick, bucket rotate about their own fixed mechanical pivot axes and maintain their shape during movement.
- Donor trailer is disconnected from tractor body; it will later become a separate towed rigid body.

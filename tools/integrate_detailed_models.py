"""Convert approved static Blender scenes into physics-pivot-local visual assets.
Run: blender -b --python tools/integrate_detailed_models.py -- /absolute/models
Physics arms retain their tested pin spacings. Cosmetics are rebased, never bodies.
"""
import bpy, sys, math, json
from pathlib import Path
from mathutils import Vector
SRC=Path(sys.argv[sys.argv.index('--')+1]); ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'landworks/assets/engineered'; OUT.mkdir(parents=True,exist_ok=True)
report={}
def export(name, objects, transform):
    bpy.ops.object.select_all(action='DESELECT')
    copies=[]
    for obj in objects:
        copy=obj.copy();copy.data=obj.data.copy();bpy.context.collection.objects.link(copy)
        world=obj.matrix_world.copy();copy.parent=None;copy.matrix_world.identity()
        for v in copy.data.vertices:
            # Godot coordinates -> Blender glTF-export coordinates.
            p=transform(world@v.co);v.co=(p[0],-p[2],p[1])
        copies.append(copy);copy.select_set(True)
    if not copies: raise RuntimeError('Empty '+name)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();joined=bpy.context.object;joined.name=name
    # Recompute normals after affine remapping; join cuts hundreds of draw nodes.
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.normals_make_consistent(inside=False);bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
    report[name]={'source_parts':len(objects),'vertices':len(joined.data.vertices),'triangles':sum(len(p.vertices)-2 for p in joined.data.polygons)}
    bpy.data.objects.remove(joined,do_unlink=True)

def arm_map(a,b,length,bucket=False):
    a=Vector(a);d=Vector(b)-a;d.y=0;L=d.length;d.normalize();up=Vector((d.z,0,-d.x))
    def f(p):
        q=p-a
        return ((-1 if bucket else 1)*q.y,(-1 if bucket else 1)*q.dot(up),-q.dot(d)*length/L)
    return f

bpy.ops.wm.open_mainfile(filepath=str(SRC/'B7100_HST_Studio.blend'))
tractor_root=bpy.data.objects['B7100_HST_STATIC']
parts=list(tractor_root.children)
z_offset=tractor_root.matrix_world.translation.z
wheels={}
for axle,x,y,r in [('Front',-.85,.4475,.26035),('Rear',.55,.4075,.3683)]:
    # Source has matching left/right engineering details; use independent sides.
    for side,sign in [('L',-1),('R',1)]:
        group=[o for o in parts if o.name.startswith(axle+'_'+side+'_')]
        for o in parts:
            if o.name.startswith((axle+'_Concave_Rim',axle+'_Sidewall_Moulding')):
                center=sum((o.matrix_world@v.co for v in o.data.vertices),Vector())/len(o.data.vertices)
                if center.y*sign>0: group.append(o)
        wheels[axle+side]=group
        export('b7100_wheel_'+axle.lower()+'_'+side.lower(),group,lambda p,x=x,y=y,r=r,sign=sign:(p.y-sign*y,p.z-r-z_offset,p.x-x))
all_wheels={o for g in wheels.values() for o in g}
export('b7100_body',[o for o in parts if o not in all_wheels],lambda p:(p.y,p.z-.667,p.x+.15))

bpy.ops.wm.open_mainfile(filepath=str(SRC/'KX080_3_Studio.blend'))
parts=list(bpy.data.objects['KX080_3_STATIC'].children)
groups={k:[] for k in ['under','upper','boom','stick','bucket','shoe','omit']}
# Exact object-name families from the approved static build, with Blender numeric suffixes.
for o in parts:
    n=o.name;p=o.matrix_world.translation
    if n.startswith(('Track shoe','Triple grouser','Shoe fastener','Track hinge pin')): k='shoe'
    elif n.startswith(('Boom lift','Stick cylinder','Bucket cylinder','Bucket bellcrank','Bucket dogbone','Knuckle flexible hose','Swivel supply hose')): k='omit'
    elif n.startswith(('Crawler','Idler','Drive sprocket','Wheel flange','Drive hub','Sprocket','Lower track','Roller axle','Carrier roller','Undercarriage','Track crossmember','Swing bearing','Swing ring','Slew ring','Blade','Curved dozer','Track tension','Track cover','Grease tension','Track rail')): k='under'
    elif n.startswith(('Main boom','Boom heel','Boom welded','Boom elbow','Boom foot','Boom hydraulic','Hose clamp','Boom Kubota')): k='boom'
    elif n.startswith(('Dipper','Bucket pivot')): k='stick'
    elif n.startswith(('Bucket','Curved bucket','Rolled bucket')): k='bucket'
    elif n.startswith(('Pin grease','Pin keeper','Keeper bolt','Boom caution','Caution symbol')):
        # Geometry may be baked into mesh rather than object location.
        center=sum((o.matrix_world@v.co for v in o.data.vertices),Vector())/len(o.data.vertices)
        k='stick' if center.x < -3.8 else 'boom'
    else:k='upper'
    groups[k].append(o)
# One detailed bottom shoe, including fasteners/pin, rebased to the belt tangent.
shoe=[]
for o in groups['shoe']:
    c=sum((o.matrix_world@v.co for v in o.data.vertices),Vector())/len(o.data.vertices)
    if abs(c.x+1.15)<.06 and abs(c.z-.03)<.08 and c.y<0:shoe.append(o)
export('kx080_track_shoe',shoe,lambda p:(p.y+.875,-(p.z-.03),-(p.x+1.15)))
export('kx080_undercarriage',groups['under'],lambda p:(p.y*.86/.875,.31+(p.z-.33)*.9,p.x*1.28/1.15))
def upper(p):
    # Main body remains at its original scale. Shift only the swing bracket
    # to the established real boom hinge, plus the visual slew ring height.
    return (p.y,p.z+.12,p.x)
for o in groups['upper']:
    if o.name.startswith(('Boom swing mounting','Vertical swing pin')):
        o.location.x+=.30; o.location.y+=.21
bpy.context.view_layer.update()
export('kx080_upper',groups['upper'],upper)
export('kx080_boom',groups['boom'],arm_map((-.96,.27,1.16),(-3.65,.27,3.04),3.0))
# The static dipper silhouette did not contain a complete eye at its upper pin.
# Add the engineering eye before rebase so it remains attached in every pose.
for name,radius,width,material in [('Dipper upper eye',.115,.30,'Warm_Kubota_Orange'),('Dipper upper pin',.06,.35,'Brushed_Steel')]:
    bpy.ops.mesh.primitive_cylinder_add(vertices=48,radius=radius,depth=width,location=(-3.65,.27,3.04),rotation=(math.pi/2,0,0))
    ob=bpy.context.object;ob.name=name;ob.data.materials.append(bpy.data.materials[material]);groups['stick'].append(ob)
bpy.context.view_layer.update()
export('kx080_stick',groups['stick'],arm_map((-3.65,.27,3.04),(-4.35,.27,1.06),2.32))
# Preserve the distributed GLB's coordinate convention. The runtime loader
# applies a Z half-turn to this bucket so its cavity faces the machine.
# Removing bucket=True here also requires removing that runtime correction.
export('kx080_bucket',groups['bucket'],arm_map((-4.35,.27,1.06),(-3.64,.27,.205),.82,True))
report['omitted_static_cross_joint_parts']=[o.name for o in groups['omit']]
report['notes']=['Detailed static source rebased to existing tested 3.0/2.32/0.82m physics pin lengths.', 'Tractor wheelbase 1.4m and track widths 0.895/0.815m match detailed source.', 'Existing dynamic cylinders and bucket linkage replace frozen static versions.']
(ROOT/'docs/detailed_asset_conversion.json').write_text(json.dumps(report,indent=2))
manifest_path=OUT/'manifest.json'
if manifest_path.exists():
    manifest=json.loads(manifest_path.read_text());manifest['parts']=report
    manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
print('DETAILED_CONVERSION_COMPLETE',json.dumps(report))

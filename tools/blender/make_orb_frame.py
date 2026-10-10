"""The ornate vessel frame (assets/ui/vessels/orb_frame.png) and the carved plinth the HUD busts sit on (assets/ui/vessels/bust_plinth.png).
Run: Blender --background --python tools/blender/make_orb_frame.py. Same helpers and metals as make_hud_vessels.py (which still makes the glass,
liquid, tray and bezels); this only redoes the frame to the reference: a thick layered ring, an engraved band, diamond studs at the four points.
"""
from pathlib import Path
import bpy, math, random
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/ui/vessels'; OUT.mkdir(parents=True,exist_ok=True)
random.seed(83)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=16
scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
scene.view_settings.view_transform='AgX'
world=bpy.data.worlds.new('Dim ash light');world.use_nodes=True;world.node_tree.nodes['Background'].inputs['Strength'].default_value=.35;scene.world=world
bpy.ops.object.camera_add(location=(0,0,7));camera=bpy.context.object;camera.data.type='ORTHO';camera.data.ortho_scale=2.7;camera.rotation_euler=(0,0,0);scene.camera=camera
for name,pos,energy,color,scale in [('Warm key',(-3,4,5),400,(1,.84,.65),4),('Cold fill',(3,-1,4),120,(.55,.65,.8),3)]:
 bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.name=name;o.data.energy=energy;o.data.color=color;o.data.shape='DISK';o.data.size=scale;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
def material(name,base,metal=.7,rough=.7):
 m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;p=n.get('Principled BSDF');p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
 coord=n.new('ShaderNodeTexCoord');noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=24;noise.inputs['Detail'].default_value=3;l.new(coord.outputs['Generated'],noise.inputs['Vector'])
 ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].position=.25;ramp.color_ramp.elements[0].color=(*(v*.27 for v in base),1);ramp.color_ramp.elements[1].position=.8;ramp.color_ramp.elements[1].color=(*base,1);l.new(noise.outputs['Fac'],ramp.inputs[0]);l.new(ramp.outputs[0],p.inputs['Base Color'])
 bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.32;bump.inputs['Distance'].default_value=.04;l.new(noise.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs[0],p.inputs['Normal']);return m
iron=material('Pitted black iron',(.17,.12,.10),.75,.66);bronze=material('Tarnished gold bronze',(.62,.42,.14),.85,.42);bone=material('Old carved bone',(.34,.29,.21),.15,.9)
objects=[]
def torus(name,r,thickness,mat,at=(0,0,0)):
 bpy.ops.mesh.primitive_torus_add(major_segments=128,minor_segments=16,location=at,major_radius=r,minor_radius=thickness);o=bpy.context.object;o.name=name;o.data.materials.append(mat);objects.append(o)
 for v in o.data.vertices:v.co*=1+random.uniform(-.003,.003)
 for p in o.data.polygons:p.use_smooth=True
 return o
def ball(name,at,scale,mat):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,location=at);o=bpy.context.object;o.name=name;o.scale=scale;o.data.materials.append(mat);objects.append(o)
 for p in o.data.polygons:p.use_smooth=True
 return o
def box(name,at,size,mat,bevel=.025):
 bpy.ops.mesh.primitive_cube_add(size=1,location=at);o=bpy.context.object;o.name=name;o.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat);mod=o.modifiers.new('Chipped edges','BEVEL');mod.width=bevel;mod.segments=3;objects.append(o);return o
def hide_all():
 for o in objects:o.hide_render=True

def render(name,width=512,height=512,ortho=2.7):
 camera.data.ortho_scale=ortho;scene.render.resolution_x=width;scene.render.resolution_y=height;scene.render.resolution_percentage=100;scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True);print('HUD_ASSET '+name,flush=True)
scene.cycles.samples=48
def rot(o,z):o.rotation_euler.z=z;return o
# Layered ring: black iron body, an engraved band of alternating blocks, a bronze inner lip with a dark gap inside it.
torus('Cast iron body',1.0,.15,iron);torus('Iron shoulder',1.0,.15,iron,at=(0,0,.02));torus('Inner dark gap',.90,.02,iron,at=(0,0,.06));torus('Bronze inner lip',.865,.03,bronze,at=(0,0,.075))
torus('Outer wire',1.15,.02,bronze);torus('Raised band edge',.94,.014,bronze,at=(0,0,.15));torus('Raised band edge outer',1.06,.014,bronze,at=(0,0,.15))
for i in range(48):   # the engraved band: short blocks with a gap between them
 a=2*math.pi*i/48;o=box('Band block',(math.cos(a)*1.0,math.sin(a)*1.0,.15),(.05,.095,.025),bronze if i%2==0 else iron,.006);o.rotation_euler.z=a
for i in range(8):   # diamond studs: big at the four points, small between
 a=math.pi/2*i/2;big=i%2==0;r=1.12 if big else 1.07
 o=box('Diamond stud',(math.cos(a)*r,math.sin(a)*r,.14),(.15 if big else .085,.09 if big else .055,.05),bronze,.012);o.rotation_euler.z=a
 o2=box('Diamond core',(math.cos(a)*r,math.sin(a)*r,.18),(.07 if big else .04,.04 if big else .026,.03),iron,.006);o2.rotation_euler.z=a
# Filigree scrolls flaring out of the lower flanks toward the tray and the bust
for sign in [-1,1]:
 for k,(x,y,rr) in enumerate([(.78,-.74,.16),(.98,-.60,.11),(.66,-.90,.10)]):
  torus('Scroll curl',rr,.022,bronze,at=(sign*x,y,.10))
 for i in range(3):
  a=math.pi+sign*(.30+i*.22) if sign<0 else -.30-i*.22
  o=box('Raised claw',(sign*(.80+i*.07),-.58+i*.18,.10),(.07,.36,.09),iron);o.rotation_euler.z=sign*-.4
box('Low worn plinth',(0,-1.07,.01),(1.1,.14,.2),iron);box('Inset inscription plate',(0,-1.065,.13),(.68,.095,.03),bronze,.01)
mesh=bpy.data.meshes.new('Shield clasp');mesh.from_pydata([(-.105,-.87,.17),(.105,-.87,.17),(.09,-1.02,.17),(0,-1.10,.20),(-.09,-1.02,.17),(0,-.91,.22)],[],[(0,1,5),(1,2,3,5),(3,4,0,5)]);mesh.materials.append(bronze)
shield=bpy.data.objects.new('Shield clasp',mesh);bpy.context.collection.objects.link(shield);objects.append(shield)
render('orb_frame',640,640,2.7);hide_all()
# The plinth the bust sits on: a long worn slab, thickest at the screen edge, with a bronze rail and a pointed flourish toward the vessel.
scene.cycles.samples=32
box('Slab',(0,0,0),(5.2,.62,.16),iron,.07)
box('Top rail',(0,.27,.12),(5.05,.03,.03),bronze,.01);box('Lower rail',(0,-.27,.12),(5.05,.03,.03),bronze,.01)
for i in range(7):
 x=-2.1+i*.7;o=box('Diamond',(x,0,.13),(.13,.08,.04),bronze,.01);o.rotation_euler.z=math.radians(0)
for x in (2.55,):   # the tip toward the vessel
 o=box('Tip',(x,0,.05),(.42,.42,.14),iron,.05);o.rotation_euler.z=math.radians(45);box('Tip stud',(x,0,.15),(.16,.16,.04),bronze,.01).rotation_euler.z=math.radians(45)
render('bust_plinth',1280,160,5.4)
print('ORB_FRAME_COMPLETE',flush=True)

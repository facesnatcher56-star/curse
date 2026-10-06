"""Blender-built, worn iron HUD vessels and fluid loop (no external artwork).
Run: Blender --background --python tools/blender/make_hud_vessels.py.
Renders transparent orb frame, glass, hotbar tray, skill bezel and 32-frame liquid atlas.
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
iron=material('Pitted black iron',(.15,.15,.16),.75,.68);bronze=material('Tarnished bronze',(.37,.25,.12),.8,.57);bone=material('Old carved bone',(.34,.29,.21),.15,.9)
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
# A heavy layered bezel and low, clawed iron pedestal.
torus('Cast iron outer rim',.98,.10,iron);torus('Bronze sealing lip',.87,.025,bronze,at=(0,0,.055));torus('Scuffed outer wire',1.065,.018,bronze)
for i in range(12):
 a=2*math.pi*i/12;ball('Hand set rivet',(math.cos(a)*.98,math.sin(a)*.98,.1),(.035,.035,.024),bronze)
for sign in [-1,1]:
 for i in range(3):
  a=math.pi+sign*(.33+i*.24) if sign<0 else -.33-i*.24
  o=box('Raised gothic claw',(sign*(.76+i*.075),-.62+i*.20,.09),(.075,.42,.095),iron);o.rotation_euler.z=sign*-.4
box('Low worn plinth',(0,-1.07,.01),(1.1,.14,.2),iron);box('Inset inscription plate',(0,-1.065,.13),(.68,.095,.03),bronze,.01)
# A worn shield clasp, with a physical ridge rather than a flat decorative icon.
mesh=bpy.data.meshes.new('Shield clasp');mesh.from_pydata([(-.105,-.87,.17),(.105,-.87,.17),(.09,-1.02,.17),(0,-1.10,.20),(-.09,-1.02,.17),(0,-.91,.22)],[],[(0,1,5),(1,2,3,5),(3,4,0,5)]);mesh.materials.append(bronze)
shield=bpy.data.objects.new('Shield clasp',mesh);bpy.context.collection.objects.link(shield);objects.append(shield)
render('orb_frame');hide_all()
# Separate glass highlights, deliberately subtle; the vessel beneath remains readable.
glass=bpy.data.materials.new('Smoky imperfect glass');glass.use_nodes=True;p=glass.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(.07,.08,.10,1);p.inputs['Metallic'].default_value=.5;p.inputs['Roughness'].default_value=.20
sphere=ball('Glass dome',(0,0,-.10),(.845,.845,.28),glass)
render('glass_dome');hide_all()
# The looping fluid is authored and rendered in Blender. Runtime clips its live level.
liquid=bpy.data.materials.new('Slow liquid currents');liquid.use_nodes=True;n=liquid.node_tree.nodes;l=liquid.node_tree.links;p=n.get('Principled BSDF');p.inputs['Metallic'].default_value=.25;p.inputs['Roughness'].default_value=.3
tex=n.new('ShaderNodeTexCoord');mapping=n.new('ShaderNodeMapping');l.new(tex.outputs['Generated'],mapping.inputs['Vector'])
noise=n.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=4.8;noise.inputs['Detail'].default_value=2;noise.inputs['Roughness'].default_value=.58;l.new(mapping.outputs['Vector'],noise.inputs['Vector'])
ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=(.055,.055,.055,1);ramp.color_ramp.elements[0].position=.24;ramp.color_ramp.elements[1].color=(.68,.68,.68,1);ramp.color_ramp.elements[1].position=.8;l.new(noise.outputs['Fac'],ramp.inputs[0]);l.new(ramp.outputs[0],p.inputs['Base Color'])
p.inputs['Emission Strength'].default_value=.25;l.new(ramp.outputs[0],p.inputs['Emission Color'])
bump=n.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.06;bump.inputs['Distance'].default_value=.025;l.new(noise.outputs['Fac'],bump.inputs['Height']);l.new(bump.outputs[0],p.inputs['Normal'])
fluid=ball('Fluid',(0,0,0),(.845,.845,.30),liquid)
scene.cycles.samples=8;frames=[]
for i in range(32):
 a=i*math.tau/32;mapping.inputs['Location'].default_value=(math.cos(a)*.22,math.sin(a)*.22,0);mapping.inputs['Rotation'].default_value=(0,0,a)
 render('fluid_'+str(i).zfill(2),256,256)
 im=bpy.data.images.load(str(OUT/('fluid_'+str(i).zfill(2)+'.png')));frames.append(list(im.pixels));bpy.data.images.remove(im)
# Blender's pixels are bottom-up; store rows in a top-down atlas for Godot UVs.
atlas=bpy.data.images.new('Liquid loop',width=2048,height=1024,alpha=True);pixels=[0.0]*(2048*1024*4)
for i,data in enumerate(frames):
 x0=(i%8)*256;y0=(3-i//8)*256
 for y in range(256):
  src=y*256*4;dst=((y0+y)*2048+x0)*4;pixels[dst:dst+1024]=data[src:src+1024]
atlas.pixels.foreach_set(pixels);atlas.filepath_raw=str(OUT/'liquid_atlas.png');atlas.file_format='PNG';atlas.save()
for i in range(32):(OUT/('fluid_'+str(i).zfill(2)+'.png')).unlink()
hide_all();scene.cycles.samples=16
# The skill tray is rendered as an actual battered metal piece, not a flat rectangle.
box('Hotbar iron tray',(0,0,0),(6.1,.80,.16),iron,.08)
for y in [-.37,.37]:box('Inset bronze rail',(0,y,.12),(5.95,.025,.028),bronze,.01)
for x in [-2.98,2.98]:
 box('End rail',(x,0,.11),(.035,.7,.03),bronze,.01)
 for y in [-.28,.28]:ball('Tray rivet',(x,y,.15),(.04,.04,.025),bronze)
render('hotbar_tray',1536,256,6.5);hide_all()
for x,y,w,h in [(-.47,0,.055,.98),(.47,0,.055,.98),(0,-.47,.98,.055),(0,.47,.98,.055)]:box('Slot bezel',(x,y,0),(w,h,.10),iron,.02)
for x,y,w,h in [(-.445,0,.015,.90),(.445,0,.015,.90),(0,-.445,.90,.015),(0,.445,.90,.015)]:box('Slot inner rim',(x,y,.07),(w,h,.02),bronze,.005)
render('skill_bezel',256,256,1.05)
print('HUD_ASSETS_COMPLETE',flush=True)

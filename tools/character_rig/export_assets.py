"""Bake the approved rig as sparse poses and a Godot SpriteFrames resource."""
from pathlib import Path
import json,hashlib,math,shutil
from PIL import Image,ImageDraw,ImageFont
import bake_rig as rig

ROOT=Path(__file__).resolve().parent
GAME=ROOT.parents[1]/"requiem/player/art/girl_rig_v2"
GAME.mkdir(parents=True,exist_ok=True)
DIRECTIONS=list(rig.FACING)
CELL=256
atlas=Image.new('RGBA',(8*CELL,17*CELL))
entries=[]
for state in ['idle','walk','sprint']:
 for direction in DIRECTIONS:
  for frame in range(1 if state=='idle' else 8):
   image=rig.render(state,frame,direction)
   index=len(entries);col=index%8;row=index//8
   alpha=image.getchannel('A').point(lambda value:255 if value>=32 else 0)
   bounds=alpha.getbbox()
   assert bounds and min(bounds[:2])>=8 and max(bounds[2:])<=248,(state,direction,frame,bounds)
   atlas.alpha_composite(image,(col*CELL,row*CELL))
   entries.append({'state':state,'direction':direction,'frame':frame,'index':index,'region':[col*CELL,row*CELL,CELL,CELL],'bounds':list(bounds)})
atlas.save(GAME/'girl_atlas.png',optimize=True)
lines=['[gd_resource type="SpriteFrames" load_steps=138 format=3]','',
 '[ext_resource type="Texture2D" path="res://player/art/girl_rig_v2/girl_atlas.png" id="1_atlas"]','']
for entry in entries:
 x,y,w,h=entry['region'];identifier='Atlas_'+str(entry['index'])
 lines += [f'[sub_resource type="AtlasTexture" id="{identifier}"]','atlas = ExtResource("1_atlas")',f'region = Rect2({x}, {y}, {w}, {h})','filter_clip = true','']
lines += ['[resource]','animations = [']
animations=[]
for state in ['idle','walk','sprint']:
 for direction in DIRECTIONS:
  matching=[entry for entry in entries if entry['state']==state and entry['direction']==direction]
  frames=', '.join('{"duration": 1.0, "texture": SubResource("Atlas_'+str(entry['index'])+'")} ' for entry in matching)
  animations.append('{\n"frames": ['+frames+'],\n"loop": true,\n"name": &"'+state+'_'+direction+'",\n"speed": '+('1.0' if state=='idle' else '8.8888888889')+'\n}')
lines += [',\n'.join(animations),']']
(GAME/'girl_frames.tres').write_text('\n'.join(lines)+'\n')
metadata={'source_type':'One AI-generated modular RGBA parts sheet, deterministic articulated texture compositing thereafter',
 'source_generator':'image_gen','source_image':'tools/character_rig/source_parts.png','source_sha256':hashlib.sha256(rig.SOURCE.read_bytes()).hexdigest(),
 'perspective':'Strict overhead orthographic constructed rig; all facings rotate this overhead rig, not the rejected oblique south sprite.',
 'directions':DIRECTIONS,'frame_size':[CELL,CELL],'pivot':[128,128],'world_scale':.5,
 'pose_counts':{'idle':1,'walk':8,'sprint':8},'loop_seconds':.9,
 'head_size':[44,57],'torso_size':[79,52],'head_torso_scale_invariant':True,
 'nominal_world_speeds':{'walk':102.4,'sprint':172.8},'stance_fraction':{'walk':.625,'sprint':.375},
 'maximum_hip_to_ankle_reach_source_px':60,'flashlight_hand':'anatomical right',
 'notes':['No generated video or frame interpolation. Every pose uses the same original part textures.',
 'The torso is compressed and rotated 180 degrees beneath the crown so its seams suggest an overhead back.',
 'Head/crown and torso dimensions are fixed. Sprint changes head/shoulder position and arm articulation, not body scale.',
 'The sparse stance key poses cancel nominal ground motion. Frame holds and acceleration/deceleration prevent a claim of continuous perfect foot locking.',
 'No baked flashlight emission or ground shadow. Dynamic game lighting remains authoritative.'],
 'crop_rectangles':rig.RECTS,'frames':entries}
(ROOT/'manifest.json').write_text(json.dumps(metadata,indent=2)+'\n')
PREVIEW=ROOT/"previews"
PREVIEW.mkdir(exist_ok=True)
# A common source frame at each action/direction, enlarged only for inspection.
rig.contact_sheet([rig.render(state,0,direction) for state in ['idle','walk','sprint'] for direction in DIRECTIONS],
 [state+' '+direction for state in ['idle','walk','sprint'] for direction in DIRECTIONS],PREVIEW/'all_directions_contacts.png',cols=8,cell=190)
rig.contact_sheet([rig.render(state,i) for state in ['walk','sprint'] for i in range(8)],
 [state+' '+str(i+1)+'/8' for state in ['walk','sprint'] for i in range(8)],PREVIEW/'production_pose_contacts.png',cols=8,cell=190)
# Native sparse gameplay-size preview: 8 direction columns, 3 action rows.
font=ImageFont.load_default(size=14)
gif=[]
scale=.5*1.65
size=round(CELL*scale)
for frame in range(8):
 canvas=Image.new('RGB',(8*190,3*210),'#292e27');draw=ImageDraw.Draw(canvas)
 for row,state in enumerate(['idle','walk','sprint']):
  for col,direction in enumerate(DIRECTIONS):
   x=col*190;y=row*210
   draw.line((x, y+177,x+190,y+177),fill='#464c40')
   draw.text((x+10,y+187),state+' '+direction,font=font,fill='#dddccc')
   image=rig.render(state,frame if state!='idle' else 0,direction).resize((size,size),Image.Resampling.LANCZOS)
   canvas.paste(image,(x+(190-size)//2,y-17),image)
 gif.append(canvas)
gif[0].save(PREVIEW/'eight_direction_motion.gif',save_all=True,append_images=gif[1:],duration=[110,110,110,120,110,110,110,120],loop=0,disposal=2)
print(json.dumps({'resource':str(GAME/'girl_frames.tres'),'atlas':str(GAME/'girl_atlas.png'),'frames':len(entries),'animations':24,'atlas_size':atlas.size,'preview':str(PREVIEW/'eight_direction_motion.gif')}))

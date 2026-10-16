"""Deterministic overhead cutout rig: transforms original modular artwork only.

World forward is +Y in the south source pose. All facings rotate this overhead
rig around the same ground-space root. No old oblique character is used.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math, json, hashlib, shutil

ROOT=Path(__file__).resolve().parent
SOURCE=ROOT/'source_parts.png'
SIZE=256
SS=3
PIVOT=(128,128)
WORLD_SCALE=.5
FACING={'s':0,'sw':-45,'w':-90,'nw':-135,'n':180,'ne':135,'e':90,'se':45}
source=Image.open(SOURCE).convert('RGBA')
RECTS={
 'torso':(70,5,425,380),'head':(520,35,770,365),
 'upper_l':(910,10,1105,380),'fore_l':(175,390,325,750),
 'upper_r':(525,388,725,752),'fore_r':(950,390,1105,753),
 'leg_l':(160,750,330,1220),'leg_r':(550,750,720,1220),
 'flashlight':(980,895,1095,1175)}
parts={}
for name,rect in RECTS.items():
 p=source.crop(rect); p=p.crop(p.getchannel('A').getbbox()); parts[name]=p
for side in ['l','r']:
 p=parts['leg_'+side]
 # Boots are rigid pieces, never stretched with the trouser segment.
 split=round(p.height*.605)
 parts['trouser_'+side]=p.crop((0,0,p.width,split+20))
 parts['thigh_'+side]=p.crop((0,0,p.width,round(split*.62)))
 parts['shin_'+side]=p.crop((0,round(split*.46),p.width,split+20))
 parts['boot_'+side]=p.crop((0,split,p.width,p.height))

def put(canvas,name,center,width,height,angle=0):
 p=parts[name].resize((max(1,round(width*SS)),max(1,round(height*SS))),Image.Resampling.LANCZOS)
 if angle: p=p.rotate(angle,Image.Resampling.BICUBIC,expand=True)
 canvas.alpha_composite(p,(round(center[0]*SS-p.width/2),round(center[1]*SS-p.height/2)))

def segment(canvas,name,a,b,width,overlap=5):
 dx=b[0]-a[0];dy=b[1]-a[1]
 length=math.hypot(dx,dy)+overlap
 angle=math.degrees(math.atan2(-dx,dy))
 put(canvas,name,((a[0]+b[0])/2,(a[1]+b[1])/2),width,length,angle)

def foot_sample(phase,speed,stance):
 # Constant-speed rearward travel during contact; smooth elevated recovery.
 stroke=speed*.9*stance/WORLD_SCALE
 if phase<stance:
  return stroke/2-stroke*phase/stance,0,True
 t=(phase-stance)/(1-stance)
 return -stroke/2+stroke*(t*t*(3-2*t)),math.sin(math.pi*t),False

def render(state='idle',frame=0,facing='s'):
 c=Image.new('RGBA',(SIZE*SS,SIZE*SS))
 phase=frame/8
 sprint=state=='sprint'
 moving=state!='idle'
 speed=172.8 if sprint else 102.4
 stance=.375 if sprint else .625
 stride_swing=[]
 for side,sign in [('l',1),('r',-1)]:
  p=(phase+(0 if side=='l' else .5))%1
  dy,lift,contact=foot_sample(p,speed,stance) if moving else (0,0,True)
  # Small lateral clearance during swing prevents feet intersecting.
  fx=128+sign*(15+lift*(3 if sprint else 2))
  fy=136+dy
  hip=(128+sign*12,129)
  ankle=(fx,fy-7)
  knee=(128+sign*(17+lift*4),129+(ankle[1]-129)*.54)
  segment(c,'thigh_'+side,hip,knee,22,9)
  segment(c,'shin_'+side,knee,ankle,18,8)
  put(c,'boot_'+side,(fx,fy),18,24,sign*3)
  stride_swing.append((side,dy,lift,contact))
 lean=7 if sprint else 0
 sway=(.9*math.sin(phase*2*math.pi)) if moving else 0
 shoulder_y=137+lean
 arms=[]
 for side,sign in [('l',1),('r',-1)]:
  # Arm opposite to corresponding leg. Torch arm has reduced excursion.
  wave=math.cos(phase*2*math.pi)*(1 if side=='r' else -1) if moving else 0
  amplitude=(19 if sprint else 9)*(0.65 if side=='r' else 1)
  shoulder=(128+sign*32+sway,shoulder_y)
  elbow=(128+sign*(39 if sprint else 36)+sway,147+lean+wave*amplitude*.6)
  hand=(128+sign*(31 if sprint else 33)+sway,161+wave*amplitude+lean)
  segment(c,'upper_'+side,shoulder,elbow,20,8)
  arms.append((side,elbow,hand))
 # Collar now points forward under the crown; compressed coat details read as
 # back seams at gameplay size. This is a strict overhead art construction.
 put(c,'torso',(128+sway,124+lean),79,52,180)
 for side,elbow,hand in arms:
  segment(c,'fore_'+side,elbow,hand,15,5)
  if side=='r':
   put(c,'flashlight',(hand[0]-1,hand[1]+4),6.5,22,-4)
 put(c,'head',(128+sway*.45,144+lean*1.35),44,57,(-1.2*math.sin(phase*2*math.pi)) if moving else 0)
 if FACING[facing]: c=c.rotate(FACING[facing],Image.Resampling.BICUBIC,center=(128*SS,128*SS))
 return c.resize((SIZE,SIZE),Image.Resampling.LANCZOS)

def contact_sheet(images,labels,path,cols=4,cell=300):
 rows=math.ceil(len(images)/cols)
 canvas=Image.new('RGB',(cols*cell,rows*(cell+32)), '#30332e')
 d=ImageDraw.Draw(canvas);font=ImageFont.load_default(size=15)
 for i,(im,label) in enumerate(zip(images,labels)):
  x=(i%cols)*cell;y=(i//cols)*(cell+32)
  p=im.resize((cell,cell),Image.Resampling.NEAREST)
  canvas.paste(p,(x,y),p)
  d.text((x+8,y+cell+6),label,font=font,fill='#dddccc')
 canvas.save(path)

if __name__=='__main__':
 ROOT.mkdir(parents=True,exist_ok=True)
 for state in ['idle','walk','sprint']:
  frames=[render(state,i) for i in range(1 if state=='idle' else 8)]
  frames[0].save(ROOT/(state+'_south_first.png'))
  if state!='idle': contact_sheet(frames,[f'{state} {i+1}/8' for i in range(8)],ROOT/(state+'_south_contacts.png'))
 contact_sheet([render('idle',0,f) for f in FACING],list(FACING),ROOT/'idle_facings.png')
 contact_sheet([render('idle'),render('walk',0),render('walk',2),render('sprint',0)],['Idle','Walk contact','Walk passing','Sprint contact'],ROOT/'first_assembly.png',cols=4,cell=300)
 print(json.dumps({'source':str(SOURCE),'output':str(ROOT),'parts':{n:list(p.size) for n,p in parts.items()},'pivot':PIVOT,'world_scale':WORLD_SCALE}))

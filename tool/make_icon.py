# Draws the app icon (aperture with a warm-to-violet gradient).
# Run from the repo root: python3 tool/make_icon.py && dart run flutter_launcher_icons
import math
from PIL import Image, ImageDraw, ImageFilter
S=4096  # supersampled
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
stops=[(0,(255,193,7)),(0.25,(255,112,67)),(0.5,(236,64,122)),(0.75,(124,77,255)),(1,(255,193,7))]
def conic(t):
    for (a,ca),(b,cb) in zip(stops,stops[1:]):
        if a<=t<=b: return lerp(ca,cb,(t-a)/(b-a))
    return stops[-1][1]

def iris(size, radius_frac):
    im=Image.new('RGBA',(size,size),(0,0,0,0))
    c=size/2; R=size*radius_frac
    # conic gradient disc
    grad=Image.new('RGB',(512,512))
    px=grad.load()
    for y in range(512):
        for x in range(512):
            a=(math.atan2(y-256,x-256)+math.pi)/(2*math.pi)
            px[x,y]=conic(a)
    grad=grad.resize((size,size),Image.BILINEAR)
    mask=Image.new('L',(size,size),0)
    d=ImageDraw.Draw(mask)
    d.ellipse([c-R,c-R,c+R,c+R],fill=255)
    # blade gaps
    r_in=R*0.34; gap=R*0.06
    for k in range(6):
        th=math.radians(60*k+15)
        vx=c+r_in*math.cos(th); vy=c+r_in*math.sin(th)
        # tangent direction
        dx=-math.sin(th); dy=math.cos(th)
        ex=vx+dx*R*2; ey=vy+dy*R*2
        d.line([(vx-dx*gap,vy-dy*gap),(ex,ey)],fill=0,width=int(gap))
    # central hexagon hole
    hexpts=[(c+r_in*math.cos(math.radians(60*k+15)),c+r_in*math.sin(math.radians(60*k+15))) for k in range(6)]
    d.polygon(hexpts,fill=0)
    # outer ring separation
    ring=R*1.10
    im.paste(grad,(0,0),mask)
    rd=ImageDraw.Draw(im)
    rd.ellipse([c-ring,c-ring,c+ring,c+ring],outline=(255,255,255,235),width=int(R*0.045))
    # small highlight dot (lens glint) in the hex
    g=r_in*0.28
    return im

def background(size):
    bg=Image.new('RGB',(size,size))
    top=(28,32,48); bot=(8,9,14)
    d=ImageDraw.Draw(bg)
    for y in range(size):
        d.line([(0,y),(size,y)],fill=lerp(top,bot,y/size))
    return bg

# Full icon (iOS + legacy Android)
full=background(S).convert('RGBA')
full.alpha_composite(iris(S,0.30))
full.convert('RGB').resize((1024,1024),Image.LANCZOS).save('assets/icon/icon.png')
# Adaptive foreground: keep within 66% safe zone
fg=iris(S,0.22)
fg.resize((1024,1024),Image.LANCZOS).save('assets/icon/icon_foreground.png')
background(1024).save('assets/icon/icon_background.png')

from pathlib import Path
import sys,json,hashlib,struct,zlib,math,subprocess
import numpy as np
from PIL import Image,ImageDraw,ImageFont
W=Path(__file__).resolve().parent;ROOT=W.parent
R=Path('C:/Users/ASUS/Desktop/HX4S20_Refactored_20261023/HX4S20_Refactored_20261023')
H=R/'src/user_source/hdl_source';D=R/'doc/robot_v67';V=R/'verification/robot_v67'
SRC=ROOT/'视频素材/robot_loops_20261028'
for p in [D,V]:p.mkdir(exist_ok=True)
sys.path.insert(0,str(ROOT/'tmp/video_tools'))
import imageio_ffmpeg
sha=lambda b:hashlib.sha256(b).hexdigest()
# Use the uncompressed source frames of the exact generated videos, including
# their identical endpoints. No extra MP4 compression generation is introduced.
clips=[];samples=[]
for name,n in [('idle',48),('welcome',72)]:
    files=sorted((SRC/('frames_'+name)).glob('*.png'))
    frames=[Image.open(files[i]).convert('RGB').resize((640,480),Image.Resampling.LANCZOS)
            for i in np.rint(np.linspace(0,len(files)-1,n)).astype(int)]
    clips.append(frames)
    samples.extend(np.asarray(f.resize((160,120),Image.Resampling.LANCZOS)).reshape(-1,3) for f in frames)
sample=np.concatenate(samples);sample=sample[:len(sample)//640*640].reshape(-1,640,3)
palette_image=Image.fromarray(sample).quantize(colors=64,method=Image.Quantize.MEDIANCUT)
pal=np.array(palette_image.getpalette(),dtype=np.uint8).reshape(-1,3)
p565=((pal[:,0].astype(np.uint16)>>3)<<11)|((pal[:,1].astype(np.uint16)>>2)<<5)|(pal[:,2]>>3)
# The synthesized synchronous palette has 64 entries, and data are checked <64.
p565=p565[:64]
rgb=np.stack([((p565>>11)<<3)|((p565>>11)>>2),(((p565>>5)&63)<<2)|(((p565>>5)&63)>>4),((p565&31)<<3)|((p565&31)>>2)],axis=1).astype(np.uint8)
pal_full=np.zeros((256,3),np.uint8);pal_full[:64]=rgb;pal_full[64:]=rgb[0]
quant=Image.new('P',(1,1));quant.putpalette(pal_full.ravel().tolist())
palette_bytes=p565.astype('<u2').tobytes();asset_id=zlib.crc32(palette_bytes)
payloads=[];indexed=[];frames_rgb=[];max_payload=0
for clip in clips:
    pp=[];ii=[];rr=[]
    for f in clip:
        ix=np.asarray(f.quantize(palette=quant,dither=Image.Dither.NONE)).copy()
        ix[ix>=64]=0
        flat=ix.ravel();starts=np.r_[0,np.flatnonzero(flat[1:]!=flat[:-1])+1];ends=np.r_[starts[1:],flat.size]
        out=bytearray()
        for start,end in zip(starts,ends):
            count=int(end-start);value=int(flat[start])
            while count:
                take=min(count,256);out.extend([take-1,value]);count-=take
        pp.append(bytes(out));ii.append(ix);rr.append(rgb[ix]);max_payload=max(max_payload,len(out))
    assert np.array_equal(ii[0],ii[-1])
    payloads.append(pp);indexed.append(ii);frames_rgb.append(rr)
stride=1<<math.ceil(math.log2((max_payload+511)//512+1))
shift=int(math.log2(stride));base=81920;bases=[base,base+48*stride]
source_image=R/'doc/video_v65/HDMI_AV_V65_LogoLoop_TF_RAW.img'
image=bytearray(source_image.read_bytes());original_length=len(image)
assert len(image)<=base*512
image.extend(bytes((bases[1]+72*stride)*512-len(image)))
metadata=[]
for c,pp in enumerate(payloads):
    records=[]
    for n,payload in enumerate(pp):
        lba=bases[c]+n*stride;header=bytearray(512)
        header[:8]=b'HXRBV001'
        struct.pack_into('<BBBBHHIIII',header,8,1,c,n,12,640,480,len(payload),zlib.crc32(payload),307200,asset_id)
        image[lba*512:lba*512+512]=header
        image[(lba+1)*512:(lba+1)*512+len(payload)]=payload
        # Independent full RLE decode checks every output pixel and length.
        p=np.frombuffer(payload,np.uint8).reshape(-1,2)
        decoded=np.repeat(p[:,1],p[:,0].astype(np.uint16)+1)
        assert decoded.size==307200 and np.array_equal(decoded,indexed[c][n].ravel())
        records.append({'frame':n,'lba':lba,'payload_bytes':len(payload),'payload_crc32':f'{zlib.crc32(payload):08x}',
                        'rgb565_sha256':sha(p565[indexed[c][n]].astype('<u2').tobytes())})
        # Lossless independent pixel oracle for the actual RTL decoder tests.
        if n in (0,len(pp)//2,len(pp)-1):
            np.savetxt(V/f'clip{c}_frame{n}_rgb565.hex',p565[indexed[c][n]].ravel(),fmt='%04x')
    out=D/('robot_idle_card_preview.mp4' if c==0 else 'robot_welcome_card_preview.mp4')
    cmd=[imageio_ffmpeg.get_ffmpeg_exe(),'-y','-v','error','-f','rawvideo','-pix_fmt','rgb24','-s','640x480','-r','12','-i','pipe:0','-an','-c:v','libx264','-crf','14','-pix_fmt','yuv420p','-movflags','+faststart',str(out)]
    subprocess.run(cmd,input=np.stack(frames_rgb[c]).tobytes(),check=True)
    metadata.append({'clip':c,'name':['idle','welcome'][c],'frames':len(pp),'seconds':len(pp)/12,'base_lba':bases[c],
                     'mean_payload_bytes':float(np.mean([len(p) for p in pp])),'max_payload_bytes':max(map(len,pp)),'frames_metadata':records})
assert image[:original_length]==source_image.read_bytes()
out=D/'HDMI_AV_V67_Robot_TF_RAW.img';out.write_bytes(image)
(D/'palette_rgb565.bin').write_bytes(palette_bytes)
(H/'av/robot_palette.hex').write_text(''.join(f'{x:04x}\n' for x in p565),encoding='ascii')
(H/'av/robot_resources.vh').write_text(f'''// Generated by robot_video_v67/make_assets.py. Matched bit and TF image required.
localparam [31:0] ROBOT_BASE_A=32'd{bases[0]},ROBOT_BASE_B=32'd{bases[1]};
localparam integer ROBOT_STRIDE_SHIFT={shift};
localparam [31:0] ROBOT_ASSET_ID=32'h{asset_id:08x};
localparam integer ROBOT_MAX_BYTES={max_payload};
''',encoding='ascii')
sheet=Image.new('RGB',(960,480),'#edf5f8')
for c in range(2):
    for col,n in enumerate([0,len(clips[c])//2,len(clips[c])-1]):
        sheet.paste(Image.fromarray(frames_rgb[c][n]).resize((320,240)),(col*320,c*240))
sheet.save(D/'card_preview_contact.png')
manifest={'format':'HXRBV001 RLE8 with count-minus-one/index pairs, global RGB565 palette','width':640,'height':480,'fps':12,'colors':64,
          'frame_stride_sectors':stride,'palette_crc32':f'{asset_id:08x}','image_bytes':len(image),'image_sha256':sha(image),
          'old_image_preserved_bytes':original_length,'source_videos':{p.name:sha(p.read_bytes()) for p in SRC.glob('*.mp4') if '12fps' not in p.name},
          'clips':metadata,'all_120_frames_roundtrip_pixel_verified':True,'first_last_identical_both_clips':True}
(D/'resource_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in manifest.items() if k!='clips'},ensure_ascii=False,indent=2))
print([(c['name'],c['mean_payload_bytes'],c['max_payload_bytes']) for c in metadata])

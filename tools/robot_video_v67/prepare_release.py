from pathlib import Path
import hashlib,json,shutil,struct,numpy as np
R=Path('C:/Users/ASUS/Desktop/HX4S20_Refactored_20261023/HX4S20_Refactored_20261023')
V=R/'verification/robot_v67';D=R/'doc/robot_v67';H=R/'src/user_source/hdl_source'
meta=json.loads((D/'resource_manifest.json').read_text(encoding='utf-8'))
palette=np.frombuffer((D/'palette_rgb565.bin').read_bytes(),'<u2')
with (D/'HDMI_AV_V67_Robot_TF_RAW.img').open('rb') as f:
 for c in meta['clips']:
  m=max(c['frames_metadata'],key=lambda x:x['payload_bytes'])
  f.seek((m['lba']+1)*512);p=np.frombuffer(f.read(m['payload_bytes']),np.uint8).reshape(-1,2)
  values=palette[np.repeat(p[:,1],p[:,0].astype(np.uint16)+1)]
  assert hashlib.sha256(values.astype('<u2').tobytes()).hexdigest()==m['rgb565_sha256']
  np.savetxt(V/f"clip{c['clip']}_frame{m['frame']}_rgb565.hex",values,fmt='%04x')
source=R/'doc/video_v65/Write_AV_V65_TF.ps1'
s=source.read_text(encoding='utf-8-sig')
s=s.replace('HDMI_AV_V65_LogoLoop_TF_RAW.img','HDMI_AV_V67_Robot_TF_RAW.img')
s=s.replace('$avManifest.sha256','$avManifest.image_sha256').replace('LogoV65DiskNative','RobotV67DiskNative')
needle='} finally { $avCheck.Dispose() }'
extra='''    foreach ($avClip in $avManifest.clips) {
        $null = $avCheck.Seek(([long]$avClip.base_lba * 512),[IO.SeekOrigin]::Begin)
        if ($avCheck.Read($avMagic,0,8) -ne 8 -or [Text.Encoding]::ASCII.GetString($avMagic) -ne 'HXRBV001') { throw 'Missing V6.7 robot video header.' }
    }
'''
s=s.replace(needle,extra+needle)
(D/'Write_AV_V67_TF.ps1').write_text(s,encoding='utf-8-sig')
stage=R/'src/td_project/HDMI_Side_Spectrum_Runs/phy_1'
shutil.copy2(stage/'HDMI_Side_Spectrum.bit',R/'output/HDMI_AV_V67_Robot_Video_J2.bit')
for n in ['HDMI_Side_Spectrum_phy.area','HDMI_Side_Spectrum_pr.timing','HDMI_Side_Spectrum_phy.ts']:
 if (stage/n).exists():shutil.copy2(stage/n,V/n)
print('Prepared V6.7 writer, copied release bit, and generated pixel oracles for the largest frames.')

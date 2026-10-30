from pathlib import Path
import datetime,hashlib,json,re,shutil,zipfile,xml.etree.ElementTree as ET
W=Path(__file__).resolve().parent;WORK=W.parent
R=Path('C:/Users/ASUS/Desktop/HX4S20_Refactored_20261023/HX4S20_Refactored_20261023')
H=R/'src/user_source/hdl_source';V=R/'verification/robot_v67';D=R/'doc/robot_v67'
stage=R/'src/td_project/HDMI_Side_Spectrum_Runs/phy_1'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert 'Generate bits file HDMI_Side_Spectrum.bit.' in (V/'place_route.log').read_text(encoding='utf-8')
assert 'ERROR' not in (V/'place_route.log').read_text(encoding='utf-8')
results=json.loads((V/'results.json').read_text(encoding='utf-8'))
required=['tb_robot_loader','tb_robot_writer','tb_robot_mode','tb_robot_ctrl','tb_robot_transition','tb_robot_board','tb_robot_early',
          'tb_cache_board','tb_transition_smooth','tb_alarm_rom_equivalence','tb_volume_ctrl','tb_volume_pcm','tb_volume_hud','mapped_roms']
assert all(results.get(n,{}).get('status')=='passed' for n in required),[(n,results.get(n)) for n in required]
bit=R/'output/HDMI_AV_V67_Robot_Video_J2.bit'
shutil.copy2(stage/'HDMI_Side_Spectrum.bit',bit)
for n in ['HDMI_Side_Spectrum_phy.area','HDMI_Side_Spectrum_pr.timing','HDMI_Side_Spectrum_phy.ts']:
 if(stage/n).exists():shutil.copy2(stage/n,V/n)
resources={};area=(V/'HDMI_Side_Spectrum_phy.area').read_text();timing=(V/'HDMI_Side_Spectrum_pr.timing').read_text()
for n in ['lut','reg','le','bram','bram32k','dsp','pll']:
 m=re.search(r'^#'+n+r'\s+(\d+)(?:\s+out of\s+(\d+))?',area,re.M)
 resources[n]={'used':int(m[1]),'total':int(m[2]) if m[2] else 19600};assert resources[n]['used']<=resources[n]['total']
setup=float(re.search(r'SWNS:\s*([-\d.]+)ns',timing)[1]);hold=float(re.search(r'HWNS:\s*([-\d.]+)ns',timing)[1]);assert hold>=0
def pads(text):
 part=text.split('Detailed IO Report')[1].split('Report Clock Domain')[0]
 return sorted(re.findall(r'^\s*(\S+)\s+(INPUT|OUTPUT|INOUT)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)',part,re.M))
assert pads(area)==pads((R/'verification/volume_v66/HDMI_Side_Spectrum_phy.area').read_text())
project=R/'src/td_project/HDMI_Side_Spectrum.al'
tree=ET.fromstring(re.sub(r'&(?!amp;|lt;|gt;|quot;|apos;)','&amp;',project.read_text(encoding='utf-8-sig')))
project_paths=[(project.parent/p.attrib['Path']).resolve() for p in tree.findall('./Source_Files//File')]
assert all(p.is_file() for p in project_paths)
assert project.read_bytes()==(project.parent/'HDMI_Side_Spectrum..10.23.al').read_bytes()
source_files=[p for p in (R/'src/user_source').rglob('*') if p.is_file()]
assert bit.stat().st_mtime>max(p.stat().st_mtime for p in source_files if p.suffix.lower() in ['.v','.vh','.hex','.adc','.sdc'])
media=json.loads((D/'resource_manifest.json').read_text(encoding='utf-8'))
image=D/'HDMI_AV_V67_Robot_TF_RAW.img';assert sha(image)==media['image_sha256']
old=R/'doc/video_v65/HDMI_AV_V65_LogoLoop_TF_RAW.img'
with image.open('rb') as f:assert f.read(old.stat().st_size)==old.read_bytes()
with zipfile.ZipFile(R/'backup_before_robot_v67_20261028/V66_sources_and_release.zip') as z:
 for n in ['src/user_source/constraints_source/pin_debug_osd_buzzer_test.adc','src/user_source/constraints_source/timing.sdc']:
  assert (R/n).read_bytes()==z.read(n)
baseline=json.loads((V/'baseline.json').read_text())
assert sha(R/'output/HDMI_AV_V66_Remote_Volume_J2.bit')==baseline['bit_sha256']
manifest={'version':'V6.7 fullscreen robot video J2 proximity / J1 remote',
 'built_at_china_time':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
 'device':'EG4S20BG256','bit':bit.name,'bit_bytes':bit.stat().st_size,'bit_sha256':sha(bit),
 'image':image.name,'image_bytes':image.stat().st_size,'image_sha256':sha(image),
 'baseline':baseline,'remote_digit_zero':{'address':'00','command':'19','raw':'00FF19E6','measured':True},
 'video':{'width':640,'height':480,'target_fps':12,'colors':64,'idle_frames':48,'welcome_frames':72,'silent':True,
          'source':'Original lossless frame sequences of user-approved generated MP4s; roundtrip all120 frames.'},
 'resources':resources,'global_setup_wns_ns':setup,'global_hold_wns_ns':hold,'whole_chip_timing_closed':setup>=0 and hold>=0,
 'constraints_and_pads_unchanged_from_v66':True,'td_project_resolved_files':len(project_paths),
 'tests':results,'physical_hardware_tested':False,'physical_card_written':False,
 'test_limits':'Full top uses models for SD transport, frame memory/reader, PLL and HDMI. Separate real frameFIFO writer test uses FIFO and external-memory response models; mapped ROM test is isolated. No whole-chip SDF or physical SDRAM data validation.',
 'timing_limit':'Existing SDRAM hard-interface and shifted-clock setup violations remain; global negative setup is not declared closed.',
 'source_sha256':{p.relative_to(R).as_posix():sha(p) for p in source_files+[project,project.parent/'HDMI_Side_Spectrum..10.23.al']}}
(V/'build_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
clock_lines='\n'.join(x for x in timing.splitlines() if re.match(r'\s*clk[0-7]\s+local',x))
(V/'clock_summary.txt').write_text(clock_lines+'\n',encoding='utf-8')

manual=f'''# V6.7 全屏机器人视频：写卡与烧录说明

日期：2026-10-28。基于当前V6.6遥控音量版。数字0使用你实测的地址00、命令19；不用开机学习。

## 1. 本次用哪两个文件

- FPGA固件：**`HDMI_AV_V67_Robot_Video_J2.bit`**。
- SD/TF镜像：**`HDMI_AV_V67_Robot_TF_RAW.img`**。
- 写卡脚本：`Write_AV_V67_TF.ps1`。

**这次要更新固件，也要把新镜像写入TF卡。** 不能只复制MP4进卡。当前工程按原始扇区读资源，不使用普通FAT文件系统。

桌面已准备好可直接操作的文件夹：

`C:/Users/ASUS/Desktop/HX4S20_V67_Robot_Release`

完整源码仍在原工程：

`C:/Users/ASUS/Desktop/HX4S20_Refactored_20261023/HX4S20_Refactored_20261023`

入口：`src/td_project/HDMI_Side_Spectrum.al`。不要选择独立的数字0测码工程。

## 2. 实现后的操作

|操作或状态|结果|
|---|---|
|上电/KEY1复位|进入原图文模式|
|短按遥控数字0|进入全屏机器人视频模式；再短按一次回到图文模式|
|长按0|只切换一次；松开后再按才再次切换|
|视频模式，远处|循环播放4秒待机视频，机器人轻微晃动、眨眼|
|稳定小于20cm|切换到6秒迎宾视频，从第0帧开始，挥手并弹出“欢迎使用我们这个产品”|
|稳定大于25cm|切回待机视频，从第0帧开始|
|20～25cm|保持当前视频；沿用原连续确认和迟滞|
|一直靠近或一直远离|当前视频正常循环，不因每次测距采样重新开始|
|进入时已经靠近|直接播放迎宾视频|
|视频模式按遥控上/下|原音量档位和音量弹窗正常，短按一档、长按不连调|
|原亮度/对比度操作|保持原KEY3、拨码开关规则和参数弹窗|
|遥控1/3/4/2|沿用报警、静音、恢复报警声、解除；报警显示和声音优先|
|退出视频模式|恢复原图文场景、轮播开关和参数，并按当前距离处理照片/详情页|

视频模式不显示原滚动字幕、双侧频谱、右上角旧小视频和其细状态条。迎宾对话框已包含在视频内容里，会正常显示。调节弹窗仍按原规则出现和消失；亮度/对比度沿用SW3/SW4条件，音量弹窗仍独立于它们。

两段视频均为无声素材，视频模式暂停原图片讲解和音乐，因此调音量时不会凭空产生视频声音；退出后按新的音量继续普通媒体。报警声音仍按原规则处理。原板上KEY2“下一张”、KEY4“轮播开关”在视频模式中不改变暂停的图片状态。

切换会等待距离稳定确认、读完目标帧、完成SDRAM写入并在帧边界提交，实际响应和帧率需上板确认。视频首尾共用相同待机姿势；距离在动作中途改变时，会在完整帧准备后切换到另一段的起始姿势，不保证任意中间动作的姿势都相同。

## 3. 先写入SD/TF卡

**整镜像写入会覆盖所选卡原分区表和已有数据布局。先备份卡上需要的文件，并核对实际磁盘编号。** 本次软件代理没有操作实物卡。

1. 开发板断电，取出TF卡并插入电脑读卡器。
2. 打开管理员PowerShell，进入桌面发布文件夹，先只列盘：

```powershell
Set-Location -LiteralPath 'C:/Users/ASUS/Desktop/HX4S20_V67_Robot_Release'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./Write_AV_V67_TF.ps1
```

3. 根据名称、USB/SD类型及容量确认本次TF卡的Number。编号可能变化，不沿用旧截图或示例编号。再运行：

```powershell
$tfCardNumber = Read-Host '输入刚核对的TF卡Number数字'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./Write_AV_V67_TF.ps1 -DiskNumber $tfCardNumber -Write
```

4. 脚本再次显示目标，按提示输入`WRITE DISK 实际编号`。它会拒绝系统盘、启动盘及不支持的目标类型。
5. 等待 **Written and verified**。脚本写入后完整读回已写区域并核对SHA256；未通过就不要跳过校验继续用卡。
6. Windows如果提示格式化，选择**取消**。安全移除读卡器，把卡插回断电的开发板。无需提前格式化。

本镜像为{image.stat().st_size:,}字节，即47.5MiB；这是写入数据范围，不是整张卡容量。资源镜像保留原V6.5卡前{old.stat().st_size:,}字节不变，新增两条机器人视频。

## 4. 再下载FPGA固件

1. 保持原J1遥控、J2测距、HDMI和USB-JTAG接线，无需换线。
2. TD/BitWizard选择 **EG4S20BG256 → Program SRAM**，下载本包`HDMI_AV_V67_Robot_Video_J2.bit`。
3. 下载成功后短按板上KEY1再松开，先等待原图文画面正常出现。
4. 遥控短按0，观察待机机器人；用白板等目标靠近10～15cm，再退到35～40cm，验证迎宾和待机切换。
5. Program SRAM掉电会丢失，下次上电需重新下载。不要用数字0测码bit代替正式V6.7。

## 5. 首次上板建议检查

- 待机约4秒循环、迎宾约6秒循环，首尾无明显跳变；近处持续停留不会反复卡在第0帧。
- 视频铺满640×480画面，原字幕、频谱、右上角旧视频及细条隐藏。
- 上/下音量、KEY3亮度/对比度及原参数弹窗可用，切视频和切模式后设置保持。
- 按0退出后，原图文、字幕、频谱、小视频、声音和测距详情页恢复。
- 长按0不来回切换；靠近/远离快速变化、报警1/3/4/2后仍能恢复。

如果视频没出现或停住，先核对bit文件名、写卡是否出现Written and verified，以及是否使用同包镜像。异常帧不会作为完整新帧提交；可按0退回图文，必要时KEY1复位后重试。保留整屏照片和操作顺序便于定位。

## 6. 已完成验证与实际限制

- 两条视频转换成640×480、目标12fps、64色RGB565调色板的RLE帧资源；48/72帧全部120帧软件逐像素往返检查通过，首尾一致。相较原MP4会有颜色量化差别，`preview/`中是实际卡格式的预览。
- 真实RTL解码9个完整视频帧，包含两段最大字节帧，校验像素、CRC、背压、坏头部/索引/版本/资源ID、超时与恢复。在50MHz/12.5MHz SPI速率输入模型中，抽测加载约35～44ms；不能当作真实TF卡响应测量。
- 使用生产`frame_read_write`和`frame_fifo_write_wavefix`验证三个完整帧、921600个像素的数据与地址，覆盖三个SDRAM槽位、较慢存储时钟和FIFO满节流。外部SDRAM与FIFO原语采用模型。
- 完整顶层验证实测码的串行NEC波形、0键长按、近远切片、弹窗、静音视频、报警、图片缓存保护和恢复；另测“图片尚在等待音频时进入视频”和“首图完成前进入/退出”。SD传输、帧存储、PLL、HDMI为模型。
- 原七场景图文、音量、PCM、HUD和淡化回归通过。报警字库从逻辑case移入两块32K BRAM，2457600个像素及RGB/VS/DE与V6.6完全一致；调色板和报警字库通过TD映射后的厂商BRAM原语仿真。
- TD完成综合、布局布线和bitgen；引脚和约束与V6.6一致。LUT {resources['lut']['used']}/19600，9K BRAM {resources['bram']['used']}/64，32K BRAM {resources['bram32k']['used']}/16。
- 全局setup WNS **{setup:.3f}ns**，hold WNS **{hold:.3f}ns**；原SDRAM硬接口及移相时钟setup遗留违例仍在，不能称为全工程时序完全收敛。
- **尚未实物上板验证，也未替你写实物卡。** 软件/模型验证不代替真实SD卡、SDRAM、显示器和传感器验收。

## 7. 回退与源文件

原V6.6固件保留在原工程`output/HDMI_AV_V66_Remote_Volume_J2.bit`。新镜像完整保留旧资源，回退V6.6只需重新Program SRAM下载该旧bit，不必为了回退重写卡。修改前源码和固件已备份在`backup_before_robot_v67_20261028/V66_sources_and_release.zip`。

完整源码、验证、清单见原工程`src/`、`verification/robot_v67/`和`doc/robot_v67/`。常规重建依次运行`verification/robot_v67/build.py syn`和`build.py phy`。保留相邻的HEX初始化文件；完整归档包含重建所需的TD流程模板。

固件SHA256：`{sha(bit)}`。

镜像SHA256：`{sha(image)}`。
'''
(R/'V6_7_全屏机器人视频_写卡与烧录说明.md').write_text(manual,encoding='utf-8')

release=Path('C:/Users/ASUS/Desktop/HX4S20_V67_Robot_Release');release.mkdir(exist_ok=True)
for p in [bit,image,D/'Write_AV_V67_TF.ps1',D/'resource_manifest.json',V/'build_manifest.json']:
 shutil.copy2(p,release/p.name)
(release/'先看这里_写卡与烧录说明.md').write_text(manual,encoding='utf-8')
(release/'preview').mkdir(exist_ok=True)
for n in ['robot_idle_card_preview.mp4','robot_welcome_card_preview.mp4','card_preview_contact.png']:
 shutil.copy2(D/n,release/'preview'/n)
key=WORK/'红外遥控器实测/数字0_20261028'
for p in key.glob('*'):
 (release/'zero_key_measurement').mkdir(exist_ok=True);shutil.copy2(p,release/'zero_key_measurement'/p.name)

# Source/verification archive is separate so the ready-to-write release stays clear.
source_zip=release/'V67_工程源码与验证.zip'
with zipfile.ZipFile(source_zip,'w',zipfile.ZIP_DEFLATED) as z:
 for p in source_files+[project,project.parent/'HDMI_Side_Spectrum..10.23.al']:
  z.write(p,p.relative_to(R))
 for stage_name in ['syn_1','phy_1']:
  for p in (R/'src/td_project/HDMI_Side_Spectrum_Runs'/stage_name).iterdir():
   if p.is_file() and p.suffix in ['.tcl','.cfg','.hex']:z.write(p,p.relative_to(R))
 for p in V.iterdir():
  if p.is_file() and p.suffix.lower() in ['.py','.sv','.v','.json','.log','.txt','.area','.timing','.ts','.hex']:
   z.write(p,p.relative_to(R))
 for p in (V/'rom_gate').iterdir():
  if p.is_file() and p.suffix.lower() in ['.py','.sv','.v','.log','.hex','.area']:z.write(p,p.relative_to(R))
 for p in W.glob('*.py'):z.write(p,Path('tools/robot_video_v67')/p.name)
 z.write(R/'V6_7_全屏机器人视频_写卡与烧录说明.md','V6_7_全屏机器人视频_写卡与烧录说明.md')
 z.write(D/'resource_manifest.json','doc/robot_v67/resource_manifest.json')
 z.write(image,'doc/robot_v67/HDMI_AV_V67_Robot_TF_RAW.img')

archive=WORK/'HDMI_AV_V67_机器人全屏视频_完整烧录包.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for p in release.rglob('*'):
  if p.is_file():z.write(p,Path(release.name)/p.relative_to(release))
shutil.copy2(archive,R/'output'/archive.name)
(R/'开始使用.md').write_text('''# 当前版本：V6.7 全屏机器人视频，J2测距 / J1遥控

- 最新固件：`output/HDMI_AV_V67_Robot_Video_J2.bit`。
- 必须配套新TF镜像：`doc/robot_v67/HDMI_AV_V67_Robot_TF_RAW.img`。
- 写卡/烧录说明：`V6_7_全屏机器人视频_写卡与烧录说明.md`。
- 桌面直接操作文件夹：`C:/Users/ASUS/Desktop/HX4S20_V67_Robot_Release`。
- 实测数字0在图文/全屏视频之间切换；远处4秒待机机器人、近处6秒挥手欢迎。原字幕、频谱和右上角旧视频在视频模式隐藏，参数弹窗和报警保留。
- 保留V6.6音量、三帧图片缓存、缩放、J2测距详情页及原图文功能。
- 14项测试记录通过，TD综合/布局布线/bitgen完成。尚未实物上板，原SDRAM时序遗留违例仍在。
''',encoding='utf-8')
(R/'最新下载文件.txt').write_text('V6.7全屏机器人视频\nFPGA：output/HDMI_AV_V67_Robot_Video_J2.bit\nTF：doc/robot_v67/HDMI_AV_V67_Robot_TF_RAW.img\n说明：V6_7_全屏机器人视频_写卡与烧录说明.md\n本次必须更新bit和TF资源镜像。尚未实物上板。\n',encoding='utf-8')
validation={'bit_sha256':sha(bit),'image_sha256':sha(image),'release_folder':str(release),'archive':str(archive),
 'archive_sha256':sha(archive),'tests_passed':len(required),'constraints_and_pads_identical':True,'archive_bytes':archive.stat().st_size}
(V/'package_verification.json').write_text(json.dumps(validation,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(validation,ensure_ascii=False,indent=2))

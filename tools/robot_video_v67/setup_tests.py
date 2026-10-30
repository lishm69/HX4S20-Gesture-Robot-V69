from pathlib import Path
import shutil
R=Path('C:/Users/ASUS/Desktop/HX4S20_Refactored_20261023/HX4S20_Refactored_20261023')
V=R/'verification/robot_v67';H=R/'src/user_source/hdl_source'
for n in ['run_integration.py','tb_cache_board.sv','tb_transition_smooth.sv','run_units.py','tb_volume_ctrl.sv','tb_volume_pcm.sv','tb_volume_hud.sv','ir_test_raster.v','osd_v651_reference.v']:
 s=(R/'verification/volume_v66'/n).read_text(encoding='utf-8').replace('volume66_work','robot67_work')
 if n=='run_integration.py':
  s=s.replace('names=sys.argv[1:] or', "names=sys.argv[1:] or")
 (V/n).write_text(s,encoding='utf-8')
shutil.copy2(H/'av/robot_palette.hex',V/'robot_palette.hex')
shutil.copy2(R/'verification/volume_v66/build.py',V/'build.py')
# Builds find initialized BRAM data in their own working directories.
for stage in ['syn_1','phy_1']:
 shutil.copy2(H/'av/robot_palette.hex',R/'src/td_project/HDMI_Side_Spectrum_Runs'/stage/'robot_palette.hex')
print(V)

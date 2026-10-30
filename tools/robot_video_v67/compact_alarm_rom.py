from pathlib import Path
import re,shutil,zipfile
R=Path('C:/Users/ASUS/Desktop/HX4S20_Refactored_20261023/HX4S20_Refactored_20261023')
H=R/'src/user_source/hdl_source';V=R/'verification/robot_v67'
with zipfile.ZipFile(R/'backup_before_robot_v67_20261028/V66_sources_and_release.zip') as z:
 s=z.read('src/user_source/hdl_source/emergency_ui_v2.v').decode('utf-8-sig').replace('\r\n','\n')
(V/'emergency_ui_v66_reference.v').write_text(s.replace('module emergency_ui_v2(','module emergency_ui_v66_reference(',1),encoding='utf-8')
rows=[0]*2048
for a,b in re.findall(r"11'd(\d+):glyph_row=32'h([0-9a-fA-F]+);",s):rows[int(a)]=int(b,16)
(H/'av/alarm_glyph_rows.hex').write_text(''.join(f'{x:08x}\n' for x in rows),encoding='ascii')
shutil.copy2(H/'av/alarm_glyph_rows.hex',H/'alarm_glyph_rows.hex')
start=s.index('function [31:0] glyph_row;');end=s.index('endfunction',start)+len('endfunction')
s=s[:start]+'''// Identical glyph rows, moved from combinational case LUTs to two 32K BRAMs.
reg [31:0] alarm_glyph_rom[0:2047] /* synthesis ram_style=bram_32k */;
initial $readmemh("alarm_glyph_rows.hex",alarm_glyph_rom);
'''+s[end:]
s=s.replace('ink_b<=0;bitmap_b<=0;col_b<=0;','ink_b<=0;col_b<=0;')
s=s.replace('  bitmap_b<=glyph_row(glyph_a,row_a);col_b<=col_a;','  col_b<=col_a;')
s=s.replace('reg vs_a,de_a,vs_b,de_b;','reg vs_a,de_a,vs_b,de_b;\nalways @(posedge clk)bitmap_b<=alarm_glyph_rom[{glyph_a,row_a}];')
(H/'emergency_ui_v2.v').write_text(s,encoding='utf-8')
for p in [V,R/'src/td_project/HDMI_Side_Spectrum_Runs/syn_1',R/'src/td_project/HDMI_Side_Spectrum_Runs/phy_1']:
 shutil.copy2(H/'av/alarm_glyph_rows.hex',p/'alarm_glyph_rows.hex')
print('Preserved 2048 alarm glyph rows exactly; synchronous BRAM read replaces existing registered case read.')

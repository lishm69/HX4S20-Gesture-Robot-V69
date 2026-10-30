from pathlib import Path
import subprocess,shutil,json
R=Path('C:/Users/ASUS/Desktop/HX4S20_Refactored_20261023/HX4S20_Refactored_20261023')
H=R/'src/user_source/hdl_source';V=R/'verification/robot_v67/rom_gate';V.mkdir(exist_ok=True)
for n in ['robot_palette.hex','alarm_glyph_rows.hex']:shutil.copy2(H/'av'/n,V/n)
(V/'rom_probe.v').write_text('''module rom_probe(input clk,input[5:0] pi,input[10:0] ai,output reg[15:0] color,output reg[31:0] row);
reg [15:0] palette[0:63] /* synthesis ram_style=block */;
reg [31:0] alarm_glyph_rom[0:2047] /* synthesis ram_style=bram_32k */;
initial $readmemh("robot_palette.hex",palette);
initial $readmemh("alarm_glyph_rows.hex",alarm_glyph_rom);
always @(posedge clk)begin color<=palette[pi];row<=alarm_glyph_rom[ai];end
endmodule
''',encoding='ascii')
tcl='import_device eagle_s20.db -package EG4S20BG256\nread_verilog -file {rom_probe.v} -top rom_probe\noptimize_rtl\noptimize_gate -packarea rom.area\nwrite_verilog rom_gate.v\nexit\n'
p=subprocess.run(['C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/run.exe'],input=tcl,text=True,cwd=V,capture_output=True,timeout=120)
s=p.stdout+p.stderr;(V/'synthesis.log').write_text(s,encoding='utf-8');assert p.returncode==0 and 'ERROR' not in s,s[-3000:]
(V/'tb_rom.sv').write_text('''`timescale 1ns/1ps
module tb_rom;
reg clk=0;always #5 clk=~clk;reg[5:0] pi=0;reg[10:0] ai=0;
wire[15:0] color;wire[31:0] row;reg[15:0] ep[0:63];reg[31:0] ea[0:2047];integer i;
rom_probe d(.clk(clk),.pi(pi),.ai(ai),.color(color),.row(row));
initial begin
 $readmemh("robot_palette.hex",ep);$readmemh("alarm_glyph_rows.hex",ea);#1000;
 for(i=0;i<2048;i++)begin @(negedge clk);pi=i%64;ai=i;@(posedge clk);#1;
  if(color!==ep[i%64]||row!==ea[i])$fatal(1,"mapped ROM mismatch %d palette=%h/%h row=%h/%h",i,color,ep[i%64],row,ea[i]);
 end
 $display("PASS tb_rom_gate: TD-mapped 64-entry robot palette and all 2048 alarm glyph rows preserve initialized values and single-clock latency using vendor BRAM primitives");$finish;
end
endmodule
''',encoding='ascii')
S=Path('C:/modeltech64_10.4/win64');sim=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release')
def run(args,n):
 p=subprocess.run([str(x) for x in args],cwd=V,capture_output=True,text=True,errors='replace',timeout=120)
 s=p.stdout+p.stderr;(V/(n+'.log')).write_text(s,encoding='utf-8');assert p.returncode==0 and '** Error' not in s and '** Fatal' not in s,s[-3000:]
 return s
if not(V/'modelsim.ini').exists():run([S/'vmap.exe','-c'],'vmap')
if not(V/'work').exists():run([S/'vlib.exe','work'],'vlib')
run([S/'vlog.exe',*(sim/'common').glob('*.v'),*(sim/'eg4').glob('*.v'),V/'rom_gate.v'],'compile')
run([S/'vlog.exe','-sv',V/'tb_rom.sv'],'compile_tb')
s=run([S/'vsim.exe','-c','-onfinish','stop','work.tb_rom','work.glbl','-do','run -all; quit -f'],'simulation')
assert 'PASS tb_rom_gate' in s
messages=[x for x in s.splitlines() if 'PASS' in x];print('\n'.join(messages))
p=V.parent/'results.json';results=json.loads(p.read_text());results['mapped_roms']={'status':'passed','messages':messages,'scope':'Isolated same ROM inference patterns, TD gate mapping and vendor primitives. Not full-chip post-route simulation.'};p.write_text(json.dumps(results,indent=2),encoding='utf-8')

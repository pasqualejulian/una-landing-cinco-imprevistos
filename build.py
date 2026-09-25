"""Export original Godot 3 scenes with isolated browser platform adapters."""
from pathlib import Path
import shutil, subprocess, json, re, os
WEB=Path(__file__).resolve().parent
REPO=WEB/'godot-project'
WORK=WEB/'.build-godot'
STAGE=WORK/'web-godot-project'
GODOT=Path(os.environ.get('GODOT_BIN','godot'))
DIST=WEB/'game-export'
TEMPLATE=os.environ.get('GODOT_WEB_TEMPLATE', '')
for directory in (STAGE,DIST): directory.mkdir(parents=True,exist_ok=True)
for folder in ['cards','fonts','images','levels','music','nodes','resources','scenes','scripts','sounds','styles','.import']:
 if (REPO/folder).exists(): shutil.copytree(REPO/folder,STAGE/folder,dirs_exist_ok=True)
for name in ['project.godot','default_bus_layout.tres','LICENSE.md']:
 shutil.copy2(REPO/name,STAGE/name)
shutil.copytree(WEB/'godot',STAGE/'web/godot',dirs_exist_ok=True)
shutil.copy2(WEB/'shell.html',STAGE/'web/shell.html')

def patch(path,old,new):
 file=STAGE/path
 text=file.read_text()
 if old not in text: raise RuntimeError(f'Expected source not found: {path}: {old[:100]}')
 file.write_text(text.replace(old,new))

patch('project.godot','run/main_scene="res://scenes/title.tscn"','run/main_scene="res://scenes/first_mission/mission.tscn"')
patch('project.godot','window/size/fullscreen=true','window/size/fullscreen=false')
patch('project.godot','levels="*res://scenes/levels.gd"','levels="*res://web/godot/levels.gd"')
patch('project.godot','[rendering]','[rendering]\n\nquality/driver/driver_name="GLES2"')
# Scene keeps the original music resource, with only the platform-specific
# autoload/controller swapped. No OS/TCP services are exported as live nodes.
file=STAGE/'scenes/game.tscn'
text=file.read_text().replace('res://scenes/game.gd','res://web/godot/game.gd')
text=text[:text.index('[node name="ShellServer"')]
text=re.sub(r'\[ext_resource[^\n]*tcp_server_shell[^\n]*\n','',text).replace('load_steps=4','load_steps=3')
file.write_text(text)
file=STAGE/'scenes/terminal.tscn'
text=file.read_text()
text=re.sub(r'\[ext_resource[^\n]*tcp_server.tscn[^\n]*\n', '', text)
text=text.replace('[node name="TCPServer" parent="." instance=ExtResource( 6 )]\n', '')
text=re.sub(r'\[connection[^\n]*from="TCPServer"[^\n]*\n', '', text)
file.write_text(text)
patch('scenes/terminal.gd','var shell = Shell.new()','var shell = preload("res://web/godot/shell.gd").new()')
patch('scenes/terminal.gd','\temit_signal("command_done")\n\t\nfunc receive_output','\temit_signal("command_done")\n\tcmd.queue_free()\n\t\nfunc receive_output')
patch('scenes/text_editor.gd','func _ready():','func _ready():\n\tset_process(false)\n\treturn\n')
patch('scenes/first_mission/mission.gd','preload("res://scenes/first_mission/engine.gd")','preload("res://web/godot/engine.gd")')
patch('scenes/first_mission/mission.gd','preload("res://scenes/first_mission/repository.gd")','preload("res://web/godot/repository.gd")')
patch('scenes/first_mission/mission.tscn','res://scenes/first_mission/mission.gd','res://web/godot/campaign.gd')
patch('scenes/first_mission/mission.gd','$Menu/BackButton.text = \"Salir\"','$Menu/BackButton.text = \"Recargar\"')
# HTML5 exports do not enable Godot's macOS LineEdit shortcuts automatically.
patch('scenes/first_mission/mission.gd','func _input(event):','''func _input(event):
	if event is InputEventKey and event.pressed and event.meta and event.scancode == KEY_A:
		var focused = get_focus_owner()
		if focused is LineEdit:
			focused.select_all()
			get_tree().set_input_as_handled()
			return''')
# This publishes diagnostic geometry/state only, no alternate action path.
file=STAGE/'scenes/first_mission/mission.gd'
file.write_text(file.read_text()+'\n'+(WEB/'godot/diagnostics.gd').read_text())
# The prototype is a single scene. Exclude old tests/docs/caches from the pack.
preset=f'''[preset.0]
name="First Mission Web"
platform="HTML5"
runnable=true
custom_features=""
export_filter="all_resources"
include_filter="resources/*, cards/*"
exclude_filter="tests/*, docs/*, cache/*, dependencies/*, levels/*"
export_path="{DIST}/index.html"
script_export_mode=1
script_encryption_key=""
[preset.0.options]
custom_template/release="{TEMPLATE}"
custom_template/debug=""
variant/export_type=0
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/custom_html_shell="res://web/shell.html"
html/head_include=""
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
progressive_web_app/enabled=false
'''
(STAGE/'export_presets.cfg').write_text(preset)
# Derive exact landing documents from the source controller, not a second copy.
source=(REPO/'scenes/guided/engine.gd').read_text()
html=re.search(r'func _html\(title, button\):\s*return """(.*?)"""',source,re.S).group(1)
css=re.search(r'func _css\(color\):\s*return """(.*?)"""',source,re.S).group(1)
config={'baseHtml':html%('Dale lugar a tu idea','Empezá ahora'),'baseCss':css%'#6750a4',
 'choiceHtml':{key:html%(title,'Empezá ahora') for key,title in [('idea_vida','Dale vida a tu idea'),('idea_proxima','Tu próxima idea empieza acá')]},
 'titles':{'idea_vida':'Dale vida a tu idea','idea_proxima':'Tu próxima idea empieza acá'}}
(DIST/'mission-config.json').write_text(json.dumps(config,ensure_ascii=False))
subprocess.run([str(GODOT),'--headless','--path',str(STAGE),'--editor','--quit'],check=True)
subprocess.run([str(GODOT),'--headless','--path',str(STAGE),'--export','First Mission Web',str(DIST/'index.html')],check=True)
shutil.copy2(REPO/'LICENSE.md',DIST/'LICENSE.md')
(DIST/'_headers').write_text('/*.wasm\n  Content-Type: application/wasm\n/*\n  X-Content-Type-Options: nosniff\n')
subprocess.run(['npm', 'run', 'build'],cwd=WEB,check=True)
print(f'Web build ready: {DIST}',flush=True)

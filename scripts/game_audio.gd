extends Node
const Bed := preload("res://scripts/audio_crossfade_bed.gd")
const MENU := "res://sfx/BGM/mixkit-games-worldbeat-466.mp3"
const CLICK := "res://sfx/ui and clidk/Audio/click1.ogg"
const WIN := "res://sfx/BGM/Win lose/mixkit-retro-game-notification-212.wav"
const LOSE := "res://sfx/BGM/Win lose/mixkit-arcade-retro-game-over-213.wav"
const GLITCH := "res://sfx/Ambience/Glitch/virtual_vibes-glitch-sound-effect-hd-379466.mp3"
const TRACKS := {
"beautiful_dream":{"name":"Beautiful Dream","path":"res://sfx/BGM/mixkit-beautiful-dream-493.mp3"},
"discover":{"name":"Discover","path":"res://sfx/BGM/mixkit-discover-587.mp3"},
"dry_gin":{"name":"Dry Gin","path":"res://sfx/BGM/mixkit-dry-gin-868.mp3"},
"pop_05":{"name":"Pop 05","path":"res://sfx/BGM/mixkit-pop-05-695.mp3"},
"sleepy_cat":{"name":"Sleepy Cat","path":"res://sfx/BGM/mixkit-sleepy-cat-135.mp3"}}
const AMBIENCE := {
"rain":"res://sfx/Ambience/Rain/boons_freak-rain-sound-188158.mp3",
"wind":"res://sfx/Ambience/Wind/soundreality-wind-blowing-457954.mp3",
"day":"res://sfx/Ambience/River/mixkit-natural-ambience-with-flowing-water-and-birds-61.wav",
"night":"res://sfx/Ambience/River/mixkit-summer-night-in-the-forest-1227.wav"}
const DEFAULTS := {"master_volume":0.85,"music_volume":0.70,"ambience_volume":0.20,"sfx_volume":0.70,"stage_ost":"shuffle"}
const BUSES := {"master_volume":"Master","music_volume":"HertzMusic","ambience_volume":"HertzAmbience","sfx_volume":"HertzSFX"}
var enabled := true
var scope := ""
var preference := "shuffle"
var music
var beds: Dictionary = {}
var glitch
var ui_player: AudioStreamPlayer
var result_player: AudioStreamPlayer
var cache: Dictionary = {}
var queue: Array[String] = []
var played: Array[String] = []
var cycle := 0
var current_track := ""
var last_stage_track := ""
var ambience_key := ""
var environment: Dictionary = {}
var rng := RandomNumberGenerator.new()
var result_count := 0
var click_count := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	for bus in ["HertzMusic","HertzAmbience","HertzSFX"]:
		if AudioServer.get_bus_index(bus)<0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count-1,bus)
			AudioServer.set_bus_send(AudioServer.get_bus_index(bus),"Master")
	music = _bed("HertzMusic",0.8)
	music.needs_next.connect(_advance_music)
	for key in AMBIENCE:
		var bed = _bed("HertzAmbience",1.2)
		bed.mix_target = 0.55
		bed.mix_gain = 0.55
		bed.needs_next.connect(func():
			if ambience_key==key and scope=="stage": bed.start(_stream(AMBIENCE[key]),key)
		)
		beds[key] = bed
	glitch = _bed("HertzSFX",0.25)
	glitch.mix_target = 0.13
	glitch.mix_gain = 0.13
	glitch.needs_next.connect(func():
		if glitch.wanted: glitch.start(_stream(GLITCH),"glitch")
	)
	ui_player = AudioStreamPlayer.new()
	ui_player.bus = "HertzSFX"
	ui_player.max_polyphony = 8
	ui_player.volume_db = -6
	add_child(ui_player)
	result_player = AudioStreamPlayer.new()
	result_player.bus = "HertzSFX"
	result_player.volume_db = -3
	add_child(result_player)

func _bed(bus: String, fade: float):
	var bed = Bed.new()
	bed.enabled = enabled
	bed.bus_name = bus
	bed.fade_seconds = fade
	add_child(bed)
	return bed

func _stream(path: String) -> AudioStream:
	if not cache.has(path):
		var source := load(path) as AudioStream
		if source==null: return null
		var stream := source.duplicate() as AudioStream
		# Loop boundaries are crossfaded by the bed, not by the import setting.
		if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis: stream.loop = false
		elif stream is AudioStreamWAV: stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		cache[path] = stream
	return cache[path]

func configure(settings: Dictionary) -> void:
	for key in BUSES: set_volume(key,float(settings.get(key,DEFAULTS[key])))
	preference = String(settings.get("stage_ost","shuffle"))
	if preference!="shuffle" and not TRACKS.has(preference): preference = "shuffle"

func set_volume(key: String, value: float) -> void:
	if not BUSES.has(key): return
	var bus := AudioServer.get_bus_index(BUSES[key])
	if bus>=0:
		AudioServer.set_bus_volume_db(bus,linear_to_db(maxf(0.0001,clampf(value,0,1))))
		AudioServer.set_bus_mute(bus,value<=0)

func set_stage_ost(id: String) -> void:
	preference = id if id=="shuffle" or TRACKS.has(id) else "shuffle"
	queue.clear()
	played.clear()
	cycle = 0
	if scope=="stage": _advance_music()

func next_stage_track() -> String:
	if queue.is_empty():
		queue.assign(TRACKS.keys())
		for i in range(queue.size()-1,0,-1):
			var j := rng.randi_range(0,i)
			var temp := queue[i]
			queue[i] = queue[j]
			queue[j] = temp
		if cycle==0 and preference!="shuffle" and preference in queue:
			queue.erase(preference)
			queue.push_front(preference)
		elif queue.size()>1 and queue[0]==last_stage_track:
			var temp := queue[0]
			queue[0] = queue[1]
			queue[1] = temp
		cycle += 1
	var id: String = queue.pop_front()
	last_stage_track = id
	played.append(id)
	return id

func set_scope(next_scope: String) -> void:
	if scope==next_scope: return
	scope = next_scope
	if scope=="menu":
		current_track = "menu_worldbeat"
		music.start(_stream(MENU) if enabled else null,current_track)
		_set_ambience("")
		glitch.silence()
	else:
		_advance_music()
		update_environment(environment)

func _advance_music() -> void:
	if scope=="menu":
		current_track = "menu_worldbeat"
		music.start(_stream(MENU) if enabled else null,current_track)
	else:
		current_track = next_stage_track()
		music.start(_stream(TRACKS[current_track]["path"]) if enabled else null,current_track)

static func ambience_for(state: Dictionary) -> String:
	if float(state.get("rain_intensity",0))>0.05: return "rain"
	if float(state.get("cloud_cover",0))>=0.55: return "wind"
	var minute := int(state.get("current_min",420))%1440
	return "day" if minute>=360 and minute<1080 else "night"

func update_environment(state: Dictionary) -> void:
	environment = state.duplicate()
	if scope!="stage": return
	_set_ambience(ambience_for(state))
	var abnormal := bool(state.get("running",false)) and absf(float(state.get("frequency",50))-50.0)>0.005
	if abnormal and not glitch.wanted: glitch.start(_stream(GLITCH) if enabled else null,"glitch")
	elif not abnormal: glitch.silence()

func _set_ambience(key: String) -> void:
	if ambience_key==key: return
	ambience_key = key
	for name in beds:
		if name==key: beds[name].start(_stream(AMBIENCE[name]) if enabled else null,name)
		else: beds[name].silence()

func set_ducked(ducked: bool) -> void:
	music.mix_target = 0.45 if ducked else 1.0
	for bed in beds.values(): bed.mix_target = 0.25 if ducked else 0.55
	if ducked: glitch.silence()

func play_click() -> void:
	click_count += 1
	if enabled:
		ui_player.stream = _stream(CLICK)
		ui_player.play()

func play_result(success: bool) -> void:
	result_count += 1
	glitch.silence()
	if enabled:
		result_player.stream = _stream(WIN if success else LOSE)
		result_player.play()

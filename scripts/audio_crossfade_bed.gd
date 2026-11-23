extends Node
## Two voices overlap at transitions and loop boundaries; no audible hard stop.
signal needs_next
var enabled := true
var bus_name := "Master"
var fade_seconds := 0.8
var voices: Array[AudioStreamPlayer] = []
var gains: Array[float] = [0.0,0.0]
var active_voice := -1
var wanted := false
var mix_gain := 1.0
var mix_target := 1.0
var stream_id := ""
var transitions := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.bus = bus_name
		player.volume_db = -80
		add_child(player)
		player.finished.connect(func():
			if i==active_voice and wanted: needs_next.emit()
		)
		voices.append(player)

func start(stream: AudioStream, id: String) -> void:
	wanted = true
	stream_id = id
	if not enabled: return
	var next := 0 if active_voice!=0 else 1
	# A rapid weather reversal reuses the fading voice instead of chopping it.
	if voices[next].playing and voices[next].stream==stream:
		active_voice = next
		return
	voices[next].stream = stream
	gains[next] = 0.0
	voices[next].volume_db = -80
	voices[next].play()
	active_voice = next
	transitions += 1

func silence() -> void:
	wanted = false

func _process(delta: float) -> void:
	mix_gain = move_toward(mix_gain,mix_target,delta*1.8)
	if not enabled: return
	if active_voice>=0 and wanted:
		var player := voices[active_voice]
		if player.playing and player.stream!=null:
			var length := player.stream.get_length()
			var overlap := minf(fade_seconds,maxf(0.05,length*0.25))
			if length>0 and player.get_playback_position()>=length-overlap:
				needs_next.emit()
	for i in range(2):
		var target := 1.0 if wanted and i==active_voice else 0.0
		gains[i] = move_toward(gains[i],target,delta/maxf(0.05,fade_seconds))
		voices[i].volume_db = linear_to_db(maxf(0.0001,gains[i]*mix_gain))
		if gains[i]<=0.0001 and target==0 and voices[i].playing: voices[i].stop()

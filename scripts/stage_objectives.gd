class_name StageObjectives
extends RefCounted

# Behavioral commissioning probes, independent of node count, position or topology.
# They make both inputs of the early taught rules necessary, without mandating gates.
static func commissioning(index: int, board) -> String:
	if index not in [1, 2, 3]: return ""
	var d = StageCatalog.get_stage(index)
	var probe = LogicBoard.new()
	if not probe.restore(board.serialize()): return "Controller data invalid."
	var problem: String = probe.validate(d.sensors, d.outputs, d.gates)
	if not problem.is_empty(): return problem
	if index in [1, 2]:
		for day in [false, true]:
			for cloud in [false, true] if index == 2 else [false]:
				probe.reset_runtime()
				var commands: Dictionary = probe.tick({"DAY": day, "CLOUD": cloud}, 0.05)
				var expected: bool = not day or (cloud and index == 2)
				if commands.get("BACKUP", false) != expected:
					return "Commissioning: DAY=%d CLOUD=%d needs BACKUP=%d. Your output is %d. Inspect the cause and signal path." % [int(day), int(cloud), int(expected), int(commands.get("BACKUP", false))]
	if index == 3:
		for peak in [false, true]:
			for charged in [false, true]:
				probe.reset_runtime()
				var commands: Dictionary = probe.tick({"DAY": true, "CLOUD": false, "PEAK": peak, "CHARGED": charged}, 0.05)
				if commands.get("BATTERY", false) != (peak and charged):
					return "Commissioning: PEAK=%d CHARGED=%d needs BATTERY=%d. Both conditions matter: a peak requests support, charge makes it available." % [int(peak), int(charged), int(peak and charged)]
	return ""

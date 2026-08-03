extends Node

signal on_authenticated(is_authenticated: bool)
signal on_leaderboard_error(error_code: String)
signal on_leaderboard_event(event_code: String)
signal on_high_score_fetched(highscore: int)
signal on_leaderboard_closed()
signal on_activities_loaded(activities: Dictionary)
signal on_activity_wants_to_play(activity_id: String, party_code: String, properties: Dictionary)
signal on_activity_started(activity_id: String, party_code: String)
signal on_activity_error(error_code: String)

var leaderboard: Object = null

var is_authenticated := false


# Change this to _ready() if you want automatically init
func init() -> void:
	if Engine.has_singleton("Leaderboard"):
		leaderboard = Engine.get_singleton("Leaderboard")
		init_signals()


func init_signals() -> void:
	leaderboard.on_authenticated.connect(func(_is_authenticated: bool) -> void:
		if _is_authenticated == true:
			is_authenticated = true
		
		on_authenticated.emit(is_authenticated)
	)
	leaderboard.on_leaderboard_error.connect(func(error_code: String) -> void:
		on_leaderboard_error.emit(error_code)
		print(error_code)
	)
	leaderboard.on_leaderboard_event.connect(func(event_code: String) -> void:
		on_leaderboard_event.emit(event_code)
	)
	
	leaderboard.on_high_score_fetched.connect(func(highscore: int) -> void:
		if highscore is int and highscore > 0:
			on_high_score_fetched.emit(highscore)
	)

	leaderboard.on_leaderboard_closed.connect(func() -> void:
		on_leaderboard_closed.emit()
	)

	leaderboard.on_activities_loaded.connect(func(activities: Dictionary) -> void:
		on_activities_loaded.emit(activities)
	)

	leaderboard.on_activity_wants_to_play.connect(func(activity_id: String, party_code: String, properties: Dictionary) -> void:
		on_activity_wants_to_play.emit(activity_id, party_code, properties)
	)

	leaderboard.on_activity_started.connect(func(activity_id: String, party_code: String) -> void:
		on_activity_started.emit(activity_id, party_code)
	)

	leaderboard.on_activity_error.connect(func(error_code: String) -> void:
		on_activity_error.emit(error_code)
	)


func check_authenticated() -> bool:
	if not leaderboard:
		not_found_plugin()
		return false
	
	return leaderboard.check_authenticated()


func signIn() -> void:
	if not leaderboard:
		not_found_plugin()
		return
	
	leaderboard.signIn()


func fetchHighScore(leaderboard_id: String) -> void:
	if not leaderboard:
		not_found_plugin()
		return
	
	if not is_authenticated:
		return
	
	leaderboard.fetchHighScore(leaderboard_id)


func submitHighScore(leaderboard_id: String, score: int) -> void:
	if not leaderboard:
		not_found_plugin()
		return
	
	if not is_authenticated:
		return
	
	leaderboard.submitHighScore(leaderboard_id, score)


func show(leaderboard_id: String) -> void:
	if not leaderboard:
		not_found_plugin()
		return
	
	leaderboard.show(leaderboard_id)


func load_activities() -> void:
	if not leaderboard:
		not_found_plugin()
		return
	leaderboard.loadActivities()


func start_activity(activity_id: String) -> void:
	if not leaderboard:
		not_found_plugin()
		return
	if not is_authenticated:
		return
	leaderboard.startActivity(activity_id)


func start_activity_with_code(activity_id: String, party_code: String) -> void:
	if not leaderboard:
		not_found_plugin()
		return
	if not is_authenticated:
		return
	leaderboard.startActivityWithCode(activity_id, party_code)


func end_activity() -> void:
	if not leaderboard:
		not_found_plugin()
		return
	leaderboard.endActivity()


func pause_activity() -> void:
	if not leaderboard:
		not_found_plugin()
		return
	leaderboard.pauseActivity()


func resume_activity() -> void:
	if not leaderboard:
		not_found_plugin()
		return
	leaderboard.resumeActivity()


func get_activity_party_code() -> String:
	if not leaderboard:
		not_found_plugin()
		return ""
	return leaderboard.getActivityPartyCode()


func not_found_plugin() -> void:
	print('[Leaderboard] Not found plugin. Please ensure that you checked Rating plugin in the export template')

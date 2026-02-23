class_name StatsTracker
extends RefCounted

## Tracks statistics over time for evolution and training.
## Supports both single values and time series data.

var stats: Dictionary = {}
var time_series: Dictionary = {}
var window_size: int = 100  # For moving averages


func _init(p_window_size: int = 100) -> void:
    window_size = p_window_size


func record(stat_name: String, value: float) -> void:
    ## Record a single statistic value
    if not stats.has(stat_name):
        stats[stat_name] = {
            "count": 0,
            "sum": 0.0,
            "min": INF,
            "max": -INF,
            "last": 0.0
        }

    var s = stats[stat_name]
    s.count += 1
    s.sum += value
    s.min = minf(s.min, value)
    s.max = maxf(s.max, value)
    s.last = value


func record_time_series(series_name: String, value: float) -> void:
    ## Record a value in a time series
    if not time_series.has(series_name):
        time_series[series_name] = []

    var series = time_series[series_name]
    series.append(value)

    # Keep only window_size most recent values
    if series.size() > window_size:
        series.pop_front()


func get_average(stat_name: String) -> float:
    ## Get average value of a statistic
    if stats.has(stat_name):
        var s = stats[stat_name]
        return s.sum / s.count if s.count > 0 else 0.0
    return 0.0


func get_last(stat_name: String) -> float:
    ## Get last recorded value
    if stats.has(stat_name):
        return stats[stat_name].last
    return 0.0


func get_min(stat_name: String) -> float:
    ## Get minimum value
    if stats.has(stat_name):
        return stats[stat_name].min
    return INF


func get_max(stat_name: String) -> float:
    ## Get maximum value
    if stats.has(stat_name):
        return stats[stat_name].max
    return -INF


func get_moving_average(series_name: String, window: int = -1) -> float:
    ## Get moving average of time series
    if not time_series.has(series_name):
        return 0.0

    var series = time_series[series_name]
    if series.is_empty():
        return 0.0

    var w := window if window > 0 else mini(window_size, series.size())
    var sum := 0.0
    var start_idx := maxi(0, series.size() - w)

    for i in range(start_idx, series.size()):
        sum += series[i]

    return sum / (series.size() - start_idx)


func get_trend(series_name: String, window: int = 10) -> float:
    ## Get trend direction (-1 to 1) over recent window
    if not time_series.has(series_name):
        return 0.0

    var series = time_series[series_name]
    if series.size() < 2:
        return 0.0

    var w := mini(window, series.size())
    var start_idx := series.size() - w

    # Simple linear regression
    var sum_x := 0.0
    var sum_y := 0.0
    var sum_xy := 0.0
    var sum_x2 := 0.0

    for i in w:
        var x := float(i)
        var y := series[start_idx + i]
        sum_x += x
        sum_y += y
        sum_xy += x * y
        sum_x2 += x * x

    var n := float(w)
    var slope := (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x)

    # Normalize to -1 to 1 range
    return clampf(slope * 0.1, -1.0, 1.0)


func reset() -> void:
    ## Clear all statistics
    stats.clear()
    time_series.clear()


func reset_stat(stat_name: String) -> void:
    ## Reset a specific statistic
    if stats.has(stat_name):
        stats.erase(stat_name)


func reset_series(series_name: String) -> void:
    ## Reset a specific time series
    if time_series.has(series_name):
        time_series[series_name].clear()


func get_summary() -> Dictionary:
    ## Get summary of all statistics
    var summary := {}

    for stat_name in stats:
        var s = stats[stat_name]
        summary[stat_name] = {
            "average": s.sum / s.count if s.count > 0 else 0.0,
            "min": s.min,
            "max": s.max,
            "last": s.last,
            "count": s.count
        }

    for series_name in time_series:
        summary[series_name + "_trend"] = get_trend(series_name)
        summary[series_name + "_avg"] = get_moving_average(series_name)

    return summary


func save_to_file(path: String) -> void:
    ## Save statistics to JSON file
    var data := {
        "stats": stats,
        "time_series": time_series,
        "timestamp": Time.get_unix_time_from_system()
    }

    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(data, "\t"))
        file.close()


func load_from_file(path: String) -> bool:
    ## Load statistics from JSON file
    var file := FileAccess.open(path, FileAccess.READ)
    if not file:
        return false

    var json_string := file.get_as_text()
    file.close()

    var json := JSON.new()
    var parse_result := json.parse(json_string)

    if parse_result != OK:
        return false

    var data: Dictionary = json.data
    stats = data.get("stats", {})
    time_series = data.get("time_series", {})

    return true
.pragma library
.import "Shared.js" as Shared

// The daily forecast by day: { Shared.dayKey(day): forecast item } of logic.dailyWeatherData
// ({ list: [{ dt (seconds), temp: { min, max }, iconName, ... }] }). Shared by the views, the
// agenda and the tooltip.
function byDay(data) {
	var map = {}
	var list = data && data.list ? data.list : []
	for (var i = 0; i < list.length; i++) {
		map[Shared.dayKey(new Date(list[i].dt * 1000))] = list[i]
	}
	return map
}

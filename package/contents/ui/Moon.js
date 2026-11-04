.pragma library

// The moon on a day, worked out here (no service): its phase, how much of it is lit, when it rises
// and sets at a place, and the next full or new moon; and whether the sun is down (the weather
// charts' nights). The positions and the rise / set search are
// SunCalc's (https://github.com/mourner/suncalc), the moon's with the larger terms of Meeus' lower
// accuracy theory added (Astronomical Algorithms, ch. 47): the main phases within about 20 minutes.
// Times are Date objects, days the local ones.
//
// SunCalc's license, for the parts taken from it:
//
// Copyright (c) 2014, Vladimir Agafonkin
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification, are
// permitted provided that the following conditions are met:
//
//    1. Redistributions of source code must retain the above copyright notice, this list of
//       conditions and the following disclaimer.
//
//    2. Redistributions in binary form must reproduce the above copyright notice, this list
//       of conditions and the following disclaimer in the documentation and/or other materials
//       provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
// COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
// GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
// NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
// OF THE POSSIBILITY OF SUCH DAMAGE.

var rad = Math.PI / 180
var dayMs = 86400000
var J1970 = 2440588
var J2000 = 2451545
var obliquity = rad * 23.4397 // Of the Earth

function toDays(date) {
	return date.valueOf() / dayMs - 0.5 + J1970 - J2000
}
function rightAscension(l, b) {
	return Math.atan2(Math.sin(l) * Math.cos(obliquity) - Math.tan(b) * Math.sin(obliquity), Math.cos(l))
}
function declination(l, b) {
	return Math.asin(Math.sin(b) * Math.cos(obliquity) + Math.cos(b) * Math.sin(obliquity) * Math.sin(l))
}
function altitude(H, phi, dec) {
	return Math.asin(Math.sin(phi) * Math.sin(dec) + Math.cos(phi) * Math.cos(dec) * Math.cos(H))
}
function siderealTime(d, lw) {
	return rad * (280.16 + 360.9856235 * d) - lw
}
// Refraction near the horizon lifts the moon a little.
function astroRefraction(h) {
	if (h < 0) {
		h = 0
	}
	return 0.0002967 / Math.tan(h + 0.00312536 / (h + 0.08901179))
}
// The sun's longitude from its mean longitude (Meeus, ch. 25: of the equinox of the date, as the
// moon's below; SunCalc's fixed perihelion lags it by precession, 0.4 degrees by 2024).
function sunCoords(d) {
	var M = rad * (357.5291 + 0.98560028 * d)
	var C = rad * (1.9148 * Math.sin(M) + 0.02 * Math.sin(2 * M) + 0.0003 * Math.sin(3 * M))
	var L = rad * (280.46646 + 0.98564736 * d) + C
	return { dec: declination(L, 0), ra: rightAscension(L, 0), l: L }
}
function moonCoords(d) {
	var L = rad * (218.316 + 13.176396 * d) // Mean longitude
	var M = rad * (134.963 + 13.064993 * d) // Mean anomaly
	var F = rad * (93.272 + 13.229350 * d) // Argument of latitude
	var D = rad * (297.850 + 12.190749 * d) // Mean elongation from the sun
	var Ms = rad * (357.529 + 0.98560028 * d) // The sun's mean anomaly
	var l = L + rad * (6.289 * Math.sin(M) + 1.274 * Math.sin(2 * D - M) + 0.658 * Math.sin(2 * D)
		+ 0.214 * Math.sin(2 * M) - 0.186 * Math.sin(Ms) - 0.114 * Math.sin(2 * F))
	var b = rad * (5.128 * Math.sin(F) + 0.280 * Math.sin(M + F) + 0.277 * Math.sin(M - F) + 0.173 * Math.sin(2 * D - F))
	var dist = 385001 - 20905 * Math.cos(M) - 3699 * Math.cos(2 * D - M) - 2956 * Math.cos(2 * D)
	return { ra: rightAscension(l, b), dec: declination(l, b), dist: dist, l: l }
}

// How high the moon is (radians, refraction included) at date for latitude / longitude (degrees).
function moonAltitude(date, lat, lon) {
	var d = toDays(date)
	var c = moonCoords(d)
	var h = altitude(siderealTime(d, rad * -lon) - c.ra, rad * lat, c.dec)
	return h + astroRefraction(h)
}

// How high the sun is (degrees, its centre) at date for latitude / longitude: it has set below
// -0.833 (refraction and its radius).
function sunAltitude(date, lat, lon) {
	var d = toDays(date)
	var c = sunCoords(d)
	return altitude(siderealTime(d, rad * -lon) - c.ra, rad * lat, c.dec) / rad
}
// For ForecastChart.nightFlags: whether the sun is down at a time (ms) at latitude / longitude,
// null without a place.
function sunDownAt(lat, lon) {
	if (typeof lat !== 'number' || typeof lon !== 'number' || !isFinite(lat) || !isFinite(lon)) {
		return null
	}
	return function(ms) {
		return sunAltitude(new Date(ms), lat, lon) < -0.833
	}
}

// { fraction (lit, 0..1), phase } at date: phase 0 new moon, 0.25 first quarter, 0.5 full moon,
// 0.75 last quarter, by how far the moon is ahead of the sun in ecliptic longitude (as the main
// phases are defined).
function illumination(date) {
	var d = toDays(date)
	var s = sunCoords(d)
	var m = moonCoords(d)
	var sdist = 149598000 // Earth - sun, km
	var phi = Math.acos(Math.sin(s.dec) * Math.sin(m.dec) + Math.cos(s.dec) * Math.cos(m.dec) * Math.cos(s.ra - m.ra))
	var inc = Math.atan2(sdist * Math.sin(phi), m.dist - sdist * Math.cos(phi))
	var ahead = (m.l - s.l) / (2 * Math.PI)
	return {
		fraction: (1 + Math.cos(inc)) / 2,
		phase: (ahead % 1 + 1) % 1,
	}
}

// The main phases, by their phase value.
var MAIN_PHASES = [
	{ key: 'new', at: 0 },
	{ key: 'firstQuarter', at: 0.25 },
	{ key: 'full', at: 0.5 },
	{ key: 'lastQuarter', at: 0.75 },
]

// When the phase next reaches target (0 / 0.25 / 0.5 / 0.75) after from: a Date, to the minute.
function nextPhase(from, target) {
	// How far the phase still has to go to target (0..1): it only grows, wrapping at 1.
	function toGo(date) {
		return ((target - illumination(date).phase) % 1 + 1) % 1
	}
	var stepMs = 6 * 3600000
	var a = new Date(from.valueOf())
	var left = toGo(a)
	// Past it in this step when the distance left jumps up (it wrapped around the target).
	for (var i = 0; i < 4 * 31; i++) {
		var b = new Date(a.valueOf() + stepMs)
		var leftB = toGo(b)
		if (leftB > left) {
			// Between a and b: narrow it down.
			var lo = a.valueOf()
			var hi = b.valueOf()
			while (hi - lo > 60000) {
				var mid = (lo + hi) / 2
				if (toGo(new Date(mid)) > toGo(new Date(lo))) {
					hi = mid
				} else {
					lo = mid
				}
			}
			return new Date(Math.round(hi / 60000) * 60000)
		}
		a = b
		left = leftB
	}
	return null
}

// When a body rises and sets on day (local, from its start to the next): { rise, set } (Date or
// null: none that day), alwaysUp / alwaysDown when it neither rises nor sets. aboveHorizon(date):
// how far it is above the horizon then (radians). SunCalc's way: by the hour, each two hours' curve
// solved for the horizon.
function horizonCrossings(day, aboveHorizon) {
	var start = new Date(day.getFullYear(), day.getMonth(), day.getDate())
	function hoursLater(h) {
		return new Date(start.valueOf() + h * 3600000)
	}
	var h0 = aboveHorizon(start)
	var rise = null
	var set = null
	var ye = 0
	for (var i = 1; i <= 24; i += 2) {
		var h1 = aboveHorizon(hoursLater(i))
		var h2 = aboveHorizon(hoursLater(i + 1))
		var a = (h0 + h2) / 2 - h1
		var b = (h2 - h0) / 2
		var xe = -b / (2 * a)
		ye = (a * xe + b) * xe + h1
		var d = b * b - 4 * a * h1
		var roots = 0
		var x1 = 0
		var x2 = 0
		if (d >= 0) {
			var dx = Math.sqrt(d) / (Math.abs(a) * 2)
			x1 = xe - dx
			x2 = xe + dx
			if (Math.abs(x1) <= 1) {
				roots++
			}
			if (Math.abs(x2) <= 1) {
				roots++
			}
			if (x1 < -1) {
				x1 = x2
			}
		}
		if (roots === 1) {
			if (h0 < 0) {
				rise = hoursLater(i + x1)
			} else {
				set = hoursLater(i + x1)
			}
		} else if (roots === 2) {
			rise = hoursLater(i + (ye < 0 ? x2 : x1))
			set = hoursLater(i + (ye < 0 ? x1 : x2))
		}
		if (rise && set) {
			break
		}
		h0 = h2
	}
	return {
		rise: rise,
		set: set,
		alwaysUp: !rise && !set && ye > 0,
		alwaysDown: !rise && !set && ye <= 0,
	}
}

// When the moon rises and sets on day (local) at latitude / longitude: as horizonCrossings, its
// upper edge on the horizon (its radius and a little refraction).
function riseSet(day, lat, lon) {
	var hc = 0.133 * rad
	return horizonCrossings(day, function(date) { return moonAltitude(date, lat, lon) - hc })
}

// When the sun rises and sets on day (local) at latitude / longitude: as horizonCrossings, its
// upper edge on the horizon (-0.833 degrees: refraction and its radius, as published times).
// null without a place.
function sunRiseSet(day, lat, lon) {
	if (typeof lat !== 'number' || typeof lon !== 'number' || !isFinite(lat) || !isFinite(lon)) {
		return null
	}
	return horizonCrossings(day, function(date) { return (sunAltitude(date, lat, lon) + 0.833) * rad })
}

// The moon on day (local): {
//   phaseKey: 'new' | 'waxingCrescent' | 'firstQuarter' | 'waxingGibbous' | 'full' | 'waningGibbous'
//     | 'lastQuarter' | 'waningCrescent' (a main phase only on the day it happens, mainAt its time),
//   fraction: lit at noon (0..1), glyph: 0..27 (the Weather Icons moon, 0 new, 14 full),
//   next: { key: 'full' | 'new', at } the next full or new moon after the day,
//   riseSet: riseSet(...) with a place (latitude and longitude numbers), else null }
function dayInfo(day, lat, lon) {
	var start = new Date(day.getFullYear(), day.getMonth(), day.getDate())
	var end = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1)
	var noon = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 12)
	var lit = illumination(noon)
	var info = {
		fraction: lit.fraction,
		glyph: Math.round(lit.phase * 28) % 28,
		phaseKey: lit.phase < 0.25 ? 'waxingCrescent' : lit.phase < 0.5 ? 'waxingGibbous'
			: lit.phase < 0.75 ? 'waningGibbous' : 'waningCrescent',
		mainAt: null,
		next: null,
		riseSet: null,
	}
	MAIN_PHASES.forEach(function(main, i) {
		var at = nextPhase(start, main.at)
		if (at && at < end) {
			info.phaseKey = main.key
			info.mainAt = at
			info.glyph = i * 7
		}
	})
	var nextFull = nextPhase(end, 0.5)
	var nextNew = nextPhase(end, 0)
	if (nextFull || nextNew) {
		info.next = !nextNew || (nextFull && nextFull < nextNew) ? { key: 'full', at: nextFull } : { key: 'new', at: nextNew }
	}
	if (typeof lat === 'number' && typeof lon === 'number' && isFinite(lat) && isFinite(lon)) {
		info.riseSet = riseSet(day, lat, lon)
	}
	return info
}

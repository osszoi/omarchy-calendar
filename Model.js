// Pure date, layout and scheduling math for the calendar widget and its panel.
// Locale- and Qt-free so node can run it (test/model-test.mjs); the QML owns
// month/weekday naming through Qt.locale().
//
// Month grid and ISO week helpers adapted from omarchy's own clock plugin (MIT).

var MS_PER_DAY = 86400000
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null
  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i
  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? 1 : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

// Always six rows of seven days, so the panel is the same height every month.
function monthGrid(year, month, weekStart, todayKey) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = String(todayKey || "")
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var key = dateKey(cellYear, cellMonth, cellDay)
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay }
      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today,
        startEpoch: Math.floor(new Date(cellYear, cellMonth, cellDay, 0, 0, 0, 0).getTime() / 1000)
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    var anchor = thursday || days[0]
    weeks.push({ week: isoWeek(anchor.year, anchor.month, anchor.day), days: days })
  }
  return weeks
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1)
  return { year: target.getFullYear(), month: target.getMonth() }
}

// ---- Bar label formats (the stock clock's ring, kept so right-click still
//      walks the formats people expect) ---------------------------------------

var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

var VERTICAL_CLOCK_FORMATS = [
  "HH\n\u2014\nmm",
  "h\n\u2014\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

// ---- Weeks -----------------------------------------------------------------

function startOfDay(epochSeconds) {
  var date = new Date(Number(epochSeconds) * 1000)
  date.setHours(0, 0, 0, 0)
  return Math.floor(date.getTime() / 1000)
}

// Day boundaries walk through Date rather than adding 86400, so a DST jump
// keeps the column lined up with the day it is labelled.
function addDays(epochSeconds, days) {
  var date = new Date(Number(epochSeconds) * 1000)
  date.setDate(date.getDate() + Number(days))
  return Math.floor(date.getTime() / 1000)
}

function weekStartEpoch(epochSeconds, weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var date = new Date(startOfDay(epochSeconds) * 1000)
  var back = (date.getDay() - start + 7) % 7
  return addDays(Math.floor(date.getTime() / 1000), -back)
}

function overlaps(a, b) {
  return a.start < b.end && b.start < a.end
}

// Google-style packing: events that overlap form a cluster, every event in it
// takes the first column free at its start time, and the cluster's column
// count is what each of its events is drawn against.
function packOverlaps(events) {
  var sorted = events.slice().sort(function(a, b) {
    return a.start - b.start || b.end - a.end || String(a.id).localeCompare(String(b.id))
  })
  var out = []
  var cluster = []
  var columnEnds = []

  function flush() {
    if (cluster.length === 0) return
    for (var i = 0; i < cluster.length; i++) cluster[i].columns = columnEnds.length
    cluster = []
    columnEnds = []
  }

  for (var i = 0; i < sorted.length; i++) {
    var event = sorted[i]
    var clusterEnd = 0
    for (var c = 0; c < columnEnds.length; c++) clusterEnd = Math.max(clusterEnd, columnEnds[c])
    if (cluster.length > 0 && event.start >= clusterEnd) flush()

    var column = -1
    for (var k = 0; k < columnEnds.length; k++) {
      if (columnEnds[k] <= event.start) { column = k; break }
    }
    if (column === -1) { column = columnEnds.length; columnEnds.push(0) }
    columnEnds[column] = event.end

    var placed = {
      event: event,
      column: column,
      columns: 1,
      start: event.start,
      end: event.end
    }
    cluster.push(placed)
    out.push(placed)
  }
  flush()
  return out
}

// One entry per day of the week, each with its events already packed into
// columns and clipped to that day (a meeting crossing midnight shows in both).
function weekLayout(events, weekStart, days) {
  var count = Number(days) || 7
  var out = []
  for (var d = 0; d < count; d++) {
    var dayStart = addDays(weekStart, d)
    var dayEnd = addDays(weekStart, d + 1)
    var slice = []
    for (var i = 0; i < events.length; i++) {
      var event = events[i]
      if (event.allDay) continue
      if (event.end <= dayStart || event.start >= dayEnd) continue
      slice.push({
        id: event.id + "@" + dayStart,
        source: event,
        start: Math.max(event.start, dayStart),
        end: Math.min(event.end, dayEnd),
        clippedStart: event.start < dayStart,
        clippedEnd: event.end > dayEnd
      })
    }
    var placed = packOverlaps(slice)
    for (var p = 0; p < placed.length; p++) {
      var clipped = placed[p].event
      placed[p].event = clipped.source
      placed[p].clippedStart = clipped.clippedStart
      placed[p].clippedEnd = clipped.clippedEnd
      placed[p].dayStart = dayStart
    }
    out.push({ dayStart: dayStart, dayEnd: dayEnd, events: placed })
  }
  return out
}

// The ISO week a displayed row belongs to: the week owning its Thursday. Same
// rule the month grid numbers its rows by, so the two never disagree about
// which week you are looking at.
function isoWeekForRange(weekStartEpoch) {
  for (var i = 0; i < 7; i++) {
    var date = new Date(addDays(weekStartEpoch, i) * 1000)
    if (date.getDay() === 4) return isoWeek(date.getFullYear(), date.getMonth(), date.getDate())
  }
  var first = new Date(weekStartEpoch * 1000)
  return isoWeek(first.getFullYear(), first.getMonth(), first.getDate())
}

function eventsForDay(events, dayStartEpoch) {
  var dayEnd = addDays(dayStartEpoch, 1)
  var out = []
  for (var i = 0; i < events.length; i++) {
    var event = events[i]
    if (event.end <= dayStartEpoch || event.start >= dayEnd) continue
    out.push(event)
  }
  out.sort(function(a, b) {
    if (!!a.allDay !== !!b.allDay) return a.allDay ? -1 : 1
    return a.start - b.start || a.priority - b.priority
  })
  return out
}

function hasEventsOn(events, dayStartEpoch) {
  return eventsForDay(events, dayStartEpoch).length > 0
}

// One pass over every event, bucketed by the day it starts, so the month grid
// asks a map 42 times instead of filtering the whole list 42 times.
function dayMarkers(events, maxPerDay) {
  var limit = Number(maxPerDay) || 3
  var buckets = {}

  function mark(key, color) {
    if (!buckets[key]) buckets[key] = { colors: [], count: 0 }
    var bucket = buckets[key]
    bucket.count++
    if (bucket.colors.length < limit && bucket.colors.indexOf(color) === -1) bucket.colors.push(color)
  }

  for (var i = 0; i < events.length; i++) {
    var event = events[i]
    var color = event.color || ""
    var cursor = startOfDay(event.start)
    // A week off is one event and seven marked days; a 10:00 meeting is one.
    var guard = 0
    while (cursor < event.end && guard < 400) {
      var date = new Date(cursor * 1000)
      mark(dateKey(date.getFullYear(), date.getMonth(), date.getDate()), color)
      if (!event.allDay) break
      cursor = addDays(cursor, 1)
      guard++
    }
  }
  return buckets
}

// All-day events, per day of the week, for the strip above the hour grid.
function allDayLayout(events, weekStart, days) {
  var count = Number(days) || 7
  var out = []
  for (var d = 0; d < count; d++) {
    var dayStart = addDays(weekStart, d)
    var dayEnd = addDays(weekStart, d + 1)
    var slice = []
    for (var i = 0; i < events.length; i++) {
      var event = events[i]
      if (!event.allDay) continue
      if (event.end <= dayStart || event.start >= dayEnd) continue
      slice.push(event)
    }
    out.push({ dayStart: dayStart, events: slice })
  }
  return out
}

// ---- What the bar shows ----------------------------------------------------

function byPrecedence(a, b) {
  return (a.priority - b.priority) || (a.start - b.start) || String(a.title).localeCompare(String(b.title))
}

// Overlapping events collapse to one: the precedence winner. Everything that
// does not overlap the winner is a different slot and stays eligible.
function pickAmongOverlapping(candidates) {
  if (candidates.length === 0) return null
  var earliest = candidates.slice().sort(function(a, b) { return a.start - b.start })[0]
  var competing = []
  for (var i = 0; i < candidates.length; i++)
    if (overlaps(candidates[i], earliest)) competing.push(candidates[i])
  competing.sort(byPrecedence)
  return competing[0]
}

function barSelection(events, nowEpoch, windowMinutes) {
  var now = Number(nowEpoch)
  var horizon = now + (Number(windowMinutes) || 60) * 60
  var ongoing = []
  var upcoming = []

  for (var i = 0; i < events.length; i++) {
    var event = events[i]
    if (event.allDay) continue
    if (event.start <= now && event.end > now) ongoing.push(event)
    else if (event.start > now && event.start <= horizon) upcoming.push(event)
  }

  var current = pickAmongOverlapping(ongoing)
  var next = pickAmongOverlapping(upcoming)
  return { ongoing: current, next: next }
}

// ---- Alerts ----------------------------------------------------------------

// Every pass recomputes from the freshest events: a meeting that moved gets a
// new key (its start is part of it), so the alert re-arms itself instead of
// firing against the time it had when it was first seen.
function alertKey(event, lead) {
  return event.id + "|" + event.start + "|" + lead
}

function dueAlerts(events, nowEpoch, leadMinutes, catchUpMinutes, fired) {
  var now = Number(nowEpoch)
  var catchUp = (Number(catchUpMinutes) || 0) * 60
  var leads = (leadMinutes || []).slice().sort(function(a, b) { return b - a })
  var out = []

  for (var i = 0; i < events.length; i++) {
    var event = events[i]
    if (event.allDay) continue
    if (event.start + catchUp < now) continue
    if (event.start > now + leads[0] * 60) continue

    var due = []
    for (var l = 0; l < leads.length; l++)
      if (now >= event.start - leads[l] * 60) due.push(leads[l])
    if (due.length === 0) continue

    var keys = []
    var unfired = false
    for (var d = 0; d < due.length; d++) {
      var key = alertKey(event, due[d])
      keys.push(key)
      if (!fired || !fired[key]) unfired = true
    }
    if (!unfired) continue

    // Late (resume, unlock, a shell that was down): one alert for the shortest
    // lead, not one per lead that quietly came due while nothing was watching.
    out.push({
      event: event,
      lead: due[due.length - 1],
      late: now >= event.start,
      keys: keys
    })
  }
  return out
}

// Keys carry the start time, so an event that moved leaves a key nothing
// matches any more. Dropping those is what keeps the file from growing forever.
function pruneFired(fired, events) {
  var live = {}
  for (var i = 0; i < events.length; i++) live[events[i].id + "|" + events[i].start] = true

  var out = {}
  for (var key in fired) {
    var base = key.substring(0, key.lastIndexOf("|"))
    if (live[base]) out[key] = fired[key]
  }
  return out
}

// ---- Formatting ------------------------------------------------------------

function truncate(text, max) {
  var value = String(text === undefined || text === null ? "" : text)
  var limit = Number(max) || 0
  if (limit <= 0 || value.length <= limit) return value
  return value.substring(0, Math.max(1, limit - 1)).replace(/\s+$/, "") + "…"
}

// "in 3m" while it matters, "in 1h05" further out. Seconds are never shown:
// a clock that ticks every second in the corner of the eye is a distraction.
function relativeLabel(seconds) {
  var total = Math.max(0, Math.round(Number(seconds) / 60))
  if (total <= 0) return "now"
  if (total < 60) return "in " + total + "m"
  var hours = Math.floor(total / 60)
  var minutes = total % 60
  return "in " + hours + "h" + (minutes > 0 ? pad2(minutes) : "")
}

function clockLabel(epochSeconds) {
  var date = new Date(Number(epochSeconds) * 1000)
  return pad2(date.getHours()) + ":" + pad2(date.getMinutes())
}

function barText(selection, nowEpoch, maxTitleChars) {
  var parts = []
  if (selection.ongoing)
    parts.push(truncate(selection.ongoing.title, maxTitleChars) + " now")
  if (selection.next)
    parts.push(truncate(selection.next.title, maxTitleChars) + " " + relativeLabel(selection.next.start - nowEpoch))
  return parts.join(" · ")
}

function staleness(syncedAt, nowEpoch) {
  var age = Math.max(0, Number(nowEpoch) - Number(syncedAt || 0))
  return {
    seconds: age,
    label: age < 120 ? "just now"
      : age < 3600 ? Math.floor(age / 60) + "m ago"
      : age < 86400 ? Math.floor(age / 3600) + "h ago"
      : Math.floor(age / 86400) + "d ago"
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    pad2: pad2,
    dateKey: dateKey,
    keyForDate: keyForDate,
    normalizedWeekStart: normalizedWeekStart,
    weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart,
    weekdayOrder: weekdayOrder,
    isoWeek: isoWeek,
    isoWeekLiteral: isoWeekLiteral,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    clockFormats: clockFormats,
    clockFormatRing: clockFormatRing,
    nextClockFormat: nextClockFormat,
    startOfDay: startOfDay,
    addDays: addDays,
    weekStartEpoch: weekStartEpoch,
    isoWeekForRange: isoWeekForRange,
    packOverlaps: packOverlaps,
    weekLayout: weekLayout,
    allDayLayout: allDayLayout,
    eventsForDay: eventsForDay,
    hasEventsOn: hasEventsOn,
    dayMarkers: dayMarkers,
    barSelection: barSelection,
    pickAmongOverlapping: pickAmongOverlapping,
    alertKey: alertKey,
    dueAlerts: dueAlerts,
    pruneFired: pruneFired,
    truncate: truncate,
    relativeLabel: relativeLabel,
    clockLabel: clockLabel,
    barText: barText,
    staleness: staleness
  }
}

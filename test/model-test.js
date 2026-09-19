// node test/model-test.js
var assert = require("assert")
var M = require("../Model.js")

var passed = 0
function test(name, fn) {
  try {
    fn()
    passed++
  } catch (error) {
    console.error("FAIL " + name + "\n  " + error.message)
    process.exitCode = 1
  }
}

function at(hour, minute) {
  var date = new Date(2026, 8, 19, hour, minute || 0, 0, 0)
  return Math.floor(date.getTime() / 1000)
}

function event(id, startHour, startMinute, durationMinutes, options) {
  var opts = options || {}
  return {
    id: id,
    title: opts.title || id,
    account: opts.account || "work",
    priority: opts.priority === undefined ? 1 : opts.priority,
    start: at(startHour, startMinute),
    end: at(startHour, startMinute) + durationMinutes * 60,
    allDay: !!opts.allDay,
    link: opts.link || ""
  }
}

test("month grid is always six rows of seven", function() {
  var weeks = M.monthGrid(2026, 8, 1, "2026-09-19")
  assert.strictEqual(weeks.length, 6)
  weeks.forEach(function(week) { assert.strictEqual(week.days.length, 7) })
})

test("iso week matches the stock clock", function() {
  assert.strictEqual(M.isoWeek(2026, 8, 19), 38)
  assert.strictEqual(M.isoWeek(2026, 0, 1), 1)
})

test("three overlapping events get three columns", function() {
  var placed = M.packOverlaps([
    event("a", 10, 0, 60),
    event("b", 10, 30, 60),
    event("c", 10, 45, 30)
  ])
  assert.strictEqual(placed.length, 3)
  placed.forEach(function(p) { assert.strictEqual(p.columns, 3) })
  assert.deepStrictEqual(placed.map(function(p) { return p.column }), [0, 1, 2])
})

test("back-to-back events share one column", function() {
  var placed = M.packOverlaps([event("a", 10, 0, 60), event("b", 11, 0, 60)])
  placed.forEach(function(p) {
    assert.strictEqual(p.column, 0)
    assert.strictEqual(p.columns, 1)
  })
})

test("separate clusters are counted separately", function() {
  var placed = M.packOverlaps([
    event("a", 9, 0, 60), event("b", 9, 30, 60),
    event("c", 14, 0, 30)
  ])
  var byId = {}
  placed.forEach(function(p) { byId[p.event.id] = p })
  assert.strictEqual(byId.a.columns, 2)
  assert.strictEqual(byId.b.columns, 2)
  assert.strictEqual(byId.c.columns, 1)
})

test("an event crossing midnight lands in both days", function() {
  var late = { id: "night", title: "night", priority: 1, start: at(23, 30), end: at(23, 30) + 7200, allDay: false }
  var week = M.weekLayout([late], M.weekStartEpoch(at(12, 0), 1), 7)
  var days = week.filter(function(day) { return day.events.length > 0 })
  assert.strictEqual(days.length, 2)
  assert.strictEqual(days[0].events[0].clippedEnd, true)
  assert.strictEqual(days[1].events[0].clippedStart, true)
})

test("bar shows nothing when the next event is more than an hour out", function() {
  var selection = M.barSelection([event("a", 15, 0, 30)], at(13, 59), 60)
  assert.strictEqual(selection.next, null)
  assert.strictEqual(selection.ongoing, null)
})

test("bar shows the event the minute it enters the hour window", function() {
  var selection = M.barSelection([event("a", 15, 0, 30)], at(14, 0), 60)
  assert.strictEqual(selection.next.id, "a")
  assert.strictEqual(M.relativeLabel(selection.next.start - at(14, 0)), "in 1h")
})

test("precedence decides which overlapping event owns the bar", function() {
  var events = [
    event("low", 15, 0, 60, { priority: 3, title: "Low" }),
    event("high", 15, 0, 60, { priority: 1, title: "High" })
  ]
  assert.strictEqual(M.barSelection(events, at(14, 30), 60).next.id, "high")
})

test("a later non-overlapping event never steals the slot", function() {
  var events = [event("first", 14, 45, 15, { priority: 9 }), event("second", 15, 0, 60, { priority: 1 })]
  assert.strictEqual(M.barSelection(events, at(14, 30), 60).next.id, "first")
})

test("ongoing and next are reported together", function() {
  var events = [event("now", 14, 0, 60), event("soon", 15, 0, 30)]
  var selection = M.barSelection(events, at(14, 30), 60)
  assert.strictEqual(selection.ongoing.id, "now")
  assert.strictEqual(selection.next.id, "soon")
  assert.strictEqual(M.barText(selection, at(14, 30), 28), "now now · soon in 30m")
})

test("alerts fire at each lead, once", function() {
  var events = [event("a", 15, 0, 30)]
  var fired = {}
  assert.strictEqual(M.dueAlerts(events, at(14, 54), [5, 1], 10, fired).length, 0)

  var five = M.dueAlerts(events, at(14, 55), [5, 1], 10, fired)
  assert.strictEqual(five.length, 1)
  assert.strictEqual(five[0].lead, 5)
  five[0].keys.forEach(function(key) { fired[key] = 1 })

  assert.strictEqual(M.dueAlerts(events, at(14, 56), [5, 1], 10, fired).length, 0)

  var one = M.dueAlerts(events, at(14, 59), [5, 1], 10, fired)
  assert.strictEqual(one.length, 1)
  assert.strictEqual(one[0].lead, 1)
})

test("a meeting that moved re-arms its alert", function() {
  var events = [event("a", 15, 0, 30)]
  var fired = {}
  M.dueAlerts(events, at(14, 55), [5, 1], 10, fired).forEach(function(alert) {
    alert.keys.forEach(function(key) { fired[key] = 1 })
  })
  var moved = [event("a", 16, 0, 30)]
  assert.strictEqual(M.dueAlerts(moved, at(15, 56), [5, 1], 10, fired).length, 1)
})

test("waking up late still alerts, once, marked late", function() {
  var events = [event("a", 15, 0, 30)]
  var alerts = M.dueAlerts(events, at(15, 3), [5, 1], 10, {})
  assert.strictEqual(alerts.length, 1)
  assert.strictEqual(alerts[0].late, true)
  assert.strictEqual(alerts[0].lead, 1)
  assert.strictEqual(alerts[0].keys.length, 2)
})

test("waking up too late does not alert at all", function() {
  assert.strictEqual(M.dueAlerts([event("a", 15, 0, 30)], at(15, 11), [5, 1], 10, {}).length, 0)
})

test("both overlapping meetings alert even though only one owns the bar", function() {
  var events = [
    event("low", 15, 0, 60, { priority: 3 }),
    event("high", 15, 0, 60, { priority: 1 })
  ]
  assert.strictEqual(M.dueAlerts(events, at(14, 59), [5, 1], 10, {}).length, 2)
})

test("fired keys for events that moved out are pruned", function() {
  var events = [event("a", 15, 0, 30)]
  var fired = {}
  fired[M.alertKey(events[0], 5)] = 1
  fired["gone|123|5"] = 1
  var pruned = M.pruneFired(fired, events)
  assert.deepStrictEqual(Object.keys(pruned), [M.alertKey(events[0], 5)])
})

test("relative labels read like a person wrote them", function() {
  assert.strictEqual(M.relativeLabel(0), "now")
  assert.strictEqual(M.relativeLabel(90), "in 2m")
  assert.strictEqual(M.relativeLabel(3600), "in 1h")
  assert.strictEqual(M.relativeLabel(3900), "in 1h05")
})

test("titles truncate with an ellipsis", function() {
  assert.strictEqual(M.truncate("Standup", 28), "Standup")
  assert.strictEqual(M.truncate("A very long meeting title here", 10), "A very lo…")
})

test("all-day events never reach the bar or the alerts", function() {
  var allDay = { id: "x", title: "Holiday", priority: 1, start: at(0, 0), end: at(0, 0) + 86400, allDay: true }
  assert.strictEqual(M.barSelection([allDay], at(9, 0), 60).ongoing, null)
  assert.strictEqual(M.dueAlerts([allDay], at(0, 0) - 60, [5, 1], 10, {}).length, 0)
})

test("day markers bucket events by their start day", function() {
  var events = [
    event("a", 10, 0, 60, { account: "work" }),
    event("b", 11, 0, 60, { account: "work" }),
    event("c", 12, 0, 60, { account: "home" })
  ]
  events[0].color = "#111111"
  events[1].color = "#111111"
  events[2].color = "#222222"
  var markers = M.dayMarkers(events, 3)
  var key = M.dateKey(2026, 8, 19)
  assert.strictEqual(markers[key].count, 3)
  assert.deepStrictEqual(markers[key].colors, ["#111111", "#222222"])
})

test("a multi-day all-day event marks every day it covers", function() {
  var holiday = { id: "h", title: "Off", priority: 1, color: "#fff", allDay: true,
                  start: at(0, 0), end: at(0, 0) + 3 * 86400 }
  var markers = M.dayMarkers([holiday], 3)
  assert.strictEqual(Object.keys(markers).length, 3)
})

test("all-day events are laid out in their own strip, not the hour grid", function() {
  var holiday = { id: "h", title: "Off", priority: 1, allDay: true,
                  start: at(0, 0), end: at(0, 0) + 86400 }
  var week = M.weekStartEpoch(at(12, 0), 1)
  assert.strictEqual(M.weekLayout([holiday], week, 7).reduce(function(n, d) { return n + d.events.length }, 0), 0)
  assert.strictEqual(M.allDayLayout([holiday], week, 7).reduce(function(n, d) { return n + d.events.length }, 0), 1)
})

test("the agenda puts all-day events above the timed ones", function() {
  var holiday = { id: "h", title: "Off", priority: 1, allDay: true, start: at(0, 0), end: at(0, 0) + 86400 }
  var meeting = event("m", 9, 0, 60)
  var day = M.eventsForDay([meeting, holiday], M.startOfDay(at(12, 0)))
  assert.strictEqual(day[0].id, "h")
})

console.log(passed + " passed")

.pragma library

// All times belong to the local calendar date on which the routine starts.
// Each activity ends at the next start; the final activity uses the following
// date's actual routine. The legacy end field is canonicalized to a blank value.

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function defaults() {
    var seed = [
        ["09:00", "Activity 1"],
        ["12:00", "Activity 2"],
        ["18:00", "Activity 3"]
    ];
    return {
        version: 2,
        default: seed.map(function(row, index) {
            return { id: "default-" + (index + 1), name: row[1], start: row[0], end: "" };
        }),
        days: {},
        dates: {}
    };
}

function _object(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function _owns(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
}

function _pad(value, length) {
    var result = String(value);
    while (result.length < length) result = "0" + result;
    return result;
}

function _validDate(date) {
    return date && typeof date.getTime === "function" && isFinite(date.getTime());
}

function dateKey(date) {
    if (!_validDate(date)) throw new Error("Choose a valid local date.");
    return _pad(date.getFullYear(), 4) + "-" + _pad(date.getMonth() + 1, 2) + "-" + _pad(date.getDate(), 2);
}

function dayKeys() {
    return ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
}

function dayKey(date) {
    if (!_validDate(date)) throw new Error("Choose a valid local date.");
    return dayKeys()[(date.getDay() + 6) % 7];
}

function dayLabel(key) {
    var index = dayKeys().indexOf(key);
    if (index < 0) throw new Error("Invalid routine day: " + key + ". Use mon through sun.");
    return ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][index];
}

function validateDateKey(value) {
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    var year = Number(value.slice(0, 4));
    var month = Number(value.slice(5, 7));
    var day = Number(value.slice(8, 10));
    if (year < 1 || month < 1 || month > 12 || day < 1) return false;
    var leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
    var lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return day <= lengths[month - 1];
}

function formatTime(minute) {
    if (typeof minute !== "number" || !isFinite(minute)) return "";
    var clock = ((Math.floor(minute) % 1440) + 1440) % 1440;
    return _pad(Math.floor(clock / 60), 2) + ":" + _pad(clock % 60, 2);
}

function _minutes(value) {
    if (typeof value !== "string" || !/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) return null;
    return Number(value.slice(0, 2)) * 60 + Number(value.slice(3, 5));
}

function _unicodeLength(value) {
    return (value.match(/[\uD800-\uDBFF][\uDC00-\uDFFF]|[\s\S]/g) || []).length;
}

function _rowLabel(row, index) {
    return "Activity " + (index + 1) + (row && typeof row.name === "string" ? " (" + row.name.trim() + ")" : "");
}

function validateRoutine(rows) {
    if (!Array.isArray(rows)) throw new Error("The routine must be a list of activities.");
    if (rows.length === 0) throw new Error("Add at least one activity.");
    if (rows.length > 128) throw new Error("Keep each routine to 128 activities or fewer.");
    var result = [];
    var ids = Object.create(null);
    var day = 0;
    var previousClock = -1;

    for (var i = 0; i < rows.length; i++) {
        var input = rows[i];
        var label = _rowLabel(input, i);
        if (!_object(input)) throw new Error(label + " must contain a name and start time.");
        if (typeof input.id !== "string" || !input.id.trim()) throw new Error(label + " needs a unique ID.");
        if (_owns(ids, input.id)) throw new Error(label + " repeats an activity ID. Give each row a unique ID.");
        ids[input.id] = true;
        if (typeof input.name !== "string" || !input.name.trim()) throw new Error("Give activity " + (i + 1) + " a name.");
        var name = input.name.trim();
        if (_unicodeLength(name) > 80) throw new Error(label + " needs a name of 80 characters or fewer.");
        var start = _minutes(input.start);
        if (start === null) {
            throw new Error(label + ": use an HH:MM start time, such as 09:00.");
        }
        if (start < previousClock) day++;
        if (day > 1) throw new Error(label + ": keep activities in time order, crossing midnight only once.");
        var absoluteStart = start + day * 1440;
        if (result.length && absoluteStart >= result[0].startMinute + 1440) {
            throw new Error(label + ": keep activities in time order within one routine day (less than 24 hours).");
        }
        result.push({ id: input.id, name: name, start: input.start, end: "",
            startMinute: absoluteStart, endMinute: null, dayOffset: day });
        previousClock = start;
    }

    for (var j = 0; j < result.length - 1; j++) {
        result[j].endMinute = result[j + 1].startMinute;
    }
    return result;
}

function normalize(rows) {
    return validateRoutine(rows);
}

function _storedRoutine(rows) {
    return validateRoutine(rows).map(function(row) {
        return { id: row.id, name: row.name, start: row.start, end: row.end };
    });
}

function _documentShape(doc) {
    if (!_object(doc) || doc.version !== 2) throw new Error("Unsupported routine file. Expected version 2 or legacy version 1.");
    if (!Array.isArray(doc.default)) throw new Error("The routine file needs a Default routine.");
    if (!_object(doc.days)) throw new Error("Day routines must be stored by weekday.");
    var keys = Object.keys(doc.days);
    for (var i = 0; i < keys.length; i++) dayLabel(keys[i]);
    if (!_object(doc.dates)) throw new Error("Specific-date routines must be stored by date.");
}

function validateDocument(doc) {
    // Old files are migrated in memory; only an explicit save writes version 2.
    if (_object(doc) && doc.version === 1) {
        if (!Array.isArray(doc.usual)) throw new Error("The legacy routine file needs a Usual routine.");
        if (doc.weekend !== null && !Array.isArray(doc.weekend)) throw new Error("Weekend must be a routine or null.");
        doc = { version: 2, default: doc.usual, days: doc.weekend === null ? {} : { sat: doc.weekend, sun: doc.weekend }, dates: doc.dates };
    }
    _documentShape(doc);
    var result = { version: 2, default: _storedRoutine(doc.default), days: {}, dates: {} };
    var days = Object.keys(doc.days);
    for (var d = 0; d < days.length; d++) {
        var day = days[d];
        try {
            result.days[day] = _storedRoutine(doc.days[day]);
        } catch (error) {
            throw new Error(dayLabel(day) + ": " + error.message);
        }
    }
    var keys = Object.keys(doc.dates);
    if (keys.length > 366) throw new Error("Keep 366 specific-date routines or fewer.");
    for (var i = 0; i < keys.length; i++) {
        var key = keys[i];
        if (!validateDateKey(key)) throw new Error("Invalid routine date: " + key + ". Use a real YYYY-MM-DD date.");
        try {
            result.dates[key] = _storedRoutine(doc.dates[key]);
        } catch (error) {
            throw new Error(key + ": " + error.message);
        }
    }
    return result;
}

function _shiftDay(date, days) {
    var shifted = new Date(date.getTime());
    // Calendar arithmetic avoids UTC conversions and 23/25-hour DST days.
    shifted.setHours(12, 0, 0, 0);
    shifted.setDate(shifted.getDate() + days);
    return shifted;
}

function _selected(doc, date) {
    var key = dateKey(date);
    var day = dayKey(date);
    if (_owns(doc.dates, key)) return { dateKey: key, dayKey: day, scope: "date", label: key, rows: normalize(doc.dates[key]) };
    if (_owns(doc.days, day)) {
        return { dateKey: key, dayKey: day, scope: "day", label: dayLabel(day), rows: normalize(doc.days[day]) };
    }
    return { dateKey: key, dayKey: day, scope: "default", label: "Default", rows: normalize(doc.default) };
}

// The persistence boundary should validate the complete document once. During
// clock updates, only the applicable routines are normalized, not every date.
function resolve(doc, now) {
    if (_object(doc) && doc.version === 1) doc = validateDocument(doc);
    _documentShape(doc);
    if (!_validDate(now)) throw new Error("Cannot resolve the routine without a valid local time.");
    var today = _selected(doc, now);
    var minute = now.getHours() * 60 + now.getMinutes() + now.getSeconds() / 60;
    var selected;
    var next;
    if (minute < today.rows[0].startMinute) {
        selected = _selected(doc, _shiftDay(now, -1));
        next = today;
        minute += 1440;
    } else {
        selected = today;
        next = _selected(doc, _shiftDay(now, 1));
    }
    var last = selected.rows[selected.rows.length - 1];
    if (last.endMinute === null) last.endMinute = Math.max(last.startMinute, 1440 + next.rows[0].startMinute);
    selected.activeIndex = -1;
    for (var i = 0; i < selected.rows.length; i++) {
        var row = selected.rows[i];
        if (minute >= row.startMinute && minute < row.endMinute) selected.activeIndex = i;
    }
    return selected;
}

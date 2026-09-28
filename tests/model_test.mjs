import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const directory = path.dirname(fileURLToPath(import.meta.url));
const source = fs.readFileSync(path.join(directory, '../qml/RoutineLogic.js'), 'utf8');
const model = vm.createContext({ Date });
vm.runInContext(source.replace(/^\.pragma library\s*\n/, ''), model);

const plain = value => JSON.parse(JSON.stringify(value));
const row = (id, start, end = '', name = id) => ({ id, name, start, end });
const doc = (routine, days = {}, dates = {}) => ({ version: 2, default: routine, days, dates });
const legacy = (usual, weekend = null, dates = {}) => ({ version: 1, usual, weekend, dates });
const local = (year, month, day, hour, minute = 0, second = 0) => new Date(year, month - 1, day, hour, minute, second);
const active = state => state.activeIndex < 0 ? null : state.rows[state.activeIndex].name;

test('defaults contain only three generic placeholders with stable IDs', () => {
    const seed = model.defaults();
    assert.deepEqual(plain(seed.default), [
        row('default-1', '09:00', '', 'Activity 1'),
        row('default-2', '12:00', '', 'Activity 2'),
        row('default-3', '18:00', '', 'Activity 3')
    ]);
    assert.deepEqual(plain(seed.days), {});
    assert.deepEqual(plain(seed.dates), {});
    assert.ok(seed.default.every(value => value.end === ''));
    assert.equal(new Set(seed.default.map(value => value.id)).size, 3);
    assert.deepEqual(plain(model.validateDocument(seed)), plain(seed));
    seed.default[0].name = 'Changed';
    assert.equal(model.defaults().default[0].name, 'Activity 1');
});

test('normalization derives ends from starts, keeps instant entries, and crosses midnight', () => {
    const rows = model.normalize([
        row('Marker', '18:10'), row('First phase', '18:10'),
        row('Second phase', '23:50'), row('Third phase', '00:20')
    ]);
    assert.equal(rows[0].startMinute, rows[0].endMinute);
    assert.equal(rows[1].endMinute, 1430);
    assert.equal(rows[2].endMinute, 1460);
    assert.equal(rows[3].startMinute, 1460);
    assert.equal(rows[3].dayOffset, 1);
    assert.equal(rows[3].endMinute, null);
    assert.equal(model.normalize([row('one', '08:00'), row('two', '10:00')])[0].endMinute, 600);
});

test('current block changes exactly at the next start with no gaps from legacy ends', () => {
    const schedule = doc([row('First', '09:00', '10:00'), row('Second', '11:00', '12:00')]);
    assert.equal(active(model.resolve(schedule, local(2026, 9, 28, 9))), 'First');
    assert.equal(active(model.resolve(schedule, local(2026, 9, 28, 9, 59, 59))), 'First');
    assert.equal(active(model.resolve(schedule, local(2026, 9, 28, 10))), 'First');
    assert.equal(active(model.resolve(schedule, local(2026, 9, 28, 11))), 'Second');
    assert.equal(active(model.resolve(schedule, local(2026, 9, 28, 12))), 'Second');
    assert.equal(active(model.resolve(schedule, local(2026, 9, 29, 8, 59, 59))), 'Second');
    assert.equal(active(model.resolve(schedule, local(2026, 9, 29, 9))), 'First');
    const equalStarts = doc([row('Point', '08:10'), row('First interval', '08:10'), row('Second interval', '09:20')]);
    assert.equal(active(model.resolve(equalStarts, local(2026, 9, 28, 8, 10))), 'First interval');
    assert.equal(active(model.resolve(equalStarts, local(2026, 9, 28, 9, 20))), 'Second interval');
});

test('Friday routine owns early Saturday, then Saturday begins at its own first activity', () => {
    const schedule = doc([row('First', '06:20'), row('Second', '21:10'), row('Overnight', '00:20')]);
    schedule.days.sat = [row('Saturday first', '10:10'), row('Saturday last', '19:20')];
    let result = model.resolve(schedule, local(2026, 9, 26, 0, 45));
    assert.equal(result.dateKey, '2026-09-25');
    assert.equal(result.scope, 'default');
    assert.equal(active(result), 'Overnight');
    result = model.resolve(schedule, local(2026, 9, 26, 10));
    assert.equal(active(result), 'Overnight');
    assert.equal(result.rows[2].endMinute, 1440 + 610);
    result = model.resolve(schedule, local(2026, 9, 26, 10, 10));
    assert.equal(result.dateKey, '2026-09-26');
    assert.equal(result.scope, 'day');
    assert.equal(active(result), 'Saturday first');
});

test('Sunday continues into Monday until the Default first start', () => {
    const schedule = doc([row('Default first', '08:40')]);
    schedule.days.sun = [row('Sunday first', '13:15'), row('Sunday last', '23:45')];
    const early = model.resolve(schedule, local(2026, 9, 28, 8));
    assert.equal(early.dateKey, '2026-09-27');
    assert.equal(early.scope, 'day');
    assert.equal(active(early), 'Sunday last');
    assert.equal(early.rows[1].endMinute, 1960);
    assert.equal(model.resolve(schedule, local(2026, 9, 28, 8, 40)).scope, 'default');
});

test('date overrides take priority and keep ownership after midnight', () => {
    const schedule = doc([row('Default first', '08:40'), row('Default last', '20:10')]);
    schedule.days.sat = [row('Saturday first', '10:00'), row('Saturday last', '22:00')];
    schedule.days.sun = [row('Sunday first', '10:00'), row('Sunday last', '22:00')];
    schedule.dates['2026-09-26'] = [row('Date first', '12:20'), row('Date last', '23:40')];
    let result = model.resolve(schedule, local(2026, 9, 26, 11));
    assert.equal(result.scope, 'default');
    assert.equal(active(result), 'Default last');
    result = model.resolve(schedule, local(2026, 9, 26, 12, 20));
    assert.equal(result.scope, 'date');
    assert.equal(result.label, '2026-09-26');
    assert.equal(active(result), 'Date first');
    result = model.resolve(schedule, local(2026, 9, 27, 1));
    assert.equal(result.dateKey, '2026-09-26');
    assert.equal(active(result), 'Date last');
    assert.equal(model.resolve(schedule, local(2026, 9, 27, 10)).scope, 'day');
});

test('early next-day override preempts the previous routine at its first start', () => {
    const schedule = doc([row('Default first', '08:40'), row('Default last', '20:10')]);
    schedule.dates['2026-09-26'] = [row('Early override', '00:25'), row('Later override', '04:10')];
    assert.equal(model.resolve(schedule, local(2026, 9, 26, 0, 24)).scope, 'default');
    assert.equal(active(model.resolve(schedule, local(2026, 9, 26, 0, 25))), 'Early override');
});

test('unset days inherit Default and different date entries do not interfere', () => {
    const schedule = model.defaults();
    schedule.dates['2026-10-01'] = [row('Future', '10:00')];
    const result = model.resolve(schedule, local(2026, 9, 26, 12));
    assert.equal(result.scope, 'default');
    assert.equal(active(result), 'Activity 2');
});

test('all seven weekdays select independent overrides with local day helpers', () => {
    const schedule = doc([row('Default', '09:00')]);
    const keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    assert.deepEqual(plain(model.dayKeys()), keys);
    for (let i = 0; i < keys.length; i++) schedule.days[keys[i]] = [row(names[i], '09:00')];
    for (let i = 0; i < keys.length; i++) {
        const date = local(2026, 9, 28 + i, 12);
        assert.equal(model.dayKey(date), keys[i]);
        assert.equal(model.dayLabel(keys[i]), names[i]);
        const result = model.resolve(schedule, date);
        assert.equal(result.scope, 'day');
        assert.equal(result.dayKey, keys[i]);
        assert.equal(result.label, names[i]);
        assert.equal(active(result), names[i]);
    }
});

test('date overrides beat weekday overrides, and unset weekdays use Default', () => {
    const schedule = doc([row('Default', '09:00')], { mon: [row('Monday', '10:00')] }, {
        '2026-09-28': [row('Special Monday', '11:00')]
    });
    const special = model.resolve(schedule, local(2026, 9, 28, 12));
    assert.equal(special.scope, 'date');
    assert.equal(special.dayKey, 'mon');
    assert.equal(active(special), 'Special Monday');
    assert.equal(active(model.resolve(schedule, local(2026, 10, 5, 12))), 'Monday');
    const tuesday = model.resolve(schedule, local(2026, 9, 29, 12));
    assert.equal(tuesday.scope, 'default');
    assert.equal(tuesday.label, 'Default');
    assert.equal(active(tuesday), 'Default');
});

test('Monday owns overnight Tuesday until Tuesday starts, using its actual first time', () => {
    const schedule = doc([row('Default', '09:00')], {
        mon: [row('Monday first', '07:20'), row('Monday second', '00:10'), row('Monday last', '03:20')],
        tue: [row('Tuesday first', '10:40'), row('Tuesday last', '20:30')]
    });
    const early = model.resolve(schedule, local(2026, 9, 29, 1));
    assert.equal(early.dateKey, '2026-09-28');
    assert.equal(early.dayKey, 'mon');
    assert.equal(early.label, 'Monday');
    assert.equal(active(early), 'Monday second');
    assert.equal(early.rows[2].endMinute, 1440 + 640);
    assert.equal(active(model.resolve(schedule, local(2026, 9, 29, 10, 39, 59))), 'Monday last');
    const boundary = model.resolve(schedule, local(2026, 9, 29, 10, 40));
    assert.equal(boundary.dayKey, 'tue');
    assert.equal(active(boundary), 'Tuesday first');
});

test('legacy migration preserves all schedules and creates independent Saturday and Sunday copies', () => {
    const input = legacy([row('Default', '09:00', '22:00')], [row('Weekend', '11:00', '23:00')], {
        '2026-09-28': [row('Holiday', '12:00', '22:00')]
    });
    const original = JSON.stringify(input);
    const migrated = model.validateDocument(input);
    assert.equal(JSON.stringify(input), original);
    assert.equal(migrated.version, 2);
    assert.equal(migrated.default[0].name, 'Default');
    assert.deepEqual(Object.keys(migrated.days), ['sat', 'sun']);
    assert.equal(migrated.days.sat[0].name, 'Weekend');
    assert.equal(migrated.days.sun[0].name, 'Weekend');
    assert.equal(migrated.dates['2026-09-28'][0].name, 'Holiday');
    assert.ok([migrated.default, migrated.days.sat, migrated.days.sun, migrated.dates['2026-09-28']].every(rows => rows[0].end === ''));
    migrated.days.sat[0].name = 'Saturday only';
    migrated.default[0].name = 'Changed default';
    migrated.dates['2026-09-28'][0].name = 'Changed date';
    assert.equal(migrated.days.sun[0].name, 'Weekend');
    assert.equal(JSON.stringify(input), original);
    assert.equal(active(model.resolve(input, local(2026, 9, 26, 12))), 'Weekend');
    assert.equal(active(model.resolve(input, local(2026, 9, 28, 12))), 'Holiday');
    assert.equal(JSON.stringify(input), original);
    assert.deepEqual(plain(model.validateDocument(legacy([row('Default', '09:00')])).days), {});
});

test('weekday validation rejects unknown keys and identifies invalid day rows', () => {
    for (const key of ['monday', 'Mon', 'MON', 'weekend', '0', '7', '']) {
        assert.throws(() => model.validateDocument(doc([row('Default', '09:00')], { [key]: [row('Day', '09:00')] })), /Invalid routine day/);
    }
    assert.throws(() => model.validateDocument(doc([row('Default', '09:00')], [])), /by weekday/);
    assert.throws(() => model.validateDocument(doc([row('Default', '09:00')], { mon: null })), /Monday.*list/);
    assert.throws(() => model.validateDocument(doc([row('Default', '09:00')], { tue: [] })), /Tuesday.*at least one/);
    assert.throws(() => model.validateDocument(doc([row('Default', '09:00')], { wed: [row('Day', '25:00')] })), /Wednesday.*HH:MM/);
    assert.throws(() => model.dayKey(new Date('invalid')), /valid local date/);
    assert.throws(() => model.dayLabel('Friday'), /Invalid routine day/);
});

test('fresh wall-clock resolution handles backward and forward time changes', () => {
    const schedule = doc([row('Alpha', '07:10'), row('Beta', '12:40'), row('Gamma', '22:10'), row('Delta', '00:20')]);
    assert.equal(active(model.resolve(schedule, local(2026, 9, 28, 13))), 'Beta');
    assert.equal(active(model.resolve(schedule, local(2026, 9, 28, 10, 15))), 'Alpha');
    assert.equal(active(model.resolve(schedule, local(2026, 9, 29, 1, 45))), 'Delta');
    assert.equal(active(model.resolve(schedule, local(2026, 9, 28, 22, 30))), 'Gamma');
});

test('local date keys and ownership remain correct across year and leap-day boundaries', () => {
    const schedule = model.defaults();
    schedule.dates['2025-12-31'] = [row('Year-end first', '16:20'), row('Year-end last', '01:10')];
    assert.equal(model.dateKey(local(2026, 1, 1, 0)), '2026-01-01');
    const date = local(2026, 1, 1, 0, 30);
    const before = date.getTime();
    assert.equal(model.resolve(schedule, date).dateKey, '2025-12-31');
    assert.equal(active(model.resolve(schedule, date)), 'Year-end first');
    assert.equal(date.getTime(), before);
    assert.equal(model.resolve(schedule, local(2024, 3, 1, 1)).dateKey, '2024-02-29');
    assert.equal(model.resolve(schedule, local(2025, 3, 1, 1)).dateKey, '2025-02-28');
});

test('date validation checks real Gregorian dates without UTC parsing', () => {
    for (const value of ['2024-02-29', '2000-02-29', '2026-12-31', '0001-01-01']) {
        assert.equal(model.validateDateKey(value), true, value);
    }
    for (const value of ['2026-02-29', '1900-02-29', '2100-02-29', '2026-04-31', '2026-13-01', '2026-00-01', '2026-01-00', '2026-1-1', '0000-01-01', 'x', null]) {
        assert.equal(model.validateDateKey(value), false, String(value));
    }
});

test('validation returns a sanitized independent value without changing persisted input', () => {
    const input = doc([row('a', '09:00', '10:00', '  Padded activity  '), row('b', '10:00')]);
    input.unknown = 'discard';
    input.default[0].startMinute = 99;
    const before = JSON.stringify(input);
    const sanitized = model.validateDocument(input);
    assert.equal(JSON.stringify(input), before);
    assert.equal(sanitized.default[0].name, 'Padded activity');
    assert.equal(sanitized.unknown, undefined);
    assert.equal(sanitized.default[0].startMinute, undefined);
    assert.equal(sanitized.default[0].end, '');
    assert.equal(input.default[0].end, '10:00');
    sanitized.default[0].name = 'Elsewhere';
    assert.equal(input.default[0].name, '  Padded activity  ');
    const invalid = doc([row('bad', '25:00')]);
    const original = JSON.stringify(invalid);
    assert.throws(() => model.validateDocument(invalid), /HH:MM/);
    assert.equal(JSON.stringify(invalid), original);
});

test('strict start times reject coercion, missing fields, and incomplete formats', () => {
    for (const value of ['9:30', '24:00', '12:60', '12:00:00', ' 09:30', 930, null, undefined]) {
        assert.throws(() => model.normalize([row('a', value)]), /HH:MM/);
    }
});

test('legacy ends are ignored and canonical rows keep a blank compatibility field', () => {
    for (const end of ['10:00', '09:00', '9:30', null, undefined]) {
        const input = [row('First', '09:00', end), row('Second', '11:00', end)];
        const result = model.normalize(input);
        assert.equal(result[0].endMinute, 660);
        assert.equal(result[1].endMinute, null);
        assert.equal(result[0].end, '');
        assert.equal(result[1].end, '');
    }
    const startOnly = { id: 'a', name: 'A', start: '09:00' };
    assert.equal(model.normalize([startOnly])[0].end, '');
});

test('moving the next start updates the preceding duration across legacy end times', () => {
    const schedule = doc([row('First', '09:00', '11:00'), row('Second', '11:00')]);
    schedule.default[1].start = '10:00';
    assert.equal(model.normalize(schedule.default)[0].endMinute, 600);
    assert.equal(active(model.resolve(schedule, local(2026, 9, 28, 10))), 'Second');
    schedule.default[1].start = '12:00';
    assert.equal(model.normalize(schedule.default)[0].endMinute, 720);
    assert.equal(active(model.resolve(schedule, local(2026, 9, 28, 11, 59, 59))), 'First');
    assert.equal(active(model.resolve(schedule, local(2026, 9, 28, 12))), 'Second');
});

test('moving the next start across midnight updates the inferred overnight range', () => {
    const schedule = doc([row('First', '22:00', '23:30'), row('Second', '23:30', '08:00')]);
    schedule.default[1].start = '00:30';
    const normalized = model.normalize(schedule.default);
    assert.equal(normalized[0].endMinute, 1470);
    assert.equal(normalized[1].dayOffset, 1);
    assert.equal(active(model.resolve(schedule, local(2026, 9, 29, 0, 29, 59))), 'First');
    assert.equal(active(model.resolve(schedule, local(2026, 9, 29, 0, 30))), 'Second');
    schedule.default[1].start = '23:00';
    assert.equal(model.normalize(schedule.default)[0].endMinute, 1380);
    assert.equal(active(model.resolve(schedule, local(2026, 9, 28, 23))), 'Second');
});

test('start ordering crosses midnight only once and stays within one routine day', () => {
    assert.throws(() => model.normalize([row('a', '09:00'), row('b', '23:00'), row('c', '08:00'), row('d', '09:00')]), /24 hours/);
    assert.throws(() => model.normalize([row('a', '23:00'), row('b', '01:00'), row('c', '00:30')]), /midnight only once/);
});

test('night-shift schedules can start in the evening without an arbitrary noon cutoff', () => {
    const rows = model.normalize([row('First', '23:00', '08:00'), row('Second', '08:00', '14:00'), row('Third', '14:00')]);
    assert.equal(rows[1].dayOffset, 1);
    assert.equal(rows[2].startMinute, 2280);
});

test('row limits, unique IDs, Unicode name limits, and schema errors are enforced', () => {
    assert.throws(() => model.normalize([]), /at least one/);
    assert.throws(() => model.normalize(Array.from({ length: 129 }, (_, i) => row(String(i), '09:00'))), /128/);
    assert.equal(model.normalize(Array.from({ length: 128 }, (_, i) => row(String(i), '09:00'))).length, 128);
    assert.throws(() => model.normalize([row('same', '09:00'), row('same', '10:00')]), /unique ID/);
    assert.throws(() => model.normalize([row('', '09:00')]), /unique ID/);
    assert.throws(() => model.normalize([row('a', '09:00', '', '   ')]), /a name/);
    assert.equal(model.normalize([row('a', '09:00', '', '🧘'.repeat(80))])[0].name, '🧘'.repeat(80));
    assert.throws(() => model.normalize([row('a', '09:00', '', '🧘'.repeat(81))]), /80 characters/);
    assert.throws(() => model.validateDocument({ version: 3 }), /version 2/);
    assert.throws(() => model.validateDocument({ version: 2 }), /Default/);
    assert.throws(() => model.validateDocument({ version: 1, usual: [] }), /Weekend/);
    assert.throws(() => model.validateDocument(legacy([row('a', '09:00')], false)), /Weekend/);
    assert.throws(() => model.validateDocument(doc([row('a', '09:00')], {}, [])), /by date/);
    assert.throws(() => model.validateDocument(doc([row('a', '09:00')], {}, { '2026-02-29': [] })), /Invalid routine date/);
});

test('date override count is bounded and error identifies a broken date routine', () => {
    const schedule = doc([row('a', '09:00')]);
    for (let i = 0; i < 366; i++) {
        schedule.dates[model.dateKey(local(2024, 1, i + 1, 12))] = [row('a', '09:00')];
    }
    assert.equal(Object.keys(model.validateDocument(schedule).dates).length, 366);
    schedule.dates['2025-01-01'] = [row('a', '09:00')];
    assert.throws(() => model.validateDocument(schedule), /366/);
    assert.throws(() => model.validateDocument(doc([row('a', '09:00')], {}, { '2026-09-26': [row('broken', '99:00')] })), /2026-09-26.*HH:MM/);
});

test('formatting wraps after midnight and invalid clock inputs fail safely', () => {
    assert.equal(model.formatTime(0), '00:00');
    assert.equal(model.formatTime(1560), '02:00');
    assert.equal(model.formatTime(-1), '23:59');
    assert.equal(model.formatTime(null), '');
    assert.throws(() => model.resolve(model.defaults(), new Date('invalid')), /valid local time/);
    assert.throws(() => model.dateKey(new Date('invalid')), /valid local date/);
});

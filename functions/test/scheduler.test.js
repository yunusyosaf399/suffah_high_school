'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {
  localFinanceDate, due, createBills, runMonthlyScheduler,
} = require('../scheduler');

class FakeDB {
  constructor(seed = {}) {
    this.data = new Map();
    this.creates = new Map();
    for (const [collection, records] of Object.entries(seed)) {
      const map = new Map();
      for (const [id, value] of Object.entries(records)) map.set(id, {...value});
      this.data.set(collection, map);
    }
  }
  collection(path) {
    const db = this;
    const docs = () => {
      if (!db.data.has(path)) db.data.set(path, new Map());
      return db.data.get(path);
    };
    const reference = (id) => ({
      id,
      get: async () => ({
        exists: docs().has(id), data: () => docs().get(id),
      }),
      create: async data => {
        if (docs().has(id)) throw Object.assign(new Error('already exists'), {code: 6});
        docs().set(id, {...data});
        db.creates.set(path, (db.creates.get(path) || 0) + 1);
      },
      set: async (data, options) => {
        docs().set(id, options?.merge
          ? {...docs().get(id), ...data} : {...data});
      },
    });
    const query = (predicates = [], count = Infinity) => ({
      limit: n => query(predicates, n),
      where: (field, operator, value) => {
        assert.equal(operator, '==');
        return query([...predicates, doc => doc[field] === value], count);
      },
      get: async () => ({
        docs: [...docs().entries()].filter(([,value]) =>
          predicates.every(predicate => predicate(value)))
          .slice(0, count).map(([id, value]) => ({
            id, data: () => ({...value}), exists: true,
          })),
      }),
      doc: reference,
    });
    return query();
  }
  records(name) {
    return this.data.get(name) || new Map();
  }
}

const date = iso => new Date(iso);
const quiet = {error() {}};
const opts = {serverTimestamp: () => 'SERVER_TIMESTAMP', logger: quiet};
const settings = (day, enabled = true) => ({
  scheduleDay: day, automaticEnabled: enabled, category: 'tuition',
});

test('Pakistan local date handles UTC rollover and month boundaries', () => {
  assert.deepEqual(localFinanceDate(date('2026-11-30T20:00:00Z')), {
    month: '2026-12', day: 1, dayKey: '20261201',
  });
  assert.deepEqual(localFinanceDate(date('2026-11-05T23:00:00Z')), {
    month: '2026-11', day: 6, dayKey: '20261106',
  });
  assert.equal(due(settings(27), 26), false);
  assert.equal(due(settings(27), 27), true);
  assert.equal(due(settings(27, false), 27), false);
  assert.equal(due(settings(0), 27), false);
  assert.equal(due(settings(28), 28), false);
});

test('no automatic config means no finance bills, receipts or debits', async () => {
  const db = new FakeDB({
    students: {s1: {active: true, classId: 'a', fullName: 'Student'}},
    classes: {a: {name: 'Class A', active: true}},
    finance_tuition_rates: {a: {amountMinor: 100000}},
  });
  const result = await runMonthlyScheduler(
    db, date('2026-11-05T06:00:00Z'), opts);
  assert.equal(result.results.length, 0);
  assert.equal(db.records('finance_fee_bills').size, 0);
  assert.equal(db.records('finance_ledger').size, 0);
  assert.equal(db.records('finance_scheduler_runtime').get('status').activeWorker, true);
});

test('generates four kinds of outstanding bills without any ledger activity', async () => {
  const db = new FakeDB({
    finance_generation_settings: {
      tuition: settings(6),
      transport: {...settings(6), category: 'transport'},
      salary: {...settings(6), category: 'salary'},
    },
    classes: {
      'nursery-a': {name: 'Nursery', section: 'A', active: true},
      closed: {name: 'Closed', active: false},
    },
    students: {
      s1: {active: true, status: 'admitted', classId: 'nursery-a',
        fullName: 'First Pupil', rollNo: '24'},
      s2: {active: true, status: 'admitted', classId: 'nursery-a',
        fullName: 'Second Pupil', rollNo: '25'},
      draft: {active: true, status: 'draft', classId: 'nursery-a'},
      closed: {active: true, classId: 'closed'},
    },
    finance_tuition_rates: {'nursery-a': {amountMinor: 120000}},
    finance_transport_rates: {
      s1: {active: true, amountMinor: 150000},
      s2: {active: false, amountMinor: 100000},
    },
    staff: {
      emp1: {active: true, roleType: 'teacher',
        firstName: 'Hassan', lastName: 'Ali'},
      emp2: {active: false, roleType: 'teacher'},
      emp3: {active: true, roleType: 'administration'},
    },
    finance_salary_rates: {
      emp1: {amountMinor: 2550000, basicMinor: 2400000,
        allowanceMinor: 100000, bonusMinor: 50000},
    },
    finance_recurring_plans: {
      rent1: {active: true, automaticEnabled: true, scheduleDay: 6,
        name: 'School building rent', category: 'Building',
        subcategory: 'Building Rent', amountMinor: 8500000},
      rent2: {active: true, automaticEnabled: false, scheduleDay: 6,
        amountMinor: 500000, name: 'Manual plan'},
      paused: {active: false, automaticEnabled: true, scheduleDay: 6,
        amountMinor: 800000, name: 'Paused plan'},
    },
  });
  const first = await runMonthlyScheduler(
    db, date('2026-11-06T06:00:00Z'), opts);

  assert.equal(first.results.length, 4);
  const fees = db.records('finance_fee_bills');
  assert.equal(fees.size, 3);
  assert.equal(fees.get('FEE-202611-tuition-s1').amountMinor, 120000);
  assert.equal(fees.get('FEE-202611-tuition-s2').amountMinor, 120000);
  assert.equal(fees.get('FEE-202611-transport-s1').amountMinor, 150000);
  assert.equal(fees.get('FEE-202611-transport-s2'), undefined);
  assert.equal(db.records('finance_salary_bills').get('SAL-202611-emp1').amountMinor, 2550000);
  assert.equal(db.records('finance_recurring_bills').get('EXP-202611-rent1').amountMinor, 8500000);
  assert.equal(db.records('finance_ledger').size, 0);
  assert.equal(fees.get('FEE-202611-tuition-s1').paidMinor, 0);
  assert.equal(db.records('finance_scheduler_runs').size, 4);
  assert.equal(db.records('finance_scheduler_runtime').get('status').lastRunSucceeded, true);

  // A prior payment changes the bill, not the scheduler's data model.
  fees.get('FEE-202611-tuition-s1').paidMinor = 20000;
  fees.get('FEE-202611-tuition-s1').status = 'partial';
  const second = await runMonthlyScheduler(
    db, date('2026-11-07T06:00:00Z'), opts);
  assert.equal(second.results.length, 4);
  assert.ok(second.results.every(result => result.skipped === 'already-completed'));
  assert.equal(fees.size, 3);
  assert.equal(fees.get('FEE-202611-tuition-s1').paidMinor, 20000);
  assert.equal(fees.get('FEE-202611-tuition-s1').status, 'partial');
  assert.equal(db.records('finance_salary_bills').size, 1);
});

test('scheduler catches up after preferred date but never early', async () => {
  const db = new FakeDB({
    finance_generation_settings: {tuition: settings(15)},
    classes: {a: {name: 'Grade', active: true}},
    students: {s1: {status: 'admitted', active: true, fullName: 'Ali', classId: 'a'}},
    finance_tuition_rates: {a: {amountMinor: 130000}},
  });
  await runMonthlyScheduler(db, date('2026-11-14T07:00:00Z'), opts);
  assert.equal(db.records('finance_fee_bills').size, 0);
  await runMonthlyScheduler(db, date('2026-11-16T07:00:00Z'), opts);
  assert.equal(db.records('finance_fee_bills').size, 1);
});

test('atomic create preserves paid amount when a monthly bill already exists', async () => {
  const id = 'SAL-202611-emp1';
  const db = new FakeDB({
    finance_salary_bills: {
      [id]: {amountMinor: 1000000, paidMinor: 350000,
        status: 'partial', staffId: 'emp1'},
    },
  });
  const result = await createBills(db, 'finance_salary_bills', [
    {id, data: {amountMinor: 1000000, paidMinor: 0, status: 'unpaid'}},
  ], () => 'NOW');
  assert.deepEqual(result, {created: 0, existing: 1});
  assert.equal(db.records('finance_salary_bills').get(id).paidMinor, 350000);
  assert.equal(db.records('finance_salary_bills').get(id).status, 'partial');
});

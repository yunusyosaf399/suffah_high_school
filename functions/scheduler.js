'use strict';

// All billing decisions use Asia/Karachi calendar dates, never the UTC date.
// Cloud Scheduler may retry and overlap: deterministic IDs + document.create()
// make every individual monthly bill idempotent across retries/manual runs.
const TIME_ZONE = 'Asia/Karachi';
const CATEGORIES = Object.freeze(['tuition', 'transport', 'salary']);

function localFinanceDate(now) {
  const values = Object.fromEntries(
    new Intl.DateTimeFormat('en-GB', {
      timeZone: TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit',
    }).formatToParts(now).filter(part => part.type !== 'literal')
      .map(part => [part.type, part.value]),
  );
  return {
    month: values.year + '-' + values.month,
    day: Number(values.day),
    dayKey: values.year + values.month + values.day,
  };
}

function due(settings, day) {
  return settings?.automaticEnabled === true &&
    Number.isInteger(settings.scheduleDay) &&
    settings.scheduleDay >= 1 && settings.scheduleDay <= 27 &&
    day >= settings.scheduleDay;
}

function minor(value) {
  return Number.isSafeInteger(value) && value > 0 ? value : 0;
}

function timestampValue(serverTimestamp) {
  return typeof serverTimestamp === 'function'
    ? serverTimestamp()
    : new Date();
}

function hasDocument(doc) {
  return doc && doc.exists !== false && !!doc.data();
}

async function mapLimited(items, limit, task) {
  let next = 0;
  const results = [];
  const workers = Array.from({length: Math.min(limit, items.length)}, async () => {
    while (next < items.length) {
      const index = next++;
      results[index] = await task(items[index]);
    }
  });
  await Promise.all(workers);
  return results;
}

async function createBills(db, collection, prepared, serverTimestamp) {
  const outcomes = await mapLimited(prepared, 15, async ({id, data}) => {
    try {
      await db.collection(collection).doc(id).create({
        ...data,
        createdAt: timestampValue(serverTimestamp),
        updatedAt: timestampValue(serverTimestamp),
      });
      return 'created';
    } catch (error) {
      // Firestore Admin SDK returns ALREADY_EXISTS=6 for concurrent creates.
      if (error.code === 6 || error.code === 'already-exists' ||
          error.code === 'ALREADY_EXISTS') return 'existing';
      return {failure: error};
    }
  });
  const created = outcomes.filter(x => x === 'created').length;
  const existing = outcomes.filter(x => x === 'existing').length;
  const errors = outcomes.filter(x => x && x.failure);
  if (errors.length) {
    throw new Error(
      'Could not generate ' + errors.length + ' of ' + prepared.length +
      ' ' + collection + ' bills: ' + String(errors[0].failure.message || errors[0].failure),
    );
  }
  return {created, existing};
}

function feeBill(month, kind, student, schoolClass, rate) {
  const id = 'FEE-' + month.replace('-', '') + '-' + kind + '-' + student.id;
  return {id, data: {
    billId: id, month, category: kind, subcategory: '',
    title: kind === 'tuition' ? 'Monthly tuition' : 'Monthly transport',
    description: '', studentId: student.id,
    studentName: student.data.fullName || '',
    rollNo: student.data.rollNo || '',
    classId: student.data.classId,
    className: schoolClass.name +
      (schoolClass.section ? ' – ' + schoolClass.section : ''),
    amountMinor: rate.amountMinor, paidMinor: 0,
    status: 'unpaid', currency: 'PKR',
    sourceRateId: kind === 'tuition' ? student.data.classId : student.id,
    generatedBy: 'firebase-monthly-scheduler',
  }};
}

function salaryBill(month, teacher, rate) {
  const id = 'SAL-' + month.replace('-', '') + '-' + teacher.id;
  return {id, data: {
    billId: id, month, category: 'salary', title: 'Monthly salary',
    staffId: teacher.id,
    staffName: [teacher.data.firstName, teacher.data.middleName,
      teacher.data.lastName].filter(Boolean).join(' ') ||
      teacher.data.fullName || '',
    basicMinor: rate.basicMinor, allowanceMinor: rate.allowanceMinor,
    bonusMinor: rate.bonusMinor, description: rate.notes || '',
    amountMinor: rate.amountMinor, paidMinor: 0,
    status: 'unpaid', currency: 'PKR',
    generatedBy: 'firebase-monthly-scheduler',
  }};
}

function expenseBill(month, plan) {
  const id = 'EXP-' + month.replace('-', '') + '-' + plan.id;
  return {id, data: {
    billId: id, planId: plan.id, month, category: 'expense',
    subcategory: plan.data.subcategory || '',
    expenseCategory: plan.data.category || 'Other',
    title: plan.data.name || '', description: plan.data.description || '',
    amountMinor: plan.data.amountMinor, paidMinor: 0,
    status: 'unpaid', currency: 'PKR',
    generatedBy: 'firebase-monthly-scheduler',
  }};
}

function asRecords(snapshot) {
  return snapshot.docs.map(doc => ({id: doc.id, data: doc.data()}));
}

function asLookup(snapshot) {
  return new Map(asRecords(snapshot).map(item => [item.id, item.data]));
}

async function prepareCategory(db, month, category) {
  if (category === 'tuition' || category === 'transport') {
    const [studentsSnap, classesSnap, ratesSnap] = await Promise.all([
      db.collection('students').limit(1000).get(),
      db.collection('classes').get(),
      db.collection(category === 'tuition'
        ? 'finance_tuition_rates' : 'finance_transport_rates').limit(1000).get(),
    ]);
    const classes = asLookup(classesSnap);
    const rates = asLookup(ratesSnap);
    let missingSetup = 0;
    const prepared = [];
    for (const student of asRecords(studentsSnap)) {
      if (student.data.active === false || student.data.status === 'draft') continue;
      const schoolClass = classes.get(student.data.classId);
      if (!schoolClass || schoolClass.active === false) continue;
      const rate = rates.get(category === 'tuition'
        ? student.data.classId : student.id);
      if (!rate || !minor(rate.amountMinor) ||
          (category === 'transport' && rate.active === false)) {
        missingSetup++;
        continue;
      }
      prepared.push(feeBill(month, category, student, schoolClass, rate));
    }
    return {collection: 'finance_fee_bills', prepared, missingSetup};
  }
  if (category === 'salary') {
    const [teachersSnap, ratesSnap] = await Promise.all([
      db.collection('staff').where('roleType', '==', 'teacher').limit(500).get(),
      db.collection('finance_salary_rates').limit(1000).get(),
    ]);
    const rates = asLookup(ratesSnap);
    const prepared = [];
    let missingSetup = 0;
    for (const teacher of asRecords(teachersSnap)) {
      if (teacher.data.active === false) continue;
      const rate = rates.get(teacher.id);
      if (!rate || !minor(rate.amountMinor) ||
          !Number.isSafeInteger(rate.basicMinor) ||
          !Number.isSafeInteger(rate.allowanceMinor) ||
          !Number.isSafeInteger(rate.bonusMinor) ||
          rate.basicMinor <= 0 || rate.allowanceMinor < 0 || rate.bonusMinor < 0 ||
          rate.basicMinor + rate.allowanceMinor + rate.bonusMinor !== rate.amountMinor) {
        missingSetup++;
        continue;
      }
      prepared.push(salaryBill(month, teacher, rate));
    }
    return {collection: 'finance_salary_bills', prepared, missingSetup};
  }
  throw new Error('Unknown finance scheduler category ' + category);
}

async function runCategory(db, month, category, preparedBuilder, serverTimestamp) {
  const id = month.replace('-', '') + '_' + category;
  const audit = db.collection('finance_scheduler_runs').doc(id);
  const old = await audit.get();
  if (hasDocument(old) && old.data().status === 'success') {
    return {category, skipped: 'already-completed'};
  }
  try {
    const {collection, prepared, missingSetup = 0} = await preparedBuilder();
    const result = await createBills(db, collection, prepared, serverTimestamp);
    await audit.set({
      month, category, status: 'success', ...result,
      missingSetup, checked: prepared.length,
      completedAt: timestampValue(serverTimestamp),
    }, {merge: true});
    return {category, ...result, missingSetup};
  } catch (error) {
    await audit.set({
      month, category, status: 'failed',
      lastError: String(error.message || error).slice(0, 500),
      attemptedAt: timestampValue(serverTimestamp),
    }, {merge: true});
    throw error;
  }
}

// Called only from a privileged Cloud Function. The mobile app cannot invoke
// this worker or create its audit records. A missing/disabled preference means
// no automatic generation, even if the function is deployed.
async function runMonthlyScheduler(db, now, {serverTimestamp, logger = console} = {}) {
  const {month, day, dayKey} = localFinanceDate(now);
  const results = [];
  const failures = [];

  await db.collection('finance_scheduler_runtime').doc('status').set({
    version: 1, timeZone: TIME_ZONE, activeWorker: true,
    lastHeartbeatAt: timestampValue(serverTimestamp),
    currentMonth: month, lastCheckDay: day,
  }, {merge: true});

  const settingsSnapshot = await db.collection('finance_generation_settings').get();
  const settings = asLookup(settingsSnapshot);
  for (const category of CATEGORIES) {
    if (!due(settings.get(category), day)) continue;
    try {
      const item = await runCategory(db, month, category,
        () => prepareCategory(db, month, category), serverTimestamp);
      results.push(item);
    } catch (error) {
      failures.push({category, error: String(error.message || error)});
      logger.error('Finance scheduler category failed', category, error);
    }
  }

  const plans = await db.collection('finance_recurring_plans')
      .where('active', '==', true).limit(500).get();
  for (const plan of asRecords(plans)) {
    if (!due(plan.data, day)) continue;
    if (!minor(plan.data.amountMinor)) continue;
    const category = 'expense_' + plan.id;
    try {
      const item = await runCategory(db, month, category,
        async () => ({collection: 'finance_recurring_bills',
          prepared: [expenseBill(month, plan)], missingSetup: 0}), serverTimestamp);
      results.push(item);
    } catch (error) {
      failures.push({category, error: String(error.message || error)});
      logger.error('Finance recurring plan failed', category, error);
    }
  }

  await db.collection('finance_scheduler_runtime').doc('status').set({
    lastCompletedAt: timestampValue(serverTimestamp),
    lastCheckDayKey: dayKey,
    lastRunSucceeded: failures.length === 0,
    lastRunSummary: {successes: results.length, failures: failures.length},
  }, {merge: true});

  if (failures.length) {
    throw new Error('Finance scheduler partially failed for ' + month +
      ': ' + failures.map(x => x.category).join(', '));
  }
  return {month, day, results, failures};
}

module.exports = {
  TIME_ZONE, CATEGORIES, localFinanceDate, due, feeBill, salaryBill,
  expenseBill, runMonthlyScheduler, createBills, prepareCategory,
};

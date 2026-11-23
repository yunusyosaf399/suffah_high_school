const { initializeApp } = require('firebase-admin/app');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const logger = require('firebase-functions/logger');

initializeApp();
const db = getFirestore();
const timeZone = 'Asia/Karachi';
const settings = db.collection('finance_generation_settings');
const runs = db.collection('finance_generation_runs');
const categories = ['tuition', 'transport', 'salary', 'recurring_expenses'];

const schoolDate = new Intl.DateTimeFormat('en-CA', {
  timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
});

const text = (value) => typeof value === 'string' ? value : '';
const integer = (value) => Number.isSafeInteger(value) ? value : 0;
const validDay = (day) => Number.isInteger(day) && day >= 1 && day <= 27;

function billFields(billId, month, amountMinor) {
  return {
    billId, month, amountMinor, paidMinor: 0, status: 'unpaid', currency: 'PKR',
    generatedBy: 'system:monthly-finance',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function feeBills(kind, month, monthId) {
  const [students, classes, rates] = await Promise.all([
    db.collection('students').orderBy('fullName').get(),
    db.collection('classes').get(),
    db.collection('finance_' + kind + '_rates').get(),
  ]);
  const activeClasses = new Map(classes.docs
    .filter((doc) => doc.data().active !== false)
    .map((doc) => [doc.id, doc.data()]));
  const rateById = new Map(rates.docs.map((doc) => [doc.id, doc.data()]));
  const bills = [];
  for (const doc of students.docs) {
    const student = doc.data();
    const schoolClass = activeClasses.get(student.classId);
    if (!schoolClass || student.active === false || student.status === 'draft') {
      continue;
    }
    const sourceRateId = kind === 'tuition' ? student.classId : doc.id;
    const rate = rateById.get(sourceRateId);
    const amount = integer(rate?.amountMinor);
    if (amount <= 0 || (kind === 'transport' && rate.active === false)) continue;
    const id = 'FEE-' + monthId + '-' + kind + '-' + doc.id;
    const section = text(schoolClass.section);
    const className = text(schoolClass.name) + (section ? ' – ' + section : '');
    bills.push({
      ref: db.collection('finance_fee_bills').doc(id),
      data: {
        ...billFields(id, month, amount),
        category: kind, subcategory: '', title: 'Monthly ' + kind,
        description: '', studentId: doc.id, studentName: text(student.fullName),
        rollNo: text(student.rollNo), classId: student.classId, className, sourceRateId,
      },
    });
  }
  return bills;
}

async function salaryBills(month, monthId) {
  const [teachers, rates] = await Promise.all([
    db.collection('staff').where('roleType', '==', 'teacher').get(),
    db.collection('finance_salary_rates').get(),
  ]);
  const rateById = new Map(rates.docs.map((doc) => [doc.id, doc.data()]));
  const bills = [];
  for (const doc of teachers.docs) {
    const teacher = doc.data();
    const rate = rateById.get(doc.id);
    const amount = integer(rate?.amountMinor);
    if (teacher.active === false || amount <= 0) continue;
    const id = 'SAL-' + monthId + '-' + doc.id;
    bills.push({
      ref: db.collection('finance_salary_bills').doc(id),
      data: {
        ...billFields(id, month, amount),
        category: 'salary', title: 'Monthly salary',
        staffId: doc.id, staffName: text(teacher.fullName),
        basicMinor: integer(rate.basicMinor),
        allowanceMinor: integer(rate.allowanceMinor),
        bonusMinor: integer(rate.bonusMinor),
        description: text(rate.notes),
      },
    });
  }
  return bills;
}

async function recurringBills(month, monthId, day) {
  const plans = await db.collection('finance_recurring_plans')
    .where('active', '==', true).get();
  return plans.docs.flatMap((doc) => {
    const plan = doc.data();
    const amount = integer(plan.amountMinor);
    if (amount <= 0 || !validDay(plan.scheduleDay) || plan.scheduleDay > day) return [];
    const id = 'EXP-' + monthId + '-' + doc.id;
    return [{
      ref: db.collection('finance_recurring_bills').doc(id),
      planRef: doc.ref,
      planVersion: doc.updateTime,
      data: {
        ...billFields(id, month, amount),
        planId: doc.id, category: 'expense', subcategory: text(plan.subcategory),
        expenseCategory: text(plan.category) || 'Other',
        title: text(plan.name), description: text(plan.description),
      },
    }];
  });
}

function isDue(preference, category, day) {
  return preference?.automaticEnabled === true &&
    (category === 'recurring_expenses' ||
      (validDay(preference.scheduleDay) && preference.scheduleDay <= day));
}

async function generate(category, month, monthId, day) {
  const setting = settings.doc(category);
  const preference = await setting.get();
  if (!isDue(preference.data(), category, day)) return;
  const recurring = category === 'recurring_expenses';
  // Expenses may have different due days; fee and salary runs finish once per month.
  const run = runs.doc(month + '-' + category + (recurring ? '-' + day : ''));
  if ((await run.get()).exists) return;
  const bills = recurring ? await recurringBills(month, monthId, day)
    : category === 'salary' ? await salaryBills(month, monthId)
      : await feeBills(category, month, monthId);

  let created = 0;
  for (let start = 0; start < bills.length; start += 100) {
    const chunk = bills.slice(start, start + 100);
    const added = await db.runTransaction(async (tx) => {
      const current = await tx.get(setting);
      if (!isDue(current.data(), category, day)) return null;
      const existing = await tx.getAll(...chunk.map((bill) => bill.ref));
      const missing = chunk.filter((_, i) => !existing[i].exists);
      const plans = recurring && missing.length
        ? await tx.getAll(...missing.map((bill) => bill.planRef)) : [];
      let count = 0;
      missing.forEach((bill, i) => {
        // A stopped or edited expense plan must not create a bill from old data.
        if (recurring && !plans[i].updateTime?.isEqual(bill.planVersion)) return;
        tx.create(bill.ref, bill.data);
        count++;
      });
      return count;
    });
    if (added === null) return;
    created += added;
  }
  await db.runTransaction(async (tx) => {
    const [current, completed] = await tx.getAll(setting, run);
    if (!completed.exists && isDue(current.data(), category, day)) {
      tx.create(run, { month, category, completedAt: FieldValue.serverTimestamp() });
    }
  });
  logger.info('Monthly finance generation completed', { month, category, created });
}

exports.generateMonthlyFinance = onSchedule({
  schedule: '0 2 * * *',
  timeZone,
  retryCount: 3,
  maxRetrySeconds: 3600,
  timeoutSeconds: 540,
  maxInstances: 1,
}, async (event) => {
  const date = new Date(event.scheduleTime);
  const parts = Object.fromEntries(schoolDate.formatToParts(date)
    .map(({ type, value }) => [type, value]));
  const month = parts.year + '-' + parts.month;
  const monthId = parts.year + parts.month;
  const results = await Promise.allSettled(categories.map((category) =>
    generate(category, month, monthId, Number(parts.day))));
  const failures = results.flatMap((result, i) => {
    if (result.status === 'fulfilled') return [];
    logger.error('Monthly finance generation failed', { month, category: categories[i], error: result.reason });
    return [categories[i]];
  });
  if (failures.length) throw new Error('Generation failed: ' + failures.join(', '));
});

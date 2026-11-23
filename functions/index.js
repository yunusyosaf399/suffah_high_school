'use strict';

const {onSchedule} = require('firebase-functions/v2/scheduler');
const {logger} = require('firebase-functions');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {runMonthlyScheduler} = require('./scheduler');

initializeApp();

// Runs once each morning at 06:10 Pakistan time. One Cloud Scheduler job
// serves all four types, with per-category / per-plan generation days.
exports.generateMonthlyFinance = onSchedule({
  schedule: '10 6 * * *',
  timeZone: 'Asia/Karachi',
  region: 'asia-south1',
  timeoutSeconds: 540,
  memory: '512MiB',
  maxInstances: 1,
  retryCount: 0,
}, async () => {
  const result = await runMonthlyScheduler(getFirestore(), new Date(), {
    serverTimestamp: () => FieldValue.serverTimestamp(),
    logger,
  });
  logger.info('Monthly finance scheduler completed', result);
});

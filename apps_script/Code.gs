/**
 * My Podcasts - Google Apps Script backend.
 *
 * Setup:
 *  1. Open your Google Sheet -> Extensions -> Apps Script.
 *  2. Replace the default code with this file.
 *  3. Set your token: Project Settings (gear icon) -> Script properties ->
 *     Add property TOKEN = your own long random secret.
 *     (Or change the TOKEN constant below, but then every change needs a
 *     new deployment version.)
 *  4. Run `setup` once (Run button) and grant permissions.
 *  5. Deploy -> New deployment -> Web app
 *       Execute as: Me
 *       Who has access: Anyone
 *     Copy the /exec URL into the app's Settings, together with the TOKEN.
 *
 * After editing this code, use Deploy -> Manage deployments -> Edit ->
 * Version: New version, so the same URL serves the new code.
 * Changing the TOKEN script property does NOT need a new version.
 */

/** Fallback used only when the TOKEN script property is not set. */
const TOKEN = 'CHANGE-ME-to-a-long-random-secret';
const SHEET_NAME = 'Podcasts';

/** Bump when this file changes, so the app can detect an outdated deployment. */
const SCRIPT_VERSION = 2;

const HEADERS = [
  'ID',
  'Video ID',
  'Title',
  'Channel',
  'YouTube URL',
  'Thumbnail URL',
  'Rank',
  'Points',
  'Points Count',
  'Date Added',
  'Last Updated',
];

// JSON field name <-> sheet header name.
const FIELDS = {
  id: 'ID',
  videoId: 'Video ID',
  title: 'Title',
  channel: 'Channel',
  url: 'YouTube URL',
  thumbnailUrl: 'Thumbnail URL',
  rank: 'Rank',
  points: 'Points',
  pointsCount: 'Points Count',
  dateAdded: 'Date Added',
  lastUpdated: 'Last Updated',
};

/** Run once from the editor to create the sheet tab and header row. */
function setup() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) sheet = ss.insertSheet(SHEET_NAME);

  const existing = sheet.getLastColumn() > 0
    ? sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0].map(String)
    : [];
  const missing = HEADERS.filter((h) => existing.indexOf(h) === -1);
  if (missing.length) {
    sheet.getRange(1, existing.length + 1, 1, missing.length).setValues([missing]);
  }

  const lastCol = sheet.getLastColumn();
  sheet.getRange(1, 1, 1, lastCol).setFontWeight('bold');
  sheet.setFrozenRows(1);
  const pointsCol = headerMap_(sheet)['Points'];
  sheet.getRange(1, pointsCol, sheet.getMaxRows(), 1).setWrap(true);
  sheet.setColumnWidth(pointsCol, 400);
}

function doGet(e) {
  return handle_(() => {
    const params = (e && e.parameter) || {};
    checkToken_(params.token);
    const action = params.action || 'list';
    if (action === 'list') return listPodcasts_();
    if (action === 'ping') {
      return { version: SCRIPT_VERSION, sheet: SHEET_NAME, count: listPodcasts_().length };
    }
    throw new Error('Unknown action: ' + action);
  });
}

function doPost(e) {
  return handle_(() => {
    const body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    checkToken_(body.token);

    const lock = LockService.getScriptLock();
    if (!lock.tryLock(25000)) throw new Error('Sheet is busy, try again');
    try {
      switch (body.action) {
        case 'add':
          return addPodcast_(body.podcast);
        case 'update':
          return updatePodcast_(body.podcast);
        case 'delete':
          return deletePodcast_(body.id);
        case 'list':
          return listPodcasts_();
        default:
          throw new Error('Unknown action: ' + body.action);
      }
    } finally {
      lock.releaseLock();
    }
  });
}

// ---------------------------------------------------------------------------

function handle_(fn) {
  let result;
  try {
    result = { ok: true, data: fn() };
  } catch (err) {
    result = { ok: false, error: String((err && err.message) || err) };
  }
  result.version = SCRIPT_VERSION;
  return ContentService.createTextOutput(JSON.stringify(result))
    .setMimeType(ContentService.MimeType.JSON);
}

/** The TOKEN script property if set, otherwise the TOKEN constant. */
function getToken_() {
  const prop = PropertiesService.getScriptProperties().getProperty('TOKEN');
  return String(prop || TOKEN).trim();
}

function checkToken_(token) {
  const expected = getToken_();
  if (!expected || expected.indexOf('CHANGE-ME') === 0) {
    throw new Error('Unauthorized: TOKEN is not set in the script. Set the TOKEN script property.');
  }
  if (String(token || '').trim() !== expected) {
    throw new Error('Unauthorized: token does not match the deployed script');
  }
}

function getSheet_() {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName(SHEET_NAME);
  if (!sheet) throw new Error('Sheet "' + SHEET_NAME + '" not found. Run setup() first.');
  return sheet;
}

/** Returns { headerName: 1-based column index }. */
function headerMap_(sheet) {
  const lastCol = sheet.getLastColumn();
  if (lastCol === 0) throw new Error('Header row is empty. Run setup() first.');
  const headers = sheet.getRange(1, 1, 1, lastCol).getValues()[0];
  const map = {};
  headers.forEach((h, i) => {
    if (h !== '') map[String(h).trim()] = i + 1;
  });
  HEADERS.forEach((h) => {
    if (!map[h]) throw new Error('Missing column "' + h + '". Run setup() again.');
  });
  return map;
}

function readRows_(sheet, map) {
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) return [];
  const values = sheet.getRange(2, 1, lastRow - 1, sheet.getLastColumn()).getValues();
  return values.map((row, i) => ({ rowIndex: i + 2, podcast: rowToPodcast_(row, map) }));
}

function rowToPodcast_(row, map) {
  const p = {};
  Object.keys(FIELDS).forEach((field) => {
    let v = row[map[FIELDS[field]] - 1];
    if (v instanceof Date) v = v.toISOString();
    p[field] = v;
  });
  p.rank = Number(p.rank) || 0;
  p.points = splitPoints_(String(p.points || ''));
  delete p.pointsCount;
  return p;
}

/** "1. foo\n2. bar" -> ["foo", "bar"] */
function splitPoints_(text) {
  return text
    .split(/\r?\n/)
    .map((line) => line.replace(/^\s*\d+[.)]\s*/, '').trim())
    .filter((line) => line.length > 0);
}

/** ["foo", "bar"] -> "1. foo\n2. bar" */
function joinPoints_(points) {
  return (points || [])
    .map((p) => String(p).replace(/\r?\n/g, ' ').trim())
    .filter((p) => p.length > 0)
    .map((p, i) => (i + 1) + '. ' + p)
    .join('\n');
}

/** Stops Sheets from treating text like "+1 tip" or "=..." as a formula. */
function asText_(value) {
  const s = String(value);
  return /^[=+\-@]/.test(s) ? "'" + s : s;
}

function validate_(p) {
  if (!p) throw new Error('Missing podcast');
  if (!p.id) throw new Error('Missing id');
  if (!p.videoId) throw new Error('Missing videoId');
  const rank = Number(p.rank);
  if (!(rank >= 1 && rank <= 10)) throw new Error('Rank must be between 1 and 10');
  const points = (p.points || []).filter((x) => String(x).trim().length > 0);
  if (points.length < 1) throw new Error('At least one point is required');
}

function writeRow_(sheet, map, rowIndex, p, dateAdded, lastUpdated) {
  const width = sheet.getLastColumn();
  const range = sheet.getRange(rowIndex, 1, 1, width);
  const row = range.getValues()[0];
  const points = joinPoints_(p.points);
  const values = {
    id: p.id,
    videoId: p.videoId,
    title: asText_(p.title || ''),
    channel: asText_(p.channel || ''),
    url: p.url || 'https://www.youtube.com/watch?v=' + p.videoId,
    thumbnailUrl: p.thumbnailUrl || 'https://i.ytimg.com/vi/' + p.videoId + '/hqdefault.jpg',
    rank: Number(p.rank),
    points: points,
    pointsCount: points ? points.split('\n').length : 0,
    dateAdded: dateAdded,
    lastUpdated: lastUpdated,
  };
  Object.keys(values).forEach((field) => {
    row[map[FIELDS[field]] - 1] = values[field];
  });
  range.setValues([row]);
}

function listPodcasts_() {
  const sheet = getSheet_();
  const map = headerMap_(sheet);
  return readRows_(sheet, map)
    .map((r) => r.podcast)
    .filter((p) => p.id);
}

function addPodcast_(p) {
  validate_(p);
  const sheet = getSheet_();
  const map = headerMap_(sheet);
  const rows = readRows_(sheet, map);

  const dup = rows.find((r) => r.podcast.videoId === p.videoId);
  if (dup) throw new Error('DUPLICATE:' + dup.podcast.id);

  const now = new Date();
  const rowIndex = sheet.getLastRow() + 1;
  writeRow_(sheet, map, rowIndex, p, now, now);
  return rowToPodcast_(sheet.getRange(rowIndex, 1, 1, sheet.getLastColumn()).getValues()[0], map);
}

function updatePodcast_(p) {
  validate_(p);
  const sheet = getSheet_();
  const map = headerMap_(sheet);
  const found = readRows_(sheet, map).find((r) => r.podcast.id === p.id);
  if (!found) throw new Error('Podcast not found: ' + p.id);

  const dateAdded = found.podcast.dateAdded ? new Date(found.podcast.dateAdded) : new Date();
  writeRow_(sheet, map, found.rowIndex, p, dateAdded, new Date());
  return rowToPodcast_(
    sheet.getRange(found.rowIndex, 1, 1, sheet.getLastColumn()).getValues()[0],
    map,
  );
}

function deletePodcast_(id) {
  if (!id) throw new Error('Missing id');
  const sheet = getSheet_();
  const map = headerMap_(sheet);
  const found = readRows_(sheet, map).find((r) => r.podcast.id === id);
  if (!found) throw new Error('Podcast not found: ' + id);
  sheet.deleteRow(found.rowIndex);
  return { id: id };
}

# OQB API map

A complete inventory of the `oqb.edcity.hk` API surface that Better OQB knows
about, so the app can be built out against the real endpoints. It merges:

1. the endpoints Better OQB **calls** (allow-listed in
   `assets/oqb_api_client.js` and built in `lib/src/services/oqb_api_requests.dart`),
2. the endpoints Better OQB **observes** OQB's own page making
   (`assets/oqb_data_bridge.js`, `assets/oqb_network_probe.js`), and
3. request/response shapes captured from an authenticated student session and
   from the public static files.

It is scoped to what one student account can see. It is **not** a public or
stable contract: paths, fields and envelopes can change without notice, and
teacher/admin accounts expose more.

> **Secrets.** Never persist or export the OQB `token` or a trial `sesskey`.
> They stay inside the authenticated WebView / same-origin JavaScript closure
> (`oqb_api_client.js`). Signed asset URLs (`?sig=...`) are short-lived — render
> and discard; never store the signature.

## Conventions

- **Origin:** every call is same-origin on `https://oqb.edcity.hk`.
- **Auth:** `/api/*` is `POST` with
  `Content-Type: application/x-www-form-urlencoded`. The client always adds
  `app=OQB` and `token=<session token>`; trial writes also add
  `trial_id` and `sesskey`. `/public/*` is unauthenticated `GET`.
- **Envelope:** `/api/*` returns `{"success": true, "result": ...}` on success
  and `{"success": false, "error": {"code", "desc", "detail"}}` on failure.
  `/public/meta.json` is a bare JSON object (no envelope).
- **Legend:** **called** = Better OQB issues it; **observed** = only seen from
  OQB's own page (passively captured, not yet issued by Better OQB).

## Endpoint summary

| Endpoint | Method | Auth | Status | Purpose |
| --- | --- | --- | --- | --- |
| `/public/meta.json` | GET | no | called | Static reference data: subjects, topics, subtopics, difficulties, publishers, key-stage and school levels. |
| `/api/get_user_meta` | POST | yes | called | Current role/context, academic year, per-subject academic years, account limits. |
| `/api/get_usable_packages` | POST | yes | called | Question banks the account may use, with per-topic / per-difficulty counts. |
| `/api/load_papers` | POST | yes | called | Papers to attempt/resume (`to_submit`) or preset/teacher templates (`preset`). |
| `/api/load_submitted_papers` | POST | yes | called | Submitted attempts for a subject (paper id, trial id, score, review flag). |
| `/api/load_paper` | POST | yes | called | Paper metadata + ordered question ids; detailed post-submission data with `opts[with_*]`. |
| `/api/search_questions` | POST | yes | called | Search/count the question bank by publisher, subject, topic, language, NSS, etc. |
| `/api/start_trial` | POST | yes | called | Start/resume an attempt (or load a submitted one for review). Returns the trial `sesskey`. |
| `/api/save_trial` | POST | yes | called | Save answers/progress (`opts[submit]=0`) or submit the attempt (`opts[submit]=1`). |
| `/api/get_user_question_stat` | POST | yes | called | Per-topic / per-difficulty attempt statistics for the user. |
| `/api/save_paper` | POST | yes | observed | Create a user paper from selected question ids (composition stays in the original OQB UI for now). |
| `/api/get_teachers` | POST | yes | observed | Teacher roster lookup. Noise for a student; explicitly excluded from the probe/inspector. |

Static / PWA files that are also publicly exposed (not data APIs):
`/manifest.json`, `/service-worker.js`, `/robots.txt`. The SPA and its assets
(`/js/*`, `/css/*`) are served only to an authenticated session. Login runs on
the EdCity CAS SSO at `wapps1.hkedcity.net/cas/...` (OAuth2, Cloudflare
Turnstile) — out of scope for the API; Better OQB defers to the real page for it.

---

## Public reference data

### `GET /public/meta.json`  (called)

No auth, no body, no envelope — a bare object. Verified top-level keys:

| Key | Item fields | Notes |
| --- | --- | --- |
| `difficulties` | `code`, `desc_zh`, `desc_en` | `0 Mixed, 1 Easy, 2 Normal, 3 Hard`. |
| `ks_levels` | `code`, `desc_zh`, `desc_en` | Key stages: `KS1 P1-P3 … KS4 S4-S6`. |
| `publishers` | `code`, `desc_zh`, `desc_en` | e.g. `EPH, HKEAA, HKEJ-IET, HKEP, MERS, KAN-KWWONG, RTHK`. |
| `sch_levels` | `code`, `desc_zh`, `desc_en` | School levels/forms. |
| `subjects` | see below | One entry per subject. |

Each `subjects[]` entry:

```text
code            e.g. "econ"   (eng, math, phy, bio, chem, econ, geog, cit, bafs, ths, pe)
year_start, year_end          academic-year span the subject is valid for
desc_zh, desc_en              display names
lang_default                  "en" / "zh"
create_disabled, sfs_required, report_disabled, legend_score   feature flags (0/1)
topics[]        { code: "econ_1", desc_zh, desc_en }
subtopics[]     { code, desc_zh, desc_en }   (empty for some subjects, e.g. econ)
sfs             { q_num_min, q_num_min_criteria: { random }, ... }   self-formed-study rules
```

Topic codes are `"{subject}_{n}"` (e.g. `econ_5`) and are the values passed to
`search_questions` `criteria[topic_code][]`.

---

## Authenticated data endpoints

All are `POST` with at least `app=OQB` and `token=...`.

### `POST /api/get_user_meta`  (called)

Body: `app`, `token`. Returns the user's role/context, academic year, per-subject
academic years and account limits. Carries identity fields (`user_info`,
`owner_id`, `*fullname`, `nickname`, …) that the client strips before anything
leaves the page.

### `POST /api/get_usable_packages`  (called)

Body: `app`, `token`, `opts[stat]=1`,
`opts[function_type]=question_attempt.compose.view`.

`result` is a list of packages:

```text
id, subject_code, publisher_code, title_zh, title_en, access_type[]
stat.count_topic              { topic_code: count }
stat.count_topic_difficulty   { topic_code: { difficulty: count } }
```

### `POST /api/load_papers`  (called)

Body: `app`, `token`, plus one criteria set:

- **To attempt/resume:** `criteria[to_submit]=1`
- **Preset/teacher templates:** `criteria[preset]=1&criteria[subject_code]={code}`

`result` is a list of paper rows (see the shared paper-row shape below).

### `POST /api/load_submitted_papers`  (called)

Body: `app`, `token`, `criteria[subject_code]={code}`. `result` is a list of
submitted paper rows, which additionally carry `trial_id`, `score`,
`score_full`, `submitted`, `marked`, `can_review`.

**Shared paper-row shape** (`load_papers` / `load_submitted_papers`):

```text
id / paper_id        paper id  (prefer paper_id; never pass a trial id to start_trial)
subject_code, title, mode_review ("exercise" | "test"), num_of_questions, time_allowed
is_teacher
submitted, marked, can_review          (submitted rows)
score, score_full, trial_id            (submitted rows)
```

### `POST /api/load_paper`  (called)

Body: `app`, `token`, `id={paperId}`. Returns paper metadata and ordered
question ids. For the detailed post-submission view add:

```text
opts[with_content]=1
opts[with_trials]=1
opts[with_trial_questions]=1
opts[with_stat]=1
```

`result` may wrap the paper (`result.paper`) or return it flat, plus a `stat`
object whose exact layout is not yet captured (kept as a sanitized map).

### `POST /api/search_questions`  (called)

Read-only query of the authenticated question bank.

```text
criteria[publisher_code][i], criteria[subject_code][i], criteria[nss][i],
criteria[lang][i], criteria[topic_code][i], criteria[subtopic_code][i], ...
opts[rand]=1        randomise order
opts[limit]=40      page size
```

Count-only: same `criteria`, with `opts[limit]=` (empty) and `opts[count]=1`.

Each result record carries stable question metadata (no body/choices):

```text
id, qcode, lang, description, subject_code, publisher_code,
difficulty_code, eaa_difficulty_code, year, question_no,
hkeaa_correct_pc, nss, is_dse,
package_id[], topic_code[], subtopic_code[], dimension_code[]
```

The question body and choices arrive only via `start_trial` or
`load_paper(with_content)`.

### `POST /api/start_trial`  (called)

Body: `app`, `token`, `id={paperId}`. Add `opts[review]=1` to load an already
submitted attempt for review (adds marking / model-answer fields). **Captures
the trial `sesskey`** from the response — required by every `save_trial`.

Response shape:

```text
result
├─ paper   { id, subject_code, title, mode_review, time_allowed, num_of_questions }
├─ trial   { id, submitted, marked, time_spent, state, resume, sesskey, score, score_full }
└─ trial_question[]
   ├─ id            ← the id save_trial uses (NOT question.id)
   ├─ seq, question_id, status, time_spent, user_input
   └─ question
      ├─ id, qcode, subject_code, publisher_code, difficulty_code, year, question_no
      ├─ itype ("choice" | …), content_type, content (HTML), url (signed asset)
      ├─ choices[]        { content|html|text|label, url|image|img|src }
      ├─ topic_code[], subtopic_code[], dimension_code[]
      └─ (review only) suggested_answer "[2]", model_answer, feedback
         + trial_question.is_correct, trial_question.score
```

`user_input` for MC items is a stringified JSON array of zero-based choice
indexes, e.g. `"[0]"` = first choice.

### `POST /api/save_trial`  (called — save & submit)

Save answers/progress (the client forces `opts[submit]=0`):

```text
app, token
trial_id={trialId}
sesskey={sesskey}            ← added by the client from the captured trial
trial_question[i][id]={trialQuestionId}
trial_question[i][user_input]=[0]
trial_question[i][time_spent]=1
trial_question[i][status]=null      (or "submitted" to reveal/lock the answer — OQB's "Show")
opts[time_spent]={trialTimeSpent}
opts[state]={"latestAccessQuestionNo":1}
opts[submit]=0
```

Every `save_trial` response echoes `result.trial_question[]` **with the answer
key**, whether or not a question was checked:

```text
id, user_input, time_spent, status,
question_id, trial_id, parent_id, num_of_children, children,
suggested_answer "[1]", suggested_score, itype,
manual_mark, case_sensitive, max_match, abba_group, aabb_group, abcd_group
```

Better OQB keeps that key in memory and only reveals a question's answer after
the learner presses **Show answer** (which sends `status=submitted` for that
item and locks it). Exercise papers (`mode_review=exercise`) have Show; test
papers do not.

**Submit** uses the same endpoint with the latest answers/state and
`opts[submit]=1`. A successful submit returns `{"success":true,"result":true}`.
Submission must only ever be reached from an explicit, confirmed user action —
never automatically.

### `POST /api/get_user_question_stat`  (called)

Body: `app`, `token`, `criteria[subject_code]={code}`. Per-topic /
per-difficulty attempt statistics for the user.

---

## Observed-only endpoints (not yet issued by Better OQB)

### `POST /api/save_paper`  (observed)

Create a user paper from selected question ids. Captured body:

```text
app, token
id=0                 (0 = create new)
subject_code=econ
published=1
mode_review=test
title=...
time_allowed=120
paper_question[0][question_id]={questionId}   (one per selected question)
```

Paper composition currently stays in the original OQB UI
(`catalog_view.dart`). This is the endpoint to drive if/when Better OQB builds
its own paper-composer.

### `POST /api/get_teachers`  (observed)

Teacher roster lookup made by OQB's own page. Irrelevant to a student flow and
intentionally filtered out of the network probe and inspector
(`oqb_network_probe.js`, `oqb_network_event.dart`).

---

## Capturing more endpoints

Better OQB ships a live capture pipeline — the fastest way to discover
endpoints this map does not yet cover:

- **`assets/oqb_network_probe.js`** wraps `fetch`, `XMLHttpRequest`,
  `navigator.sendBeacon` and `PerformanceObserver`, and reports **every**
  same-origin `/api/*` and `/public/*` request (method, URL, status, redacted
  request/response previews) to Flutter. Secrets (`token`, `sesskey`, `sig`,
  cookies, identity fields) are redacted at the source.
- **`assets/oqb_data_bridge.js`** additionally parses a curated allow-list of
  data endpoints and folds their responses into the in-app catalog.
- **`lib/src/widgets/oqb_network_inspector.dart`** surfaces the captured events
  in the running app.

To extend the map: sign in on the real OQB page inside Better OQB, exercise a
flow (compose a paper, open a report, browse a new subject), then read the
inspector. Add any new endpoint here with its captured body and a sanitized
response shape before wiring it into `oqb_api_client.js` (allow-list) and
`oqb_api_requests.dart` (typed builder). Do not add an endpoint that has not
been observed, and never widen the secret-redaction rules.

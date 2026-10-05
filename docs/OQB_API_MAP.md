# OQB observed API map

This file records endpoints observed from an authenticated OQB student session.
It is intentionally limited to endpoints used by the current account and should
not be treated as a public or stable API contract.

Never persist or export the OQB `token` or trial `sesskey`. Better OQB should
keep them inside the authenticated WebView / same-origin JavaScript context.

## Core endpoints

| Endpoint | Method | Observed body | Purpose |
| --- | --- | --- | --- |
| `/public/meta.json` | GET | none | Static metadata: subjects, topics, subtopics, difficulties, publishers and school levels. |
| `/api/get_user_meta` | POST | `app=OQB&token=...` | Current role/context, academic year, subject academic years and account limits. |
| `/api/get_usable_packages` | POST | `app=OQB&token=...&opts[stat]=1&opts[function_type]=question_attempt.compose.view` | Packages/question banks the authenticated user may access, plus topic/difficulty counts. |
| `/api/load_papers` | POST | `app=OQB&token=...&criteria[to_submit]=1` | Papers currently available for the user to attempt/resume. |
| `/api/load_papers` | POST | `app=OQB&token=...&criteria[preset]=1&criteria[subject_code]=econ` | Preset/teacher-provided paper templates for a subject. |
| `/api/load_submitted_papers` | POST | `app=OQB&token=...&criteria[subject_code]=econ` | Submitted attempts for a subject, including paper/trial IDs, score and review availability. |
| `/api/load_paper` | POST | `app=OQB&token=...&id={paperId}` | Paper metadata and ordered question IDs. |
| `/api/load_paper` | POST | `app=OQB&token=...&id={paperId}&opts[with_content]=1&opts[with_trials]=1&opts[with_trial_questions]=1&opts[with_stat]=1` | Detailed post-submission paper, question, trial and statistics data. |
| `/api/search_questions` | POST | `app=OQB&token=...&criteria[...]&opts[rand]=1&opts[limit]=40` | Search the authenticated question bank by publisher, subject, NSS flag, language, topic and other criteria. |
| `/api/search_questions` | POST | same criteria with `opts[count]=1` | Count matching questions without loading the full records. |
| `/api/save_paper` | POST | `app=OQB&token=...&id=0&subject_code=econ&published=1&mode_review=test&title=...&time_allowed=120&paper_question[0][question_id]={questionId}` | Create a user paper from selected question IDs. |
| `/api/start_trial` | POST | `app=OQB&token=...&id={paperId}` | Start or resume a trial and return the trial plus full question records. |
| `/api/start_trial` | POST | `app=OQB&token=...&id={paperId}&opts[review]=1` | Load an already submitted attempt for review, including marking/model-answer fields. |
| `/api/save_trial` | POST | see below | Save answers/progress or submit the active trial. |
| `/api/get_user_question_stat` | POST | `app=OQB&token=...&criteria[subject_code]=econ` | Per-topic/per-difficulty attempt statistics for the user. |

## Question search

An observed HKEAA Economics Topic 5 search used:

```text
criteria[publisher_code][0]=HKEAA
criteria[subject_code][0]=econ
criteria[nss][0]=1
criteria[lang][0]=en
criteria[topic_code][0]=econ_5
opts[rand]=1
opts[limit]=40
```

The corresponding count request used the same criteria with:

```text
opts[limit]=
opts[count]=1
```

Search results include stable question metadata such as:

```text
id
qcode
lang
description
subject_code
publisher_code
difficulty_code
eaa_difficulty_code
year
question_no
hkeaa_correct_pc
nss
is_dse
package_id[]
topic_code[]
subtopic_code[]
dimension_code[]
```

The question body and choices are loaded when a trial is started or when
`load_paper` is called with content enabled.

## Starting a trial

Observed `start_trial` response shape:

```text
result
├─ paper
│  ├─ id
│  ├─ subject_code
│  ├─ title
│  ├─ mode_review
│  ├─ time_allowed
│  └─ num_of_questions
├─ trial
│  ├─ id
│  ├─ submitted
│  ├─ marked
│  ├─ time_spent
│  ├─ state
│  ├─ resume
│  └─ sesskey
└─ trial_question[]
   ├─ id
   ├─ seq
   ├─ question_id
   ├─ status
   ├─ time_spent
   ├─ user_input
   └─ question
      ├─ id
      ├─ qcode
      ├─ subject_code
      ├─ publisher_code
      ├─ difficulty_code
      ├─ year
      ├─ question_no
      ├─ itype
      ├─ content_type
      ├─ content
      ├─ url
      ├─ choices[]
      ├─ topic_code[]
      ├─ subtopic_code[]
      └─ dimension_code[]
```

Before submission, answer-key fields are not present in the normal trial
response. In review mode, the question record additionally exposes fields such
as `suggested_answer`, `model_answer`, `feedback`, and the trial question
contains `is_correct` and `score`.

Question and choice assets are returned as signed URLs and should be treated as
short-lived. Do not persist the signatures.

## Saving an answer / progress

Observed answer-save request:

```text
POST /api/save_trial

app=OQB
token=...
trial_id={trialId}
sesskey=...
trial_question[0][id]={trialQuestionId}
trial_question[0][user_input]=[0]
trial_question[0][time_spent]=1
trial_question[0][status]=null
opts[time_spent]=1
opts[state]={"latestAccessQuestionNo":1}
opts[submit]=0
```

The response changes the trial question status to `attempted`.

For a multiple-choice item, the observed `user_input` is a JSON-like array of
zero-based choice indexes. For example, `[0]` is the first choice. The review
response for the captured question used `suggested_answer="[2]"`, meaning the
third choice was correct.

Better OQB must use the trial-question ID returned by `start_trial`; the
question-bank question ID alone is not sufficient for `save_trial`.

## Submitting a trial

Submission uses the same `/api/save_trial` endpoint with the latest answers
and progress state, but:

```text
opts[submit]=1
```

The captured successful submission returned:

```json
{"success":true,"result":true}
```

Do not call this automatically. Submission must remain an explicit user action.

## Review / report flow

After submission, the observed sequence was:

```text
load_submitted_papers(subject)
        ↓
start_trial(id=paperId, opts[review]=1)
        ↓
load_paper(
  id=paperId,
  with_content=1,
  with_trials=1,
  with_trial_questions=1,
  with_stat=1
)
```

This exposes:

- submitted/marked status and score
- per-question user input and correctness
- suggested/model answers
- per-topic statistics
- per-difficulty statistics
- full paper totals and time spent

## Package access

`get_usable_packages` returned the authenticated banks that the account can
use. The HKEAA packages are marked with `access_type=["school"]`; some other
publishers are marked `["free"]`.

For Better OQB, this endpoint should drive the subject/bank list instead of a
hard-coded subject list.

With `opts[stat]=1`, each package also includes counts such as:

```text
stat.count_topic
stat.count_subtopic
stat.count_topic_difficulty
```

Those counts are suitable for showing topic availability and difficulty filters
without searching the entire bank first.

## Architecture implication

Better OQB should no longer use DOM scraping as the primary data source.

Preferred path:

```text
hidden authenticated WebView
        ↓
same-origin JS API adapter
        ↓
OQB JSON endpoints
        ↓
sanitized Dart models
        ↓
Flutter UI
```

Keep the OQB authentication token and trial `sesskey` inside the
WebView/JavaScript context. Do not persist them in Dart storage. The Flutter
layer should receive only the parsed data it needs.

`start_trial` may create an attempt, `save_paper` creates server-side data,
and `save_trial?submit=1` submits work. These endpoints must only run after
the corresponding explicit user action.

## Still unknown / needs another focused capture

The main study flow is now mapped. Remaining optional behavior:

- bookmark/favourite question
- annotation/highlight/note actions, if OQB supports them
- deleting/renaming a user-created paper
- retrying an exercise / creating another trial when `max_trial_no` permits
- any long-answer/manual-marking-specific payloads

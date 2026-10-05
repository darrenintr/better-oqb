# OQB observed API map

This file records endpoints observed from an authenticated OQB student session.
It is intentionally limited to endpoints used by the current account and should
not be treated as a public or stable API contract.

## Core endpoints

| Endpoint | Method | Observed body | Purpose |
| --- | --- | --- | --- |
| `/public/meta.json` | GET | none | Static metadata: subjects, topics, subtopics, difficulties, publishers and school levels. |
| `/api/get_user_meta` | POST | `app=OQB&token=...` | Current role/context, academic year, subject academic years and account limits. |
| `/api/get_usable_packages` | POST | `app=OQB&token=...&opts[stat]=1&opts[function_type]=question_attempt.compose.view` | Packages/question banks the authenticated user may access, plus topic/difficulty counts. |
| `/api/load_papers` | POST | `app=OQB&token=...&criteria[to_submit]=1` | Papers currently available for the user to attempt/resume. |
| `/api/load_paper` | POST | `app=OQB&token=...&id={paperId}` | Paper metadata and ordered question IDs. |
| `/api/start_trial` | POST | `app=OQB&token=...&id={paperId}` | Starts or resumes a trial and returns the trial plus full question records. |

## Important response structure

### `start_trial`

Observed response shape:

```text
result
├─ paper
│  ├─ id
│  ├─ subject_code
│  ├─ title
│  ├─ mode_review
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
      ├─ dimension_code[]
      ├─ suggested_answer
      ├─ model_answer
      └─ feedback
```

Question and choice assets are returned as signed URLs and should be treated as
short-lived. Do not persist the signatures.

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
Dart models
        ↓
Flutter UI
```

Keep the OQB authentication token inside the WebView/JavaScript context. Do not
persist it in Dart storage. The Flutter layer should receive only the parsed
data it needs.

`start_trial` may create an attempt, so it must only be called after an
explicit user action to start/resume a paper. Do not prefetch every paper with
this endpoint.

## Still unknown

The following flows still need a focused capture:

- saving/changing an answer
- updating time/progress
- bookmark/annotation
- submitting a trial
- loading post-submission marking/report data

Capture these on a short disposable paper where possible.

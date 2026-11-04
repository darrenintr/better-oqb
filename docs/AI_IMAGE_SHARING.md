# Image questions and Ask ChatGPT

The text-only ChatGPT URL cannot attach image bytes. OQB often returns the entire question and each option as an image; sending `(image)` placeholders is not a complete question.

## Updated flow

- Text-only questions keep the existing URL-prefill and clipboard flow.
- Image questions open a full-question preview. Every question and choice image is fetched before export. The authenticated OQB asset loader is used first, with a direct fetch fallback for signed CDN assets.
- The preview preserves HTML, tables and the position of inline formula images. It contains all option labels, the learner's answer, OQB's correct answer, and Traditional Chinese explanation instructions.
- A PNG is rendered from the complete card, not just the visible viewport. The native share sheet opens automatically once the card is ready; the Share question image button retries it.
- Choose ChatGPT when it is offered by the device. Its availability and receiving behavior require physical-device testing. Otherwise save the PNG to Files and attach it in ChatGPT. The complete request is also copied as text. No claim is made that URL-prefill uploads an image or that dismissing a share sheet sends a message.

## Data handling and limits

Only the selected question is exported. Handwritten working and surrounding app UI are excluded. OQB cookies and signed asset URLs are not put into shared metadata or text. The derived PNG is stored in the app's temporary `oqb-question-shares` directory; exports older than one day are cleaned on the next share. No public image hosting, new AI API key or OCR is used.

Missing, failed or undecodable images stop export with a retry/screenshot message rather than silently omitting an option. SVG/embedded documents and oversized images currently require screenshots. Automated tests cover source extraction, all four options, missing assets, inline image order, rendering and PNG export; a physical iPad/ChatGPT handoff is still a separate validation step.

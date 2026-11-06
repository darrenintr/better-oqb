# Handwritten working and ChatGPT preview

Open working with the pen button above the study reader. Landscape tablets show
question and working side by side; portrait uses top/bottom panes. The scratch
page scrolls with a finger by default; Pencil and mouse draw. Enable Finger
drawing to use touch for ink instead. Pen colours, thickness, whole-stroke eraser,
undo/redo, clear and plain/grid/ruled paper are available.

Working is keyed by paper ID and OQB question ID, stored as local JSON under the
app's Application Support directory. Writes are serialized per document and use
a temporary file then rename. It is not submitted to OQB, synced to other devices,
or attached to ChatGPT. Removing app data also removes saved working. There is no
PencilKit pressure/tilt support or handwriting recognition in this implementation.

After a wrong answer is revealed, Ask ChatGPT why includes the available question
text, choices, selected answer and OQB's answer. The complete prompt is copied
before opening ChatGPT. Prefill depends on the destination app/browser. Long URL
prompts request a clipboard paste rather than silently truncating the question.
Images still need a manually attached screenshot; signed OQB asset URLs are not
included. ICT preformatted code keeps indentation. Explanation instructions request
Traditional Chinese, math working and program/variable tracing.

## Validation and provenance

This branch reuses the existing ask-chatgpt-wrong-answers implementation and adds
new handwriting code. It is a reconstruction, not the unavailable local commit
f9b19cf mentioned in the earlier chat. Its previous claimed 154-test result does
not apply to this code. Use the current GitHub Actions results.

The iOS Pencil preview workflow runs analysis and tests before building an unsigned
IPA. The artifact is named better-oqb-ios-unsigned. It requires signing before
installation; physical Apple Pencil behavior must still be tested on an iPad.

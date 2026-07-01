# Screenshot and Vision Input Roadmap

This document defines the near-term screenshot MVP and the longer-term product
direction toward a universal input/output layer.

## Positioning

Bomb Squad started as a communication staging layer: draft first, review in the
middle, then deploy to the live app. That remains useful, but the broader shape
is not only "make my outgoing text safer." The stronger direction is:

- user output: voice and text become safe, clear, deployable communication
- computer input: selected text, screenshots, and screen context become readable
  explanations or next actions
- one transient panel sits between the user and the live app in both directions

In that framing, screenshots are not just a convenience feature. They are the
first concrete step toward vision input.

The current two-pane panel still maps well:

- left pane: captured input, either text, voice transcription, or screen image
- right pane: interpreted output, either rewritten text or explanation

The product should avoid becoming two separate apps. The win is one lightweight
I/O layer that handles "what I am trying to say" and "what the computer is
showing me" with the same gesture discipline and the same review/interpret loop.

## Product Thesis

Human-computer communication is mostly mediated through:

- voice
- vision
- text derived from voice or vision

The app already has a strong voice path:

- right Shift hold
- record while held
- transcribe with ASR
- insert text into the staging draft

The weak path is vision. Text selection is useful, but it only works when the
target app exposes selectable text and the user knows exactly which text matters.
Many real situations are visual:

- a UI state that is hard to describe
- an error dialog
- a chart, table, image, or PDF
- a chat thread with layout, reactions, attachments, and surrounding context
- a screen where the relevant meaning is not cleanly selectable

Vision input should become a first-class source, not an attachment afterthought.

## Near-Term Feature: Screenshot Attachment MVP

Status: implemented locally

### Goal

Add a low-risk screenshot button to the existing input-support panel.

The MVP should let the user capture a rectangular screen region and keep the
result attached to the current compose session. The first version does not need
to paste the image into Slack, Gmail, Notion, or another destination app.

### User Flow

1. User opens the Bomb Squad panel.
2. User clicks a screenshot button near the lower-left utility controls.
3. Bomb Squad temporarily hides its panel.
4. macOS standard region selection appears.
5. User drags a rectangle and confirms.
6. A PNG is saved to a predictable local location.
7. Bomb Squad shows the panel again with a small screenshot thumbnail.
8. The user can remove the attachment or use the saved file manually.

### MVP Scope

Included:

- add a screenshot icon button to `StagingEditorView`
- launch macOS interactive screenshot capture
- save a PNG file locally
- restore the panel after capture completes
- show one or more attached screenshot thumbnails in the left pane
- allow removing an attached screenshot
- surface capture failure or cancellation in the existing error area

Not included in the first pass:

- automatic image paste into every target app
- custom full-screen crop UI
- VLM analysis of the screenshot
- OCR extraction
- cloud upload
- history persistence for images
- sending screenshots to the review API

### Technical Approach

Use the macOS `screencapture` utility for the first implementation:

```text
screencapture -i <output-file>
```

Reasons:

- it gives region selection for free
- it matches normal macOS expectations
- it avoids building a custom global overlay
- it avoids adding ScreenCaptureKit complexity before the product behavior is
  proven

The first output location should be:

```text
~/Desktop/BombSquad-YYYYMMDD-HHMMSS.png
```

Later, this can move to:

```text
~/Library/Application Support/BombSquad/Screenshots/
```

Desktop is acceptable for the MVP because the user can immediately find the
file and drag it into another app if automatic attachment is not implemented
yet.

### Proposed Code Changes

Current implementation files:

- `BombSquad/Models/ScreenshotAttachment.swift`
- `BombSquad/Services/ScreenshotCaptureService.swift`
- `BombSquad/ViewModels/ReviewViewModel.swift`
- `BombSquad/Views/StagingEditorView.swift`
- `BombSquad/AppDelegate.swift`

New model:

- `BombSquad/Models/ScreenshotAttachment.swift`
  - `id`
  - `url`
  - `createdAt`
  - optional image metadata such as pixel size

New service:

- `BombSquad/Services/ScreenshotCaptureService.swift`
  - creates a destination URL
  - runs `screencapture -i`
  - returns a `ScreenshotAttachment`
  - maps cancellation and failures to user-readable errors

View model changes:

- `ReviewViewModel`
  - `@Published var screenshotAttachments: [ScreenshotAttachment]`
  - `@Published var isCapturingScreenshot: Bool`
  - `func addScreenshotAttachment(_ attachment: ScreenshotAttachment)`
  - `func removeScreenshotAttachment(id:)`

App delegate changes:

- add a screenshot capture entry point
- temporarily hide the panel while capture is active
- run the capture
- restore the panel after capture or cancellation
- keep the existing view model alive during capture

View changes:

- `StagingEditorView`
  - add a `camera.viewfinder` or similar icon button near the help/mic area
  - show a small thumbnail strip under the editor or above the utility row
  - disable the button while capture is running

Notification option:

- add `Notification.Name.captureScreenshot`
- the SwiftUI button posts the notification
- `AppDelegate` owns the actual capture because it owns the panel window

This follows the current pattern used by `.closePanel` and `.showManagement`.

### Acceptance Criteria

- Clicking the screenshot button hides the Bomb Squad panel before selection.
- The macOS region selector can capture the app behind Bomb Squad.
- Cancelling the capture returns to the Bomb Squad panel without adding an
  attachment.
- Successful capture creates a PNG file.
- The panel shows a thumbnail and file name/path after capture.
- Removing the attachment updates the UI without deleting the file in the MVP.
- Existing text review, voice input, right Shift gestures, and deploy behavior
  continue to work.
- Debug build passes:

```bash
xcodebuild -project BombSquad.xcodeproj -scheme BombSquad -configuration Debug build
```

### Risks

- `screencapture` behavior can vary slightly across macOS versions.
- Screen recording permissions may be requested by macOS depending on capture
  behavior and OS policy.
- Hiding and restoring a floating `NSPanel` must preserve the current
  `ReviewViewModel`.
- If the user changes apps during capture, the panel should still return
  predictably.
- Desktop output is simple but noisy; move to Application Support after the
  interaction is validated.

## Phase 2: Screenshot Paste Assistance

After the MVP works, add a manual-friendly paste path.

Candidate behavior:

- copy the screenshot file or image data to the pasteboard
- show a small "copy image" button on the thumbnail
- optionally copy the latest screenshot automatically after capture

Do not immediately combine this with text deployment. Target apps differ:

- some apps accept image data pasted from the clipboard
- some apps accept file URLs
- some web apps intercept paste events differently
- some apps upload images asynchronously and need focus to remain stable

This phase should be tested explicitly in:

- Slack
- Gmail
- Apple Mail
- Notion
- browser textareas

## Phase 3: Vision Interpretation Mode

This is the point where screenshot becomes product core.

Status: local first pass implemented

### Goal

After a screenshot is captured, switch the current panel session into vision
mode. Any text currently in the original draft is ignored for that session. The
left pane becomes the captured screen image, and the right pane becomes the
model's explanation of that image.

This is no longer "screenshot attachment." It is "screen as input."

### User Flow

1. User opens the panel, or is already in the panel with text present.
2. User clicks the vision/screenshot button.
3. The app checks screen recording permission before entering capture.
4. The panel hides and macOS region capture starts.
5. User captures a region.
6. The panel returns in vision mode.
7. Left pane shows the captured screenshot instead of the text editor.
8. Right pane shows a loading state, then a structured explanation:
   - what is visible
   - important text
   - likely user-relevant meaning
   - possible next actions
   - uncertainty or missing context
9. User can type or dictate a follow-up question, such as "この部分は何？"
10. The answer updates using the image plus the follow-up instruction.

Open question:

- whether the previous compose draft should be restored if the user leaves
  vision mode. Product direction says ignore it during vision mode; preserving
  it in memory for a back action may still be useful.

### Open Gesture Decision

Avoid overloading right Shift too far.

Possible bindings:

- right Shift double-tap remains text selection or compose review
- a separate hotkey invokes screen understanding
- a visible screenshot/vision button starts vision capture from the panel
- later, a configurable function-key double-tap can be added

Recommendation:

Start with an explicit button. Add a global gesture only after the behavior is
clearly useful and the accidental-trigger risk is understood.

### Minimal UI Behavior

Left pane in vision mode:

- title changes from `原文` to `画面`
- large screenshot preview replaces `SendableTextEditor`
- controls show image filename, pixel size, and a remove/retake action
- existing draft text is hidden and does not affect review state

Right pane in vision mode:

- title changes from `レビュー結果` / `読み取り結果` to `画面の説明`
- while loading, show `画面を読み取っています...`
- after success, show an editable explanation field only if we want the user to
  copy or refine it; otherwise a read-only structured result is enough
- primary action is `コピー`, not `送信`

Do not auto-deploy vision output into the original app in the first version.
Vision output is understanding support, so clipboard copy is the safe exit.

### Interface Model

Introduce a broader input mode instead of treating everything as text:

```swift
enum InputSessionMode {
    case composeText
    case transformText
    case screenshotAttachment
    case visionInterpretation
}
```

The current `ReviewMode.compose` and `.transform` can remain for text review,
but the product model should eventually distinguish:

- operation: review, transform, visionInterpret
- input medium: text, audio, image, screen
- output intent: send, understand, summarize, explain, reply

This matters for API design and usage metering.

The current code has `ReviewViewModel.mode` as an immutable `ReviewMode`. For a
small first implementation, avoid forcing every text path through a large
refactor. Add a separate mutable session state:

```swift
enum InputSessionKind {
    case text
    case vision
}
```

Then add vision-specific state to `ReviewViewModel`:

```swift
@Published var sessionKind: InputSessionKind = .text
@Published var visionImage: ScreenshotAttachment?
@Published var visionResult: VisionInterpretationResult?
@Published var isInterpretingVision = false
@Published var visionInstruction = ""
```

`ReviewMode.compose` / `.transform` can continue to control existing text
prompting and deploy behavior. `sessionKind == .vision` controls the visual
layout and the new vision request path.

### Vision Result Shape

Use a structured result instead of a single prose blob:

```swift
struct VisionInterpretationResult: Codable, Hashable {
    let summary: String
    let visibleText: [String]
    let interpretation: String
    let suggestedActions: [String]
    let uncertainties: [String]
}
```

This keeps the UI stable and allows later features:

- copy only the summary
- turn suggested actions into reply drafts
- ask follow-up questions against the same screenshot
- meter and log vision operations separately from text reviews

### Prompt Direction

The first vision prompt should be practical, not poetic:

```text
You are an assistant that helps the user understand the current screen.
Describe only what can be inferred from the screenshot.
Extract important visible text.
Explain the likely meaning for a non-expert user.
List concrete next actions.
Call out uncertainty instead of guessing.
Return structured JSON in Japanese.
```

For communication contexts such as Slack or Gmail, the model should focus on:

- who is asking for what
- deadlines or action items
- emotionally loaded wording
- hidden assumptions
- what the user likely needs to do next

For app or system UI contexts, the model should focus on:

- current state
- error messages
- blocked controls or missing permissions
- next safe steps

### OpenAI VLM Selection

Use the OpenAI Responses API for the first real implementation. The current
OpenAI docs describe Responses as the primary interface that accepts text and
image inputs and returns text or JSON output. The image/vision guide also points
to Responses API for image analysis use cases.

Recommended default for this product:

- default: `gpt-5.4-mini`
- high-quality/manual option: `gpt-5.5`
- low-cost experiment: `gpt-5.4-nano`

Rationale:

- Screen interpretation is an always-on utility path, so latency and cost matter
  more than maximum reasoning for the default.
- The app needs enough visual/text reasoning to read UI, messages, tables, and
  errors. A small current model should be tested first before paying for the
  flagship model on every screenshot.
- Use the flagship model for complex screenshots: dense tables, code, design
  critique, multi-panel dashboards, or ambiguous UI state.
- Avoid GPT Image models for this path. They are for image generation/editing,
  not screen understanding output.

Evaluation set before locking the default:

- Slack message with tone/context
- Gmail thread with visible reply composer
- macOS permission dialog
- web app error state
- table/chart screenshot
- mixed Japanese/English UI
- dense design or Figma-like screen

Acceptance threshold for the default model:

- identifies the main visible app/context
- extracts important on-screen text accurately enough to act
- distinguishes facts from guesses
- gives useful next actions
- returns within the interaction budget for a transient panel

### Implementation Steps

1. Convert screenshot success into vision mode:
   - set `sessionKind = .vision`
   - set `visionImage = attachment`
   - ignore current `draft` for the active session
   - trigger `runVisionInterpretation()`
2. Update left pane:
   - render screenshot preview when `sessionKind == .vision`
   - hide text character count and text editor
   - show retake/remove controls
3. Update right pane:
   - render loading/empty/result states for vision
   - copy result to clipboard as the first exit path
4. Add `VisionProvider`:
   - `func interpret(imageURL: URL, instruction: String?, language: OutputLanguage) async throws -> VisionInterpretationResult`
5. Add `OpenAIVisionClient`:
   - encode PNG as a data URL for the first version
   - call Responses API
   - request structured JSON
6. Add a lightweight model selector:
   - default to the chosen OpenAI vision model
   - keep it independent from the existing text review model until usage data
     says they should be unified
7. Add server gateway support after the local proof:
   - route through `/api/ai/vision`
   - meter operation as `vision_interpret`
   - avoid storing screenshots by default

Current local checkpoint:

- screenshot success switches the current panel to vision mode
- the left pane shows the captured screenshot instead of the text editor
- the right pane calls OpenAI Responses API and shows a structured explanation
- result copy uses the clipboard only; it does not write back to the source app
- default vision model is `gpt-5.4-mini`, with `gpt-4.1-mini` fallback for
  accounts or environments where the newer model is unavailable

## Phase 4: API and Data Model Extension

The existing API contract is text-first. Vision needs a new operation.

Candidate endpoint:

```text
POST /api/ai/vision
```

Candidate request shape:

```json
{
  "request_id": "uuid",
  "operation": "vision_interpret",
  "input": {
    "image": {
      "mime_type": "image/png",
      "data_base64": "..."
    },
    "user_instruction": "この画面で何が起きているか説明して"
  },
  "preferences": {
    "output_language": "japanese"
  },
  "client": {
    "platform": "macos",
    "app_version": "0.1.0"
  }
}
```

Candidate response shape:

```json
{
  "request_id": "uuid",
  "result": {
    "summary": "画面全体の要約",
    "visible_text": ["画面内で読める重要テキスト"],
    "interpretation": "ユーザー向けの説明",
    "suggested_actions": ["次に取れる行動"],
    "uncertainties": ["読み取れない点や推測の限界"]
  },
  "meta": {
    "model_vendor": "openai",
    "model_id": "vision-capable-model",
    "latency_ms": 1200
  }
}
```

Do not store screenshots by default. Treat screen captures as sensitive input.
If server processing is required, upload only for the active request and avoid
persistent storage unless the user explicitly opts in.

## Phase 5: Toward Universal I/O

The proposed "Universal I/O" name fits the expanded thesis better than Bomb
Squad if the product is no longer only about defusing risky communication.

Bomb Squad:

- strong metaphor for dangerous outgoing messages
- memorable for the first use case
- less natural for screen understanding, accessibility, and general I/O support

Universal I/O:

- broader and more literal
- supports voice, vision, text, and future input/output channels
- better fit for a product that mediates both what the user sends and what the
  computer shows
- may need a warmer product voice in UI copy because the name is abstract

Recommendation:

Keep the implementation modular so the product can be renamed without another
deep app rename:

- avoid new hard-coded user-facing "Bomb Squad" copy in feature internals
- keep bundle IDs stable until there is a clear release decision
- use neutral internal names where possible: `InputSession`, `CaptureService`,
  `VisionInterpretation`, `Attachment`
- do not rename the repository or bundle again until the product direction and
  domain are settled

## Recommended Execution Order

1. Implement screenshot attachment MVP using `screencapture -i`.
2. Validate the capture flow in the real app with Slack/Gmail/Notion behind the
   panel.
3. Add thumbnail display, remove action, and clear error handling.
4. Add manual copy/paste assistance for the latest screenshot.
5. Define the `vision_interpret` API contract in `docs/api-contract.md`.
6. Add local-only vision UI with mock results.
7. Wire a real vision-capable provider through the server-side AI gateway.
8. Add a deliberate global gesture only after the explicit UI path feels right.

## Product Judgment

The direction is coherent. The important constraint is sequencing.

Screenshot attachment is a good first step because it gives immediate utility
without forcing the whole app into a vision architecture. Vision interpretation
is likely the more important long-term product surface, but it should be built
on a working capture primitive, a clear session model, and a server-side AI
gateway that can handle image inputs safely.

The product should be framed less as "review my text" and more as:

```text
One layer between humans and software:
understand what is on screen, shape what you send back.
```

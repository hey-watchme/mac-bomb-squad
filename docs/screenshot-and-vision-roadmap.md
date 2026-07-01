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

### Goal

Capture the current screen or region, then ask a vision-capable model to explain
what is on screen in the same two-pane Bomb Squad interface.

### User Flow

1. User invokes a vision command.
2. The app captures either the full visible screen or a selected region.
3. Left pane shows the captured image.
4. Right pane shows a structured explanation:
   - what is visible
   - important text
   - likely user-relevant meaning
   - possible next actions
   - uncertainty or missing context
5. User can type or dictate a follow-up question, such as "この部分は何？"
6. The answer updates using the image plus the follow-up instruction.

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
